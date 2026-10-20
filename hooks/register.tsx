import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Dash, LiveAgent, MootState, Task } from '../types'

const PANE = 'moot'
const REFRESH_MS = 20000

const dash = atom({ plugin: 'moot', key: 'dash' } as const, { state: null, path: '', error: '', readAt: 0 } as Dash)
const live = atom({ plugin: 'moot', key: 'live' } as const, [] as LiveAgent[])

async function statePath($: EngineInterface): Promise<string | null> {
  const repo = await $.session.repo()
  if (!repo) return null
  let id = ''
  try {
    id = String(await $.fs.read(`${repo.root}/.moot/current`)).trim()
  } catch {
    return null
  }
  return id ? `${repo.root}/.moot/work/${id}/state.json` : null
}

async function reload($: EngineInterface) {
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

function mark(status: string) {
  if (status === 'done') return '[x]'
  if (status === 'active') return '[>]'
  return '[ ]'
}

function k(n: number | undefined) {
  return n === undefined ? '' : `${Math.round(n / 1000)}k`
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
    if ((await read($, dash))?.state) void openPane($).catch(() => undefined)
    return next(e)
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
    const [d, liveAgents] = await Promise.all([read($, dash), read($, live)])
    const usage = await $.session.usage().catch(() => null)
    const s = d?.state
    if (!s) {
      return (
        <Box flexDirection="column">
          <Text dimColor>no moot work in this repo{d?.error ? `: ${d.error}` : ''}</Text>
        </Box>
      )
    }
    const gate = (name: string) => (s.gates?.[name] ? ' ✓' : '')
    const council = `council ${s.council.status}${s.council.round ? ` r${s.council.round}` : ''}${
      s.council.contested ? ` · ${s.council.contested} contested` : ''
    }${gate('council')}`
    const spec = `spec ${s.spec.status}${s.spec.judgeRounds ? ` · judge r${s.spec.judgeRounds}` : ''}${gate('spec')}`
    const plan = `plan ${s.plan.status}${s.plan.judgeRounds ? ` · judge r${s.plan.judgeRounds}` : ''}${gate('plan')}`
    const task = currentTask(s.tasks ?? [])
    const done = (s.tasks ?? []).filter(t => t.stages.length > 0 && t.stages.every(st => st.status === 'done')).length
    const tokens = usage?.context.tokens
    const percent = usage?.context.percent
    const warn = tokens !== undefined && tokens >= (s.contextWarnTokens ?? 350000)
    const byName = new Map((liveAgents ?? []).map(a => [a.name, a]))
    const stateNames = new Set((s.agents ?? []).map(a => a.name))
    const extra = (liveAgents ?? []).filter(a => !stateNames.has(a.name))

    return (
      <Box flexDirection="column">
        <Text bold>
          {s.id} · {s.title || '(no title)'}
        </Text>
        <Text dimColor>
          {s.kind} · {s.ceremony} · phase {s.phase}
        </Text>
        <Text>{council}</Text>
        <Text>{spec}</Text>
        <Text>{plan}</Text>
        {task ? (
          <Text bold>
            task {task.id} ({task.order}/{s.tasks.length}, {done} done) {task.title}
          </Text>
        ) : (
          <Text dimColor>no tasks yet</Text>
        )}
        {task?.stages.map(st => (
          <Text key={st.name} dimColor={st.status === 'done'}>
            {'  '}
            {mark(st.status)} {st.name}
          </Text>
        ))}
        <Text bold>agents</Text>
        <Text>
          {'  '}lead · {k(tokens)}
          {percent !== undefined ? ` (${percent}%)` : ''}
        </Text>
        {(s.agents ?? []).map(a => (
          <Text key={a.name} dimColor={a.status === 'done' || a.status === 'lost'}>
            {'  '}
            {a.name} · {a.role ?? '?'} · {a.runner ?? ''}
            {a.model ? `-${a.model}` : ''} · {a.status ?? '?'}
            {byName.get(a.name)?.ctx ? ` · ${k(byName.get(a.name)?.ctx)}` : ''}
          </Text>
        ))}
        {extra.map(a => (
          <Text key={a.id} dimColor>
            {'  '}
            {a.name} · {a.status} · {k(a.ctx)} (not in state)
          </Text>
        ))}
        <Text bold>links</Text>
        {(s.links ?? []).map(l =>
          l.url ? (
            <Text key={l.label}>
              {'  '}
              <Link href={l.url} label={l.label} />
            </Text>
          ) : (
            <Text key={l.label} dimColor>
              {'  '}
              {l.label}: {l.path ?? ''}
            </Text>
          ),
        )}
        {warn ? (
          <Text color="red">
            context {k(tokens)} is past {k(s.contextWarnTokens)}: write a handoff with /moot:handoff and start a fresh session
          </Text>
        ) : null}
        <Text dimColor>updated {s.updatedAt ?? 'never'}</Text>
      </Box>
    )
  })
}
