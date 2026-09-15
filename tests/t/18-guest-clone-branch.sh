#!/usr/bin/env bash
# Trap (spotted 2026-09-15, before it cost anything): the guest clones the HOST
# checkout, and `git clone` takes the source's CURRENT branch. So a rebuild while
# the maintainer happens to sit on a feature branch hands the VM that branch
# without a word, and every later boot keeps ff-pulling it.
# The rendered definition must pin the default branch, and up.sh must SAY so when
# the checkout is somewhere else, so deviating stays a decision.
#
# Every case below runs up.sh from a FIXTURE copy of the repo, never from the
# checkout the suite lives in: up.sh derives REPO_DIR from its own path, so a test
# that leaned on the suite's own branch would assert something different on a dev
# VM (a branch), on a push build (a branch) and on a PR build (detached) — which is
# exactly how the first version of this test went red in CI and green everywhere else.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home
t_use_stubs limactl
export STUB_LOG="$T_TMP/stub.log"; : > "$STUB_LOG"
export FAKE_DISKS='{"name":"d","dir":"/x"}'
export FAKE_INSTANCES=''                    # no instance yet -> up.sh renders + starts
printf 'lima:\n  instance: t\n  data_disk: d\n' > "$T_TMP/cfg.yaml"

# fixture: a clone (so refs/remotes/origin/HEAD exists, as on a real checkout)
git init -q -b main --bare "$T_TMP/origin.git"
git clone -q "$T_TMP/origin.git" "$T_TMP/seed" 2>/dev/null
cp -R "$T_REPO/platform" "$T_REPO/lib" "$T_TMP/seed/"
( cd "$T_TMP/seed" && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm one && git push -q origin HEAD:main )
git clone -q "$T_TMP/origin.git" "$T_TMP/fix" 2>/dev/null
UP="$T_TMP/fix/platform/lima/up.sh"

# ---- the premise, verified rather than assumed --------------------------------
( cd "$T_TMP/fix" && git checkout -q -b feature )
git clone -q "$T_TMP/fix" "$T_TMP/naive" 2>/dev/null
assert_eq "$(git -C "$T_TMP/naive" branch --show-current)" "feature" "a plain clone follows the source's current branch (the trap)"
git clone -q --branch main "$T_TMP/fix" "$T_TMP/pinned" 2>/dev/null
assert_eq "$(git -C "$T_TMP/pinned" branch --show-current)" "main" "--branch pins it regardless (the fix)"

# ---- the rendered definition carries the pin ----------------------------------
DEF="$(grep -h 'git clone' "$T_REPO/platform/lima/vm.yaml.template")"
assert_contains "$DEF" 'git clone --branch "@REPO_BRANCH@"' "the template clones a pinned branch, not whatever HEAD is"
assert_not_contains "$DEF" 'git clone "$SRC"' "and no unpinned clone is left behind"

# ---- on a feature branch: the note names both branches ------------------------
OUT="$(bash "$UP" "$T_TMP/cfg.yaml" 2>&1)"; RC=$?
assert_eq "$RC" "0" "up.sh renders from a feature branch"
assert_contains "$OUT" "will clone BRANCH 'main'" "and says which branch the guest actually gets"
assert_contains "$OUT" "To run 'feature' in the guest instead" "with the way to deviate on purpose"

# ---- on the default branch: nothing to say ------------------------------------
( cd "$T_TMP/fix" && git checkout -q main )
export FAKE_INSTANCES=''
OUT="$(bash "$UP" "$T_TMP/cfg.yaml" 2>&1)"; RC=$?
assert_eq "$RC" "0" "up.sh renders from the default branch"
# "will clone BRANCH", not "the guest will clone": up.sh has a NEIGHBOURING note
# ("the guest will clone from GitHub instead of this checkout") about WHERE it
# clones from, and the looser string matched that one too.
assert_not_contains "$OUT" "will clone BRANCH" "and stays quiet when there is nothing to deviate from"

# ---- neither ref: still renders ------------------------------------------------
# A CI checkout has no refs/remotes/origin/HEAD and leaves a detached HEAD. Under
# `set -e` a failing command substitution in an assignment ends the script, so the
# first version of this feature took up.sh down before it rendered anything —
# green on a dev VM, red on every runner.
mkdir -p "$T_TMP/bare"
cp -R "$T_REPO/platform" "$T_REPO/lib" "$T_TMP/bare/"
git init -q -b main "$T_TMP/bare"
( cd "$T_TMP/bare" && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm one && git checkout -q --detach )
assert_eq "$(git -C "$T_TMP/bare" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)" \
  "" "the fixture has no origin/HEAD (half the CI condition)"
assert_eq "$(git -C "$T_TMP/bare" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" \
  "" "and a detached HEAD (the other half)"
export FAKE_INSTANCES=''
OUT="$(bash "$T_TMP/bare/platform/lima/up.sh" "$T_TMP/cfg.yaml" 2>&1)"; RC=$?
assert_eq "$RC" "0" "up.sh still renders when origin/HEAD is missing and HEAD is detached"
assert_not_contains "$OUT" "To run '' in the guest" "and a detached HEAD is not reported as a branch to deviate to"
t_end
