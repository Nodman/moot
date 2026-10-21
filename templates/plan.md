# <ID> <title> plan

<One paragraph: what the plan ships, from which spec, how many PRs, how they stack.>

## TL;DR

- <Number of PRs and the order, in one line.>
- <The riskiest PR and why.>
- <What changed since the last version, or "first version".>
- <What needs the human's decision at GO 3, or "nothing".>

## PR list

| order | branch | base | scope | ticket |
|---|---|---|---|---|
| 1 | <ticket-prefix-123-short-name> | <main branch> | <one line> | <existing id · new> |
| 2 | <...> | <branch of PR 1> | <one line> | <...> |

## Existing tickets

| ticket | covered by | or dropped because |
|---|---|---|

<Only when state.tickets is not empty. Every ticket is covered by a PR or dropped with a reason.>

## Global constraints

- <Exact values from the spec that every PR must respect, one line each.>

## PR 1: <title>

- Branch: `<branch>` · Base: `<base>` · Ticket: <id or new>
- Scope: <what this PR changes and what it leaves for later PRs>

### Files

| file | change |
|---|---|
| `<exact path>` | <create · modify · delete: single responsibility> |

### Interfaces

- <Exact names and signatures this PR produces for later PRs or consumes from earlier ones.>

### Tests

- <One line per test behaviour: "fails when X". Name the production change that would make it fail when it is not obvious. "TDD n/a: reason" is allowed. No test code.>

### Brief

<What the executor needs beyond the above: repo rules that apply, gotcha topics, the design or asset to compare against, verification commands from the repo profile.>

## Open questions

- <Only what the human must decide at GO 3. Empty is fine.>
