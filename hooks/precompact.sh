#!/usr/bin/env bash
# PreCompact: with current moot work, block the first compaction of a session and tell the human
# to ask the lead for a handoff. The second attempt in the same session goes through.
set -euo pipefail

input="$(cat || true)"
common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
[[ -n "$common" ]] || exit 0
moot="$(dirname "$common")/.moot"
[[ -f "$moot/current" ]] || exit 0

session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
[[ -n "$session" ]] || exit 0
mark="$moot/.compact-$session"
[[ -f "$mark" ]] && exit 0

touch "$mark"
echo "moot: compaction blocked once. Ask the lead for /moot:handoff first, then compact or start a fresh session." >&2
exit 2
