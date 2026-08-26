#!/usr/bin/env bash
# Bug (2026-08-25, fixes eb5f6e8 + e55af01): two halves of the same file.
# (a) ~/.claude.json is a FILE; the generic dir-link loop's `mkdir -p` fallback
#     would create a DIRECTORY with that name on a fresh disk and break Claude
#     Code outright. The file variant must seed an empty {} instead.
# (b) the provision-time copy is one-way (Claude Code rewrites the file
#     atomically, so nothing syncs back); folder trust must therefore be
#     RE-ASSERTED for every existing worktree (96-worktree-trust.sh), making a
#     stale or empty restored file harmless.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home
t_use_stubs sudo mountpoint findmnt

GUEST="$T_TMP/guest"; MNT="$T_TMP/mnt"; mkdir -p "$GUEST" "$MNT"
# fresh disk, brand-new home: no ~/.claude.json anywhere
FAKE_MOUNT="$MNT" HOME="$GUEST" WT_DATA_MOUNT="$MNT" bash "$T_REPO/platform/lima/data-disk.sh" >/dev/null
assert_regular_file "$GUEST/.claude.json" "~/.claude.json is a regular FILE (not a directory) on a fresh disk"
assert_eq "$(cat "$GUEST/.claude.json")" "{}" "seeded as an empty JSON object"
assert_regular_file "$MNT/.claude.json" "the disk snapshot is a file too"

# rebuild: empty home, disk holds a snapshot -> restored as a file
GUEST2="$T_TMP/guest2"; mkdir -p "$GUEST2"
echo '{"projects":{"/old":{"hasTrustDialogAccepted":true}}}' > "$MNT/.claude.json"
FAKE_MOUNT="$MNT" HOME="$GUEST2" WT_DATA_MOUNT="$MNT" bash "$T_REPO/platform/lima/data-disk.sh" >/dev/null
assert_regular_file "$GUEST2/.claude.json" "restored as a regular file on rebuild"
assert_contains "$(cat "$GUEST2/.claude.json")" '/old' "restored content intact"

# trust re-assertion over existing worktrees (the one-way copy is only a net)
mkdir -p "$GUEST2/wt/demo/a" "$GUEST2/wt/demo/b"
touch "$GUEST2/wt/demo/a/.git" "$GUEST2/wt/demo/b/.git"
HOME="$GUEST2" bash "$T_REPO/provision/96-worktree-trust.sh" >/dev/null
TRUST="$(HOME="$GUEST2" node -e 'const j=require(process.env.HOME+"/.claude.json");const p=j.projects;console.log(["a","b"].every(n=>p[process.env.HOME+"/wt/demo/"+n]&&p[process.env.HOME+"/wt/demo/"+n].hasTrustDialogAccepted)?"all-trusted":"missing", p["/old"]?"old-kept":"old-lost")')"
assert_eq "$TRUST" "all-trusted old-kept" "trust re-asserted for every worktree; unrelated entries kept"
t_end
