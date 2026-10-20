import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

// Throwaway spike for moot. Proves three things:
// 1. a pane can read a JSON state file through $.fs.read and redraw when an atom changes
// 2. per-subagent context is available from turn.step usage via e.agentId
// 3. a tool.call hook can see Write/Edit targets and re-read the file

const PANE = 'mootspike'
const STATE_PATH = '.moot/state.json'

type AgentRow = { id: string; type: string; model: string; ctx: number; out: number; steps: number; status: string }

const fileState = atom({ plugin: 'mootspike', key: 'file' } as const, { text: '', error: '', readAt: 0, reads: 0 })
const agents = atom({ plugin: 'mootspike', key: 'agents' } as const, [] as AgentRow[])

async function reload($: EngineInterface) {
  const at = await $.clock.now()
  try {
    const text = await $.fs.read(STATE_PATH)
    await update($, fileState, s => ({ text, error: '', readAt: at, reads: (s?.reads ?? 0) + 1 }))
  } catch (err) {
    await update($, fileState, s => ({ ...(s ?? { text: '', readAt: 0, reads: 0 }), error: String(err), readAt: at }))
  }
}

function openPane($: EngineInterface) {
  return $.ui.open({ id: PANE, title: 'moot spike', columns: 60, rows: 8 })
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'mootspike',
      description: 'moot spike pane: open, close, reload',
      argumentHint: '[open|close|reload]',
    })
    await reload($)
    void openPane($).catch(() => undefined)
    return next(e)
  })

  on('command.run', { command: 'mootspike' }, async ($, e) => {
    const verb = e.args.trim() || 'open'
    if (verb === 'close') {
      await $.ui.close({ id: PANE })
      return { text: 'spike closed' }
    }
    if (verb === 'reload') {
      await reload($)
      return { text: 'spike reloaded' }
    }
    const o = await openPane($)
    return { text: o.isPlaced ? 'spike opened' : `spike not placed: ${o.reason}` }
  })

  on('agent.spawn', async ($, e, next) => {
    const started = await next(e)
    if (started.deny !== undefined || !started.agentId) return started
    const row: AgentRow = { id: started.agentId, type: e.name ?? e.subagentType, model: started.model, ctx: 0, out: 0, steps: 0, status: 'running' }
    await update($, agents, list => [...(list ?? []), row].slice(-10))
    return started
  })

  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    const u = result.usage
    if (e.agentId && u) {
      const ctx = u.input_tokens + u.cache_read_input_tokens + u.cache_creation_input_tokens
      await update($, agents, list => (list ?? []).map(a => (a.id === e.agentId ? { ...a, ctx, out: a.out + u.output_tokens, steps: a.steps + 1 } : a)))
    }
    return result
  })

  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    if (e.agentId) await update($, agents, list => (list ?? []).map(a => (a.id === e.agentId ? { ...a, status: `done:${e.reason}` } : a)))
    return r
  })

  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    const fp = (e as unknown as { file_path?: string }).file_path
    if ((e.tool === 'Write' || e.tool === 'Edit') && typeof fp === 'string' && fp.endsWith('state.json')) await reload($)
    return ran
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const [f, list] = await Promise.all([read($, fileState), read($, agents)])
    let parsed = ''
    try {
      const j = JSON.parse(f?.text || '{}') as { id?: string; phase?: string }
      parsed = `${j.id ?? '?'} phase=${j.phase ?? '?'}`
    } catch {
      parsed = 'bad json'
    }
    const rows = list ?? []
    return (
      <Box flexDirection="column">
        <Text>
          state: {parsed} reads={f?.reads ?? 0} {f?.error ? `err=${f.error}` : ''}
        </Text>
        <Text>
          cols={e.props.bodyColumns} placement={String(e.props.placement)}
        </Text>
        {rows.length === 0 ? <Text>no agents yet</Text> : null}
        {rows.map(a => (
          <Text key={a.id}>
            {a.type} {a.model} ctx={a.ctx} out={a.out} steps={a.steps} {a.status}
          </Text>
        ))}
      </Box>
    )
  })
}
