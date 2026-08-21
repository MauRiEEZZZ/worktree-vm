#!/usr/bin/env bash
# 95-shell.sh — wire the wt-* helpers into ~/.bashrc (marker-guarded; idempotent).
# The library stays in the repo checkout and is sourced from there, so a
# `git pull` updates the helpers with no re-provision.
set -eu -o pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if grep -q "worktree-vm dev-session helpers" ~/.bashrc 2>/dev/null; then
  echo "wt-* helpers already wired into ~/.bashrc"
  exit 0
fi
cat >> ~/.bashrc <<EOF

# --- worktree-vm dev-session helpers (wt-*) --------------------------------
[ -f "$REPO_DIR/lib/wt/wt.sh" ] && . "$REPO_DIR/lib/wt/wt.sh"
# ---------------------------------------------------------------------------
EOF
echo "wired lib/wt/wt.sh into ~/.bashrc"
