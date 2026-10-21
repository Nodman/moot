#!/usr/bin/env bash
# Headless codex runner. One run = one report file; everything else sits next to it.
#
#   codex-run.sh run --name <name> --model <model> --effort <e> --prompt <file> --out <report.md>
#                    [--charter <agent.md>] [--resume <session-id>] [--image <file>]... [--workdir <dir>] [--background]
#       Runs codex in a tmux pane next to the lead (the first run splits to the right, later runs
#       stack below it) and returns at once. Without tmux, or with --background, it runs as a
#       background process. Prints name, session id, mode, pane, paths.
#   codex-run.sh wait <report.md> [--timeout <seconds>]     done <rc> | timeout | dead
#   codex-run.sh status <report.md>                         done <rc> | running | dead
#   codex-run.sh kill <report.md>
#   codex-run.sh session-id <report.md>
#   codex-run.sh render <log> <report> <color>              internal: the --json stream on stdin
#
# Next to <report.md>: <base>.log (the --json event stream), <base>.prompt.md (what codex got),
# <base>.run.sh (the runner), <base>.job (mode and pid or pane), <report.md>.done (exit code;
# 97 = exited 0 without a report, 137 = killed). CODEX_BIN overrides the binary.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
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

agent_color() { # name → ansi color code
  local sum; sum="$(printf '%s' "$1" | cksum)"; sum="${sum%% *}"
  case $((sum % 4)) in 0) echo 34 ;; 1) echo 35 ;; 2) echo 33 ;; 3) echo 36 ;; esac
}

# Reads the codex --json stream, keeps every raw line in the log, prints a readable trace.
cmd_render() { # log report color
  set +e   # a display bug must never SIGPIPE-kill the codex run
  local log="${1:?}" report="${2:-}" color="${3:-36}"
  local B="" R="" G="" C="" D="" N=""
  if [[ -t 1 ]]; then B=$'\e[1m'; R=$'\e[31m'; G=$'\e[32m'; C=$'\e['"$color"m; D=$'\e[2m'; N=$'\e[0m'; fi
  : > "$log"
  local line type itype txt cmd rc
  while IFS= read -r line; do
    printf '%s\n' "$line" >> "$log"
    if ! jq -e . >/dev/null 2>&1 <<<"$line"; then printf '%s! %s%s\n\n' "$D" "$line" "$N"; continue; fi
    type="$(jq -r '.type // empty' <<<"$line" 2>/dev/null)"
    case "$type" in
      thread.started)
        txt="$(jq -r '.thread_id // empty' <<<"$line" 2>/dev/null)"
        [[ -n "$txt" ]] && printf '%ssession %s%s\n\n' "$B" "$txt" "$N" ;;
      item.started|item.completed)
        itype="$(jq -r '.item.item_type // .item.type // empty' <<<"$line" 2>/dev/null)"
        case "$itype" in
          command_execution)
            cmd="$(jq -r '.item.command // empty' <<<"$line" 2>/dev/null | tr '\n' ' ' | cut -c1-120)"
            if [[ "$type" == item.started && -n "$cmd" ]]; then printf '%s$ %s%s\n\n' "$C" "$cmd" "$N"
            elif [[ "$type" == item.completed ]]; then
              rc="$(jq -r '.item.exit_code // 0' <<<"$line" 2>/dev/null)"
              [[ "$rc" != 0 ]] && printf '%s! exit %s: %s%s\n\n' "$R" "$rc" "$cmd" "$N"
            fi ;;
          web_search)
            if [[ "$type" == item.completed ]]; then
              txt="$(jq -r '.item.query // empty' <<<"$line" 2>/dev/null | cut -c1-120)"
              [[ -n "$txt" ]] && printf '%s? %s%s\n\n' "$C" "$txt" "$N"
            fi ;;
          agent_message)
            if [[ "$type" == item.completed ]]; then
              txt="$(jq -r '.item.text // empty' <<<"$line" 2>/dev/null)"
              [[ -n "$txt" ]] && printf '%s%s%s\n\n' "$C" "$txt" "$N"
            fi ;;
          reasoning)
            if [[ "$type" == item.completed ]]; then
              txt="$(jq -r '.item.text // empty' <<<"$line" 2>/dev/null | tr '\n' ' ' | cut -c1-160)"
              [[ -n "$txt" ]] && printf '%s* %s%s\n\n' "$D" "$txt" "$N"
            fi ;;
          todo_list)
            txt="$(jq -r '[.item.items[]? | select(.completed == false)][0].text // empty' <<<"$line" 2>/dev/null)"
            [[ -n "$txt" ]] && printf '%s> %s%s\n\n' "$D" "$txt" "$N" ;;
        esac ;;
      turn.completed)
        txt="$(jq -r '"\(.usage.input_tokens // 0) in / \(.usage.output_tokens // 0) out"' <<<"$line" 2>/dev/null)"
        printf '%sdone: %s%s\n\n' "$G" "$txt" "$N" ;;
      error)
        txt="$(jq -r '.message // "unknown error"' <<<"$line" 2>/dev/null)"
        printf '%sERROR %s%s\n\n' "$R" "$txt" "$N" ;;
    esac
  done
  [[ -n "$report" ]] && printf '%sreport: %s%s\n' "$D" "$report" "$N"
  return 0
}

