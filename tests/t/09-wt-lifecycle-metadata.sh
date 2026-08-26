#!/usr/bin/env bash
# Bug (2026-08-24, fix e786c3b): only the dashboard wrote session metadata, so a
# CLI-created session left wt-rm's tombstone with nothing to archive — not
# restorable with fidelity (branch/agent/model/task lost).
# Plus (2026-08-26, fix 9963b8e): wt-rm must also clean the .parked marker.
# Real git, real tmux (private socket via the shim), gh stubbed.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home
t_use_stubs gh
export WT_NO_LAUNCH=1

# a local "remote" + pre-seeded clone so nothing talks to GitHub
git init -q --bare "$T_TMP/up.git"
git clone -q "$T_TMP/up.git" "$T_TMP/seed" 2>/dev/null
( cd "$T_TMP/seed" && git config user.email t@t && git config user.name t \
  && echo hi > README.md && git add README.md && git commit -qm init && git push -q origin HEAD:main )
mkdir -p "$T_HOME/repos" "$T_HOME/.config/wt"
git clone -q "$T_TMP/up.git" "$T_HOME/repos/demo" 2>/dev/null
printf 'repos:\n  demo: example-org/demo-repo\n' > "$T_HOME/.config/wt/config.yaml"

run_wt() { bash -c ". '$T_REPO/lib/wt/wt.sh'; $1"; }

run_wt "wt-new demo feat-a --model haiku --priority p1 --auto 'do the thing'" >/dev/null 2>&1
META="$T_HOME/.wt-sessions/demo--feat-a.json"
assert_file "$META" "wt-new writes session metadata"
FIELDS="$(node -e 'const j=require(process.argv[1]);console.log(j.repo,j.branch,j.agent,j.model,j.priority,JSON.stringify(j.task),j.auto,typeof j.createdAt)' "$META")"
assert_eq "$FIELDS" 'demo feat/feat-a claude haiku p1 "do the thing" true number' "metadata carries full restore fidelity"

# park it, then remove: tombstone must appear WITH the data, marker must be gone
mkdir -p "$T_HOME/.wt-meta"; echo 1 > "$T_HOME/.wt-meta/demo--feat-a.parked"
run_wt "wt-rm demo feat-a" >/dev/null 2>&1
TOMB="$T_HOME/.wt-sessions/archive/demo--feat-a.json"
assert_file "$TOMB" "wt-rm tombstones the metadata into archive/"
assert_contains "$(node -e 'const j=require(process.argv[1]);console.log(j.model, j.deletedAt?"deletedAt-set":"no-deletedAt")' "$TOMB")" "haiku deletedAt-set" "tombstone keeps fidelity + deletedAt"
assert_no_path "$T_HOME/.wt-sessions/demo--feat-a.json" "active metadata removed"
assert_no_path "$T_HOME/.wt-meta/demo--feat-a.parked" "the .parked marker is cleaned up"
t_end
