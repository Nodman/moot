#!/usr/bin/env bash
# Headless codex runner. One run = one report file; everything else sits next to it.
#
#   codex-run.sh run --name <name> --model <model> --effort <e> --prompt <file> --out <report.md>
#                    [--charter <agent.md>] [--resume <session-id>] [--image <file>]... [--workdir <dir>] [--no-pane]
#       Spawns codex in the background and returns at once. Prints name, session id, pane, paths.
#   codex-run.sh wait <report.md> [--timeout <seconds>]     done <rc> | timeout | dead
#   codex-run.sh status <report.md>                         done <rc> | running | dead
#   codex-run.sh kill <report.md>
#   codex-run.sh session-id <report.md>
#
# Next to <report.md>: <base>.log (the --json event stream), <base>.prompt.md (what codex got),
# <base>.pid, <report.md>.done (exit code; 97 = exited 0 without a report). The tmux pane id is
# kept per member name in <dir>/<name>.pane and reused across rounds. CODEX_BIN overrides the binary.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
need jq

codex_bin() { echo "${CODEX_BIN:-codex}"; }

base_of() { echo "${1%.md}"; }

# Charter body without its frontmatter, then the prompt.
compose_prompt() { # charter prompt
  if [[ -n "$1" ]]; then
    awk 'body { print; next } /^---$/ { n++; if (n == 2) body = 1 }' "$1"
    printf '\n\n'
  fi
  cat "$2"
}

read_session_id() { # log
  [[ -f "$1" ]] || return 0
  { jq -r -R 'fromjson? | select(.type == "thread.started") | .thread_id' "$1" 2>/dev/null || true; } | head -1
}

pane_alive() { tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$1"; }

open_pane() { # pane-file name workdir session-id
  local pane_file="$1" name="$2" workdir="$3" sid="$4" pane=""
  [[ -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null 2>&1 || { echo none; return; }
  [[ -f "$pane_file" ]] && pane="$(cat "$pane_file")"
  if [[ -n "$pane" ]] && pane_alive "$pane"; then
    tmux respawn-pane -k -t "$pane" -c "$workdir" "$(codex_bin) resume $sid" 2>/dev/null || pane=""
  else
    pane=""
  fi
  if [[ -z "$pane" ]]; then
    pane="$(tmux split-window -d -h -l 40% -t "$TMUX_PANE" -c "$workdir" -P -F '#{pane_id}' "$(codex_bin) resume $sid" 2>/dev/null || true)"
  fi
  [[ -n "$pane" ]] || { echo none; return; }
  tmux select-pane -t "$pane" -T "$name" 2>/dev/null || true
  echo "$pane" > "$pane_file"
  echo "$pane"
}

cmd_run() {
  local name="" model="" effort="" prompt="" out="" charter="" resume="" workdir="$PWD" no_pane=""
  local images=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      --effort) effort="$2"; shift 2 ;;
      --prompt) prompt="$2"; shift 2 ;;
      --out) out="$2"; shift 2 ;;
      --charter) charter="$2"; shift 2 ;;
      --resume) resume="$2"; shift 2 ;;
      --image) images+=("$2"); shift 2 ;;
      --workdir) workdir="$2"; shift 2 ;;
      --no-pane) no_pane=1; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [[ -n "$name" && -n "$model" && -n "$effort" && -n "$prompt" && -n "$out" ]] \
    || die "usage: codex-run.sh run --name --model --effort --prompt --out [--charter] [--resume] [--image]... [--workdir] [--no-pane]"
  [[ -f "$prompt" ]] || die "no prompt file: $prompt"
  [[ -z "$charter" || -f "$charter" ]] || die "no charter file: $charter"
  [[ "$out" == *.md ]] || die "--out must end in .md"
  out="$(cd "$(dirname "$out")" 2>/dev/null && pwd)/$(basename "$out")" || die "no directory for $out"
  workdir="$(cd "$workdir" && pwd)" || die "no workdir: $workdir"
  command -v "$(codex_bin)" >/dev/null 2>&1 || die "codex not found (set CODEX_BIN)"

  local base log sentinel pid_file prompt_file runner pane_file
  base="$(base_of "$out")"
  log="$base.log"; sentinel="$out.done"; pid_file="$base.pid"; prompt_file="$base.prompt.md"; runner="$base.run.sh"
  pane_file="$(dirname "$out")/$name.pane"
  rm -f "$out" "$log" "$sentinel" "$pid_file"
  compose_prompt "$charter" "$prompt" | write_atomic "$prompt_file"

  local -a cmd=("$(codex_bin)" exec)
  if [[ -n "$resume" ]]; then
    cmd+=(resume "$resume" -c sandbox_mode='"read-only"')
  else
    cmd+=(-s read-only)
  fi
  cmd+=(-m "$model" -c model_reasoning_effort="$effort" -c tools.web_search=true --skip-git-repo-check --json)
  local img; for img in "${images[@]+"${images[@]}"}"; do cmd+=(-i "$img"); done
  cmd+=(-o "$out" -)

  {
    echo '#!/usr/bin/env bash'
    printf 'cd %q || { echo 1 > %q; exit 1; }\n' "$workdir" "$sentinel"
    printf '%q ' "${cmd[@]}"; printf '< %q > %q 2>&1\n' "$prompt_file" "$log"
    echo 'rc=$?'
    printf '[[ "$rc" == 0 && ! -s %q ]] && rc=97\n' "$out"
    printf 'echo "$rc" > %q\n' "$sentinel"
  } > "$runner"
  chmod +x "$runner"
  nohup "$runner" >/dev/null 2>&1 &
  echo $! > "$pid_file"

  local sid="" i
  for i in $(seq 1 60); do
    sid="$(read_session_id "$log")"
    [[ -n "$sid" ]] && break
    [[ -f "$sentinel" ]] && break
    sleep 0.5
  done
  if [[ -z "$sid" ]]; then
    [[ -f "$sentinel" ]] && die "codex exited before starting (rc $(cat "$sentinel")); see $log"
    sid="unknown"
  fi

  local pane=none
  if [[ -z "$no_pane" && "$sid" != unknown ]]; then
    pane="$(open_pane "$pane_file" "$name" "$workdir" "$sid")"
  fi
  printf 'name=%s\nsession=%s\npane=%s\nreport=%s\nlog=%s\nsentinel=%s\n' "$name" "$sid" "$pane" "$out" "$log" "$sentinel"
}

