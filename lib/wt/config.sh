# config.sh — load the derived config env (generated from ~/.config/wt/config.yaml
# by lib/config/generate-env.sh), apply defaults, and define the path/id helpers.

WT_CONFIG_DIR="${WT_CONFIG_DIR:-$HOME/.config/wt}"

# Auto-regenerate the derived env when the config changed since it was generated.
if [ -f "$WT_CONFIG_DIR/config.yaml" ] && [ "$WT_CONFIG_DIR/config.yaml" -nt "$WT_CONFIG_DIR/env.sh" ]; then
  bash "$WT_ROOT_DIR/lib/config/generate-env.sh" >/dev/null 2>&1 || true
fi
[ -f "$WT_CONFIG_DIR/env.sh" ] && . "$WT_CONFIG_DIR/env.sh"

# Defaults for a bare install (no config yet). WT_REPOS maps a short key to the
# GitHub owner/repo; WT_PATHS carries optional clone-path overrides (key -> abs path).
declare -gA WT_REPOS 2>/dev/null || true
declare -gA WT_PATHS 2>/dev/null || true
: "${WT_DEFAULT_BASE_BRANCH:=main}"
: "${WT_AGENT_DEFAULT:=claude}"
: "${WT_IDE_BACKEND:=none}"
: "${WT_IDE_PORT_BASE:=6000}"
: "${WT_SESSIONS_DIR:=$HOME/.wt-sessions}"
: "${WT_HOOKS_DIR:=$HOME/.config/wt/hooks}"
: "${WT_SECRETS_SRC:=}"

export WT_TREES="$HOME/wt"               # worktrees live at $WT_TREES/<key>/<name>
export WT_META="$HOME/.wt-meta"          # per-session markers (e.g. chosen agent)
export WT_SESSIONS_DIR                   # dashboard session metadata + tombstones

# Clone path for <key>: an explicit override from config (clone_paths) wins
# unconditionally, else the canonical ~/repos/<key>.
_wt_clonepath() {
  local key="$1"
  [ -n "${WT_PATHS[$key]:-}" ] && { echo "${WT_PATHS[$key]}"; return; }
  echo "$HOME/repos/$key"
}
_wt_sid()       { echo "$1--$2"; }   # tmux/agent id from <key> <name>
