# Roles

The lead reads this table before every spawn and passes runner, model and
effort explicitly. Edit by hand. One row per role; the council has one row
per member. `runner` is `claude` (Agent tool) or `codex` (headless CLI).
`model` is what the runner accepts: `fable`, `opus`, `sonnet` for claude; a
codex model name for codex. `effort` is `low`, `medium`, `high`.

| role | runner | model | effort | does | never |
|---|---|---|---|---|---|
| council | claude | fable | high | proposes and argues design, read-only | edit files |
| council | codex | gpt-6-astra | high | proposes and argues design, read-only | edit files |
| judge | claude | opus | high | scores a spec or plan against criteria, pass or fail with findings | write the thing it judges |
| executor | claude | opus | high | implements one PR in the worktree, code and tests, reports to a file | open PRs, message other agents |
| reviewer | claude | fable | high | reviews the diff before the PR, compares to design, lists tests to keep, merge or delete | fix code |
| qa | claude | opus | high | runs the app, before and after captures, compares to design | judge design |
| legwork | claude | sonnet | medium | factpack, repo inspection, comment triage, inventories | decisions |
| advisor | claude | fable | high | answers one question from any role, read-only | spawn anything |

The lead is the session itself: it frames, spawns, merges verdicts, writes
spec and plan, commits, and keeps state. It does no big implementation work.

## Banned models

The lead refuses to spawn these even when asked.

- haiku
