#!/usr/bin/env bash
# Bug (2026-09-07): the documented upgrade — "merge to main, then run install.sh in
# the guest" — provisioned the OLD core. install.sh provisions the clone it is IN,
# and only the boot-time provision step ever pulls that clone, so nothing between
# those two steps moved it. The guest sat four commits behind and provisioning
# re-installed the older dashboard unit over the newer one, silently undoing the
# KillMode fix that keeps a restart from killing every session.
# install.sh still must not pull (it would rewrite itself mid-run), so it says so.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home
. "$T_REPO/lib/repo-freshness.sh"

git init -q --bare "$T_TMP/up.git"
git clone -q "$T_TMP/up.git" "$T_TMP/work" 2>/dev/null
( cd "$T_TMP/work" && git config user.email t@t && git config user.name t \
  && echo one > f && git add f && git commit -qm one && git push -q origin HEAD:main )
git clone -q -b main "$T_TMP/up.git" "$T_TMP/clone" 2>/dev/null

# ---- up to date: silence ------------------------------------------------------
OUT="$(wt_warn_if_behind "$T_TMP/clone" 2>&1)"
assert_eq "$OUT" "" "a current checkout says nothing"

# ---- someone merges to main; the clone has not pulled -------------------------
( cd "$T_TMP/work" && echo two > f && git commit -qam two && git push -q origin HEAD:main )
OUT="$(wt_warn_if_behind "$T_TMP/clone" 2>&1)"
assert_contains "$OUT" "1 commit(s) behind origin/main" "a stale checkout is named, with how far behind"
assert_contains "$OUT" "provisions the OLD core" "and what that means for this run"
assert_contains "$OUT" "git -C $T_TMP/clone pull --ff-only" "and the exact command to fix it"

# ---- it warns, it does NOT pull ------------------------------------------------
assert_eq "$(git -C "$T_TMP/clone" rev-list --count HEAD..origin/main)" "1" "the checkout is left exactly where it was"

# ---- after pulling, silence again ----------------------------------------------
git -C "$T_TMP/clone" pull -q --ff-only
assert_eq "$(wt_warn_if_behind "$T_TMP/clone" 2>&1)" "" "and it stops once you have pulled"

# ---- never fails the caller on an odd checkout ---------------------------------
mkdir -p "$T_TMP/plain"
wt_warn_if_behind "$T_TMP/plain" >/dev/null 2>&1
assert_eq "$?" "0" "a directory that is not a git repo is not an error"
git -C "$T_TMP/clone" checkout -q --detach
wt_warn_if_behind "$T_TMP/clone" >/dev/null 2>&1
assert_eq "$?" "0" "nor is a detached HEAD"
t_end
