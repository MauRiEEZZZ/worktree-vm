#!/usr/bin/env bash
# Gap (2026-09-03): wt-resume could only restart a session idle. Waking a crashed
# session then cost a second round — a message to tell it what to do — where both
# agents accept a prompt right next to their continue/resume flag
# (`claude --continue [prompt]`, `codex resume --last [PROMPT]`).
# Real git, real tmux (private socket via the shim), claude stubbed so the launch
# path runs for real and records its argv.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home
t_use_stubs gh claude
export STUB_LOG="$T_TMP/stub.log"

git init -q --bare "$T_TMP/up.git"
git clone -q "$T_TMP/up.git" "$T_TMP/seed" 2>/dev/null
( cd "$T_TMP/seed" && git config user.email t@t && git config user.name t \
  && echo hi > README.md && git add README.md && git commit -qm init && git push -q origin HEAD:main )
mkdir -p "$T_HOME/repos" "$T_HOME/.config/wt"
git clone -q "$T_TMP/up.git" "$T_HOME/repos/demo" 2>/dev/null
printf 'repos:\n  demo: example-org/demo-repo\n' > "$T_HOME/.config/wt/config.yaml"

run_wt() { bash -c ". '$T_REPO/lib/wt/wt.sh'; $1"; }
last_launch() { for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$STUB_LOG" ] && break; sleep 0.2; done; tail -1 "$STUB_LOG" 2>/dev/null; }

run_wt "wt-new demo feat-a --auto 'first task'" >/dev/null 2>&1
assert_contains "$(last_launch)" "first task" "wt-new passes the opening task"
ttmux kill-session -t "=demo--feat-a" 2>/dev/null

# ---- resume with a task ---------------------------------------------------------
: > "$STUB_LOG"
run_wt "wt-resume demo feat-a --task now do the next item" >/dev/null 2>&1
LAUNCH="$(last_launch)"
assert_contains "$LAUNCH" "--continue" "resume still continues the conversation"
assert_contains "$LAUNCH" "now do the next item" "and hands it the new task in the same launch"
ttmux kill-session -t "=demo--feat-a" 2>/dev/null

# ---- base64 form, for quoting-hostile tasks -------------------------------------
: > "$STUB_LOG"
B64="$(printf '%s' 'fix "the" thing' | base64 | tr -d '\n')"
run_wt "wt-resume demo feat-a --task-b64 $B64" >/dev/null 2>&1
assert_contains "$(last_launch)" 'fix "the" thing' "--task-b64 survives the quoting"
ttmux kill-session -t "=demo--feat-a" 2>/dev/null

# ---- no task = exactly what it did before ---------------------------------------
: > "$STUB_LOG"
run_wt "wt-resume demo feat-a" >/dev/null 2>&1
assert_eq "$(last_launch)" "claude --continue --remote-control wt/demo/feat-a" "without --task the launch is unchanged"
ttmux kill-session -t "=demo--feat-a" 2>/dev/null

# ---- a running session cannot be handed a task; it must say so ------------------
# A real session that stays up: the claude stub exits at once, so hold the tmux
# session open with a sleep instead of pretending the stub is a live agent.
WT_NO_LAUNCH=1 run_wt "wt-new demo feat-b --auto" >/dev/null 2>&1
ttmux new-session -d -s "demo--feat-b" -c "$T_HOME/wt/demo/feat-b" "sleep 30"
OUT="$(run_wt "wt-resume demo feat-b --task please continue" 2>&1)"
assert_contains "$OUT" "already running" "a live session is attached, not relaunched"
assert_contains "$OUT" "--task ignored" "a task for a live session is never dropped silently"
ttmux kill-session -t "=demo--feat-b" 2>/dev/null
t_end
