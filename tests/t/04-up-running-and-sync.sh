#!/usr/bin/env bash
# Bug (2026-08-25, fix 91c1899): on a RUNNING instance, `limactl start` is a
# silent no-op (provisioning only runs at boot), yet up.sh printed "re-running
# provisioning" and exited 0 in a second — the user thought their change was
# applied. Must refuse honestly with the real options. And --sync-config is the
# route that actually applies host config edits to a running guest.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home
t_use_stubs limactl
export STUB_LOG="$T_TMP/stub.log"; : > "$STUB_LOG"
export FAKE_DISKS='{"name":"t-data","size":1,"dir":"/x","instance":"t"}'
export FAKE_GUEST_HOME="$T_TMP/guest"; mkdir -p "$FAKE_GUEST_HOME"
ln -s "$T_REPO" "$FAKE_GUEST_HOME/worktree-vm"

cat > "$T_TMP/cfg.yaml" <<'EOF'
repos:
  demo: octocat/Hello-World
dashboard:
  port: 7311
lima:
  instance: t
  data_disk: t-data
EOF

# RUNNING + no flag -> honest refusal, nonzero, and NO start call
export FAKE_INSTANCES='{"name":"t","status":"Running","dir":"/y"}'
OUT="$(bash "$T_REPO/platform/lima/up.sh" "$T_TMP/cfg.yaml" 2>&1)"; RC=$?
if [ "$RC" != 0 ]; then t_pass "running instance: refuses (nonzero exit)"; else t_fail "running instance: must not exit 0"; fi
assert_contains "$OUT" "refusing" "refusal says so explicitly"
assert_contains "$OUT" "sync-config" "refusal points at --sync-config"
assert_not_contains "$(cat "$STUB_LOG")" "limactl start" "no start was issued"

# STOPPED + no flag -> boots (start called)
export FAKE_INSTANCES='{"name":"t","status":"Stopped","dir":"/y"}'
OUT2="$(WT_LIMA_OUT="$T_TMP/render.yaml" bash "$T_REPO/platform/lima/up.sh" "$T_TMP/cfg.yaml" 2>&1)"; RC2=$?
assert_eq "$RC2" "0" "stopped instance: proceeds"
assert_contains "$(cat "$STUB_LOG")" "limactl start" "stopped instance: start issued"

# --sync-config + RUNNING -> config lands byte-identical, env regenerated, dashboard restarted
export FAKE_INSTANCES='{"name":"t","status":"Running","dir":"/y"}'
OUT3="$(bash "$T_REPO/platform/lima/up.sh" --sync-config "$T_TMP/cfg.yaml" 2>&1)"; RC3=$?
assert_eq "$RC3" "0" "--sync-config on a running guest succeeds"
if cmp -s "$T_TMP/cfg.yaml" "$FAKE_GUEST_HOME/.config/wt/config.yaml"; then t_pass "guest config byte-identical to host config"; else t_fail "guest config differs"; fi
assert_contains "$(grep '^PORT=' "$FAKE_GUEST_HOME/.config/wt/dashboard.env")" "7311" "derived env regenerated in the guest"
assert_contains "$(cat "$STUB_LOG")" "systemctl restart wt-dashboard" "dashboard restart issued"

# --sync-config + STOPPED -> polite refusal
export FAKE_INSTANCES='{"name":"t","status":"Stopped","dir":"/y"}'
OUT4="$(bash "$T_REPO/platform/lima/up.sh" --sync-config "$T_TMP/cfg.yaml" 2>&1)"; RC4=$?
if [ "$RC4" != 0 ]; then t_pass "--sync-config on a stopped guest refuses"; else t_fail "--sync-config on a stopped guest must refuse"; fi
t_end
