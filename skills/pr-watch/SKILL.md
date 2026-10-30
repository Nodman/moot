---
name: pr-watch
description: Use to babysit the open PRs of a moot epic or task until the last one is merged — one pass per call: shows the stack, syncs the worktree with the stack GitHub restacked after a merge, triages new PR comments into a file, runs fix rounds with a scoped review, posts the replies, and closes the work after the last merge. Run it under /loop to keep watching. The human merges and marks PRs ready; this skill resolves only the threads its fixes closed.
---

# /moot:pr-watch

One pass over the chain. Under `/loop /moot:pr-watch` the passes repeat
until the work is closed; see Pacing at the end.

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Run inside the work's
worktree (`state.worktree`). Every write under `.moot/` goes through
`moot-state.sh` or `moot-note.sh`. Load `.moot/gotchas/git.md` when it
exists. Stages are appended to `state.tasks[].stages` the way `/moot:pr`
does it, for example:

```
moot-state.sh jq '(.tasks[] | select(.id == "<id>") | .stages) += [{name: "sync", status: "done"}]'
```

Rules that hold in every pass:

- You never merge, never mark a draft ready, and never edit or delete a
  comment. You resolve a review thread only when a fix closed it.
- The chain is a GitHub stack (`/moot:pr` links it). After a merge GitHub
  rebases the open branches itself and force-pushes them, so the local
  branches go stale; `gh stack sync` follows that. A fix commit goes out
  as a guarded fast-forward push, never forced:
  `git merge-base --is-ancestor origin/<branch> <branch> && git push origin <branch>`.
  A fast-forward cannot clobber GitHub's restack.
- Local branches carry the remote names. A `-fix` suffixed local branch
  is "not part of a stack" to `gh stack view`.
- A comment author is a bot when its login ends in `[bot]` or the API
  reports `user.type` as `Bot`. Bots get replies at once; a human gets a
  reply at once only when the answer is a fix or a fact.

## 1. Status

`moot-state.sh get`, then for every task with a `pr`:

```
gh pr view <n> --json state,isDraft,reviewDecision,mergeable,statusCheckRollup,comments,reviews,headRefOid
```

Show one line per PR in order: id, number, state, draft or ready, review
decision, checks (running, green, red), and how many comments are newer
than the top line of `tasks/<id>/comments.md` (none yet: all of them).
Then, on the lowest open branch (a detached HEAD makes the view fail
with "not on any branch"), `gh stack view --short` and show it. When it
fails because the stack is not tracked here yet: `gh stack checkout
<number of the lowest open PR>` once, which pulls the stack from GitHub,
then view again. A work with a
single PR has no stack; skip the stack lines and step 2.

## 2. Sync

Run `gh stack sync` with a clean tree, on the lowest open branch, when a
PR is MERGED and a task after it is still open. Not after a fix round,
and not because the view marks a branch as needing a rebase: report that
and leave the Rebase stack button to the human at merge time. Sync
fetches, follows the rebase GitHub did after the merge, cascades the open
branches onto their parents, and pushes them with lease. Then:

- Synced: append stage `merged` to each task whose PR is MERGED and has
  no such stage yet, and `sync` to each branch it rebased.
- "could not determine the previous base of <branch> after <main>
  changed; rebase this branch manually": the main branch moved under the
  lowest open branch, which is normal a day after a rebase. Nothing was
  pushed and nothing is needed; the PR stays mergeable. Do not run `gh
  stack rebase` on an approved PR: it force-pushes, restarts CI, and may
  dismiss approvals before a cut.
- Divergence, which aborts the sync in a non-interactive terminal: the
  remote is the truth, this worktree holds nothing unpushed between
  passes. `git fetch origin`, then `git reset --hard origin/<branch>` on
  the branch you are on and `git branch -f <branch> origin/<branch>` for
  every other open branch, then sync again. Stay on a branch throughout.
