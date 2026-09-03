#!/usr/bin/env bash
# Bug (2026-09-03): a reviewer session could not read the dev worktree it exists to
# review. The seeded settings.local.json listed "Read"/"Bash" but no
# additionalDirectories, so the first look outside its own worktree was refused and
# an unattended reviewer stopped on "3 consecutive actions were blocked" — measured
# on portal--7560-escalation-flow-list-rv, dead at a grep into ~/wt/portal/7560-….
# Guards: --read-dir lands in additionalDirectories, survives a resume, and
# wt-review passes the dev worktree without being asked.
# Real git, real tmux (private socket via the shim), gh + claude stubbed.
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
dirs_of() { node -e 'const j=require(process.argv[1]);console.log((j.permissions.additionalDirectories||[]).join(" "))' "$1" 2>/dev/null; }

# ---- 1. an ordinary --auto session gets no extra directories ------------------
run_wt "wt-new demo plain --auto" >/dev/null 2>&1
PLAIN="$T_HOME/wt/demo/plain/.claude/settings.local.json"
assert_file "$PLAIN" "an --auto session is seeded"
assert_eq "$(dirs_of "$PLAIN")" "" "no --read-dir means no extra directories"

# ---- 2. --read-dir lands in additionalDirectories -----------------------------
run_wt "wt-new demo rv --auto --deny-post --read-dir '$T_HOME/wt/demo/plain' --read-dir '$T_HOME/.wt-meta'" >/dev/null 2>&1
RV="$T_HOME/wt/demo/rv/.claude/settings.local.json"
assert_eq "$(dirs_of "$RV")" "$T_HOME/wt/demo/plain $T_HOME/.wt-meta" "--read-dir is repeatable and lands in additionalDirectories"
assert_contains "$(cat "$RV" 2>/dev/null)" '"Bash(wt-push:*)"' "the outward-action ASK rules are still there"

# ---- 3. it survives a resume (a marker, not the argv, is the memory) ----------
assert_eq "$(cat "$T_HOME/.wt-meta/demo--rv.readdirs")" "$T_HOME/wt/demo/plain $T_HOME/.wt-meta" "the read dirs are remembered per session"
rm -f "$RV"
ttmux kill-session -t "=demo--rv" 2>/dev/null   # the stub already exited; make the state explicit
run_wt "wt-resume demo rv" >/dev/null 2>&1
assert_eq "$(dirs_of "$RV")" "$T_HOME/wt/demo/plain $T_HOME/.wt-meta" "wt-resume re-seeds them instead of narrowing access"

# ---- 4. wt-review asks for the dev worktree by itself -------------------------
# wt-new is shadowed so the assertion is about the ARGUMENTS wt-review passes, not
# about a second worktree appearing.
ARGS="$(bash -c ". '$T_REPO/lib/wt/wt.sh'; wt-new() { echo \"\$*\"; }; wt-review demo plain --scope committed" 2>/dev/null | tail -1)"
assert_contains "$ARGS" "--read-dir $T_HOME/wt/demo/plain" "wt-review grants the reviewer the worktree it reviews"
t_end
