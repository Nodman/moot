#!/usr/bin/env bash
# moot setup helper: check | ignore local|global | scaffold | upgrade
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
  if gh stack --version >/dev/null 2>&1; then echo "gh stack: ok"; else echo "gh stack: missing (gh extension install github/gh-stack)"; fi

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

# Brings an older .moot/ up to the current templates. Values the repo has are never changed:
# config.json gains the keys the template added; repo.md gains the sections and lines the
# template added (as unknown) and renamed lines keep their value under the new label; roles.md
# gains the roles its table lacks. Prints one line per change, or "up to date".
upgrade() {
  [[ -d .moot ]] || die "no .moot/ here; run scaffold first"
  local changed=0
  if [[ -f .moot/config.json ]]; then
    local merged added
    merged="$(jq -s '.[0] * .[1]' "$tpl/config.json" .moot/config.json)"
    added="$(jq -n --argjson t "$(cat "$tpl/config.json")" --argjson c "$(cat .moot/config.json)" \
      '[($t | paths(type != "object")) as $p | select(($c | getpath($p)) == null) | $p | join(".")] | .[]' -r)"
    if [[ -n "$added" ]]; then
      printf '%s\n' "$merged" > .moot/config.json
      while IFS= read -r k; do echo "config: added $k"; done <<< "$added"; changed=1
    fi
    local stale
    stale="$(jq -n --argjson t "$(cat "$tpl/config.json")" --argjson c "$(cat .moot/config.json)" \
      '[($c | paths(type != "object")) as $p | select(($t | getpath($p)) == null) | $p | join(".")] | .[]' -r)"
    [[ -n "$stale" ]] && while IFS= read -r k; do echo "config: $k is no longer read (left in place)"; done <<< "$stale"
  fi
  if [[ -f .moot/repo.md ]]; then
    python3 - "$tpl/repo.md" .moot/repo.md <<'PY2' && changed=1 || true
import re, sys
tpl, dst = open(sys.argv[1]).read().splitlines(), open(sys.argv[2]).read().splitlines()
RENAMED = {  # old label as written → the key of the template line that replaced it
    "capture a screenshot of a screen (command taking `<route> <out.png>`):": "capture a screenshot of a screen",
    "setup command to run inside a fresh worktree:": "setup inside a fresh worktree",
}
key = lambda label: re.split(r":| \(", label, maxsplit=1)[0].strip()
# template: section → [(key, full label)]
sections, cur = {}, None
for line in tpl:
    if line.startswith("## "): cur = line[3:].strip(); sections.setdefault(cur, [])
    elif cur and line.startswith("- "): sections[cur].append((key(line[2:]), line[2:].rstrip()))
changes = []
out, cur, have = [], None, {}
def flush():  # add the current section's missing lines before leaving it
    missing = [(k, label) for k, label in sections.get(cur, []) if k not in have]
    if not missing: return
    while out and out[-1] == "": out.pop()
    for k, label in missing:
        out.append(f"- {label} unknown"); changes.append(f"repo.md: added '{k}' under {cur}")
    out.append("")
for line in dst:
    if line.startswith("## "):
        flush(); cur = line[3:].strip(); have = {}; out.append(line); continue
    if line.startswith("- ") and cur in sections:
        for old, newkey in RENAMED.items():
            if line[2:].startswith(old):
                label = next((l for k, l in sections[cur] if k == newkey), None)
                if label:
                    line = f"- {label} {line[2 + len(old):].strip()}".rstrip()
                    changes.append(f"repo.md: renamed '{old.rstrip(':')}' to '{newkey}'")
        have[key(line[2:])] = True
    out.append(line)
flush()
for name, lines in sections.items():
    if not any(l.strip() == f"## {name}" for l in dst):
        out += ["", f"## {name}", ""] + [f"- {label} unknown" for _, label in lines]
        changes.append(f"repo.md: added section {name}")
if changes:
    open(sys.argv[2], "w").write("\n".join(out).rstrip("\n") + "\n")
    print("\n".join(changes)); sys.exit(0)
sys.exit(1)
PY2
  fi
  if [[ -f .moot/roles.md ]]; then
    local role
    while IFS= read -r row; do
      role="$(printf '%s' "$row" | awk -F'|' '{gsub(/^ +| +$/, "", $2); print $2}')"
      if ! grep -q "^| $role |" .moot/roles.md; then
        # append after the last table row
        python3 - .moot/roles.md "$row" <<'PY3'
import sys
p, row = sys.argv[1], sys.argv[2]
lines = open(p).read().splitlines()
last = max(i for i, l in enumerate(lines) if l.startswith("| "))
lines.insert(last + 1, row)
open(p, "w").write("\n".join(lines) + "\n")
PY3
        echo "roles: added the $role row"; changed=1
      fi
    done < <(grep '^| ' "$tpl/roles.md" | grep -v '^| role |\|^|---')
    grep -q 'xhigh' .moot/roles.md && echo "roles: effort xhigh is no longer routed; set those rows to high"
  fi
  [[ "$changed" == 1 ]] || echo "upgrade: up to date"
}

case "${1:-}" in
  check) check ;;
  ignore) ignore "${2:-}" ;;
  scaffold) scaffold ;;
  upgrade) upgrade ;;
  *) die "usage: setup.sh check | ignore local|global | scaffold | upgrade" ;;
esac
