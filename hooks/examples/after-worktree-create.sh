#!/usr/bin/env bash
# Hook: after-worktree-create — fires at the end of worktree setup in wt-new,
# after the generic dependency restore and gitignored-config seeding, before the
# agent launches.
#   $1 = repo key    $2 = session name    $3 = worktree dir    $4 = branch
# Best-effort: a non-zero exit only prints a warning. Keep it fast + idempotent.
set -eu
# key="$1" name="$2" dir="$3" branch="$4"
# Example: touch "$3/.mycompany-marker"
exit 0
