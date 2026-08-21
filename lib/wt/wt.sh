# wt.sh — entrypoint for the wt-* dev-session helpers. Source this from ~/.bashrc:
#   . <repo>/lib/wt/wt.sh
#
# Worktree-based parallel AI dev sessions (Claude Code / OpenAI Codex) across the
# repos configured in ~/.config/wt/config.yaml. Layout: clone per repo at
# ~/repos/<key> (overridable), worktrees at ~/wt/<key>/<name>, tmux/agent session
# id "<key>--<name>".

WT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WT_ROOT_DIR="$(cd "$WT_LIB_DIR/../.." && pwd)"
export WT_ROOT_DIR

# Order matters: config first (everything reads it), commands last-ish (they use
# the helpers), completion at the end (it needs the commands to exist).
. "$WT_LIB_DIR/config.sh"
. "$WT_LIB_DIR/hooks.sh"
. "$WT_LIB_DIR/meta.sh"
. "$WT_LIB_DIR/color.sh"
. "$WT_LIB_DIR/perms.sh"
. "$WT_LIB_DIR/agent.sh"
. "$WT_LIB_DIR/worktree.sh"
. "$WT_LIB_DIR/commands.sh"
. "$WT_LIB_DIR/ide.sh"
. "$WT_LIB_DIR/help.sh"
. "$WT_LIB_DIR/completion.sh"
