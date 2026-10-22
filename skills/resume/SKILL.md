---
name: resume
description: Use at the start of a session that continues moot work — reads the state and the latest handoff in full, reconciles stale agents, re-watches review pages, and confirms the next action with the human before anything runs.
---

# /moot:resume

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. The session start hook
already injected the START HERE section; this skill reads the rest.

1. `moot-state.sh current <ID>` with the id the human named, else the one
   the hook reported: this binds the work to this session, so parallel
   sessions in one checkout never read each other's state. Then
   `moot-state.sh get` and read the file named by the "Latest handoff"
   link in full with Read. If there is no handoff, say so and read
   `factpack.md`, `spec.md` or `plan.md`, whichever the phase points at.
2. Agents listed as `running` in the state are gone with the old session.
   Mark them `lost` with `moot-state.sh jq` and say which reports exist on
   disk and which do not. Codex agents keep their session id; a later round
   can resume them, do not mark those lost.
3. When a GO is open, call ArtifactComments with action `watch` on that
   page's url, so comments sent to Claude reach this session again, then
   read its comments once and list the unresolved threads. Pages whose gate
   has passed are locked and are not watched.
4. If the hook or the handoff reports context above the threshold, stop here
   and tell the human to start a fresh session.
5. Say the next action and the open GO in two lines and wait. Nothing runs
   before the human answers, even when the handoff says the GO was given: a
   GO belongs to the session it was given in.
