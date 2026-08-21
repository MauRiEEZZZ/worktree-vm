#!/usr/bin/env bash
# Hook: seed-main — fires per repo key in wt-seed-main, before the generic copy
# from the configured secrets.source (which only runs when that value is set).
#   $1 = repo key    $2 = main clone dir
# Best-effort: a non-zero exit only prints a warning. Keep it idempotent.
set -eu
# key="$1" clone="$2"
# Example: cp -f "$HOME/my-secrets/$1/.env" "$2/.env" 2>/dev/null || true
exit 0
