# tests/lib.sh — shared harness for the shell tests. Zero external deps.
#
# ISOLATION CONTRACT (hard requirement — the suite runs on dev VMs where the
# operator's own tmux server and live session data sit right next to it):
#  * every test gets a FRESH temporary HOME; nothing may touch the real
#    ~/.claude, ~/.wt-meta, the sessions metadata dir or any data disk.
#  * every tmux invocation — from tests AND from code under test — goes through
#    a shim that clears $TMUX (which would otherwise override any socket
#    setting and hit the OPERATOR'S server) and targets a test-private socket.
#    Only sessions on that private socket are ever created or killed; cleanup
#    kills them by exact name and NEVER runs kill-server.
#  * tools that must not run for real (limactl, gh, sudo, ...) are opt-in stubs.
# tests/t/00-isolation.sh proves this contract before anything else runs.
set -u

T_TEST_NAME="$(basename "$0" .sh)"
T_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T_TMP="$(mktemp -d "${TMPDIR:-/tmp}/wt-test.XXXXXX")"
T_HOME="$T_TMP/home"
T_STUBS="$T_TMP/stubs"
mkdir -p "$T_HOME" "$T_STUBS"
T_REAL_TMUX="$(command -v tmux || echo /usr/bin/tmux)"
T_SOCK="wt-test-$$"
export T_REPO T_TMP T_HOME T_REAL_TMUX T_SOCK

# ---- assertions ---------------------------------------------------------------
_t_n=0; _t_failed=0
t_pass() { _t_n=$((_t_n + 1)); echo "  ok $_t_n - $1"; }
t_fail() { _t_n=$((_t_n + 1)); _t_failed=1; echo "  NOT OK $_t_n - $1"; }
assert_eq()           { if [ "$1" = "$2" ]; then t_pass "$3"; else t_fail "$3 (expected [$2], got [$1])"; fi; }
assert_contains()     { case "$1" in *"$2"*) t_pass "$3" ;; *) t_fail "$3 (missing [$2])" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) t_fail "$3 (unexpected [$2])" ;; *) t_pass "$3" ;; esac; }
assert_file()         { if [ -f "$1" ]; then t_pass "$2"; else t_fail "$2 (no file: $1)"; fi; }
assert_no_path()      { if [ ! -e "$1" ]; then t_pass "$2"; else t_fail "$2 (unexpectedly exists: $1)"; fi; }
assert_symlink()      { if [ -L "$1" ]; then t_pass "$2"; else t_fail "$2 (not a symlink: $1)"; fi; }
assert_regular_file() { if [ -f "$1" ] && [ ! -L "$1" ] && [ ! -d "$1" ]; then t_pass "$2"; else t_fail "$2 (not a regular file: $1)"; fi; }
t_skip_all() { echo "  SKIP - $1"; exit 77; }

# ---- tmux shim (ALWAYS installed: safety default) -------------------------------
# Clears $TMUX (it would override any socket choice) and pins the private socket.
cat > "$T_STUBS/tmux" <<EOF
#!/usr/bin/env bash
exec env -u TMUX "$T_REAL_TMUX" -L "$T_SOCK" "\$@"
EOF
chmod +x "$T_STUBS/tmux"
PATH="$T_STUBS:$PATH"
export PATH

# ---- opt-in stubs ----------------------------------------------------------------
t_use_stubs() {  # copy named stubs from tests/stubs into the test PATH
  local s
  for s in "$@"; do
    cp "$T_REPO/tests/stubs/$s" "$T_STUBS/$s" && chmod +x "$T_STUBS/$s"
  done
}

# ---- helpers ---------------------------------------------------------------------
ttmux() { "$T_STUBS/tmux" "$@"; }   # explicit: tmux on the test-private socket
t_sandbox_home() { HOME="$T_HOME"; export HOME; }

# ---- cleanup ---------------------------------------------------------------------
t_cleanup() {
  local s
  # kill ONLY sessions on the private test socket, by exact name; never kill-server
  # (the private server exits by itself once its last session is gone)
  for s in $(env -u TMUX "$T_REAL_TMUX" -L "$T_SOCK" list-sessions -F '#{session_name}' 2>/dev/null); do
    env -u TMUX "$T_REAL_TMUX" -L "$T_SOCK" kill-session -t "=$s" 2>/dev/null || true
  done
  rm -rf "$T_TMP"
}
trap t_cleanup EXIT

t_end() {
  if [ "$_t_failed" = 0 ]; then echo "PASS $T_TEST_NAME ($_t_n assertions)"; exit 0
  else echo "FAIL $T_TEST_NAME"; exit 1; fi
}
