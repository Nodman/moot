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
