#!/usr/bin/env bash
# The template used to hard-code a read-only mount of the whole host home. On a
# macOS host that is not harmless: a tool in the guest that walks `/` (a plain
# `find /`) reaches the protected folders under the home through the mount,
# macOS raises a privacy prompt, and until someone answers it on the host ALL
# file access through the mount blocks — every guest process touching it hangs.
# lima.host_mounts makes the mount list configurable. Contract tested here:
#  * absent key = exactly the old rendering (existing configs do not change);
#  * a list renders one read-only mount per path; `none` / [] render no mounts;
#  * render-time warnings name what a narrowed list cuts off (the host checkout
#    the guest clones from, and host paths the guest reads from the config).
. "$(dirname "$0")/../lib.sh"
t_sandbox_home
t_use_stubs limactl
export FAKE_DISKS='{"name":"t-data","size":1,"dir":"/x","instance":"t"}' FAKE_INSTANCES=''
mkdir -p "$T_HOME/code" "$T_HOME/hooks" "$T_HOME/secrets"

# render <config-body>: writes $T_TMP/cfg.yaml, renders; sets MOUNTS (the mount
# block of the rendered file) and ERR (up.sh's stderr)
render() {
  printf '%s\n' "$1" > "$T_TMP/cfg.yaml"
  rm -f "$T_TMP/render.yaml"
  ERR="$(WT_LIMA_OUT="$T_TMP/render.yaml" bash "$T_REPO/platform/lima/up.sh" "$T_TMP/cfg.yaml" 2>&1 >/dev/null)"
  MOUNTS="$(sed -n '/^mountType:/,/^$/p' "$T_TMP/render.yaml" 2>/dev/null)"
}
BASE='lima:
  instance: t
  data_disk: t-data'

LEGACY='mountType: "virtiofs"
mounts:
  - location: "~"
    writable: false   # read-only: copy things out if needed; real work lives on the VM disk'

# ---- default: byte-identical to the historical hard-coded block ----------------
render "$BASE"
assert_eq "$MOUNTS" "$LEGACY" "absent key renders exactly the old whole-home mount"
cp "$T_TMP/render.yaml" "$T_TMP/default.yaml"
render "$BASE
  host_mounts: [\"~\"]"
# (the config is embedded verbatim in the render, so its one extra line is dropped)
D="$(diff "$T_TMP/default.yaml" <(grep -v 'host_mounts:' "$T_TMP/render.yaml"))"
assert_eq "$D" "" "explicit [\"~\"] renders byte-identical to the absent key"

# ---- a two-path list (dash form, ~ expanded, trailing slash dropped) -------------
render "$BASE
  host_mounts:
    - ~/code/
    - $T_REPO"
assert_eq "$MOUNTS" "mountType: \"virtiofs\"
mounts:
  - location: \"$T_HOME/code\"
    writable: false   # read-only: copy things out if needed; real work lives on the VM disk
  - location: \"$T_REPO\"
    writable: false   # read-only: copy things out if needed; real work lives on the VM disk" \
  "two paths render two read-only mounts at the expanded paths"
assert_not_contains "$MOUNTS" 'location: "~"' "…and the whole home is no longer mounted"

# ---- none / empty list: no mounts at all -----------------------------------------
render "$BASE
  host_mounts: none"
assert_eq "$MOUNTS" 'mountType: "virtiofs"
mounts: []' "host_mounts: none renders mounts: []"
render "$BASE
  host_mounts: []"
assert_eq "$MOUNTS" 'mountType: "virtiofs"
mounts: []' "host_mounts: [] renders mounts: [] (not a fallback to the whole home)"

# ---- a relative entry is refused before anything is rendered -----------------------
render "$BASE
  host_mounts: [relative/dir]"
assert_contains "$ERR" "not an absolute path" "a relative entry is an error"
assert_no_path "$T_TMP/render.yaml" "…and nothing is rendered"

# ---- warnings ----------------------------------------------------------------------
CFG_PATHS="hooks:
  dir: $T_HOME/hooks
secrets:
  source: $T_HOME/secrets
clone_paths:
  demo: $T_HOME/code/demo"

render "$CFG_PATHS
$BASE
  host_mounts: none"
assert_contains "$ERR" "$T_REPO is not under any lima.host_mounts path — the guest will clone from https://" \
  "uncovered host checkout: warns that the guest clones from the public URL"
assert_contains "$ERR" "hooks.dir = $T_HOME/hooks is not under any lima.host_mounts path — the guest cannot read it" \
  "uncovered hooks.dir warns"
assert_contains "$ERR" "secrets.source = $T_HOME/secrets is not under any lima.host_mounts path" \
  "uncovered secrets.source warns"
assert_contains "$ERR" "clone_paths.demo = $T_HOME/code/demo is not under any lima.host_mounts path" \
  "uncovered absolute clone_paths entry warns"
assert_file "$T_TMP/render.yaml" "warnings are not fatal: the file is still rendered"

render "$CFG_PATHS
$BASE
  host_mounts: [~, $T_REPO]"
assert_not_contains "$ERR" "lima.host_mounts" "every path covered: no warnings"

render "$CFG_PATHS
$BASE
  host_mounts: [~/hooks, $T_REPO]"
assert_not_contains "$ERR" "hooks.dir" "a mount of exactly that directory covers it"
assert_contains "$ERR" "secrets.source = $T_HOME/secrets" "…while a sibling outside the mount still warns"

# ~/... in the config expands to the GUEST home in the guest: guest-local, no warning
render "hooks:
  dir: ~/hooks
$BASE
  host_mounts: none"
assert_not_contains "$ERR" "hooks.dir" "a ~/ path is guest-local: no warning"
t_end
