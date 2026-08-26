#!/usr/bin/env bash
# Bug (2026-08-24): tmux resolves -t by exact match, then PREFIX, then fnmatch.
# Bare session ids made wt-ls report a stopped session as running (has-session
# matched its <sid>-review neighbour), wt-resume refuse to start it, and wt-rm
# able to kill the NEIGHBOUR's tmux. Fix fe8fed0: '=' exact targets everywhere.
# Bug (2026-08-25): '=<sid>' is only a SESSION target; capture-pane/send-keys
# need a PANE target — '=<sid>' gave "can't find pane" / zero lines, so the
# dashboard read the wrong (or no) pane. Fix a9a7d68: '=<sid>:' for pane-taking
# commands. All tmux here runs on the test-private socket (see lib.sh).
. "$(dirname "$0")/../lib.sh"
t_sandbox_home

# --- the tmux semantics that caused it all (documented as assertions) ----------
ttmux new-session -d -s wttest-p-review "bash -c 'echo MARKER_REVIEW; sleep 120'"
# only the -review neighbour exists: bare prefix target matches it, '=' does not
if ttmux has-session -t wttest-p 2>/dev/null; then t_pass "bare target prefix-matches the neighbour (the trap exists)"; else t_fail "expected tmux prefix matching"; fi
if ttmux has-session -t "=wttest-p" 2>/dev/null; then t_fail "'=' target must not prefix-match"; else t_pass "'=' target does not prefix-match"; fi
ttmux new-session -d -s wttest-p "bash -c 'echo MARKER_P; sleep 120'"
sleep 1
# pane-taking commands: '=name' fails, '=name:' captures the RIGHT pane
if ttmux capture-pane -t "=wttest-p" -p >/dev/null 2>&1; then t_fail "'=name' unexpectedly valid as a pane target"; else t_pass "'=name' fails for capture-pane (why the ':' form exists)"; fi
CAP="$(ttmux capture-pane -t "=wttest-p:" -p 2>/dev/null)"
assert_contains "$CAP" "MARKER_P" "'=name:' captures the session's own pane"
assert_not_contains "$CAP" "MARKER_REVIEW" "'=name:' never leaks the neighbour's pane"

# --- the repo code must use those forms ----------------------------------------
# session targets: '=' everywhere; no bare -t "$sid" left in the wt library
BARE="$(grep -rnE 'tmux (has-session|kill-session|attach|switch-client) -t "(\$|ide-\$)' "$T_REPO/lib/wt" || true)"
assert_eq "$BARE" "" "no bare session targets left in lib/wt"
# pane targets: server.js routes capture-pane through paneTarget() which appends ':'
assert_contains "$(grep 'capture-pane' "$T_REPO/dashboard/server.js")" "paneTarget(" "server.js capture-pane uses paneTarget()"
assert_contains "$(grep 'paneTarget = ' "$T_REPO/dashboard/server.js")" '=${sid}:' "paneTarget() appends the ':' pane form"
assert_contains "$(grep 'send-keys' "$T_REPO/lib/wt/color.sh")" '=$sid:' "color.sh send-keys uses the '=sid:' pane form"

# --- functional: wt-ls with only the -review neighbour running ------------------
mkdir -p "$T_HOME/wt/demo/x" "$T_HOME/wt/demo/x-review"
touch "$T_HOME/wt/demo/x/.git" "$T_HOME/wt/demo/x-review/.git"
ttmux new-session -d -s demo--x-review "sleep 120"
LS="$(bash -c ". '$T_REPO/lib/wt/wt.sh'; wt-ls" | cat)"
assert_contains "$(printf '%s\n' "$LS" | awk -F'\t' '$2=="x"{print $4}')" "stopped" "wt-ls reports the base session as stopped"
assert_contains "$(printf '%s\n' "$LS" | awk -F'\t' '$2=="x-review"{print $4}')" "running" "wt-ls reports the -review neighbour as running"
t_end
