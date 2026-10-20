# Brief: <task id> <title>

- Work: <work id> · PR <order> of <total> · Branch: `<branch>` · Base: `<base>`
- Worktree: <absolute path>
- Report: run `<absolute path to moot-note.sh> file tasks/<task id>/executor-report.md` with the report on stdin. Never use Write for the report.

## Scope

<What this PR changes and what it leaves to later PRs, from the plan. One paragraph.>

## Files

| file | change |
|---|---|
| `<exact path>` | <create · modify · delete: what> |

## Interfaces

- <Exact names and signatures produced for later PRs or consumed from earlier ones.>

## Test behaviours

- <One line each, in the order to implement them. "TDD n/a: reason" where it applies.>

## Commands

- test: `<from the repo profile>`
- type check: `<...>`
- lint: `<...>`
- after checkout: `<...>`

## Repo rules

- <Instruction files to read first, with paths.>
- <Test style rules, with paths.>
- Gotcha topics: <names, files under .moot/gotchas/>

## Design

- <Asset path to compare against, or "none".>

## Constraints

- <Exact values from the spec's Decisions table that this PR must respect.>
