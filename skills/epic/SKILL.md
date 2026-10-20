---
name: epic
description: Use to start or continue an epic under full ceremony — intake of tickets, PRD and designs, a factpack, then the council, spec and plan skills with their human gates, then one worktree and the PR loop for every task in plan order. Reads the state and resumes from the current phase.
---

# /moot:epic

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Run from the main
checkout. Every write under `.moot/` goes through `moot-state.sh` or
`moot-note.sh`. The phase in the state decides where this skill starts; a
phase already passed is never repeated.

## intake

New epic: ask for the id (the tracker's epic id, or a short slug) and a
title, then `moot-state.sh init <ID> --kind epic --ceremony full --title
"<title>"`. Existing work: `moot-state.sh current <ID>` and `/moot:resume`.

Collect into `assets/` everything a human would look at, through Bash
(`cp`, `curl -o`, `gh`):

- Tickets: `tracker` in `.moot/config.json` is `github` → `gh issue view <n>
  --json title,body,comments` for every ticket the human names, one
  `ticket-<n>.md` each; `repo` → the fetch command from `.moot/repo.md`;
  `none` → ask the human for files or pasted text.
- PRD, design exports, screenshots, recordings: paths or urls from the
  human. A connected design tool exports frames here; the plugin itself
  has no design-tool dependency.

Write `assets/index.md`: one line per file with where it came from. Say
when the folder is empty. The phase stays `intake` until the factpack is
read.

## factpack

Spawn `moot:legwork` with the model from the legwork row, name `legwork-
factpack`, background. Brief: the question or epic in one paragraph, the
assets folder, the output path `factpack.md`, the template
`${CLAUDE_PLUGIN_ROOT}/templates/factpack.md`, and the repo rules from
`.moot/repo.md`. Read the file, shut the agent down, ask the human the
questions it left. Set `phase: council`.

## council, spec, plan

Run `/moot:council`, then `/moot:spec`, then `/moot:plan`. Each ends with
its own literal GO and sets the next phase. Nothing here is skipped or
shortened for an epic.

## execute

Once per epic, when `worktree.enabled` in `.moot/config.json` is true:
EnterWorktree with the name `<id in lower case>`. The session is now in
`.claude/worktrees/<name>` on branch `worktree-<name>`. Run the profile's
`worktree.setup` command there. Store the absolute path in
`state.worktree`. When the state already names a worktree, EnterWorktree
with that `path` instead. Worktrees off: stay in the main checkout and
say so.

Then for every task in `state.tasks[]` in `order`, run `/moot:pr`. Between
tasks: when `goPerPr` is true the next task waits for its GO; when false
the chain runs until a stop. After the last draft PR set `phase: done`,
write a handoff with `/moot:handoff`, and tell the human the list of PR
urls in merge order and that the worktree stays until the chain is merged.

The human merges. After each squash merge the remaining chain needs a
rebase onto the main branch before the next PR is reviewed; `/moot:merge`
does that when it exists, otherwise do it by hand in the worktree.
