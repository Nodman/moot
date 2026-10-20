#!/usr/bin/env bash
# SessionStart: when this repo has current moot work, inject the latest handoff's START HERE
# section, the state summary, the gotchas index, and the GO rule. Silent otherwise.
set -euo pipefail

input="$(cat || true)"
case "$input" in *'"agent_type"'*) printf '{}'; exit 0 ;; esac   # never into subagents

common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
[[ -n "$common" ]] || { printf '{}'; exit 0; }
moot="$(dirname "$common")/.moot"
[[ -f "$moot/current" ]] || { printf '{}'; exit 0; }

find "$moot" -maxdepth 1 -name '.compact-*' -mtime +1 -delete 2>/dev/null || true   # old PreCompact markers

id="$(cat "$moot/current")"
work="$moot/work/$id"
state="$work/state.json"
[[ -f "$state" ]] || { printf '{}'; exit 0; }

summary="$(jq -r '"moot work \(.id) (\(.kind), \(.ceremony)): phase \(.phase) · council \(.council.status) r\(.council.round) · spec \(.spec.status) · plan \(.plan.status) · tasks \([.tasks[]? | select(.stages | length > 0 and all(.status == "done"))] | length)/\(.tasks | length) · updated \(.updatedAt // "never")"' "$state")"

latest="$(ls -1 "$work/handoffs"/handoff-*.md 2>/dev/null | sort | tail -1 || true)"
if [[ -n "$latest" ]]; then
  # The START HERE section: from its heading to the next "## " heading.
  top="$(awk '/^## START HERE/{p=1; next} /^## /{if(p) exit} p' "$latest")"
  handoff="Latest handoff: $latest"$'\n'"$top"
else
  handoff="No handoff yet for $id."
fi

gotchas=""
[[ -f "$moot/gotchas/index.md" ]] && gotchas="$(cat "$moot/gotchas/index.md")"

warn=""
tokens="$(printf '%s' "$input" | jq -r '.context_tokens // empty' 2>/dev/null || true)"
limit="$(jq -r '.contextWarnTokens // 350000' "$state")"
if [[ -n "$tokens" && "$tokens" -ge "$limit" ]]; then
  warn=$'\n\n'"Context is already at $tokens tokens, above the moot threshold of $limit. Write a handoff with /moot:handoff and start a fresh session before doing more."
fi

text="$summary

$handoff

Gotchas index (load a topic file from .moot/gotchas/ when a stage names it):
$gotchas

Rules: state lives at $state and is written only through \${CLAUDE_PLUGIN_ROOT}/scripts/moot-state.sh; every other write under .moot/ goes through moot-note.sh. Nothing moves past a gate (council, spec, plan, each PR) without the human's explicit GO in this session. Start with /moot:resume to confirm the next action.$warn"

jq -n --arg ctx "$text" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
