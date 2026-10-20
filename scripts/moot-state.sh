#!/usr/bin/env bash
# The only writer of .moot/work/<ID>/state.json. Works from a linked worktree too.
#
#   moot-state.sh init <ID> --kind epic|task --ceremony full|light [--title "..."]
#   moot-state.sh get                 print the state
#   moot-state.sh path                print the absolute path of state.json (for Read)
#   moot-state.sh merge '<json>'      deep-merge an object into the state ('-' reads stdin)
#   moot-state.sh jq '<filter>'       apply a jq filter that returns the whole new state
#   moot-state.sh current [<ID>]      print or set the current work id
#
# The work id comes from MOOT_ID or .moot/current. Every write sets updatedAt.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
need jq

tpl="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../templates/state.json"

state_path() { echo "$(work_dir "$(current_id)")/state.json"; }

require_state() {
  local p; p="$(state_path)"
  [[ -f "$p" ]] || die "no state at $p"
  echo "$p"
}

# Runs a jq program against a file and writes the result back only when jq succeeded and
# produced one JSON object. A failed or empty jq run never touches the state.
rewrite() { # file jq-args...
  local p="$1"; shift
  local out
  out="$(jq "$@" "$p")" || die "jq failed; state untouched"
  printf '%s' "$out" | jq -e 'type == "object"' >/dev/null 2>&1 || die "jq result is not an object; state untouched"
  printf '%s\n' "$out" | write_atomic "$p"
}

apply() { # jq filter → rewrite state with updatedAt
  local p; p="$(require_state)"
  rewrite "$p" --arg at "$(now_utc)" "$1 | .updatedAt = \$at"
}

cmd_init() {
  local id="${1:-}"; shift || true
  [[ -n "$id" ]] || die "usage: moot-state.sh init <ID> --kind epic|task --ceremony full|light [--title ...]"
  local kind="" ceremony="" title=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kind) kind="$2"; shift 2 ;;
      --ceremony) ceremony="$2"; shift 2 ;;
      --title) title="$2"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [[ "$kind" == "epic" || "$kind" == "task" ]] || die "--kind must be epic or task"
  [[ "$ceremony" == "full" || "$ceremony" == "light" ]] || die "--ceremony must be full or light"
  local dir; dir="$(work_dir "$id")"
  [[ -e "$dir/state.json" ]] && die "state exists: $dir/state.json"
  local warn; warn="$(jq -r '.contextWarnTokens // 350000' "$(moot_dir)/config.json" 2>/dev/null || echo 350000)"
  mkdir -p "$dir/assets" "$dir/council" "$dir/handoffs" "$dir/tasks"
  cp "$tpl" "$dir/state.json"
  rewrite "$dir/state.json" --arg id "$id" --arg kind "$kind" --arg ceremony "$ceremony" --arg title "$title" \
     --argjson warn "$warn" --arg at "$(now_utc)" \
     '.id = $id | .kind = $kind | .ceremony = $ceremony | .title = $title
      | .contextWarnTokens = $warn | .updatedAt = $at'
  echo "$id" > "$(moot_dir)/current"
  echo "$dir/state.json"
}

cmd_merge() {
  local json="${1:-}"
  [[ -n "$json" ]] || die "usage: moot-state.sh merge '<json object>' (or - for stdin)"
  [[ "$json" == "-" ]] && json="$(cat)"
  echo "$json" | jq -e 'type == "object"' >/dev/null || die "merge needs a JSON object"
  local p; p="$(require_state)"
  rewrite "$p" --argjson patch "$json" --arg at "$(now_utc)" '. * $patch | .updatedAt = $at'
}

cmd_current() {
  if [[ -n "${1:-}" ]]; then
    [[ -f "$(work_dir "$1")/state.json" ]] || die "no state for $1"
    echo "$1" > "$(moot_dir)/current"
  fi
  current_id
}

case "${1:-}" in
  init) shift; cmd_init "$@" ;;
  get) cat "$(require_state)" ;;
  path) require_state ;;
  merge) cmd_merge "${2:-}" ;;
  jq) [[ -n "${2:-}" ]] || die "usage: moot-state.sh jq '<filter>'"; apply "$2" ;;
  current) cmd_current "${2:-}" ;;
  *) die "usage: moot-state.sh init|get|path|merge|jq|current" ;;
esac
