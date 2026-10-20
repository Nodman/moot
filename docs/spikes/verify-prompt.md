# Verification review of the moot plugin design

You are a red-team reviewer. Your only question: **what in this design will not work as written?**
Not taste, not proposals, not style. Only claims that are false, APIs that do not exist or behave
differently, and sequences that cannot run. Every finding needs evidence: a doc URL, a file path and
line in the sources below, or a command you ran. No finding without evidence.

## Inputs

- The design page (HTML, read it fully): `/private/tmp/claude-502/-Users-dmytro-burmistrov-repos-apollo-mobile/d5c26a8e-3aea-40b8-ad09-eae3aade35b4/scratchpad/moot-design.html`
- Claude Code mod type definitions (ground truth for the mod API): `/private/tmp/claude-502/-Users-dmytro-burmistrov-repos-apollo-mobile/d5c26a8e-3aea-40b8-ad09-eae3aade35b4/scratchpad/cc-types/claude-code.d.ts`
- A working reference mod (flightdeck): `/private/tmp/claude-502/-Users-dmytro-burmistrov-repos-apollo-mobile/d5c26a8e-3aea-40b8-ad09-eae3aade35b4/scratchpad/flightdeck-src/hooks/register.tsx`
- The previous workflow plugin this replaces (conveyor), useful for how plugins, hooks and codex runs are wired: `/Users/dmytro.burmistrov/.claude/plugins/cache/conveyor-marketplace/conveyor/0.1.39/`
- Claude Code docs online: https://docs.claude.com/en/docs/claude-code/ (hooks, plugins, mods, settings). Codex CLI docs: https://github.com/openai/codex . Use web search when a claim is about documented behaviour.
- Installed versions: Claude Code 2.1.303, Codex CLI 0.163.0, tmux present.

## Claims to check first (then anything else you find)

1. Mods: a plugin `hooks/hooks.json` with `{"modules": ["./register.tsx"]}` loads a module whose `register(on, options)` can subscribe to `turn.step` and get per-subagent token usage through `e.agentId`; `$.fs.read` can read a JSON file under the session cwd; `$.state` writes redraw a `Pane`; `$.clock.every` exists; the pane docks at 110+ columns and self-opens at 144+.
2. Settings hooks: a `PreCompact` hook can block compaction (exit code 2 or JSON decision) and show a message to the model; it cannot inject context. `SessionStart` on resume gets `context_tokens`. A plugin can ship these hooks in `hooks/hooks.json` next to the `modules` key.
3. Codex: `codex exec -m <model> -c tools.web_search=true -c model_reasoning_effort=high -s read-only --json -i <png> -o <report> - < prompt` emits a `thread.started` event with the session id; `codex resume <id>` attaches a TUI to that session in another terminal while the headless run is still going; `codex exec resume <id>` continues the session headless for a later round.
4. Claude Code built-in worktrees (EnterWorktree tool, WorktreeCreate hook) can be used by a plugin skill instead of the plugin's own git worktree scripts.
5. A skill can publish an HTML page with the Artifact tool and comments on it come back to the session.
6. Per-subagent "resume by name" (SendMessage to a named agent) keeps the subagent's context across council rounds.
7. Anything in the state file shape, the stage list, or the stacked-PR + chain rebase story that cannot work with `gh` and git as described.

## Output

Write the report to the path given by `-o` (or print it if none). Format:

```
# Verification report

## Blocking (design cannot work as written)
- <claim> — <what is actually true> — <evidence>

## Wrong detail (works with a change)
- ...

## Could not verify
- <claim> — <what you tried>

## Verified true
- <claim> — <evidence>
```

Be terse. Max 60 lines. Do not restate the design.