# Splits off the lead's pane the first time, then off the right-most pane so later runs stack.
open_pane() { # runner
  local runner="$1" target="${TMUX_PANE:-}" window right="" candidate at_right pane=""
  [[ -n "$target" ]] || { echo ""; return; }
  window="$(tmux display-message -p -t "$target" '#{window_id}')"
  while IFS=' ' read -r candidate at_right; do
    [[ "$candidate" != "$target" && "$at_right" == 1 ]] && right="$candidate"
  done < <(tmux list-panes -t "$window" -F '#{pane_id} #{pane_at_right}')
  if [[ -n "$right" ]]; then
    pane="$(tmux split-window -d -v -t "$right" -P -F '#{pane_id}' "$runner" 2>/dev/null || true)"
  else
    pane="$(tmux split-window -d -h -l 40% -t "$target" -P -F '#{pane_id}' "$runner" 2>/dev/null || true)"
  fi
  echo "$pane"
}

cmd_run() {
  local name="" model="" effort="" prompt="" out="" charter="" resume="" workdir="$PWD" background=""
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
      --background) background=1; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [[ -n "$name" && -n "$model" && -n "$effort" && -n "$prompt" && -n "$out" ]] \
    || die "usage: codex-run.sh run --name --model --effort --prompt --out [--charter] [--resume] [--image]... [--workdir] [--background]"
  [[ -f "$prompt" ]] || die "no prompt file: $prompt"
  [[ -z "$charter" || -f "$charter" ]] || die "no charter file: $charter"
  [[ "$out" == *.md ]] || die "--out must end in .md"
  out="$(cd "$(dirname "$out")" 2>/dev/null && pwd)/$(basename "$out")" || die "no directory for $out"
  workdir="$(cd "$workdir" && pwd)" || die "no workdir: $workdir"
  local bin; bin="$(command -v "$(codex_bin)")" || die "codex not found (set CODEX_BIN)"
  local i img; for i in "${!images[@]}"; do   # the pane does not inherit the lead's cwd or env
    img="${images[$i]}"
    [[ -f "$img" ]] || die "no image file: $img"
    images[$i]="$(cd "$(dirname "$img")" && pwd)/$(basename "$img")"
  done

  local base log sentinel prompt_file runner job color
  base="$(base_of "$out")"
  log="$base.log"; sentinel="$out.done"; prompt_file="$base.prompt.md"; runner="$base.run.sh"; job="$base.job"
  color="$(agent_color "$name")"
  rm -f "$out" "$log" "$sentinel" "$job"
  compose_prompt "$charter" "$prompt" | write_atomic "$prompt_file"

  local -a cmd=("$bin" exec)
  if [[ -n "$resume" ]]; then
    cmd+=(resume "$resume" -c sandbox_mode='"read-only"')   # resume rejects -s
  else
    cmd+=(-s read-only)
  fi
  cmd+=(-m "$model" -c model_reasoning_effort="$effort" -c tools.web_search=true --skip-git-repo-check --json)
  for img in "${images[@]+"${images[@]}"}"; do cmd+=(-i "$img"); done
  cmd+=(-o "$out" -)

  local mode=background
  [[ -z "$background" && -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null 2>&1 && mode=tmux

  local banner="[$name model=$model effort=$effort]"
  {
    echo '#!/usr/bin/env bash'
    printf 'if [[ -t 1 ]]; then printf %q; else printf %q; fi\n' $'\e['"$color"'m'"$banner"$'\e[0m\n' "$banner"$'\n'
    printf 'cd %q || { echo 1 > %q; exit 1; }\n' "$workdir" "$sentinel"
    printf '%q ' "${cmd[@]}"; printf '< %q 2>&1 | %q render %q %q %q\n' "$prompt_file" "$here/codex-run.sh" "$log" "$out" "$color"
    echo 'rc="${PIPESTATUS[0]}"'
    printf '[[ "$rc" == 0 && ! -s %q ]] && rc=97\n' "$out"
    printf 'echo "$rc" > %q\n' "$sentinel"
    [[ "$mode" == tmux ]] && echo 'sleep 10'   # the pane lingers so the human can read the tail
  } > "$runner"
  chmod +x "$runner"

  local pane="" pid=""
  if [[ "$mode" == tmux ]]; then
    pane="$(open_pane "$runner")"
    if [[ -n "$pane" ]]; then tmux select-pane -t "$pane" -T "$name" 2>/dev/null || true; else mode=background; fi
  fi
  if [[ "$mode" == background ]]; then
    nohup "$runner" >/dev/null 2>&1 &
    pid=$!
  fi
  jq -n --arg name "$name" --arg model "$model" --arg mode "$mode" --arg pid "$pid" --arg pane "$pane" \
    --arg workdir "$workdir" --arg created "$(now_utc)" \
    '{name: $name, model: $model, mode: $mode, workdir: $workdir, created: $created}
     + (if $pid != "" then {pid: ($pid | tonumber)} else {} end)
     + (if $pane != "" then {pane: $pane} else {} end)' > "$job"

  local sid=""
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
  printf 'name=%s\nsession=%s\nmode=%s\npane=%s\nreport=%s\nlog=%s\nsentinel=%s\n' \
    "$name" "$sid" "$mode" "${pane:-none}" "$out" "$log" "$sentinel"
}

job_alive() { # job
  local mode pid pane
  mode="$(jq -r .mode "$1")"; pid="$(jq -r '.pid // empty' "$1")"; pane="$(jq -r '.pane // empty' "$1")"
  case "$mode" in
    background) [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null ;;
    tmux) [[ -n "$pane" ]] && tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$pane" ;;
    *) return 1 ;;
  esac
}

