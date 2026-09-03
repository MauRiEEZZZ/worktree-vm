#!/usr/bin/env bash
# Bug (2026-09-03): a session that finished its work and correctly refused to do the
# outward step (push / draft PR) had no way to SAY so anywhere anyone looks. It said
# it in its own tmux pane and stopped; two PRs then sat for 3 and 16 hours.
# wt-handoff writes a marker the dashboard lifts to the top.
# Real git, real tmux (private socket via the shim), gh + claude stubbed.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home
t_use_stubs gh claude
export WT_NO_LAUNCH=1

git init -q --bare "$T_TMP/up.git"
git clone -q "$T_TMP/up.git" "$T_TMP/seed" 2>/dev/null
( cd "$T_TMP/seed" && git config user.email t@t && git config user.name t \
  && echo hi > README.md && git add README.md && git commit -qm init && git push -q origin HEAD:main )
mkdir -p "$T_HOME/repos" "$T_HOME/.config/wt"
git clone -q "$T_TMP/up.git" "$T_HOME/repos/demo" 2>/dev/null
printf 'repos:\n  demo: example-org/demo-repo\n' > "$T_HOME/.config/wt/config.yaml"

run_wt() { bash -c ". '$T_REPO/lib/wt/wt.sh'; $1"; }
MARK="$T_HOME/.wt-meta/demo--feat-a.handoff"

run_wt "wt-new demo feat-a --auto" >/dev/null 2>&1

# ---- the everyday call: a bare message from inside the worktree ---------------
run_wt "cd '$T_HOME/wt/demo/feat-a' && wt-handoff 'ready for wt-push + draft PR: Show the rejection reason'" >/dev/null 2>&1
assert_file "$MARK" "a session inside its worktree can hand over without naming itself"
assert_eq "$(cat "$MARK")" "ready for wt-push + draft PR: Show the rejection reason" "the line is stored verbatim"

# ---- explicit <repo> <name>, from anywhere ------------------------------------
run_wt "wt-handoff demo feat-a needs a push" >/dev/null 2>&1
assert_eq "$(cat "$MARK")" "needs a push" "an explicit repo/name works from outside the worktree"

# ---- a message that merely starts with a known repo key is still a message ----
run_wt "cd '$T_HOME/wt/demo/feat-a' && wt-handoff demo is broken, needs a rebuild" >/dev/null 2>&1
assert_eq "$(cat "$MARK")" "demo is broken, needs a rebuild" "prose is not mistaken for repo/name arguments"

# ---- clearing, and cleanup with the session -----------------------------------
run_wt "wt-handoff demo feat-a --clear" >/dev/null 2>&1
assert_no_path "$MARK" "--clear removes the marker"
run_wt "cd '$T_HOME/wt/demo/feat-a' && wt-handoff 'ready'" >/dev/null 2>&1
run_wt "wt-rm demo feat-a" >/dev/null 2>&1
assert_no_path "$MARK" "wt-rm cleans it up with the rest of the markers"

# ---- an empty call refuses instead of writing an empty flag -------------------
OUT="$(run_wt "cd '$T_HOME/wt/demo' && wt-handoff" 2>&1)"
assert_contains "$OUT" "not inside a worktree" "outside a worktree it says so"
t_end
