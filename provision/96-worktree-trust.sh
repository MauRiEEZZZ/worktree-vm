#!/usr/bin/env bash
# 96-worktree-trust.sh — re-assert Claude Code folder trust for every existing
# worktree (~/wt/<repo>/<name>).
#
# Why this exists: ~/.claude.json (which holds the folder-trust list) lives on
# the guest's native disk and is rewritten ATOMICALLY by Claude Code, so it can
# neither be symlinked onto the Lima data disk (rename(2) replaces the symlink)
# nor usefully protected by a one-way provision-time copy (the disk snapshot
# goes stale immediately). Instead of synchronising the file, we make the part
# that matters SELF-HEALING: every provision run re-asserts trust for every
# worktree that exists. A stale or empty restored ~/.claude.json is then
# harmless — without this, each worktree re-prompts for trust after a rebuild,
# which hangs exactly the unattended (--auto) sessions.
#
# Worktrees created AFTER this run get trust the normal way: wt-new/wt-resume
# call _wt_seed_perms for unattended sessions, and interactive sessions answer
# the dialog once. On the next provision run they are swept up here too.
# Idempotent; harmless on WSL/plain Ubuntu (everything is durable there, the
# re-assert is a no-op refresh).
set -eu -o pipefail

command -v node >/dev/null 2>&1 || { echo "node not available; skipping trust re-assert"; exit 0; }
WT_TREES="$HOME/wt"
[ -d "$WT_TREES" ] || { echo "no $WT_TREES yet; nothing to trust"; exit 0; }
dirs=()
for d in "$WT_TREES"/*/*; do
  [ -e "$d/.git" ] && dirs+=("$d")   # a worktree's .git is a file (gitdir pointer)
done
[ "${#dirs[@]}" -gt 0 ] || { echo "no worktrees; nothing to trust"; exit 0; }
node -e '
const fs = require("fs"), os = require("os");
const f = os.homedir() + "/.claude.json";
let j = {}; try { j = JSON.parse(fs.readFileSync(f, "utf8")); } catch {}
j.projects = j.projects || {};
let fresh = 0;
for (const p of process.argv.slice(1)) {
  j.projects[p] = j.projects[p] || {};
  if (!j.projects[p].hasTrustDialogAccepted) { j.projects[p].hasTrustDialogAccepted = true; fresh++; }
}
fs.writeFileSync(f + ".tmp", JSON.stringify(j, null, 2));
fs.renameSync(f + ".tmp", f);
console.log(`worktree trust: ${process.argv.length - 1} worktree(s) asserted (${fresh} newly)`);
' "${dirs[@]}"