cmd_status() {
  local out="${1:?usage: codex-run.sh status <report.md>}" sentinel job
  sentinel="$out.done"; job="$(base_of "$out").job"
  [[ -f "$sentinel" ]] && { echo "done $(cat "$sentinel")"; return; }
  [[ -f "$job" ]] || die "no run for $out"
  if job_alive "$job"; then echo running
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
  local out="${1:?usage: codex-run.sh kill <report.md>}" sentinel job mode pid pane
  sentinel="$out.done"; job="$(base_of "$out").job"
  [[ -f "$sentinel" ]] && { echo "already done ($(cat "$sentinel"))"; return; }
  [[ -f "$job" ]] || die "no run for $out"
  job_alive "$job" || { echo dead; return; }
  mode="$(jq -r .mode "$job")"; pid="$(jq -r '.pid // empty' "$job")"; pane="$(jq -r '.pane // empty' "$job")"
  if [[ "$mode" == tmux ]]; then
    tmux kill-pane -t "$pane" 2>/dev/null || true
    echo 137 > "$sentinel"
  else
    pkill -TERM -P "$pid" 2>/dev/null || true
    kill -TERM "$pid" 2>/dev/null || true
    local i; for i in 1 2 3 4 5; do [[ -f "$sentinel" ]] && break; sleep 1; done
    if [[ ! -f "$sentinel" ]]; then
      pkill -KILL -P "$pid" 2>/dev/null || true
      kill -KILL "$pid" 2>/dev/null || true
      echo 137 > "$sentinel"
    fi
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
  render) shift; cmd_render "$@" ;;
  *) die "usage: codex-run.sh run|wait|status|kill|session-id" ;;
esac
