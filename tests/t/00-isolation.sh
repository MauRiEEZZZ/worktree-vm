#!/usr/bin/env bash
# 00-isolation: PROVES the safety contract before any test relies on it.
# Background (2026-08-24): a test block ran `tmux kill-server` assuming
# TMUX_TMPDIR isolated it — but $TMUX overrides that, and it killed the
# operator's live tmux server with every running session on it. Hence: shim
# with cleared $TMUX + private socket, and this test proving the separation.
. "$(dirname "$0")/../lib.sh"

# 1. the shim is what PATH resolves
assert_eq "$(command -v tmux)" "$T_STUBS/tmux" "PATH resolves tmux to the test shim"

# 2. a session created through the shim exists on the PRIVATE socket...
ttmux new-session -d -s wttest-iso 'sleep 60'
assert_eq "$(ttmux list-sessions -F '#{session_name}' | grep -cx wttest-iso)" "1" \
  "session visible on the private socket"

# 3. ...and is INVISIBLE to the default server (read-only check; if no default
# server exists, e.g. in CI, that is equally proof of separation)
DEFAULT_LIST="$("$T_REAL_TMUX" list-sessions -F '#{session_name}' 2>/dev/null || true)"
assert_not_contains "$DEFAULT_LIST" "wttest-iso" "test session invisible to the default tmux server"

# 4. the sandbox HOME is not the real one and lives under the test tmp dir
REAL_HOME="$HOME"
t_sandbox_home
assert_contains "$HOME" "$T_TMP" "sandbox HOME lives under the test tmp dir"
if [ "$HOME" = "$REAL_HOME" ]; then t_fail "sandbox HOME must differ from the real HOME"; else t_pass "sandbox HOME differs from the real HOME"; fi

# 5. cleanup kills only our named session (checked implicitly by the trap; here:
# killing it by exact name works and leaves the default server's list unchanged)
ttmux kill-session -t "=wttest-iso"
assert_eq "$(ttmux list-sessions 2>/dev/null | wc -l)" "0" "private socket empty after named kill"
DEFAULT_LIST_AFTER="$("$T_REAL_TMUX" list-sessions -F '#{session_name}' 2>/dev/null || true)"
assert_eq "$DEFAULT_LIST_AFTER" "$DEFAULT_LIST" "default server session list untouched"

t_end
