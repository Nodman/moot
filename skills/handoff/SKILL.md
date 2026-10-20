---
name: handoff
description: Use to write a moot handoff — at session end, when the dashboard's context warning fires, before /clear, or whenever the human asks. Writes a timestamped file, updates the state links, and shuts down finished agents.
---

# /moot:handoff

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. The handoff is the only
thing the next session reads first, so write it for someone with no memory of
this session.

1. Read the current state: `moot-state.sh get`. Bring the state up to date
   first if anything happened that it does not show (`moot-state.sh merge`).
2. Compose the handoff from `${CLAUDE_PLUGIN_ROOT}/templates/handoff.md`.
   The START HERE section is what the session start hook injects, so it must
   stand alone: next action as one sentence, the open GO, phase line, links
   copied from the state, agents still alive, worktree path.
3. Write it: pipe the markdown to `moot-note.sh handoff`. It stamps the file
   name and points the "Latest handoff" link at it. Print the path.
4. Shut down every agent you will not message again. Mark them in the state
   (`status: done` or `lost`) with `moot-state.sh jq`.
5. If you are writing this because of the context warning, say so and
   recommend a fresh session. Do not keep working after the handoff.

Older handoffs stay as history; never edit or delete them.
