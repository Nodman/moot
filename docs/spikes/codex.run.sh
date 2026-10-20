#!/usr/bin/env bash
# Prototype of moot's codex-run.sh: headless exec, JSON stream to a log, sentinel at the end.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
"${CODEX_BIN:-codex}" exec -m gpt-6-astra -c tools.web_search=true -c model_reasoning_effort=high -s read-only --skip-git-repo-check \
  --json -o "$DIR/codex-report.md" - < "$DIR/prompt.md" > "$DIR/codex.jsonl" 2>&1
rc=$?
if [[ "$rc" == 0 && ! -s "$DIR/codex-report.md" ]]; then rc=97; fi
echo "$rc" > "$DIR/codex-report.md.done"
