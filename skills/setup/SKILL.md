---
name: setup
description: Use to install moot into the current repository — creates the git-ignored .moot/ folder with config, roles, gotchas index, and a repo profile written by an inspection agent. Interactive; safe to re-run.
---

# /moot:setup

Run from the repository's main checkout, not from a worktree. Scripts live in
`${CLAUDE_PLUGIN_ROOT}/scripts/`. Never overwrite a file that already exists
under `.moot/` unless the user asks for it in this session.

## 1. Preflight

Run `setup.sh check`. It prints one line per tool. Rules:

- `git` main checkout required. If it reports a worktree, stop and tell the
  user to run setup from the main checkout.
- `gh` required and authenticated. Missing → tell the user how to install and
  log in, then stop.
- `jq` required.
- `codex` and `tmux` optional. Missing → say once that council rows with the
  codex runner stay dormant until it is installed. If `codex` prints
  `hangs`, show the user the path of the working copy the script found, if
  any, and suggest the quarantine fix it prints.
- `claude` below the version the script names → the dashboard mod will not
  load; everything else works. Say so once.

## 2. Ignore question

`.moot/` is never committed. Ask with AskUserQuestion, one question, two
options, and recommend the first:

- "This repo only" → `setup.sh ignore local` (appends to `.git/info/exclude`).
- "All my repos" → `setup.sh ignore global` (appends to the global excludes
  file; the script creates `~/.gitignore` and sets `core.excludesfile` only
  when no global file is configured, and says so).

Skip the question when `setup.sh check` reports `.moot/` as already ignored.

## 3. Scaffold

`setup.sh scaffold` creates `.moot/`, `.moot/gotchas/`, `.moot/work/` and
seeds `config.json`, `roles.md` and `gotchas/index.md` from the plugin
templates when they are absent. It prints what it created and what it skipped.

## 4. Repo profile

Spawn the `moot:legwork` agent (model from the legwork row of
`.moot/roles.md`; pass it explicitly) with this brief:

- Output path: `.moot/repo.md`. Template: `${CLAUDE_PLUGIN_ROOT}/templates/repo.md`.
- Fill every section from evidence in the repo: package manifests, lockfiles,
  CI config, Makefiles or task runners, README, contributor docs, PR
  template, instructions files (CLAUDE.md, AGENTS.md, `.cursor/rules`),
  existing skills under `.claude/skills` and `.agents/skills`, git config and
  remotes, branch protection if `gh` can read it.
- Write `unknown` where the repo gives no evidence. Never guess a command.
- Reply with one line: `written + N lines`.

If `.moot/repo.md` already exists, ask the user whether to refresh it before
spawning. On refresh, the agent reads the old file first and keeps every
human edit it cannot contradict with evidence.

## 5. Seed config from the profile

Read `.moot/repo.md` and update `.moot/config.json` with the facts it holds:
`mainBranch`, `merge`, `ticketPrefix`, `worktree.setup`, `evidence.capture`,
and `tracker` (set to `repo` when the profile names all three tracker
operations, otherwise leave `none`). Keep every other key as it is. Show the
user the resulting file.

## 6. Roles

Show `.moot/roles.md`. When the preflight found no `codex`, say that the
codex council row will be skipped until it is installed; do not delete the row.
Ask nothing else; the user edits the table by hand later.

## 7. Finish

Open `.moot/repo.md` for the user to review (print its path and the sections
marked `unknown`). Then print the next steps:

- `/moot:epic` for an epic with council, spec, plan and stacked PRs.
- `/moot:task` for a single ticket or fix.
- `/moot:dash` for the dashboard pane.

Re-running setup is safe: existing files are kept, the ignore step is
skipped when already done, and only the profile asks before a refresh.
