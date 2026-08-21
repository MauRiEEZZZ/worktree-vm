#!/usr/bin/env bash
# Hook: agent-launch — fires in wt-new and wt-resume just before the agent
# starts in tmux.
#   $1 = session id (<repo>--<name>)   $2 = worktree dir
#   $3 = agent (claude|codex)          $4 = mode (new|resume)
# Best-effort: a non-zero exit only prints a warning. Keep it fast + idempotent.
set -eu
exit 0
