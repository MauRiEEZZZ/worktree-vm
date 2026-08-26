#!/usr/bin/env bash
# tests/run.sh — run the whole suite. Zero external deps: plain bash + real
# tmux/git/node, opt-in stubs for everything that must not run for real
# (limactl, gh, sudo). See tests/lib.sh for the isolation contract; a dev
# session can run this next to a live tmux server and live session data.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

pass=0; fail=0; skip=0; failed_names=""
for t in tests/t/*.sh; do
  echo "== $t"
  bash "$t"; rc=$?
  case $rc in
    0)  pass=$((pass + 1)) ;;
    77) skip=$((skip + 1)) ;;
    *)  fail=$((fail + 1)); failed_names="$failed_names $t" ;;
  esac
done

if [ -d tests/js ] && command -v node >/dev/null 2>&1; then
  echo "== node --test tests/js"
  if node --test tests/js/*.test.mjs; then pass=$((pass + 1)); else fail=$((fail + 1)); failed_names="$failed_names tests/js"; fi
fi

echo
echo "suite: $pass passed, $fail failed, $skip skipped"
[ -n "$failed_names" ] && echo "failed:$failed_names"
[ "$fail" = 0 ]