pid_alive() { [[ -f "$1" ]] && kill -0 "$(cat "$1")" 2>/dev/null; }

cmd_status() {
  local out="${1:?usage: codex-run.sh status <report.md>}" sentinel pid_file
  sentinel="$out.done"; pid_file="$(base_of "$out").pid"
  if [[ -f "$sentinel" ]]; then echo "done $(cat "$sentinel")"
  elif pid_alive "$pid_file"; then echo running
  else sleep 1; [[ -f "$sentinel" ]] && echo "done $(cat "$sentinel")" || echo dead
  fi
}

cmd_wait() {
  local out="${1:?usage: codex-run.sh wait <report.md> [--timeout <s>]}"; shift
  local timeout=540
  while [[ $# -gt 0 ]]; do
    case "$1" in --timeout) timeout="$2"; shift 2 ;; *) die "unknown flag: $1" ;; esac
  done
  local deadline=$(( $(date +%s) + timeout )) s
  while :; do
    s="$(cmd_status "$out")"
    [[ "$s" == running ]] || { echo "$s"; return; }
    [[ $(date +%s) -lt $deadline ]] || { echo timeout; return; }
    sleep 5
  done
}

cmd_kill() {
  local out="${1:?usage: codex-run.sh kill <report.md>}" sentinel pid_file pid
  sentinel="$out.done"; pid_file="$(base_of "$out").pid"
  [[ -f "$sentinel" ]] && { echo "already done ($(cat "$sentinel"))"; return; }
  pid_alive "$pid_file" || { echo dead; return; }
  pid="$(cat "$pid_file")"
  pkill -TERM -P "$pid" 2>/dev/null || true
  kill -TERM "$pid" 2>/dev/null || true
  local i; for i in 1 2 3 4 5; do [[ -f "$sentinel" ]] && break; sleep 1; done
  if [[ ! -f "$sentinel" ]]; then
    pkill -KILL -P "$pid" 2>/dev/null || true
    kill -KILL "$pid" 2>/dev/null || true
    echo 137 > "$sentinel"
  fi
  echo "killed ($(cat "$sentinel"))"
}

cmd_session_id() {
  local out="${1:?usage: codex-run.sh session-id <report.md>}" sid
  sid="$(read_session_id "$(base_of "$out").log")"
  [[ -n "$sid" ]] || die "no session id yet in $(base_of "$out").log"
  echo "$sid"
}

case "${1:-}" in
  run) shift; cmd_run "$@" ;;
  wait) shift; cmd_wait "$@" ;;
  status) shift; cmd_status "$@" ;;
  kill) shift; cmd_kill "$@" ;;
  session-id) shift; cmd_session_id "$@" ;;
  *) die "usage: codex-run.sh run|wait|status|kill|session-id" ;;
esac
