# agent.sh — assemble the shell command that launches an AI agent.

# Build the shell command to launch an agent.
#   $1=agent $2=label $3=mode(new|resume) $4=task $5=auto(0/1) $6=denypost(0/1) $7=model
# For claude, auto/deny-post are applied by _wt_seed_perms (trust + settings.local.json),
# not via argv; this only assembles the command. For codex (no remote-control / no
# settings file) auto still maps to the bypass-approvals flag.
_wt_agent_cmd() {
  local agent="$1" label="$2" mode="$3" task="$4" auto="${5:-0}" denypost="${6:-0}" model="${7:-}" c
  case "$agent" in
    codex)
      # Codex has no claude.ai remote-control/--name; drive it via tmux attach.
      # `resume --last` is cwd-filtered, so it picks THIS worktree's latest session.
      if [ "$mode" = resume ]; then c="codex resume --last"; else c="codex"; fi
      [ "$auto" = 1 ] && c="$c --dangerously-bypass-approvals-and-sandbox"
      [ -n "$model" ] && c="$c -c $(printf %q "model=$model")"
      { [ "$mode" != resume ] && [ -n "$task" ]; } && c="$c $(printf %q "$task")"
      echo "$c" ;;
    *)  # claude (default) -- normal permission mode; auto/deny-post live in settings.local.json
      if [ "$mode" = resume ]; then c="claude --continue --remote-control $(printf %q "$label")";
      else c="claude --name $(printf %q "$label") --remote-control $(printf %q "$label")"; fi
      [ -n "$model" ] && c="$c --model $(printf %q "$model")"   # override the default (e.g. a cheap model for auto-reviews)
      { [ "$mode" != resume ] && [ -n "$task" ]; } && c="$c $(printf %q "$task")"
      echo "$c" ;;
  esac
}
