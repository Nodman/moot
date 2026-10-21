---
name: council
description: Use to run the moot design council on the current epic — independent proposals, one swap-and-judge round, then the lead decides the open points with the human, writes one verdict file and asks for the first human GO. Extra rounds only when the human asks. Heavy and multi-model; run it only when the human asks for it or /moot:epic reaches the council phase.
---

# /moot:council

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. All files of this phase
go under `council/` in the work dir, written with `moot-note.sh file
council/<name>`; the state changes go through `moot-state.sh`. Members
research and argue; nobody edits the repo. You, the lead, never propose a
design yourself: you frame, relay, tally, and write the verdict.

## 1. Members

Read `.moot/roles.md`. The members are the rows with role `council`; each
member is named `<runner>-<model>` and keeps that name in agent names, file
names, and every mention to the human. Refuse a model from the banned list.

For codex rows run `setup.sh check`; when it reports codex missing or
hanging, drop those rows and tell the human once. With one member left the
council is a deep brainstorm: say so now, and again in the verdict.

Preconditions: `moot-state.sh get` shows the work, `factpack.md` exists, and
`assets/` holds what intake collected (it may be empty; say so).

## 2. Frame

Short Q&A with the human until the design question is one paragraph with
success criteria. Locked product decisions are listed as such, so members
attack the design, not the decisions.

Write `council/brief.md`, identical for every member:

- the question and the success criteria
- the locked decisions
- the ticket ids with one line each; the factpack holds the digest
- repo root, the absolute path of `factpack.md`, the absolute path of
  `assets/` with one line per file in it
- pointers to the repo's own rules from `.moot/repo.md`
- "Round 1: follow the proposal format in your charter."

Then update the state: `phase: council`, `council.status: running`,
`council.round: 1`, `council.members: [names]`.

## 3. Round 1, proposals

Report path per member: `council/r1-<name>.md`. Spawn all members in the
same response.

Claude member: Agent tool, `subagent_type: moot:council-member`, `name:
<name>`, `model:` from the row, run in the background. Prompt: "Council
round 1. Read your charter's round 1 format. Brief: <absolute brief path>.
Write your report to <absolute report path>." Add the agent to
`state.agents[]` with `role: council`, `runner`, `model`, `status: running`,
`startedAt`, `report`.

Codex member: write `council/r1-<name>-prompt.md` with the brief plus
"Round 1. Your final message is your report." Then:

```
codex-run.sh run --name <name> --model <model> --effort <effort> \
  --prompt <prompt path> --out <report path> \
  --charter ${CLAUDE_PLUGIN_ROOT}/agents/council-member.md \
  --workdir <repo root> [--image <asset> for every image in assets/]
```

Every path is absolute. It prints the session id and the tmux pane. Tell
the human the session id right away. The pane shows the live run (commands,
searches, messages, errors) and closes a few seconds after the run ends;
without tmux the run is a background process. Record `codexSessionId` and
`pane` on the agent entry, for example:

```
moot-state.sh jq '.agents += [{name: "codex-gpt", role: "council", runner: "codex", model: "gpt",
  status: "running", startedAt: "<now>", endedAt: null, codexSessionId: "<id>", pane: "<pane>",
  report: "council/r1-codex-gpt.md"}]'
```

Wait. Claude members come back as task notifications. For each codex
member run `codex-run.sh wait <report> --timeout 1800` as a background
Bash call; its result arrives as a notification the same way. On `dead` or
`timeout`: `codex-run.sh kill <report>`, mark the agent `lost`, drop the
member, tell the human. A codex report with exit code 97 is empty, and a
Claude member that returns without its report file is lost: treat both
the same.

Read every report with Read. Mark the agent `done` on the entry but keep it
alive; it has another round. When a report has "Questions for the human",
ask them now and put the answers into the round 2 prompt.

## 4. Round 2, swap and judge

For each member write `council/r2-<name>-prompt.md`: "Round 2. Follow the
round 2 format in your charter. Below are the other members' round 1
reports, verbatim. This is the last round unless the human asks for
another." followed by every other report under a heading with its author's
name, plus any human answers from round 1. Report path:
`council/r2-<name>.md`.

Claude member: SendMessage to the named agent: "Round 2. Read <prompt path>
and write your report to <report path>." Codex member: `codex-run.sh run
--resume <codexSessionId>` with the same name, model, effort, the new prompt
and the new out path; no charter, the session has it. Wait and read as in
round 1. Update `council.round: 2`.

Deep brainstorm (one member): the round 2 prompt is instead "Attack your own
round 1 proposal as a second member would: list what you would agree with,
disagree with, or replace by a third option, then write the round 2
sections against yourself."

## 5. Decide

Tally every point from the round 2 reports into `council/tally.md`: one
row per point, merged where two members name the same point, with each
member's stance (agreed, disagreed, third option) and the evidence. Then
sort the rows:

- Settled: every member agrees. No decision needed.
- Lead-decided: the evidence on one side clearly wins. You decide and write
  why; the human can override it in the verdict.
- Human-decided: the evidence is balanced, or the members swapped sides on
  it. Ask the human now, one AskUserQuestion per point with each position
  as an option. The answer is settled with source "human".

Set `council.contested` to the number of lead-decided plus human-decided
points. No further member round runs by default.

Extra round, only when the human asks for one and names the points: write
`council/contested-r<N>.md` with those points and every position, send it
to every member as "Round N. For each point pick a side or a third option
with evidence, and say whether your view changed.", reports to
`council/r<N>-<name>.md`, then redo the tally for those points. Stop when
no member changed a view.

## 6. Verdict

Write `council/verdict.md` from `${CLAUDE_PLUGIN_ROOT}/templates/verdict.md`.
Settled points go into the settled table, human answers included with
"human" as who argued it. Lead-decided points go into the lead-decided table
with written reasoning, so the human can override each one. Keep the human
override section on top and empty. Add a "Verdict" link with `path:
council/verdict.md`, set `council.status: done`. No review page is
published for the verdict.

Shut down every Claude member now (none is messaged again); mark every
agent `done` with `endedAt`. Codex sessions keep their ids in the state.

## 7. GO 1

Show the human the TL;DR and the lead-decided table. Ask in these words:
"GO for the council verdict?" and wait. Only a literal GO passes. When the
human edits the override section first, read the file again before
continuing. When the human asks for an extra round on named points instead,
run it as in step 5, update the verdict, and ask again. On GO:
`gates.council: <now>`, `phase: spec`.