- Conflict: sync restored every branch. Run `gh stack rebase`, resolve
  the conflict yourself in the worktree, `gh stack rebase --continue`,
  then `gh stack sync` again. Run the profile's test, type check, and lint
  commands on each branch you touched, one after another; red goes to an
  executor fix round as in `/moot:pr`, then sync again. A conflict in
  logic you cannot decide stops the pass: show the human the files.

## 3. Comment triage

For every PR with new comments whose checks are finished. A PR with checks
still running is reported as waiting and left for the next pass; bots
comment when their check ends, and a fix pushed now would only cross
them.

Spawn `moot:legwork`, name `legwork-comments-<id>`, model from the legwork
row, background. Brief: the PR number, these commands

```
gh pr view <n> --comments
gh api repos/{owner}/{repo}/pulls/<n>/comments
gh api repos/{owner}/{repo}/pulls/<n>/reviews
gh api graphql -f query='{ repository(owner: "{owner}", name: "{repo}") { pullRequest(number: <n>) { reviewThreads(first: 100) { nodes { id isResolved comments(first: 1) { nodes { databaseId } } } } } } }'
```

and the output command `moot-note.sh file tasks/<id>/comments.md`. The file
starts with the date of the newest comment, then one table: author (with
`bot` after the login when it is one), `path:line` or "PR", comment id,
where it lives (inline, conversation, review), the thread id for an inline
comment (the thread whose first comment has that id; skip resolved
threads), what they ask in one line, kind (fix, nit, question, mistaken),
status (open). When the file exists,
the agent reads it first and keeps every row and status already there.
Read the file, shut the agent down.

## 4. Act

Lowest open PR first. For each PR with open rows:

- fix and nit: one fix round per PR per pass. Stages "fixes after comments
  #n" and "review #n+1". The executor's prompt names the task brief and
  lists the rows as `path:line · what to change`. Verify as in `/moot:pr`,
  commit, then a reviewer round whose base is the commit before the fix,
  so it judges the fix only. Clean: the guarded fast-forward push from the
  rules. Set the rows to `fixed <sha>`, reply on each with one short
  message, "Fixed in <sha>: <what changed, one line>", and when the fix
  closes the thread completely, resolve it. A row the fix answers only in
  part gets the reply and stays open.
- mistaken: check it yourself in the code before anything else. Really
  mistaken and from a bot: reply with the reason, set `declined`. From a
  human: write the reply into `tasks/<id>/replies.md` with the comment id,
  set `waiting`, and tell the human; they post it or say "post". Not
  mistaken after all: treat as a fix row.
- question: answer from the code, post it, set `answered`. An answer that
  needs a decision from the human goes to `replies.md` as above.
- A row already `fixed` whose author asks the same thing at the same place
  again: set `repeat`, no second fix round, show the human.

Posting: an inline review comment gets
`gh api repos/{owner}/{repo}/pulls/<n>/comments/<id>/replies -f body=...`;
a conversation comment or a review summary gets `gh pr comment <n> --body
...`. Resolving an inline thread:

```
gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<thread id>"}) { thread { isResolved } } }'
```

Only inline threads can be resolved; a conversation comment just gets
the reply. Update `comments.md` through `moot-note.sh file` with the new
statuses.

## 5. Report

End every pass with one line per PR: what this pass did on it, and what
it waits on (checks, a reviewer, the human's merge, a drafted reply, a
conflict). A PR that is approved, green, not draft, with no open rows is
reported as "ready to merge: #<n>". The human merges.

## 6. Close

When every PR is MERGED: set `phase: merged`, write a handoff with
`/moot:handoff`, and tell the human that the worktree can be removed now
(ExitWorktree, or `git worktree remove` from the main checkout) and that
`.moot/work/<id>/` stays as the record.

## Pacing

Under `/loop`, schedule the next pass with ScheduleWakeup: about 10
minutes while checks run on any PR or a fix just pushed, 20 to 30 minutes
when everything waits on humans. Stop the loop at Close, or when a pass
ends in a stop only the human can clear (a conflict, two red verifies,
a blocking review after two fix rounds); say what to do, the human runs
`/loop /moot:pr-watch` again after.
