#!/usr/bin/env bash
# Hook: post-provision — fires at the end of install.sh, after all provision
# steps. No arguments.
# Typical overlay uses: import a stable ASP.NET dev certificate, seed
# ~/.claude/CLAUDE.md with project conventions, merge host Claude settings into
# the guest, copy extra skills into ~/.claude/skills.
# Best-effort: a non-zero exit only prints a warning. Keep it idempotent —
# install.sh may be re-run at any time.
set -eu
exit 0
