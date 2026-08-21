# hooks.sh — the hook runner. Hooks are optional user/overlay scripts at
# $WT_HOOKS_DIR/<name>.sh (see hooks/README.md for the contract). They are
# best-effort by design: a failing or missing hook never breaks the command.

# _wt_hook <name> [args...] : run the hook script if present; warn on failure.
_wt_hook() {
  local name="$1"; shift
  local script="$WT_HOOKS_DIR/$name.sh"
  [ -f "$script" ] || return 0
  if ! bash "$script" "$@"; then
    echo "warning: hook '$name' failed — continuing" >&2
  fi
  return 0
}
