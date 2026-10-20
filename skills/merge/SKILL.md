---
name: merge
description: Use while the human merges the draft PRs of a moot epic or task — shows the chain's state, triages PR comments into a file, runs fix rounds with a scoped review, restacks the open chain after each merge with chain-rebase.sh, and closes the work after the last merge. The human merges and resolves threads; this skill never does.
---

# /moot:merge

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Run inside the work's
worktree (`state.worktree`). Every write under `.moot/` goes through
`moot-state.sh` or `moot-note.sh`. Load `.moot/gotchas/git.md` when it
exists. Stages are appended to `state.tasks[].stages` the way `/moot:pr`
does it, for example:

```
moot-state.sh jq '(.tasks[] | select(.id == "<id>") | .stages) += [{name: "restack", status: "done"}]'
```

## 1. Status

`moot-state.sh get`, then for every task with a `pr`:

```
gh pr view <n> --json state,reviewDecision,mergeable,statusCheckRollup,comments,reviews
```

Show one line per PR in order: id, number, state, review decision, checks,
and how many comments are newer than the top line of
`tasks/<id>/comments.md` (none yet: all of them). Then run
`chain-rebase.sh --dry-run` and show its output. End with what comes next:
restack, triage, or wait for the human.

## 2. Restack

When the dry run lists a merged PR with open ones after it, ask "Restack
now?" and wait. On yes, run `chain-rebase.sh`. It rebases the open branches
in order, pushes with lease, retargets the first open PR to the main branch,
updates `tasks[].base`, and leaves the worktree on the first open branch.
Append stage `merged` to each task it reported merged and `restack` to each
branch it moved.

A conflict leaves the rebase in progress. Resolve it yourself in the
worktree, `git rebase --continue`, and run the script again; it skips what
is already restacked. Never push by hand between two runs. After a restack
with conflicts, run the profile's test, type check, and lint commands on the
first open branch one after another; red goes to an executor fix round as in
`/moot:pr`, then verify and push again.

## 3. Comment triage

For every PR with new comments, spawn `moot:legwork`, name
`legwork-comments-<id>`, model from the legwork row, background. Brief: the
PR number, these commands

```
gh pr view <n> --comments
gh api repos/{owner}/{repo}/pulls/<n>/comments
gh api repos/{owner}/{repo}/pulls/<n>/reviews
```

and the output command `moot-note.sh file tasks/<id>/comments.md`. The file
starts with the date of the newest comment, then one table: author,
`path:line` or "PR", comment id, what they ask in one line, kind (fix,
question, nit, disagree), status (open). When the file exists, the agent
reads it first and keeps every row and status already there. Read the file,
shut the agent down.

Then act on the open rows:

- fix and nit: one executor fix round. Stages "fixes after comments #n" and
  "review #n+1". The executor's prompt names the task brief and lists the
  rows as `path:line · what to change`. Verify as in `/moot:pr`, commit,
  then a reviewer round whose base is the commit before the fix, so it
  judges the fix only. Clean: `git push` (no force; the branch was not
  rebased). Set the rows to `fixed <sha>`.
- question: draft the answer in `tasks/<id>/replies.md`, one entry per row
  with the comment id. The human posts them, or says "post" and you run
  `gh api repos/{owner}/{repo}/pulls/<n>/comments/<id>/replies -f body=...`
  per entry. Set the rows to `answered`.
- disagree: one line each with your view, then wait for the human. Set the
  rows to what the human decided and treat a "fix it" as a fix row.

You never resolve a review thread, and never edit or delete a comment.
Update `comments.md` through `moot-note.sh file` with the new statuses.

## 4. Close

When `chain-rebase.sh --dry-run` reports every PR merged: set `phase:
merged`, write a handoff with `/moot:handoff`, and tell the human that the
worktree can be removed now (ExitWorktree, or `git worktree remove` from
the main checkout) and that `.moot/work/<id>/` stays as the record.
