export type Stage = { name: string; status: string }

export type Task = {
  id: string
  order: number
  title: string
  branch?: string
  pr?: number | null
  stages: Stage[]
}

export type StateAgent = {
  name: string
  role?: string
  runner?: string
  model?: string
  status?: string
}

export type LinkRow = { label: string; url?: string; path?: string }

export type MootState = {
  id: string
  kind: string
  title: string
  ceremony: string
  phase: string
  gates: Record<string, string | null>
  council: { status: string; round: number; contested: number; members: string[] }
  spec: { status: string; judgeRounds: number }
  plan: { status: string; judgeRounds: number }
  tasks: Task[]
  agents: StateAgent[]
  links: LinkRow[]
  worktree: string | null
  contextWarnTokens: number
  updatedAt: string | null
}

export type Dash = { state: MootState | null; path: string; error: string; readAt: number }

export type LiveAgent = { id: string; name: string; ctx: number; status: string }

declare module 'claude-code' {
  interface PluginState {
    moot: { dash: Dash; live: LiveAgent[] }
  }
}
