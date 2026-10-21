---
name: task
description: Use for a single ticket or fix under light ceremony — a research brief by legwork, a one-PR plan by the lead, one literal GO, then the same PR stages as an epic. No council, no spec, no judge.
---

# /moot:task

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Run from the main
checkout. Every write under `.moot/` goes through `moot-state.sh` or
`moot-note.sh`.

## 1. Start

Ask for the ticket id (or a short slug) and a title, then `moot-state.sh
init <ID> --kind task --ceremony light --title "<title>"`. Fetch and
read the ticket the way `/moot:epic` does at intake (its id in
`state.tickets`, a digest for the brief, no copy on disk), collect any
screenshot or design into `assets/`, and write `assets/index.md`.

## 2. Research

Spawn `moot:legwork` with the model from the legwork row, name
`legwork-<ID>`, background. Brief: the ticket digest, the assets folder,
output `research.md`, template
`${CLAUDE_PLUGIN_ROOT}/templates/factpack.md`, repo rules from
`.moot/repo.md`. Read the file, shut the agent down, ask the human the
questions it left.

## 3. Plan

Write `plan.md` from `${CLAUDE_PLUGIN_ROOT}/templates/plan.md` with one PR:
branch from the ticket prefix and the id, base the main branch, exact
files, interfaces, one-line test behaviours, the brief notes. One page.
When the fix honestly needs more than one PR, say so and switch to
`/moot:epic` instead. No judge in light ceremony: read it once as the plan
judge would, then render it:

```
render-page.sh <work dir>/plan.md --eyebrow "Plan · <ID> · 1 PR"
```

Publish and link it as `/moot:plan` does when `pages` is `artifact`.

## 4. GO

Show the PR row and ask in these words: "GO for the plan?" and wait. Only a
literal GO passes. On GO: `gates.plan: <now>`, `plan.status: approved`,
`phase: execute`, and one entry in `state.tasks[]` with the ticket id,
plus `tasks/<ID>/plan-excerpt.md`.

## 5. Execute

Worktree as in `/moot:epic`, then `/moot:pr` for the one task. Its GO is
not asked again: the plan GO covers a single PR. After the draft PR set
`phase: done` and write a handoff.
