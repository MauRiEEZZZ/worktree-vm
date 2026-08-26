#!/usr/bin/env bash
# Bug (2026-08-25, fix 46a0b8f): `limactl disk ls` has no -q (only `limactl
# list` does); `disk ls -q 2>/dev/null` swallowed the flag error, grep saw
# nothing, and up.sh tried to create the data disk on EVERY run — dying fatally
# ("disk already exists") on the exact re-provision flow the README documents.
# The stub rejects -q with Lima's real error; existence must go via --json,
# stderr must stay visible, and no create may run when the disk exists.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home
t_use_stubs limactl
export STUB_LOG="$T_TMP/stub.log"; : > "$STUB_LOG"
export FAKE_DISKS='{"name":"t-data","size":1,"dir":"/x","instance":"t"}'
export FAKE_INSTANCES=''

cat > "$T_TMP/cfg.yaml" <<'EOF'
repos:
  demo: octocat/Hello-World
lima:
  instance: t
  data_disk: t-data
EOF
OUT="$(WT_LIMA_OUT="$T_TMP/render.yaml" bash "$T_REPO/platform/lima/up.sh" "$T_TMP/cfg.yaml" 2>&1)"; RC=$?
assert_eq "$RC" "0" "up.sh proceeds with an existing disk (no fatal)"
assert_not_contains "$OUT" "already exists" "no create attempted for an existing disk"
assert_not_contains "$(cat "$STUB_LOG")" "disk create" "stub log confirms: zero create calls"
assert_contains "$OUT" "rendered" "up.sh reached rendering"
# a broken listing must abort loudly, not guess
FAKE_DISKS_BREAK=1
cat > "$T_STUBS/limactl" <<'EOF'
#!/usr/bin/env bash
[ "$1 ${2:-}" = "disk ls" ] && { echo "Error: something unexpected" >&2; exit 1; }
[ "$1" = list ] && { echo ""; exit 0; }
exit 0
EOF
chmod +x "$T_STUBS/limactl"
OUT2="$(WT_LIMA_OUT="$T_TMP/render2.yaml" bash "$T_REPO/platform/lima/up.sh" "$T_TMP/cfg.yaml" 2>&1)"; RC2=$?
if [ "$RC2" != 0 ]; then t_pass "a failing listing aborts"; else t_fail "a failing listing must abort"; fi
assert_contains "$OUT2" "not guessing" "abort message is explicit"
t_end
