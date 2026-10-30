---
name: pr
description: Use to run one task through the moot PR stages — GO, brief, implement, verify, review and fixes, evidence, draft PR. Called by /moot:epic for each task in plan order and by /moot:task for its single PR.
---

# /moot:pr

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Files for the task go to
`tasks/<id>/` in the work dir through `moot-note.sh file tasks/<id>/<name>`;
the state through `moot-state.sh`. You sequence, verify, and gate; agents do
the implementation, the review, and the captures. Pass the model from
`.moot/roles.md` on every spawn, shut each agent down right after reading
its report, and read files, never the agent's message.

Stages are rows in `state.tasks[].stages`. Set each one `active` when it
starts and `done` when it ends, for example:

```
moot-state.sh jq '(.tasks[] | select(.id == "<id>") | .stages) |= (map(if .name == "implement" then .status = "done" else . end) + [{name: "verify", status: "active"}])'
```

## GO

Skip when `goPerPr` in `.moot/config.json` is false and the previous task in
this chain reached draft PR. Otherwise show the task's plan excerpt and ask
in these words: "GO for PR <order>, <title>?" and wait. Only a literal GO
passes. On GO set `tasks[].go` to now and the stages list to the default
rows: brief, implement, verify, review #1, evidence, draft PR.

## Branch

Inside the worktree (`state.worktree`; the session is already in it):
`git fetch origin` and `git checkout -b <branch> <base>`, where the base is
`origin/<main branch>` for the first PR of the chain and the previous task's
branch otherwise. When the branch already exists, check it out and say so.

## Brief

Write `tasks/<id>/brief.md` from `${CLAUDE_PLUGIN_ROOT}/templates/brief.md`:
scope, files, interfaces and test behaviours from the plan excerpt;
commands from `.moot/repo.md`; the repo rules and the gotcha topics for the
files it touches; the design asset; the constraints from the spec's
Decisions table. The Report line carries the absolute path of
`moot-note.sh`.

## Implement

Spawn `moot:executor`, name `executor-<id>`, model from the executor row,
background. Prompt: "Implement the brief at <absolute brief path>." Add it
to `state.agents[]` with `report: tasks/<id>/executor-report.md`. Read the
report when it returns. Questions in it: answer them yourself, or ask the
advisor (`moot:advisor`, output `tasks/<id>/advice-<n>.md`) or the human,
then send the answer to the executor with SendMessage and wait again. A
filled "Profile wrong or incomplete" field is appended to `.moot/repo.md`
under Profile feedback now.

## Verify

Read the full diff yourself: `git diff <base>...<branch>` plus the
untracked files. Run the profile's test, type check, and lint commands one
after another, never in parallel. All green: commit on the branch with a
message that names the task id and the title. Anything red: send the
executor the failure as a fix round (stage "fixes after verify"); red a
second time, stop and tell the human.

## Review

Spawn `moot:reviewer`, name `reviewer-<id>`, model from the reviewer
row, background. Prompt: worktree, base, branch, brief path, executor
report path, design asset or evidence report when one exists, repo rules
to load, test command, and the output command for
`tasks/<id>/review-1.md`. Read the findings file.

`blocking`: append stages "fixes after review #n" and "review #n+1". Send
the findings to the same executor with SendMessage (spawn a fresh one when
it is gone), wait, verify again as above, commit, then SendMessage the same
reviewer: "Round <n+1>. The branch changed. Review the whole diff again
against every criterion, not only your earlier findings. Output:
<output command for tasks/<id>/review-<n+1>.md>." One executor and one
reviewer per task keep their reads cached; a fresh one pays for them
again. Two fix rounds without a clean verdict: stop and show the human the
open findings. Tests the reviewer marked delete or merge are part of the
fix round.

`clean`, or when you stop: shut the reviewer down and move on. The
executor stays until the draft PR is open.

## Evidence

Only when the repo profile has a capture command or procedure and the PR
touches UI; otherwise mark the stage done with "n/a: <reason>", say so in
the PR body, and at the first skipped PR of the work tell the human which
profile line would turn it on. Spawn `moot:qa`, name `qa-<id>`, model from
the qa row, background. Prompt: worktree, base, branch, the launch and
capture lines of the profile verbatim, route, design
asset, evidence folder `tasks/<id>/evidence/` (absolute), template path
`${CLAUDE_PLUGIN_ROOT}/templates/evidence-report.md`, and the output command
for `tasks/<id>/evidence/report.md`. Read the report, then render it:

```
render-page.sh <work dir>/tasks/<id>/evidence/report.md --eyebrow "Evidence · <id>"
```

When `pages` is `artifact`, publish `report.html` with the Artifact tool;
the captures are embedded in it. Store
`{label: "Evidence <id>", url, path: "tasks/<id>/evidence/report.html"}` in
the links. Deltas against the design that the human did not approve go back
to the executor as a fix round, then review again.

## Draft PR

Write `tasks/<id>/pr-body.md` from `${CLAUDE_PLUGIN_ROOT}/templates/pr-body.md`.
When the profile names a PR template, fill that template's sections and
append moot's Review block to it. Numbers: tests added and deleted from
the reviewer's last Tests table; test lines and production lines from
`git diff --numstat <base>...<branch>`, counting files whose path contains
`test` or `spec` as test lines.

```
git push -u origin <branch>
gh pr create --draft --base <base branch> --head <branch> --title "<id>: <title>" --body-file <pr-body path>
```

Store the PR number in `tasks[].pr`, add `{label: "PR #<n>", url}` to the
links, mark the stage done. When the chain now has two or more PRs, link
them into a GitHub stack, bottom to top:

```
gh stack link <pr numbers of every task in order>
```

GitHub then restacks the open PRs itself after each merge; `/moot:pr-watch`
follows it. Shut the executor down and mark it done with `endedAt`. When `tracker` is `github` or `repo`, attach the PR link to the
ticket with the profile's command; never edit a ticket the lead did not
create. Tell the human the PR url and the next task.

Stops happen only on a failed verify twice, a blocking review after two fix
rounds, or an agent that needs the human. Everything else runs to the
draft PR.
