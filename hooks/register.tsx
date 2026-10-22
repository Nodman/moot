import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Dash, LiveAgent, MootState, StateAgent, Task } from '../types'

const PANE = 'moot'
const REFRESH_MS = 20000
const TICK_MS = 1000
const SPIN = ['◐', '◓', '◑', '◒']

const dash = atom({ plugin: 'moot', key: 'dash' } as const, { state: null, path: '', error: '', readAt: 0 } as Dash)
const live = atom({ plugin: 'moot', key: 'live' } as const, [] as LiveAgent[])
const tick = atom({ plugin: 'moot', key: 'tick' } as const, 0 as number)

async function readId(path: string, $: EngineInterface): Promise<string> {
  try {
    return String(await $.fs.read(path)).trim()
  } catch {
    return ''
  }
}

// This session's own work first (bound by moot-state.sh init or current), else the last claimed.
async function statePath($: EngineInterface): Promise<string | null> {
  const repo = await $.session.repo()
  if (!repo) return null
  const sid = await $.session.id().catch(() => '')
  let id = sid ? await readId(`${repo.root}/.moot/sessions/${sid}`, $) : ''
  if (!id) id = await readId(`${repo.root}/.moot/current`, $)
  return id ? `${repo.root}/.moot/work/${id}/state.json` : null
}

// The engine's own status per agent beats what the hooks below pieced together.
const ENGINE_STATUS: Record<string, string> = {
  running: 'running',
  completed: 'done',
  killed: 'done',
  failed: 'failed',
  idle: 'idle',
  waiting: 'idle',
  pending: 'idle',
}

async function syncAgents($: EngineInterface) {
  const infos = await $.agent.list().catch(() => null)
  if (!infos) return
  const byId = new Map(infos.map(a => [a.id, a]))
  await update($, live, list =>
    (list ?? []).map(a => {
      const info = byId.get(a.id)
      const status = info ? (ENGINE_STATUS[info.status] ?? a.status) : 'done' // dropped from the list: ended
      return status === a.status ? a : { ...a, status }
    }),
  )
}

async function reload($: EngineInterface) {
  await syncAgents($)
  const readAt = await $.clock.now()
  const path = await statePath($)
  if (!path) {
    await update($, dash, () => ({ state: null, path: '', error: '', readAt }))
    return
  }
  try {
    const text = String(await $.fs.read(path))
    await update($, dash, () => ({ state: JSON.parse(text) as MootState, path, error: '', readAt }))
  } catch (err) {
    await update($, dash, d => ({ ...(d ?? { state: null }), path, error: String(err), readAt }))
  }
}

async function openPane($: EngineInterface) {
  return $.ui.open({ id: PANE, title: 'moot', columns: 60 })
}

function currentTask(tasks: Task[]): Task | undefined {
  return (
    tasks.find(t => t.stages.some(s => s.status === 'active')) ??
    tasks.find(t => t.stages.length === 0 || t.stages.some(s => s.status !== 'done')) ??
    tasks[tasks.length - 1]
  )
}

function busy(s: MootState | null | undefined, agents: LiveAgent[]): boolean {
  if (!s) return false
  if ([s.council, s.spec, s.plan].some(p => p.status === 'running')) return true
  if ((s.agents ?? []).some(a => a.status === 'running')) return true
  if (agents.some(a => a.status === 'running')) return true
  return (s.tasks ?? []).some(t => t.stages.some(st => st.status === 'active'))
}

function k(n: number | undefined) {
  return n === undefined ? '' : `${Math.round(n / 1000)}k`
}

function bar(percent: number | undefined, cells = 8) {
  if (percent === undefined) return ''
  const on = Math.round((Math.min(100, Math.max(0, percent)) / 100) * cells)
  return '▰'.repeat(on) + '▱'.repeat(cells - on)
}

