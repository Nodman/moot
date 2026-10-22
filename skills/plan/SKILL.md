---
name: plan
description: Use after the spec passed GO 2 — cuts the spec into an ordered list of small stacked PRs in plan.md, runs the plan judge until it passes, renders and publishes the PR-list page, asks for GO 3, then creates the local task records and mirrors them to the tracker when one is configured.
---

# /moot:plan

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Files go to the work dir
through `moot-note.sh file <name>`; the state through `moot-state.sh`. The
plan is an ordered PR list. The reader is an executor with zero context for
this repo, so paths and names are exact.

## 1. Inputs

`moot-state.sh get` must show `gates.spec` set. Read `spec.md`, the
Decisions table first. Read `.moot/repo.md` for the main branch, the ticket
prefix, the merge policy, and the verification commands. The existing
tickets are `state.tickets` with the digest in the factpack; fetch one
again when the digest is not enough. Set `plan.status: running`, `phase:
plan`.

## 2. Cut

Cut the spec by PR size, not by ticket: one PR is one change a human
reviews in one sitting, with its own tests. Order them so each PR builds
on the previous one. PR 1 bases on the main branch; PR n bases on the branch
of PR n-1. Branch names start with the ticket prefix when the repo has one.

When the epic already has tickets: map each PR to one existing ticket or
mark it `new`. A ticket that needs several PRs keeps its id with a branch
suffix (`-a`, `-b`). Every existing ticket is covered or listed as dropped
with a reason; the human sees both lists at GO 3. If the tickets are
already PR-sized, adopt them one to one.

## 3. Write

Write `plan.md` from `${CLAUDE_PLUGIN_ROOT}/templates/plan.md`. Keep every
section name. The PR list table is the page's primary view, so every row
stands alone. Each PR section holds the exact files, the interfaces it
produces or consumes, one-line test behaviours, and the brief notes the
executor will need: repo rules that apply, gotcha topics, the asset to
compare against as `![<what it shows>](assets/<file>)` so the page shows
it, verification commands. No test code, no implementation
code: real code in plans is what makes reviews hard. Before the judge, read
the plan as the judge would: every requirement mapped, no drift in names,
bases correct, nothing too big.

## 4. Judge

Spawn `moot:plan-judge` with the model from the judge row of
`.moot/roles.md`, name `plan-judge`, in the background. Prompt: the
absolute paths of the plan, the spec, the factpack, the assets folder, the
repo profile, and the output file `plan-judge-1.md` in the work dir. Add
it to `state.agents[]`. Read the findings file.

On `fail`: fix every finding, bump `plan.judgeRounds`, and SendMessage the
same judge: "Round <n>. The plan changed. Re-read it in full and score it
against every criterion again, not only your earlier findings. Output:
<work dir>/plan-judge-<n>.md." One judge per plan keeps its reads cached.
After three fails stop and show the human the open findings.

On `pass`, or when you stop: shut the judge down, mark it done.

## 5. Page

```
render-page.sh <work dir>/plan.md --eyebrow "Plan · <ID> · <n> PRs · judge passed in <rounds> rounds"
```

Publish `plan.html` exactly as the spec skill publishes `spec.html`: when
`pages` is `artifact`, Artifact tool with icon `list`, link `{label: "Plan
page", url, path: "plan.html"}`, ArtifactComments `watch` when the publish
result does not confirm it.

## 6. GO 3

Show the human the PR list, the existing tickets table when there is one,
and the open questions, with the page link. Ask in these words: "GO for
the plan?" and wait. Only a literal GO passes. Feedback from the page or
the chat is folded in, judged again when it changes more than wording,
re-rendered, published to the same url, and asked again.

On GO: `gates.plan: <now>`, `plan.status: approved`, `phase: execute`, and
stop watching the page (ArtifactComments `watch` with `on: false`): the
plan is locked, later comments are not feedback.

## 7. Tasks

Tasks are always local records. For every PR, in order, add to
`state.tasks[]`: `{id, order, title, branch, base, pr: null, go: null,
stages: []}` and create `tasks/<id>/` with `moot-note.sh file
tasks/<id>/plan-excerpt.md` holding that PR's section of the plan. The id
is the existing ticket id when the PR maps to one.

For PRs marked `new`, the id depends on `tracker` in `.moot/config.json`:

- `none`: `<ID>-<order>` (for example `PROJ-123-2`).
- `github` or `repo`: show the titles and ask "Create these <n> tickets in
  <tracker>?" and wait; the plan GO does not cover writes to the tracker.
  On yes: `gh issue create` with the PR title and its plan section as the
  body, or the create command the repo profile names; the id is what comes
  back. On no: local ids as for `none`.

Add every created id to `state.tickets`. Never close, edit, or re-title a
ticket you did not create. Show the final
task list and say that execution starts with `/moot:epic` at PR 1, one GO
per PR.
