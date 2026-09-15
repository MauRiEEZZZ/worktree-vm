#!/usr/bin/env bash
# Trap (spotted 2026-09-15, before it cost anything): the guest clones the HOST
# checkout, and `git clone` takes the source's CURRENT branch. So a rebuild while
# the maintainer happens to sit on a feature branch hands the VM that branch
# without a word, and every later boot keeps ff-pulling it. Verified against a real
# clone: host on a feature branch -> clone lands on the feature branch.
# The rendered definition must pin the default branch, and up.sh must SAY so when
# the checkout is somewhere else, so deviating stays a decision.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home
t_use_stubs limactl
export STUB_LOG="$T_TMP/stub.log"; : > "$STUB_LOG"
export FAKE_DISKS='{"name":"d","dir":"/x"}'
export FAKE_INSTANCES=''                    # no instance yet -> up.sh renders + starts

printf 'lima:\n  instance: t\n  data_disk: d\n' > "$T_TMP/cfg.yaml"

# `git clone` really does follow the source's HEAD — the premise, not an assumption.
git init -q -b main "$T_TMP/src"
( cd "$T_TMP/src" && git config user.email t@t && git config user.name t \
  && echo a > f && git add f && git commit -qm one && git checkout -q -b feature )
git clone -q "$T_TMP/src" "$T_TMP/naive" 2>/dev/null
assert_eq "$(git -C "$T_TMP/naive" branch --show-current)" "feature" "a plain clone follows the source's current branch (the trap)"
git clone -q --branch main "$T_TMP/src" "$T_TMP/pinned" 2>/dev/null
assert_eq "$(git -C "$T_TMP/pinned" branch --show-current)" "main" "--branch pins it regardless (the fix)"

# The rendered Lima definition must carry that --branch.
OUT="$(bash "$T_REPO/platform/lima/up.sh" "$T_TMP/cfg.yaml" 2>&1)"
DEF="$(grep -h 'git clone' "$T_REPO/platform/lima/vm.yaml.template")"
assert_contains "$DEF" 'git clone --branch "@REPO_BRANCH@"' "the template clones a pinned branch, not whatever HEAD is"
assert_not_contains "$DEF" 'git clone "$SRC"' "and no unpinned clone is left behind"

# up.sh must say which branch the guest gets when the checkout is elsewhere. The
# suite runs from a real checkout, so whether the note fires depends on where that
# checkout sits — assert the branch of the message, not the mood of the repo.
HEAD_BR="$(git -C "$T_REPO" symbolic-ref --quiet --short HEAD 2>/dev/null || echo detached)"
DEF_BR="$(git -C "$T_REPO" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
[ -n "$DEF_BR" ] || DEF_BR=main
if [ "$HEAD_BR" != "$DEF_BR" ]; then
  assert_contains "$OUT" "the guest will clone '$DEF_BR'" "a checkout on another branch is called out"
  assert_contains "$OUT" "To run '$HEAD_BR' in the guest instead" "with the way to deviate on purpose"
else
  assert_not_contains "$OUT" "the guest will clone" "no note when the checkout is on the default branch"
  t_pass "nothing to deviate from (checkout is on $DEF_BR)"
fi
t_end
