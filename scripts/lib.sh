#!/usr/bin/env bash
# Shared helpers for moot scripts. Source, do not run.
set -euo pipefail

die() { echo "moot: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

# Main checkout root, even when called from a linked worktree: the parent of the common git dir.
moot_root() {
  local common
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || die "not a git repository"
  dirname "$common"
}

moot_dir() { echo "$(moot_root)/.moot"; }

now_utc() { date -u +%Y-%m-%dT%H:%MZ; }
stamp() { date +%Y-%m-%d-%H%M; }

# The work id: MOOT_ID in the environment wins, then this session's binding
# (.moot/sessions/<session id>, written by moot-state.sh init and current), then .moot/current,
# the last work any session claimed. Parallel sessions in one checkout each keep their own.
current_id() {
  if [[ -n "${MOOT_ID:-}" ]]; then echo "$MOOT_ID"; return; fi
  local f
  if [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
    f="$(moot_dir)/sessions/$CLAUDE_CODE_SESSION_ID"
    [[ -f "$f" ]] && { cat "$f"; return; }
  fi
  f="$(moot_dir)/current"
  [[ -f "$f" ]] || die "no current work; run moot-state.sh init first or set MOOT_ID"
  cat "$f"
}

# Binds the work id to this session and records it as the last claimed.
bind_current() { # id
  echo "$1" > "$(moot_dir)/current"
  if [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
    mkdir -p "$(moot_dir)/sessions"
    echo "$1" > "$(moot_dir)/sessions/$CLAUDE_CODE_SESSION_ID"
  fi
}

work_dir() { echo "$(moot_dir)/work/$1"; }

# Writes stdin to a file atomically.
write_atomic() {
  local dest="$1" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp "$(dirname "$dest")/.tmp.XXXXXX")"
  cat > "$tmp"
  mv "$tmp" "$dest"
}
