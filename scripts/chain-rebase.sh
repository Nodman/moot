#!/usr/bin/env bash
# Restacks the open PR chain after the human merged one or more of its PRs.
#
#   chain-rebase.sh [--dry-run]
#
# Run inside the work's worktree with a clean tree. Tasks come from the state in plan order
# (branch, pr); the main branch and the merge policy from .moot/config.json. A task is merged when
# gh reports its PR MERGED. The first open branch goes onto origin/<main>: with squash, --onto from
# the merged parent's PR head, so the squashed commits are dropped; with merge, a plain rebase.
# Each later branch goes onto the one before it, from that branch's remote tip. All rebases run
# first, then every branch that differs from its remote is pushed with --force-with-lease, the
# first open PR is retargeted to <main>, tasks[].base follows, and the worktree ends on the first
# open branch. A conflict stops the script with the rebase in progress: resolve it,
# `git rebase --continue`, rerun; branches already restacked are skipped. Do not push by hand
# between runs: the remote tips are how the script finds each branch's own commits.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
need jq; need gh
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

dry=""
case "${1:-}" in "") ;; --dry-run) dry=1 ;; *) die "usage: chain-rebase.sh [--dry-run]" ;; esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git worktree"
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die "the tree is not clean; commit or stash first"
for d in rebase-merge rebase-apply; do
  [[ ! -d "$(git rev-parse --git-path "$d")" ]] || die "a rebase is in progress; git rebase --continue (or --abort), then rerun"
done

config="$(moot_dir)/config.json"
main="$(jq -r '.mainBranch // "main"' "$config")"
policy="$(jq -r '.merge // "squash"' "$config")"
state="$("$here/moot-state.sh" get)"

git fetch origin --quiet
git show-ref --verify --quiet "refs/remotes/origin/$main" || die "no origin/$main after fetch"

run() { if [[ -n "$dry" ]]; then echo "  would: $*"; else "$@"; fi; }
has_ref() { git show-ref --verify --quiet "$1"; }
pr_json() { gh pr view "$1" --json state,headRefOid,baseRefName 2>/dev/null || die "gh cannot read PR #$1"; }

ids=(); branches=(); prs=(); pr_bases=()
while IFS=$'\t' read -r id branch pr; do
  ids+=("$id"); branches+=("$branch"); prs+=("$pr"); pr_bases+=("")
done < <(jq -r '.tasks | sort_by(.order)[] | [.id, (.branch // ""), (.pr // "" | tostring)] | @tsv' <<<"$state")
[[ ${#ids[@]} -gt 0 ]] || die "no tasks in the state"

# Pass 1: which tasks are merged, which are open. merged_head is the PR head of the last merged one.
merged_head=""; open=()
for i in "${!ids[@]}"; do
  id="${ids[$i]}"; branch="${branches[$i]}"; pr="${prs[$i]}"
  if [[ -z "$branch" ]]; then echo "$id: no branch yet, the chain ends here"; break; fi
  if [[ -n "$pr" ]]; then
    json="$(pr_json "$pr")"
    if [[ "$(jq -r .state <<<"$json")" == MERGED ]]; then
      [[ ${#open[@]} -eq 0 ]] || die "$id (PR #$pr) is merged but an earlier PR is still open; restack by hand"
      merged_head="$(jq -r .headRefOid <<<"$json")"
      echo "$id: merged, PR #$pr"
      continue
    fi
    pr_bases[$i]="$(jq -r .baseRefName <<<"$json")"
  fi
  has_ref "refs/heads/$branch" || die "$id: no local branch $branch"
  open+=("$i")
done
[[ ${#open[@]} -gt 0 ]] || { echo "every PR is merged; nothing to restack"; exit 0; }
if [[ -n "$merged_head" ]]; then
  git cat-file -e "$merged_head^{commit}" 2>/dev/null || die "the merged PR head $merged_head is not in this repo"
fi

# Pass 2: rebase, top of the chain first.
prev_branch=""; prev_moved=""; moved=()
for i in "${open[@]}"; do
  id="${ids[$i]}"; branch="${branches[$i]}"
  if [[ -z "$prev_branch" ]]; then
    onto="origin/$main"; upstream=""
    [[ "$policy" == squash && -n "$merged_head" ]] && upstream="$merged_head"
  else
    onto="$prev_branch"
    if has_ref "refs/remotes/origin/$prev_branch"; then upstream="origin/$prev_branch"; else upstream="$prev_branch"; fi
  fi
  if [[ -z "$prev_moved" ]] && git merge-base --is-ancestor "$onto" "$branch"; then
    echo "$id: $branch already on $onto"
    prev_branch="$branch"; prev_moved=""
    continue
  fi
  if [[ -n "$upstream" ]]; then
    git merge-base --is-ancestor "$upstream" "$branch" \
      || die "$id: $branch does not contain $upstream, so its own commits cannot be told apart; git rebase --onto $onto <old base> $branch by hand"
    echo "$id: rebase $branch onto $onto from $upstream"
    run git rebase --quiet --onto "$onto" "$upstream" "$branch" \
      || die "conflict in $branch: resolve it, git rebase --continue, then rerun chain-rebase.sh"
  else
    echo "$id: rebase $branch onto $onto"
    run git rebase --quiet "$onto" "$branch" \
      || die "conflict in $branch: resolve it, git rebase --continue, then rerun chain-rebase.sh"
  fi
  moved+=("$i")
  prev_branch="$branch"; prev_moved=1
done

# Pass 3: push what differs from the remote, retarget the first open PR, update the state.
for i in "${open[@]}"; do
  branch="${branches[$i]}"
  was_moved=""
  for m in ${moved[@]+"${moved[@]}"}; do [[ "$m" == "$i" ]] && was_moved=1; done
  if [[ -n "$was_moved" ]] || ! has_ref "refs/remotes/origin/$branch" \
     || [[ "$(git rev-parse "$branch")" != "$(git rev-parse "origin/$branch")" ]]; then
    echo "${ids[$i]}: push $branch"
    run git push --quiet --force-with-lease -u origin "$branch"
  fi
done

first="${open[0]}"
first_id="${ids[$first]}"; first_branch="${branches[$first]}"; first_pr="${prs[$first]}"
if [[ -n "$first_pr" && "${pr_bases[$first]}" != "$main" ]]; then
  echo "$first_id: retarget PR #$first_pr to $main"
  run gh pr edit "$first_pr" --base "$main"
fi
if [[ "$(jq -r --arg id "$first_id" '.tasks[] | select(.id == $id) | .base // ""' <<<"$state")" != "$main" ]]; then
  echo "$first_id: base is now $main in the state"
  run "$here/moot-state.sh" jq "(.tasks[] | select(.id == \"$first_id\")).base = \"$main\""
fi
run git checkout --quiet "$first_branch"
echo "chain restacked; the worktree is on $first_branch"
