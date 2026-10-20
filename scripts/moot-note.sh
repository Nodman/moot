#!/usr/bin/env bash
# Writes under .moot/ that are not the state file. Works from a linked worktree too.
#
#   moot-note.sh handoff            stdin → work/<ID>/handoffs/handoff-<date>-<time>.md, link updated
#   moot-note.sh gotcha <topic>     stdin → appended to .moot/gotchas/<topic>.md, index line added
#   moot-note.sh file <rel-path>    stdin → work/<ID>/<rel-path> (briefs, reports, factpack, pages)
#
# Each command prints the absolute path it wrote.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cmd_handoff() {
  local id dir dest rel
  id="$(current_id)"
  dir="$(work_dir "$id")"
  [[ -d "$dir" ]] || die "no work dir for $id"
  local base n=1
  base="handoffs/handoff-$(stamp)"
  rel="$base.md"
  while [[ -e "$dir/$rel" ]]; do n=$((n + 1)); rel="$base-$n.md"; done
  dest="$dir/$rel"
  write_atomic "$dest"
  local links
  links="$(jq -c --arg rel "$rel" '[.links[]? | select(.label != "Latest handoff")] + [{label: "Latest handoff", path: $rel}]' "$dir/state.json")"
  MOOT_ID="$id" "$here/moot-state.sh" merge "{\"links\": $links}" >/dev/null
  echo "$dest"
}

cmd_gotcha() {
  local topic="${1:-}"
  [[ "$topic" =~ ^[a-z0-9-]+$ ]] || die "topic must be lowercase letters, digits and dashes"
  local gdir file index
  gdir="$(moot_dir)/gotchas"
  mkdir -p "$gdir"
  file="$gdir/$topic.md"
  index="$gdir/index.md"
  if [[ ! -f "$file" ]]; then
    printf '# %s\n\n' "$topic" > "$file"
    [[ -f "$index" ]] || printf '# Gotchas index\n\n' > "$index"
    grep -q "^- $topic.md" "$index" || echo "- $topic.md — $topic" >> "$index"
  fi
  { printf '\n## %s\n\n' "$(now_utc)"; cat; } >> "$file"
  echo "$file"
}

cmd_file() {
  local rel="${1:-}"
  [[ -n "$rel" ]] || die "usage: moot-note.sh file <relative path under the work dir>"
  [[ "$rel" != /* && "$rel" != *..* ]] || die "path must be relative and inside the work dir"
  local dest; dest="$(work_dir "$(current_id)")/$rel"
  write_atomic "$dest"
  echo "$dest"
}

case "${1:-}" in
  handoff) cmd_handoff ;;
  gotcha) cmd_gotcha "${2:-}" ;;
  file) cmd_file "${2:-}" ;;
  *) die "usage: moot-note.sh handoff | gotcha <topic> | file <rel-path>" ;;
esac
