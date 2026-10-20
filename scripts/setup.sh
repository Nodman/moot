#!/usr/bin/env bash
# moot setup helper: check | ignore local|global | scaffold
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tpl="$here/../templates"
MIN_CLAUDE="2.1.287"

die() { echo "setup: $*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Launches the binary with a time limit; prints ok, hangs, or missing.
probe() {
  local bin="$1"
  have "$bin" || { echo missing; return; }
  if perl -e 'alarm 8; exec @ARGV' "$bin" --version >/dev/null 2>&1; then echo ok; else echo hangs; fi
}

version_ge() { # a b → true when a >= b, dotted numbers
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" == "$2" ]]
}

check() {
  local gitdir common
  gitdir="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
  [[ -n "$gitdir" ]] || die "not a git repository"
  common="$(git rev-parse --path-format=absolute --git-common-dir)"
  # In a linked worktree the git dir is .git/worktrees/<name>; in the main checkout both paths match.
  if [[ "$gitdir" != "$common" ]]; then
    echo "git: worktree (run setup from the main checkout)"
  else
    echo "git: main checkout"
  fi

  if have gh && gh auth status >/dev/null 2>&1; then echo "gh: ok"; else echo "gh: missing or not logged in"; fi
  if have jq; then echo "jq: ok"; else echo "jq: missing"; fi

  local codex
  codex="$(probe codex)"
  echo "codex: $codex"
  if [[ "$codex" == "hangs" ]]; then
    local alt
    alt="$(ls -d "$HOME"/.codex/packages/app-server-daemon/releases/*/bin/codex 2>/dev/null | sort | tail -1 || true)"
    [[ -n "$alt" ]] && echo "codex: working copy at $alt (set CODEX_BIN to it)"
    echo "codex: likely quarantine; fix: xattr -d com.apple.quarantine \"$(readlink -f "$(command -v codex)")\""
  fi

  if have tmux; then echo "tmux: ok"; else echo "tmux: missing"; fi

  local cv
  cv="$(claude --version 2>/dev/null | awk '{print $1}' || true)"
  if [[ -z "$cv" ]]; then echo "claude: version unknown"
  elif version_ge "$cv" "$MIN_CLAUDE"; then echo "claude: $cv ok"
  else echo "claude: $cv below $MIN_CLAUDE (dashboard mod needs $MIN_CLAUDE)"; fi

  if git check-ignore -q .moot 2>/dev/null; then echo "ignore: .moot/ already ignored"; else echo "ignore: .moot/ not ignored yet"; fi
}

append_once() { # file line
  mkdir -p "$(dirname "$1")"
  touch "$1"
  grep -qxF "$2" "$1" || echo "$2" >> "$1"
}

ignore() {
  case "${1:-}" in
    local)
      append_once ".git/info/exclude" ".moot/"
      echo "ignore: .moot/ added to .git/info/exclude" ;;
    global)
      local f
      f="$(git config --global core.excludesfile || true)"
      if [[ -z "$f" ]]; then
        f="$HOME/.gitignore"
        git config --global core.excludesfile "$f"
        echo "ignore: set core.excludesfile to $f"
      fi
      f="${f/#\~/$HOME}"
      append_once "$f" ".moot/"
      echo "ignore: .moot/ added to $f" ;;
    *) die "usage: setup.sh ignore local|global" ;;
  esac
}

seed() { # template dest
  if [[ -e "$2" ]]; then echo "scaffold: skip $2 (exists)"; else cp "$1" "$2"; echo "scaffold: created $2"; fi
}

scaffold() {
  mkdir -p .moot/gotchas .moot/work
  seed "$tpl/config.json" .moot/config.json
  seed "$tpl/roles.md" .moot/roles.md
  seed "$tpl/gotchas-index.md" .moot/gotchas/index.md
}

case "${1:-}" in
  check) check ;;
  ignore) ignore "${2:-}" ;;
  scaffold) scaffold ;;
  *) die "usage: setup.sh check | ignore local|global | scaffold" ;;
esac
