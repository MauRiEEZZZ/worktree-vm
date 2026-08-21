# perms.sh — seed a worktree so a DETACHED claude session launches cleanly for
# --auto / --deny-post.
#
# We deliberately do NOT use claude's CLI permission flags here, because each one
# breaks a headless tmux launch: --permission-mode bypassPermissions shows an
# interactive "accept" warning that just hangs (and --dangerously-skip-permissions
# silently exits); a fresh worktree path also triggers claude's folder-trust dialog
# (same hang); and --disallowedTools is variadic, so it swallows the trailing
# positional task. Instead we prepare state on disk:
#   * pre-trust the worktree path in ~/.claude.json  -> no folder-trust dialog;
#   * write .claude/settings.local.json               -> auto = broad allow (no
#     per-tool prompts), deny-post = ASK before gh pr review/comment/merge
#     (prompts, then posts on your approval; ask overrides the broad allow).
# claude then launches in NORMAL mode with a clean positional task, gets Remote
# Control, and still cannot post to GitHub. settings.local.json is claude's own
# gitignored local file; we also add it to the repo's git exclude so it never
# dirties the worktree.
_wt_seed_perms() {  # $1=dir $2=auto(0/1) $3=denypost(0/1)  -- claude only
  local dir="$1" auto="${2:-0}" denypost="${3:-0}"
  [ "$auto" = 1 ] || [ "$denypost" = 1 ] || return 0
  WT_TRUST_DIR="$dir" node -e 'const fs=require("fs"),os=require("os");const f=os.homedir()+"/.claude.json";try{const j=JSON.parse(fs.readFileSync(f,"utf8"));const p=process.env.WT_TRUST_DIR;j.projects=j.projects||{};j.projects[p]=j.projects[p]||{};j.projects[p].hasTrustDialogAccepted=true;fs.writeFileSync(f+".tmp",JSON.stringify(j,null,2));fs.renameSync(f+".tmp",f);}catch(e){}' 2>/dev/null || true
  mkdir -p "$dir/.claude"
  # deny-post uses the ASK tier (not deny): posting to GitHub prompts for confirmation
  # and runs after you approve (deny is absolute and would block even a you-approved
  # post). Precedence is deny > ask > allow, so ask overrides the broad Bash allow.
  # mcp__codex(__*) lets the Codex second-opinion run without a prompt.
  local allow="" ask=""
  [ "$auto" = 1 ] && allow='"Bash","Read","Edit","Write","Glob","Grep","WebFetch","mcp__codex","mcp__codex__*"'
  [ "$denypost" = 1 ] && ask='"Bash(gh pr review:*)","Bash(gh pr comment:*)","Bash(gh pr merge:*)"'
  printf '{"permissions":{"allow":[%s],"ask":[%s]}}\n' "$allow" "$ask" > "$dir/.claude/settings.local.json"
  local ex; ex="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/info/exclude"
  [ -f "$ex" ] && ! grep -qxF '.claude/settings.local.json' "$ex" 2>/dev/null && echo '.claude/settings.local.json' >> "$ex"
}
