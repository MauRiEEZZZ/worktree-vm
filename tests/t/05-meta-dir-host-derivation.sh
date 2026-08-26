#!/usr/bin/env bash
# Bug (2026-08-25, fix 2317586): the data-disk step runs BEFORE the guest config
# is seeded, so deriving sessions.meta_dir in the guest could only ever find the
# default — a configured meta_dir silently stayed on the volatile disk: the
# exact data loss the persistence round was meant to fix, hidden by ordering.
# up.sh must derive it on the HOST and inject it into the rendered step.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home
t_use_stubs limactl sudo mountpoint findmnt
export FAKE_DISKS='{"name":"t-data","size":1,"dir":"/x","instance":"t"}' FAKE_INSTANCES=''

cat > "$T_TMP/cfg.yaml" <<'EOF'
repos:
  demo: octocat/Hello-World
sessions:
  meta_dir: ~/.custom-sessions
lima:
  instance: t
  data_disk: t-data
EOF
WT_LIMA_OUT="$T_TMP/render.yaml" bash "$T_REPO/platform/lima/up.sh" "$T_TMP/cfg.yaml" >/dev/null 2>&1
assert_contains "$(cat "$T_TMP/render.yaml")" 'WT_SESSIONS_DIR="$HOME/.custom-sessions"' \
  "the rendered data-disk step carries the host-derived meta_dir"

# execute that step exactly as a FIRST provision (guest has NO config yet)
GUEST="$T_TMP/guest"; MNT="$T_TMP/mnt"; mkdir -p "$GUEST" "$MNT"
ln -s "$T_REPO" "$GUEST/worktree-vm"
node -e '
const yaml = require("fs").readFileSync(process.argv[1], "utf8");
// extract the data-disk provision script (block scalar) without a YAML lib:
const lines = yaml.split("\n"); let out = [], grab = false;
for (const l of lines) {
  if (grab) { if (/^    script: \|/.test(l) || /^  - mode:/.test(l) || /^[a-z]/.test(l)) grab = false; else out.push(l.replace(/^      /, "")); }
  if (/WT_DATA_MOUNT/.test(l)) { grab = true; out.push(l.replace(/^      /, "")); }
}
require("fs").writeFileSync(process.argv[2], out.join("\n"));
' "$T_TMP/render.yaml" "$T_TMP/dd-step.sh"
sed -i "s|/mnt/lima-t-data|$MNT|" "$T_TMP/dd-step.sh"
FAKE_MOUNT="$MNT" HOME="$GUEST" bash "$T_TMP/dd-step.sh" >/dev/null 2>&1

assert_symlink "$GUEST/.custom-sessions" "exactly the configured meta_dir is linked onto the disk"
assert_eq "$(readlink "$GUEST/.custom-sessions")" "$MNT/.custom-sessions" "…and points at the data disk"
assert_no_path "$GUEST/.wt-sessions" "the DEFAULT .wt-sessions is NOT created"
t_end
