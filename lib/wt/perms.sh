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
#     (prompts, then posts on your approval; ask overrides the broad allow),
#     and additionalDirectories for the paths the session must read OUTSIDE its
#     own worktree.
# claude then launches in NORMAL mode with a clean positional task, gets Remote
# Control, and still cannot post to GitHub. settings.local.json is claude's own
# gitignored local file; we also add it to the repo's git exclude so it never
# dirties the worktree.
_wt_seed_perms() {  # $1=dir $2=auto(0/1) $3=denypost(0/1) $4=read dirs (space-separated)  -- claude only
  local dir="$1" auto="${2:-0}" denypost="${3:-0}" readdirs="${4:-}"
  [ "$auto" = 1 ] || [ "$denypost" = 1 ] || [ -n "$readdirs" ] || return 0
  WT_TRUST_DIR="$dir" node -e 'const fs=require("fs"),os=require("os");const f=os.homedir()+"/.claude.json";try{const j=JSON.parse(fs.readFileSync(f,"utf8"));const p=process.env.WT_TRUST_DIR;j.projects=j.projects||{};j.projects[p]=j.projects[p]||{};j.projects[p].hasTrustDialogAccepted=true;fs.writeFileSync(f+".tmp",JSON.stringify(j,null,2));fs.renameSync(f+".tmp",f);}catch(e){}' 2>/dev/null || true
  mkdir -p "$dir/.claude"
  # deny-post uses the ASK tier (not deny): posting to GitHub prompts for confirmation
  # and runs after you approve (deny is absolute and would block even a you-approved
  # post). Precedence is deny > ask > allow, so ask overrides the broad Bash allow.
  # mcp__codex(__*) lets the Codex second-opinion run without a prompt.
  local allow="" ask=""
  [ "$auto" = 1 ] && allow='"Bash","Read","Edit","Write","Glob","Grep","WebFetch","mcp__codex","mcp__codex__*"'
  # The outward helpers belong to whoever is talking to the user: a session running
  # them would push or open a PR on a RELAYED "yes", which is not the user's own.
  # ask, not deny, so a session someone is actually driving can still do it after an
  # explicit confirmation — and note --auto's broad "Bash" allow makes this rule the
  # only thing standing between an unattended session and origin.
  ask='"Bash(wt-push:*)","Bash(wt-pr-draft:*)"'
  [ "$denypost" = 1 ] && ask="$ask"',"Bash(gh pr review:*)","Bash(gh pr comment:*)","Bash(gh pr merge:*)"'
  # additionalDirectories: paths the session must reach OUTSIDE its own worktree.
  # Without them a REVIEWER — whose whole job is to read a dev worktree it must not
  # touch — is stopped on its first read there: "Read" in the allow list only covers
  # the project directory, and a `grep ~/wt/<repo>/<name>` from an unattended session
  # is refused by the auto-mode classifier. Measured 2026-09-03: a reviewer sat dead
  # on "3 consecutive actions were blocked" at a grep into the worktree it was
  # reviewing. Read-only is NOT enforced here (Claude has no read-only directory
  # tier); the task text is what forbids writing, as it always did.
  local extra="" d
  for d in $readdirs; do extra="$extra,\"$d\""; done
  extra="${extra#,}"
  printf '{"permissions":{"allow":[%s],"ask":[%s],"additionalDirectories":[%s]}}\n' \
    "$allow" "$ask" "$extra" > "$dir/.claude/settings.local.json"
  local ex; ex="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/info/exclude"
  [ -f "$ex" ] && ! grep -qxF '.claude/settings.local.json' "$ex" 2>/dev/null && echo '.claude/settings.local.json' >> "$ex"
}
