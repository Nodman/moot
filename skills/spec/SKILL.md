---
name: spec
description: Use after the council verdict passed GO 1 — turns the verdict and the human's answers into spec.md, runs the spec judge until it passes, renders and publishes the review page, and asks for GO 2. Nothing is planned or built here.
---

# /moot:spec

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Files go to the work dir
through `moot-note.sh file <name>`; the state through `moot-state.sh`. You
write the spec, the judge scores it, the human approves it.

## 1. Inputs

`moot-state.sh get` must show `gates.council` set. Read `council/verdict.md`
in full, the human override section first: anything there beats the verdict
body. Read `factpack.md` and list `assets/`. Set `spec.status: running`,
`phase: spec`.

## 2. Questions

Ask the human only about the open points the verdict left for them and
anything the override made unclear. One question at a time, AskUserQuestion
with options when they exist. Stop when the answers stop changing the
design. The design itself is not reopened here; that was the council.

## 3. Write

Write `spec.md` from `${CLAUDE_PLUGIN_ROOT}/templates/spec.md`. Keep every
section and its name; the renderer and the judge depend on them. Bullets
over prose. The Decisions table holds the settled points, the lead-decided
points, and the human's answers, each with its source. Requirements are
numbered and each one is checkable. Tests are one-line behaviours, no test
code. A design frame is shown, not named: `![<what it shows>](assets/<file>)`
on its own line where the behaviour is described; the renderer embeds it
in the page. Before the judge, read the spec again as the judge would: template
text left in, placeholders, contradictions, two-way readings, verdict points
dropped silently.

## 4. Judge

Spawn `moot:spec-judge` with the model from the judge row of
`.moot/roles.md`, name `spec-judge`, in the background. Prompt: the
absolute paths of the spec, the verdict, the factpack, the assets folder,
and the output file `spec-judge-1.md` in the work dir. Add it to
`state.agents[]`. Read the findings file.

On `fail`: fix every finding in `spec.md`, bump `spec.judgeRounds`, and
SendMessage the same judge: "Round <n>. The spec changed. Re-read it in
full and score it against every criterion again, not only your earlier
findings. Output: <work dir>/spec-judge-<n>.md." One judge per spec keeps
its reads cached; a fresh one would pay for them again. When you believe
a finding is wrong, say so to the human instead of ignoring it. After
three fails stop and show the human the open findings.

On `pass`, or when you stop: shut the judge down, mark it done.

## 5. Page

```
render-page.sh <work dir>/spec.md --eyebrow "Spec · <ID> · judge passed in <n> rounds"
```

When `pages` in `.moot/config.json` is `artifact`, publish `spec.html` with
the Artifact tool: icon `document`, description one sentence. Store the
link in the state as `{label: "Spec page", url: <url>, path: "spec.html"}`.
If the publish result does not say this session watches the page, call
ArtifactComments with action `watch`. Any other `pages` value: store the
path only.

## 6. GO 2

Show the human the TL;DR and the open questions, with the page link. Ask in
these words: "GO for the spec?" and wait. Only a literal GO passes.
Comments sent to Claude from the page, and answers in the chat, are
feedback: fold them into `spec.md`, run the judge once more if the change
is more than wording, re-render, publish to the same url, and ask again.

On GO: `gates.spec: <now>`, `spec.status: approved`, `phase: plan`, and
stop watching the page (ArtifactComments `watch` with `on: false`): the
spec is locked, later comments are not feedback. Next is `/moot:plan`.
