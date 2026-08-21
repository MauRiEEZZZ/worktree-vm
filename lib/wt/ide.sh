# ide.sh — pluggable IDE backends for wt-ide. Dispatches on the configured
# backend (ide.backend: none | rider | code-server) to ide/<backend>.sh, which
# must define the 4-function contract:
#   ide_install               one-time install of the backend (idempotent)
#   ide_start <key> <name> <dir> <sid>   start (or report) the backend for a worktree,
#                                        in tmux session <sid> (= ide-<key>--<name>),
#                                        logging to /tmp/<sid>.log, and print how to
#                                        connect from the workstation
#   ide_stop <sid>            stop the backend (default: kill the tmux session)
#   ide_url <sid>             print the connect URL/link if available

# wt-ide <repo> <name> : start the configured IDE backend on the worktree and
#   print how to connect from your workstation. The backend runs in tmux session
#   ide-<repo>--<name>; wt-ls shows its port in the IDE column.
wt-ide() {
  case "${1:-}" in -h|--help) _wt_help wt-ide; return 0;; esac
  _wt_pipe wt-ide "$@" && return   # batch: wt-ls | grep ... | wt-ide
  if [ $# -lt 2 ]; then echo "usage: wt-ide <repo> <name>"; return 1; fi
  local key="$1" name="$2"
  local dir="$WT_TREES/$key/$name" sid="ide-$(_wt_sid "$key" "$name")"
  [ -d "$dir" ] || { echo "no worktree: $dir (create it with wt-new)"; return 1; }
  local backend="${WT_IDE_BACKEND:-none}"
  if [ "$backend" = none ] || [ -z "$backend" ]; then
    echo "No IDE backend is configured, so wt-ide has nothing to start."
    echo "Set 'ide: backend:' to 'rider' or 'code-server' in ~/.config/wt/config.yaml to enable it."
    return 1
  fi
  local impl="$WT_ROOT_DIR/ide/$backend.sh"
  [ -f "$impl" ] || { echo "unknown IDE backend '$backend' (expected $impl)"; return 1; }
  # shellcheck source=/dev/null
  . "$impl"
  ide_install || return 1
  ide_start "$key" "$name" "$dir" "$sid"
}

# wt-ide-stop [<repo> <name>] : stop the IDE backend of <repo>/<name>, or — with
#   no argument — the only running IDE backend. Pipeable.
wt-ide-stop() {
  case "${1:-}" in -h|--help) _wt_help wt-ide-stop; return 0;; esac
  _wt_pipe wt-ide-stop "$@" && return
  local sid
  if [ $# -ge 2 ]; then
    sid="ide-$(_wt_sid "$1" "$2")"
  else
    local list; list=$(tmux ls 2>/dev/null | sed -E 's/:.*//' | grep -E '^ide-')
    local n; n=$(printf '%s\n' "$list" | grep -c .)
    [ "$n" -eq 0 ] && { echo "no IDE backend running"; return 0; }
    [ "$n" -gt 1 ] && { echo "multiple IDE backends running — pass <repo> <name>:"; printf '  %s\n' $list; return 1; }
    sid="$list"
  fi
  if tmux has-session -t "$sid" 2>/dev/null; then
    tmux kill-session -t "$sid"; echo "IDE stopped: $sid"
  else
    echo "no IDE backend: $sid"; return 1
  fi
}
