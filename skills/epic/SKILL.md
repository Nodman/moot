---
name: epic
description: Use to start or continue an epic under full ceremony — intake of tickets, PRD and designs, a factpack, then the council, spec and plan skills with their human gates, then one worktree and the PR loop for every task in plan order. Reads the state and resumes from the current phase.
---

# /moot:epic

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Run from the main
checkout. Every write under `.moot/` goes through `moot-state.sh` or
`moot-note.sh`. The phase in the state decides where this skill starts; a
phase already passed is never repeated.

## intake

New epic: ask for the id (the tracker's epic id, or a short slug) and a
title, then `moot-state.sh init <ID> --kind epic --ceremony full --title
"<title>"`. Existing work: `moot-state.sh current <ID>` and `/moot:resume`.

Tickets: ask which tickets belong to the epic. None yet is normal; they
are created after the plan is approved. For each id named, fetch the ticket
now and read it: `tracker` `github` → `gh issue view <n> --json
title,body,comments`; `repo` → the fetch command from `.moot/repo.md`;
`none` → the human pastes the text. Keep nothing of it on disk except the
ids: `moot-state.sh jq '.tickets = ["<id>", ...]'`. Tickets change, so a
copy would go stale; what the work needs from them goes into the brief as
a digest, one paragraph per ticket: what it asks, acceptance criteria,
anything its comments settle. Anyone who later needs more than the digest
fetches the ticket again.

Collect into `assets/` everything else a human would look at, through
Bash (`cp`, `curl -o`): PRD, design exports, screenshots, recordings, from
paths or urls the human gives.

Design links: you grab the screenshots, the human does not export by
hand. Use whatever the design tool offers in this session, an MCP server
or a CLI, to render each frame to a PNG and put it in `assets/<tool>-<frame
name>.png`; a tool that returns an url is followed by `curl -o` at once,
such urls expire. A link to a whole file or page: list its frames with the
tool and ask the human which ones matter. Without a connected tool, ask
the human for exported PNGs. Members and judges only see files in
`assets/`, never the design tool.

Figma, as the example: `create_session` with the file key, `get_screenshot`
per frame link (`node-id` in the url) in its default mode, which returns a
short-lived url, then `curl -o`; `get_metadata` lists the frames of a link
without `node-id`.

Write `assets/index.md`: one line per file with where it came from, for a
design frame its url, so anyone can fetch it again. Say when the folder is
empty. The phase stays `intake` until the factpack is read.

## factpack

Spawn `moot:legwork` with the model from the legwork row, name `legwork-
factpack`, background. Brief: the question or epic in one paragraph, the
ticket digest from intake, the assets folder, the output path
`factpack.md`, the template
`${CLAUDE_PLUGIN_ROOT}/templates/factpack.md`, and the repo rules from
`.moot/repo.md`. Read the file, shut the agent down, ask the human the
questions it left. Set `phase: council`.

## council, spec, plan

Run `/moot:council`, then `/moot:spec`, then `/moot:plan`. Each ends with
its own literal GO and sets the next phase. Nothing here is skipped or
shortened for an epic.

## execute

Once per epic, when `worktree.enabled` in `.moot/config.json` is true:
EnterWorktree with the name `<id in lower case>`. The session is now in
`.claude/worktrees/<name>` on branch `worktree-<name>`. Run the profile's
`worktree.setup` command there. Store the absolute path in
`state.worktree`. When the state already names a worktree, EnterWorktree
with that `path` instead. Worktrees off: stay in the main checkout and
say so.

Then for every task in `state.tasks[]` in `order`, run `/moot:pr`. Between
tasks: when `goPerPr` is true the next task waits for its GO; when false
the chain runs until a stop. After the last draft PR set `phase: done`,
write a handoff with `/moot:handoff`, and tell the human the list of PR
urls in merge order and that the worktree stays until the chain is merged.

The human merges. After each merge the remaining chain needs a rebase
onto the main branch before the next PR is reviewed; `/moot:merge` does
that, triages the PR comments, and closes the work after the last merge.
