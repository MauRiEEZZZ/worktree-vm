#!/usr/bin/env bash
# codex-review.sh — run Codex's second opinion so that it either RUNS or SAYS that it
# did not. A standalone script (bash lib/wt/codex-review.sh ...), not sourced by wt.sh:
# a review session's shell has none of the wt-* functions (they live in the user's
# interactive shell), so the task text hands the reviewer this file by absolute path.
#
# Why it exists (2026-10-07). The review task asked for
#   codex review -c sandbox_mode="read-only" --base origin/<default> .
# where the final '.' was the sentence's full stop — and the reviewers ran it as
# written. `codex review` takes an optional [PROMPT] positional that cannot be
# combined with --base, so Codex stopped on a usage error ("the argument '--base
# <BRANCH>' cannot be used with '[PROMPT]'" — 134 times in one VM's transcripts) and
# the reviewers wrote "Codex: no findings" over an opinion that was never given. The
# other quiet way to lose it: a base that does not exist in the clone (origin/main on a
# repo whose default branch is develop). Codex exits 0 and picks a base of its own.
#
# usage: codex-review.sh [--base <ref>] [--dir <worktree>] [ignored...]
#   --base  the ref to review against. One that does not exist here is replaced by the
#           repo's default branch (origin/HEAD, else `git remote show origin`), and that
#           replacement is said. Without --base the default branch is used.
#   --dir   the worktree to review (default: the current directory). The directory
#           carries the scope, as in wt-review: the review worktree holds the committed
#           state, the dev worktree also holds the uncommitted work.
#   Anything else — a stray '.', for instance — is reported and IGNORED instead of
#   becoming Codex's [PROMPT].
#
# The FIRST line of the output is always one of
#   CODEX SECOND OPINION: ran (...)        Codex's review follows            exit 0
#   CODEX SECOND OPINION: NOTHING TO REVIEW  no diff against the base         exit 0
#   CODEX SECOND OPINION: DID NOT RUN: ...   the reason, Codex's stderr      exit non-zero
# so "Codex ran and found nothing" can only ever be written over the first.
set -u

notes=()
rc=1

# did_not_run <reason> [<file whose tail to show>] : the loud failure, non-zero exit.
# Defined before the argument loop so the loop itself can fail loudly.
did_not_run() {
  local reason="$1" tail_of="${2:-}" n
  echo "CODEX SECOND OPINION: DID NOT RUN: $reason"
  for n in ${notes[@]+"${notes[@]}"}; do echo "  note: $n"; done
  if [ -n "$tail_of" ] && [ -s "$tail_of" ]; then
    echo "  codex stderr (last lines):"
    tail -n 15 "$tail_of" | sed 's/^/    /'
  fi
  echo "  Report this in the review: Codex did NOT review this diff. Do not write 'Codex: no findings'."
  exit "${rc:-1}"
}

# needs_value <flag> [<candidate>] : a flag that takes a value must be given one.
# Without this, `shift 2` with a single argument left shifts nothing and the loop below
# spins forever -- in an unattended review that is a silent hang, which is the one failure
# this helper exists to make loud. A following flag is refused too: `--base --dir x` would
# otherwise swallow `--dir` as the base and quietly fall back to the default branch.
needs_value() {
  case "${2-}" in
    "")  did_not_run "$1 needs a value" ;;
    --*) did_not_run "$1 needs a value, got the flag $2" ;;
  esac
}

base="" dir="" stray=()
while [ $# -gt 0 ]; do
  case "$1" in
    --base)   needs_value --base "${2-}"; base="$2"; shift 2 ;;
    --base=*) base="${1#--base=}"; shift ;;
    --dir)    needs_value --dir "${2-}"; dir="$2"; shift 2 ;;
    --dir=*)  dir="${1#--dir=}"; shift ;;
    -h|--help) sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)        stray+=("$1"); shift ;;
  esac
done

[ "${#stray[@]}" -gt 0 ] && notes+=("ignored argument(s) that would have become Codex's [PROMPT]: ${stray[*]}")

dir="${dir:-$PWD}"
cd "$dir" 2>/dev/null || did_not_run "cannot enter $dir"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || did_not_run "$dir is not a git worktree"
command -v codex >/dev/null 2>&1 || did_not_run "codex is not installed (not on PATH)"

# the repo's default branch: origin/HEAD, else what the remote says it is
defbr="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
if [ -z "$defbr" ]; then
  defbr="$(git remote show origin 2>/dev/null | sed -n 's/^ *HEAD branch: //p' | head -1)"
  [ -n "$defbr" ] && defbr="origin/$defbr"
fi
if [ -z "$base" ]; then
  [ -n "$defbr" ] || did_not_run "no --base given and the repo's default branch cannot be resolved"
  base="$defbr"; notes+=("no --base given; reviewing against the default branch $base")
elif ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
  if [ -n "$defbr" ] && git rev-parse --verify --quiet "$defbr^{commit}" >/dev/null; then
    notes+=("base '$base' does not exist in this clone; using $defbr, the repo's default branch")
    base="$defbr"
  else
    did_not_run "base '$base' does not exist in this clone and no default branch could be resolved"
  fi
fi
sha="$(git rev-parse --short=12 "$base")"

# Untracked files are invisible to `codex review`, which works from the diff, and to the
# `git diff` below -- so a worktree whose only change is new files reads as NOTHING TO
# REVIEW. Say so rather than let the reviewer read silence as "Codex saw it and was happy".
nuntracked="$(git ls-files --others --exclude-standard -- . 2>/dev/null | wc -l | tr -d ' ')"
[ "${nuntracked:-0}" -gt 0 ] && notes+=("$nuntracked untracked file(s) are NOT part of Codex's review; it reviews the diff only")

# nothing to review: HEAD and the working tree equal the merge-base with the base
mb="$(git merge-base HEAD "$base" 2>/dev/null || echo "$base")"
if git diff --quiet "$mb" -- . 2>/dev/null; then
  echo "CODEX SECOND OPINION: NOTHING TO REVIEW (the working tree equals the merge-base ${mb:0:12} with $base)"
  for n in ${notes[@]+"${notes[@]}"}; do echo "  note: $n"; done
  exit 0
fi

out="$(mktemp)"; err="$(mktemp)"
trap 'rm -f "$out" "$err"' EXIT
# read-only sandbox: the reviewer must not be able to touch the worktree it reviews.
codex review -c sandbox_mode="read-only" --base "$base" </dev/null >"$out" 2>"$err"; rc=$?
[ "$rc" -eq 0 ] || did_not_run "codex review exited $rc" "$err"
if [ -z "$(tr -d '[:space:]' < "$out")" ]; then
  rc=1; did_not_run "codex review exited 0 but produced no output (no review was given)" "$err"
fi

echo "CODEX SECOND OPINION: ran ($(codex --version 2>/dev/null | head -1 || echo codex), base $base @ $sha, dir $dir, $(wc -l < "$out" | tr -d ' ') lines follow)"
for n in ${notes[@]+"${notes[@]}"}; do echo "  note: $n"; done
echo
cat "$out"
