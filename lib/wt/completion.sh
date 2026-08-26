# completion.sh — tab completion: arg1 = repo key; arg2 of wt-rm/wt-env = existing
# worktree names; wt-rm arg3 = -f. (wt-new arg2 = a new name -> no suggestion.)
_wt_complete() {
  local cur prev cmd repo names
  cur="${COMP_WORDS[COMP_CWORD]}"; prev="${COMP_WORDS[COMP_CWORD-1]}"; cmd="${COMP_WORDS[0]}"
  # after --agent (wt-new): suggest the agent names
  if [ "$prev" = "--agent" ]; then COMPREPLY=( $(compgen -W "claude codex" -- "$cur") ); return; fi
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "${!WT_REPOS[*]} --help" -- "$cur") ); return
  fi
  # wt-new option flags anywhere after the name
  if [ "$cmd" = "wt-new" ] && [[ "$cur" == -* ]]; then
    COMPREPLY=( $(compgen -W "--agent --branch --task-b64" -- "$cur") ); return
  fi
  if [ "$COMP_CWORD" -eq 2 ]; then
    repo="${COMP_WORDS[1]}"
    case "$cmd" in
      wt-rm|wt-env|wt-resume|wt-ide|wt-ide-stop|wt-model)
        [ -d "$WT_TREES/$repo" ] && names=$(cd "$WT_TREES/$repo" && ls -1 2>/dev/null)
        COMPREPLY=( $(compgen -W "$names" -- "$cur") ) ;;
    esac
    return
  fi
  if [ "$COMP_CWORD" -eq 3 ] && [ "$cmd" = "wt-model" ]; then
    COMPREPLY=( $(compgen -W "default ${WT_MODEL_CHOICES:-}" -- "$cur") ); return
  fi
  if [ "$COMP_CWORD" -eq 3 ] && [ "$cmd" = "wt-rm" ]; then
    COMPREPLY=( $(compgen -W "-f" -- "$cur") )
  fi
}
complete -F _wt_complete wt-new wt-rm wt-env wt-resume wt-restore wt-review wt-ide wt-ide-stop wt-seed-main wt-model