function pad(text: string, width: number) {
  return text.length >= width ? text : text + ' '.repeat(width - text.length)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'moot-dash',
      description: 'moot dashboard pane: open, close, reload',
      argumentHint: '[open|close|reload]',
    })
    await reload($)
    $.clock.every(REFRESH_MS, () => void reload($))
    $.clock.every(TICK_MS, async () => {
      const [d, agents] = await Promise.all([read($, dash), read($, live)])
      if (busy(d?.state, agents ?? [])) await update($, tick, t => (t ?? 0) + 1)
    })
    return next(e)   // the pane opens only on /moot-dash, never by itself
  })

  on('command.run', { command: 'moot-dash' }, async ($, e) => {
    const verb = e.args.trim() || 'open'
    if (verb === 'close') {
      await $.ui.close({ id: PANE })
      return { text: 'moot dashboard closed' }
    }
    await reload($)
    if (verb === 'reload') return { text: 'moot dashboard reloaded' }
    const opened = await openPane($)
    return { text: opened.isPlaced ? 'moot dashboard open' : `moot dashboard waits: ${opened.reason}` }
  })

  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    const command = (e as unknown as { command?: string }).command
    if (e.tool === 'Bash' && typeof command === 'string' && /\.moot\/|moot-state\.sh|moot-note\.sh/.test(command)) {
      await reload($)
    }
    return ran
  }).catch(($, e, next) => next(e))

  on('agent.spawn', async ($, e, next) => {
    const started = await next(e)
    if (started.deny !== undefined || !started.agentId) return started
    const name = (e as unknown as { name?: string }).name ?? e.subagentType
    const row: LiveAgent = { id: started.agentId, name, ctx: 0, status: 'running' }
    await update($, live, list => [...(list ?? []).filter(a => a.id !== row.id), row].slice(-20))
    return started
  }).catch(($, e, next) => next(e))

  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    const u = result.usage
    if (e.agentId && u) {
      const ctx = u.input_tokens + u.cache_read_input_tokens + u.cache_creation_input_tokens
      await update($, live, list => (list ?? []).map(a => (a.id === e.agentId ? { ...a, ctx } : a)))
    }
    return result
  })

  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    if (e.agentId) await update($, live, list => (list ?? []).map(a => (a.id === e.agentId ? { ...a, status: 'done' } : a)))
    return r
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Link } = $.ui.resolve(e)
    const [d, liveAgents, t] = await Promise.all([read($, dash), read($, live), read($, tick)])
    const usage = await $.session.usage().catch(() => null)
    const s = d?.state
    if (!s) {
      return (
        <Box flexDirection="column" paddingX={1}>
          <Text dimColor>no moot work in this repo{d?.error ? `: ${d.error}` : ''}</Text>
        </Box>
      )
    }
    const spin = SPIN[(t ?? 0) % SPIN.length]
    const sym = (status: string | undefined) => {
      if (status === 'done' || status === 'approved') return <Text color="success">✓</Text>
      if (status === 'running' || status === 'active') return <Text color="warning">{spin}</Text>
      if (status === 'lost' || status === 'failed') return <Text color="error">✗</Text>
      if (status === 'idle') return <Text dimColor>◌</Text>
      return <Text dimColor>○</Text>
    }
    const phases: { name: string; status: string; detail: string; gate: boolean }[] = [
      {
        name: 'council',
        status: s.council.status,
        detail: [s.council.round ? `r${s.council.round}` : '', s.council.contested ? `${s.council.contested} to decide` : '']
          .filter(Boolean)
          .join(' · '),
        gate: Boolean(s.gates?.council),
      },
      { name: 'spec', status: s.spec.status, detail: s.spec.judgeRounds ? `judge r${s.spec.judgeRounds}` : '', gate: Boolean(s.gates?.spec) },
      { name: 'plan', status: s.plan.status, detail: s.plan.judgeRounds ? `judge r${s.plan.judgeRounds}` : '', gate: Boolean(s.gates?.plan) },
    ]
    const task = currentTask(s.tasks ?? [])
    const done = (s.tasks ?? []).filter(x => x.stages.length > 0 && x.stages.every(st => st.status === 'done')).length
    const tokens = usage?.context.tokens
    const percent = usage?.context.percent
    const warn = tokens !== undefined && tokens >= (s.contextWarnTokens ?? 350000)
    const byName = new Map((liveAgents ?? []).map(a => [a.name, a]))
    const stateNames = new Set((s.agents ?? []).map(a => a.name))
    const extra = (liveAgents ?? []).filter(a => !stateNames.has(a.name))
    const agentRow = (a: StateAgent | LiveAgent, status: string | undefined, ctx: number | undefined) => (
      <Text key={a.name} dimColor={status === 'done'}>
        {sym(status)} {pad(a.name, 22)} {ctx ? k(ctx) : ''}
      </Text>
    )

    return (
      <Box flexDirection="column" paddingX={1}>
        <Text bold color="claude">
          MOOT · {s.id} · {s.title || '(no title)'}
        </Text>
        <Text dimColor>
          {s.kind} · {s.ceremony} · phase {s.phase}
        </Text>

        <Box flexDirection="column" borderStyle="round" borderColor="planMode" paddingX={1} marginTop={1}>
          <Text bold color="planMode">
            PHASES
          </Text>
          {phases.map(p => (
            <Text key={p.name} dimColor={p.status === 'pending'}>
              {sym(p.status)} {pad(p.name, 8)} {p.detail}
              {p.gate ? <Text color="success"> gate ✓</Text> : null}
            </Text>
          ))}
        </Box>

        <Box flexDirection="column" borderStyle="round" borderColor="claude" paddingX={1}>
          {task ? (
            <Text bold color="claude">
              TASK {task.order}/{s.tasks.length} · {task.id} {task.title}
            </Text>
          ) : (
            <Text bold color="claude">
              TASKS · none yet
            </Text>
          )}
          {task ? (
            <Text dimColor>
              {done}/{s.tasks.length} done{task.pr ? ` · PR #${task.pr}` : ''}
            </Text>
          ) : null}
          {task?.stages.map(st => (
            <Text key={st.name} dimColor={st.status === 'done'}>
              {sym(st.status)} {st.name}
            </Text>
          ))}
        </Box>

        <Box flexDirection="column" borderStyle="round" borderColor="success" paddingX={1}>
          <Text bold color="success">
            AGENTS
          </Text>
          <Text>
            <Text color="success">●</Text> {pad('lead', 22)} <Text color={warn ? 'error' : undefined}>{bar(percent)}</Text>{' '}
            {percent !== undefined ? `${percent}% ` : ''}
            {k(tokens)}
          </Text>
          {(s.agents ?? []).map(a => agentRow(a, a.status, byName.get(a.name)?.ctx))}
          {extra.map(a => agentRow(a, a.status, a.ctx))}
        </Box>

        {(s.links ?? []).length ? (
          <Box flexDirection="column" borderStyle="round" borderColor="permission" paddingX={1}>
            <Text bold color="permission">
              LINKS
            </Text>
            {(s.links ?? []).map(l =>
              l.url ? (
                <Text key={l.label}>
                  <Link href={l.url} label={l.label} />
                </Text>
              ) : (
                <Text key={l.label} dimColor>
                  {l.label} · {l.path ?? ''}
                </Text>
              ),
            )}
          </Box>
        ) : null}

        {warn ? (
          <Text color="error">
            ⚠ context {k(tokens)} past {k(s.contextWarnTokens)}: /moot:handoff, then a fresh session
          </Text>
        ) : null}
        <Text dimColor>updated {s.updatedAt ?? 'never'}</Text>
      </Box>
    )
  })
}
