# moot

A Claude Code plugin for bigger engineering tasks. Debate the design first
with a multi-model council, pass human gates for council, spec and plan, then
ship small stacked PRs with review and evidence.

Design: `docs/design.html`.

## Install

Development, from a checkout:

```
claude --plugin-dir ~/repos/moot
```

Then in a repository:

```
/moot:setup
```

Setup creates a git-ignored `.moot/` folder with the config, the roles table,
a gotchas index, and a repo profile written by an inspection agent.

## Commands

- `/moot:epic`, `/moot:task`: start or continue work under full or light ceremony.
- `/moot:council`, `/moot:spec`, `/moot:plan`, `/moot:pr`: the phases, run by the two above.
- `/moot:merge`: while the human merges — PR comment triage, fix rounds, chain restack after each merge.
- `/moot:resume`, `/moot:handoff`: session start and session end.
- `/moot-dash [open|close|reload]`: the dashboard pane. It opens by itself when the repo has current moot work.
