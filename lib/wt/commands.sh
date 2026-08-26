# commands.sh — the user-facing wt-* commands.

# wt-new <repo> <name> [--agent claude|codex] [task... | --task-b64 <b64>] : create
#   worktree ~/wt/<repo>/<name> on branch feat/<name> from the repo's default
#   branch, prepare dependencies, and start the chosen AI agent in tmux (default
#   claude with Remote Control; codex = OpenAI Codex CLI).
wt-new() {
  case "${1:-}" in -h|--help) _wt_help wt-new; return 0;; esac
  if [ $# -lt 2 ]; then echo "usage: wt-new <repo> <name> [--agent claude|codex] [--branch <existing>] [task... | --task-b64 <b64>]"; return 1; fi
  local key="$1" name="$2"; shift 2
  local task="" existing="" fromref="" agent="$WT_AGENT_DEFAULT" auto=0 denypost=0 model="" priority=""
  # options: --agent <claude|codex>, --branch <existing branch> (check out a PR
  #   branch instead of creating a new one), --from <ref> (new feat/<name> branch
  #   off <ref> instead of the default branch — e.g. a PR head, so two sessions can
  #   work the same PR code without a branch conflict), --auto, --deny-post,
  #   --model <alias> (override the default model; empty = your own default),
  #   --task-b64 <b64>, anything else = the task.
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent)    agent="${2:-}"; shift 2;;
      --branch)   existing="${2:-}"; shift 2;;
      --from)     fromref="${2:-}"; shift 2;;
      --auto)     auto=1; shift;;
      --deny-post) denypost=1; shift;;
      --model)    model="${2:-}"; shift 2;;
      --priority) priority="${2:-}"; shift 2;;
      --task-b64) task=$(printf '%s' "${2:-}" | base64 -d 2>/dev/null); shift 2;;
      *)          task="$*"; break;;
    esac
  done
  case "$agent" in claude|codex) ;; *) echo "unknown agent: $agent (choose claude or codex)"; return 1;; esac
  command -v "$agent" >/dev/null 2>&1 || { echo "agent '$agent' is not installed on this machine"; return 1; }
  # COST KNOB: without an explicit --model, fall back to the configured
  # agents.default_model (claude only — the aliases are Claude's). An explicit
  # --model always wins, and the literal '--model default' explicitly requests
  # the ACCOUNT default, bypassing agents.default_model (wt-review uses this so
  # an empty review model never silently inherits the dev default). Empty
  # config = the account default, exactly as before. This is the single
  # decision point: the dashboard's create flow spawns wt-new, so it inherits
  # the same rule. The effective model lands in the session marker, so
  # wt-resume, wt-ls and the dashboard all show/keep what really runs.
  if [ "$model" = default ]; then model=""
  elif [ -z "$model" ] && [ "$agent" = claude ]; then model="$WT_DEFAULT_MODEL"; fi
  local repo; repo="$(_wt_ensure "$key")" || return 1
  local base; base="$(_wt_base "$repo")"
  local dir="$WT_TREES/$key/$name" branch="feat/$name" sid; sid="$(_wt_sid "$key" "$name")"
  [ -e "$dir" ] && { echo "already exists: $dir"; return 1; }
  mkdir -p "$WT_TREES/$key"
  git -C "$repo" worktree prune 2>/dev/null || true   # drop stale registrations so recreate at a reused path (e.g. wt-restore) doesn't fail
  if [ -n "$existing" ]; then
    # check out an existing branch (e.g. a PR branch) instead of a new feat/<name>
    branch="$existing"
    git -C "$repo" fetch --quiet origin "$existing" 2>/dev/null || true
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$existing"; then
      git -C "$repo" worktree add "$dir" "$existing" || return 1
    else
      git -C "$repo" worktree add --track -b "$existing" "$dir" "origin/$existing" || return 1
    fi
  elif git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    # a feat/<name> branch already exists (e.g. left over from a removed session) -> reuse it
    # instead of failing on `add -b`, which would leave a broken metadata-only session
    git -C "$repo" worktree add "$dir" "$branch" || return 1
  else
    if [ -n "$fromref" ]; then
      git -C "$repo" fetch --quiet origin "${fromref#origin/}" 2>/dev/null || true
    fi
    git -C "$repo" worktree add "$dir" -b "$branch" "${fromref:-origin/$base}" || return 1
  fi
  _wt_seed_env "$repo" "$dir"   # inherit gitignored local config (.env*, appsettings.*.json) from the main clone
  _wt_prepare "$dir"
  _wt_hook after-worktree-create "$key" "$name" "$dir" "$branch"
  local basedesc; if [ -n "$existing" ]; then basedesc="existing branch"; elif [ -n "$fromref" ]; then basedesc="from $fromref"; else basedesc="from origin/$base"; fi
  _wt_agent_set "$sid" "$agent"   # remember the chosen agent for resume/ls/dashboard
  _wt_flags_set "$sid" "$([ "$auto" = 1 ] && echo -n 'auto ')$([ "$denypost" = 1 ] && echo -n 'denypost')"  # so wt-resume relaunches the same way
  _wt_model_set "$sid" "$model"   # remember the model override (if any) for resume
  [ -n "$priority" ] && _wt_priority_set "$sid" "$priority"   # optional starting priority (editable later on the dashboard)
  # Session metadata, same shape the dashboard writes: without it, wt-rm's
  # tombstone has nothing to archive and a CLI-created session can't be restored
  # with fidelity (branch/agent/model/task). Never overwrite an existing file —
  # dashboard-created sessions already wrote a richer one (source URL fields).
  # Best-effort: metadata is a convenience, never a reason for wt-new to fail.
  if [ ! -f "$WT_SESSIONS_DIR/$sid.json" ]; then
    mkdir -p "$WT_SESSIONS_DIR" 2>/dev/null || true
    WT_J_REPO="$key" WT_J_NAME="$name" WT_J_AGENT="$agent" WT_J_AUTO="$auto" WT_J_DENY="$denypost" \
    WT_J_MODEL="$model" WT_J_PRIORITY="${priority:-p2}" WT_J_BRANCH="$branch" WT_J_TASK="$task" \
    node -e 'const e=process.env,fs=require("fs");const j={repo:e.WT_J_REPO,name:e.WT_J_NAME,agent:e.WT_J_AGENT,auto:e.WT_J_AUTO==="1",denyPost:e.WT_J_DENY==="1",model:e.WT_J_MODEL||"",priority:e.WT_J_PRIORITY||"p2",sourceUrl:null,sourceRepo:null,sourceNumber:null,sourceKind:null,branch:e.WT_J_BRANCH,task:e.WT_J_TASK||null,createdAt:Date.now()};fs.writeFileSync(process.argv[1],JSON.stringify(j,null,2));' \
      "$WT_SESSIONS_DIR/$sid.json" 2>/dev/null || true
  fi
  if [ -n "${WT_NO_LAUNCH:-}" ]; then echo "worktree: $dir  (branch $branch, $basedesc) [no-launch, agent $agent$([ "$auto" = 1 ] && echo -n ', auto')${model:+, model $model}]"; return 0; fi
  # Agent label: "wt/<repo>/<name>" — recognizable + grouped under the wt/ prefix (claude).
  local label="wt/$key/$name"
  [ "$agent" = claude ] && _wt_seed_perms "$dir" "$auto" "$denypost"  # trust + settings.local so an --auto/--deny-post session launches unattended
  local cmd; cmd="$(_wt_agent_cmd "$agent" "$label" new "$task" "$auto" "$denypost" "$model")"
  _wt_hook agent-launch "$sid" "$dir" "$agent" new
  tmux new-session -d -s "$sid" -c "$dir" "$cmd"
  _wt_apply_color "$sid" "$agent"   # give the session its (dashboard-matching) prompt-bar colour
  echo "worktree: $dir  (branch $branch, $basedesc)"
  echo "$agent:   $label   |   tmux: $sid${task:+   (task: $task)}"
  if [ -n "${TMUX:-}" ]; then tmux switch-client -t "=$sid";
  elif [ -t 1 ]; then tmux attach -t "=$sid";
  else echo "attach with: tmux attach -t =$sid"; fi
}

# wt-resume <repo> <name> : reopen an existing worktree session in tmux and resume
#   the last conversation (claude --continue) with Remote Control + the
#   wt/<repo>/<name> name. Use after a VM restart (tmux gone) or on a 'stopped'
#   session. If the tmux session still runs, this simply attaches to it.
wt-resume() {
  case "${1:-}" in -h|--help) _wt_help wt-resume; return 0;; esac
  _wt_pipe wt-resume "$@" && return   # batch: wt-ls | grep ... | wt-resume
  if [ $# -lt 2 ]; then echo "usage: wt-resume <repo> <name>"; return 1; fi
  local key="$1" name="$2"
  local dir="$WT_TREES/$key/$name" sid label agent flags auto=0 denypost=0 model
  sid="$(_wt_sid "$key" "$name")"; label="wt/$key/$name"
  agent="$(_wt_agent_get "$sid")"   # resume with the same agent it was created with
  flags="$(_wt_flags_get "$sid")"   # and the same launch flags (auto / deny-post)
  model="$(_wt_model_get "$sid")"   # and the same model override (if any)
  [[ "$flags" == *auto* ]] && auto=1; [[ "$flags" == *denypost* ]] && denypost=1
  [ -d "$dir" ] || { echo "no worktree: $dir (use wt-new to create one)"; return 1; }
  if tmux has-session -t "=$sid" 2>/dev/null; then
    echo "session already running: $sid"
  elif [ -n "${WT_NO_LAUNCH:-}" ]; then
    echo "would resume: $label ($agent) in $dir [no-launch]"; return 0
  else
    [ "$agent" = claude ] && _wt_seed_perms "$dir" "$auto" "$denypost"  # idempotent: re-assert trust + settings.local before relaunch
    _wt_hook agent-launch "$sid" "$dir" "$agent" resume
    tmux new-session -d -s "$sid" -c "$dir" "$(_wt_agent_cmd "$agent" "$label" resume "" "$auto" "$denypost" "$model")"
    _wt_apply_color "$sid" "$agent"   # re-apply the prompt-bar colour (it isn't persisted)
    echo "resumed: $label ($agent)  (tmux $sid)"
  fi
  if [ -n "${TMUX:-}" ]; then tmux switch-client -t "=$sid";
  elif [ -t 1 ]; then tmux attach -t "=$sid";
  else echo "attach with: tmux attach -t =$sid"; fi
}

# wt-restore <repo> <name> [--branch <b>] [--agent claude|codex] [--model <m>] [--auto] [--deny-post]
#   Restore a DELETED session: recreate the worktree at the SAME path (so the
#   preserved Claude conversation in ~/.claude/projects/<path> matches again) and
#   resume with claude --continue. Recreate = WT_NO_LAUNCH wt-new (checkout/deps/
#   markers), then wt-resume (--continue).
wt-restore() {
  case "${1:-}" in -h|--help) _wt_help wt-restore; return 0;; esac
  if [ $# -lt 2 ]; then echo "usage: wt-restore <repo> <name> [--branch <b>] [--agent claude|codex] [--model <m>] [--auto] [--deny-post]"; return 1; fi
  local key="$1" name="$2"; shift 2
  local branch="" agent="$WT_AGENT_DEFAULT" model="" auto="" denypost=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch)    branch="${2:-}"; shift 2;;
      --agent)     agent="${2:-}"; shift 2;;
      --model)     model="${2:-}"; shift 2;;
      --auto)      auto="--auto"; shift;;
      --deny-post) denypost="--deny-post"; shift;;
      *) echo "unknown option: $1 (see: wt-restore --help)"; return 1;;
    esac
  done
  local dir="$WT_TREES/$key/$name"
  if [ ! -e "$dir/.git" ]; then          # -e: in a worktree .git is a FILE (gitdir pointer), not a dir
    local br=""; [ -n "$branch" ] && br="--branch $branch"
    local md=""; [ -n "$model" ] && md="--model $model"
    WT_NO_LAUNCH=1 wt-new "$key" "$name" --agent "$agent" $br $md $auto $denypost || return 1
  else
    echo "worktree already exists: $dir  (resuming only)"
  fi
  wt-resume "$key" "$name"   # claude --continue on the same path -> the preserved conversation returns
}

# wt-review <repo> <name> [--scope committed|working|all] [--agent claude|codex] :
#   start a SEPARATE, independent review session on the work-in-progress of dev
#   session wt/<repo>/<name>. The reviewer inspects the LIVE dev worktree read-only
#   (never touches the dev session) against the merge-base with the default branch,
#   gets a second opinion from Codex (MCP), and REPORTS only (posts nothing;
#   --auto --deny-post). scope: committed = committed diff only; working (default)
#   = + uncommitted tracked changes; all = + untracked files.
wt-review() {
  case "${1:-}" in -h|--help) _wt_help wt-review; return 0;; esac
  local key="" name="" scope=working agent="$WT_AGENT_DEFAULT" model=""
  local pos=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --scope) scope="${2:-}"; shift 2;;
      --agent) agent="${2:-}"; shift 2;;
      --model) model="${2:-}"; shift 2;;
      --*) echo "unknown option: $1 (see: wt-review --help)"; return 1;;
      *) pos+=("$1"); shift;;
    esac
  done
  # ONE key (agents.review_model) governs ALL review sessions: this command
  # covers both manual use and the dashboard's review button (which spawns
  # wt-review); the PR-review watcher reads the same key via PR_REVIEW_MODEL.
  # An explicit --model wins; claude only (the aliases are Claude's).
  # When the key is empty, reviews run on the ACCOUNT default ('default'
  # sentinel) — deliberately NOT on agents.default_model: a review must never
  # silently inherit whatever cheap tier the dev sessions were pushed to. Which
  # tier reviews deserve is the owner's call; see config.example.yaml for the
  # recommended split (a finding a weak reviewer misses costs a day of external
  # review round-trip, not tokens).
  [ -z "$model" ] && [ "$agent" = claude ] && model="${WT_REVIEW_MODEL:-default}"
  if [ "${#pos[@]}" -ge 2 ]; then
    key="${pos[0]}"; name="${pos[1]}"
  elif [ "${#pos[@]}" -eq 0 ]; then
    # no <repo> <name> given -> derive them from the current worktree
    # ($WT_TREES/<repo>/<name>), so a dev session can review itself with just `wt-review [--scope ...]`
    local rel="${PWD#$WT_TREES/}"
    if [ "$rel" = "$PWD" ] || [ "$rel" = "${rel%%/*}" ]; then
      echo "no <repo> <name> given and not inside a worktree (~/wt/<repo>/<name>)"; return 1
    fi
    key="${rel%%/*}"; rel="${rel#*/}"; name="${rel%%/*}"
  else
    echo "usage: wt-review [<repo> <name>] [--scope committed|working|all] [--agent claude|codex]"; return 1
  fi
  case "$scope" in committed|working|all) ;; *) echo "unknown scope: $scope (committed|working|all)"; return 1;; esac
  local devdir="$WT_TREES/$key/$name"
  { [ -d "$devdir/.git" ] || [ -f "$devdir/.git" ]; } || { echo "no dev worktree: $devdir (see: wt-ls)"; return 1; }
  local rname="$name-review" rdir="$WT_TREES/$key/$name-review"
  [ -e "$rdir" ] && { echo "review worktree already exists: $rdir  (clean up first: wt-rm $key $rname -f)"; return 1; }
  # base = merge-base of the dev branch with the repo's default branch
  local defbr; defbr="$(_wt_base "$devdir")"
  local devhead base; devhead="$(git -C "$devdir" rev-parse HEAD)"
  base="$(git -C "$devdir" merge-base HEAD "origin/$defbr" 2>/dev/null)"; [ -z "$base" ] && base="origin/$defbr"
  # scope -> which diff the reviewer inspects (read-only, against the LIVE dev worktree $devdir)
  local diffcmd extra=""
  case "$scope" in
    committed) diffcmd="git -C $devdir diff $base...HEAD" ;;
    working)   diffcmd="git -C $devdir diff $base" ;;
    all)       diffcmd="git -C $devdir diff $base"; extra=" Additionally, list the untracked files with 'git -C $devdir ls-files --others --exclude-standard' and read those too." ;;
  esac
  local task="You are an INDEPENDENT reviewer. Review the work-in-progress of dev session wt/$key/$name. The live dev worktree is at $devdir; the base is commit $base (merge-base with origin/$defbr), dev HEAD is $devhead. Scope=$scope. Inspect the changes read-only with: $diffcmd .$extra Read surrounding code (in this review worktree or via $devdir) for context where needed, but CHANGE nothing in $devdir. ALSO get an independent second opinion from Codex via the codex MCP server (the mcp__codex__* tools) on the same diff/scope; if the MCP tool fails, fall back to 'codex exec'. Consolidate both opinions into concrete findings (correctness/bugs, security, tests, edge cases, style) with file:line where possible, plus a short overall conclusion. REPORT ONLY: post NOTHING to GitHub and change no code -- this is pre-PR work-in-progress; report your findings here (the user reads along via Remote Control)."
  local b64; b64="$(printf '%s' "$task" | base64 | tr -d '\n')"
  echo "review session for wt/$key/$name (scope $scope, base ${base:0:12}${model:+, model $model}) -> wt/$key/$rname"
  if [ -n "$model" ]; then
    wt-new "$key" "$rname" --agent "$agent" --model "$model" --auto --deny-post --from "$devhead" --task-b64 "$b64"
  else
    wt-new "$key" "$rname" --agent "$agent" --auto --deny-post --from "$devhead" --task-b64 "$b64"
  fi
}

# wt-model <repo> <name> <model|default> : change a session's model and relaunch
#   it so the change takes effect. Relaunching KEEPS the conversation (claude
#   --continue on the same worktree path); what is NOT possible is changing the
#   model of a live process without a relaunch — anything mid-generation at that
#   moment is interrupted. On a stopped session it just records the model for
#   the next resume. 'default' clears the override (back to agents.default_model
#   / the account default at next launch).
wt-model() {
  case "${1:-}" in -h|--help) _wt_help wt-model; return 0;; esac
  if [ $# -lt 3 ]; then echo "usage: wt-model <repo> <name> <model|default>"; return 1; fi
  local key="$1" name="$2" model="$3" sid; sid="$(_wt_sid "$key" "$name")"
  [ -d "$WT_TREES/$key/$name" ] || { echo "no worktree: $WT_TREES/$key/$name (see: wt-ls)"; return 1; }
  case "$model" in
    default) model="" ;;
    *[!a-zA-Z0-9._-]*|"") echo "invalid model alias: '$model'"; return 1 ;;
  esac
  _wt_model_set "$sid" "$model"
  echo "model for $sid set to ${model:-default (no override)}"
  if tmux has-session -t "=$sid" 2>/dev/null; then
    if [ -n "${WT_NO_LAUNCH:-}" ]; then echo "would relaunch with the new model [no-launch]"; return 0; fi
    echo "relaunching so it takes effect — the conversation is kept (claude --continue); anything mid-generation is interrupted"
    tmux kill-session -t "=$sid" 2>/dev/null || true
    wt-resume "$key" "$name"
  else
    echo "session is not running — the model applies on the next wt-resume"
  fi
}

# wt-rm <repo> <name> [-f] : kill the tmux session, remove the worktree + branch.
#   Safe by default (refuses when unmerged/dirty); -f forces.
wt-rm() {
  case "${1:-}" in -h|--help) _wt_help wt-rm; return 0;; esac
  _wt_pipe wt-rm "$@" && return   # batch: wt-ls | grep ... | wt-rm [-f]
  if [ $# -lt 2 ]; then echo "usage: wt-rm <repo> <name> [-f]"; return 1; fi
  local key="$1" name="$2" force="${3:-}"
  local repo; repo="$(_wt_clonepath "$key")"
  local dir="$WT_TREES/$key/$name" branch="feat/$name" sid; sid="$(_wt_sid "$key" "$name")"
  # actual branch of the worktree (may be a PR branch, not feat/<name>)
  local wtbranch; wtbranch=$(git -C "$dir" branch --show-current 2>/dev/null); [ -n "$wtbranch" ] && branch="$wtbranch"
  if [ "$force" = "-f" ]; then
    tmux kill-session -t "=$sid" 2>/dev/null || true
    tmux kill-session -t "=ide-$sid" 2>/dev/null || true
    git -C "$repo" worktree remove --force "$dir" && git -C "$repo" branch -D "$branch" 2>/dev/null
    rm -f "$WT_META/$sid.agent" "$WT_META/$sid.flags" "$WT_META/$sid.model" "$WT_META/$sid.priority" "$WT_META/$sid.idle_since" "$WT_META/$sid.parked"
  else
    # safe: try to remove FIRST; only kill the sessions if the worktree is clean and removed
    git -C "$repo" worktree remove "$dir" || return 1
    tmux kill-session -t "=$sid" 2>/dev/null || true
    tmux kill-session -t "=ide-$sid" 2>/dev/null || true
    git -C "$repo" branch -d "$branch" 2>/dev/null
    rm -f "$WT_META/$sid.agent" "$WT_META/$sid.flags" "$WT_META/$sid.model" "$WT_META/$sid.priority" "$WT_META/$sid.idle_since" "$WT_META/$sid.parked"
  fi
  # TOMBSTONE the dashboard session metadata (if any) so a CLI delete is just as
  # restorable as a dashboard delete: move $WT_SESSIONS_DIR/<sid>.json -> archive/
  # with deletedAt (preserves branch/agent/model/priority/task/source). The Claude
  # history in ~/.claude survives regardless.
  local _psf="$WT_SESSIONS_DIR/$sid.json"
  if [ -f "$_psf" ]; then
    mkdir -p "$WT_SESSIONS_DIR/archive"
    node -e 'const fs=require("fs"),[p,a,s]=process.argv.slice(1);try{const j=JSON.parse(fs.readFileSync(p,"utf8"));j.deletedAt=Date.now();fs.writeFileSync(a+"/"+s+".json",JSON.stringify(j,null,2));fs.unlinkSync(p)}catch(e){}' "$_psf" "$WT_SESSIONS_DIR/archive" "$sid"
  fi
}

# wt-env <repo> [name] : (re)copy the gitignored local config (.env*, appsettings.*.json)
#   from the main clone into worktree <name>, or into all worktrees of <repo>.
#   Overwrites existing files. Use after adding/updating .env in the main clone.
wt-env() {
  case "${1:-}" in -h|--help) _wt_help wt-env; return 0;; esac
  if [ $# -lt 1 ]; then echo "usage: wt-env <repo> [name]"; return 1; fi
  local key="$1" name="${2:-}" repo; repo="$(_wt_clonepath "$key")"
  [ -d "$repo/.git" ] || { echo "repo not cloned: $key"; return 1; }
  local targets=() d f
  if [ -n "$name" ]; then targets=("$WT_TREES/$key/$name"); else
    shopt -s nullglob; targets=("$WT_TREES/$key"/*); shopt -u nullglob; fi
  for d in "${targets[@]}"; do
    [ -e "$d/.git" ] || continue
    echo "$key/$(basename "$d"):"
    _wt_local_files "$repo" \
    | while IFS= read -r f; do mkdir -p "$d/$(dirname "$f")"; cp -f "$repo/$f" "$d/$f" && echo "  -> $f"; done
  done
}

# wt-seed-main [<key>] : seed the MAIN clone(s) with local, gitignored config
#   (appsettings.Development.json, .env, *.local.json) from a durable folder
#   ($WT_SECRETS_SRC/<key>/, repo-relative paths). Once after a fresh VM; wt-new
#   then inherits into every worktree, wt-env <key> pushes to existing worktrees.
#   Also fires the seed-main hook per key, so an overlay can add its own seeding.
wt-seed-main() {
  case "${1:-}" in -h|--help) _wt_help wt-seed-main; return 0;; esac
  local src_root="$WT_SECRETS_SRC"
  local keys=() key f n src dst
  if [ -n "${1:-}" ]; then keys=("$1"); else keys=("${!WT_REPOS[@]}"); fi
  for key in "${keys[@]}"; do
    [ -n "${WT_REPOS[$key]:-}" ] || { echo "unknown repo: $key (see: wt-repos)" >&2; continue; }
    dst="$(_wt_clonepath "$key")"
    _wt_hook seed-main "$key" "$dst"
    [ -n "$src_root" ] || continue           # no secrets source configured -> hook only
    src="$src_root/$key"
    [ -d "$src" ] || { [ -n "${1:-}" ] && echo "$key: no secrets folder ($src)" >&2; continue; }
    [ -d "$dst/.git" ] || { echo "$key: main clone missing ($dst) - clone it first (e.g. wt-new $key ...)" >&2; continue; }
    echo "$key: seeding <- $src"
    n=0
    while IFS= read -r f; do
      f="${f#./}"; mkdir -p "$dst/$(dirname "$f")"
      cp -f "$src/$f" "$dst/$f" && { echo "  -> $f"; n=$((n+1)); }
    done < <(cd "$src" && find . -type f -not -path '*/.git/*' 2>/dev/null)
    [ "$n" -eq 0 ] && echo "  (no files)"
  done
  return 0
}

# wt-ls : all dev sessions (all repos).
wt-ls() {
  case "${1:-}" in -h|--help) _wt_help wt-ls; return 0;; esac
  # one table: repo · name · agent · state · ide(port) · branch. TTY -> aligned with
  # header + summary; piped -> flat tab lines (greppable), no noise. repo+name stay
  # column 1+2 so piping into wt-rm/wt-resume/wt-ide keeps working.
  local rows d key name sid agent cl ide port branch
  rows=$(
    shopt -s nullglob
    for d in "$WT_TREES"/*/*; do
      [ -e "$d/.git" ] || continue
      key="$(basename "$(dirname "$d")")"; name="$(basename "$d")"; sid="${key}--${name}"
      agent="$(_wt_agent_get "$sid")"
      tmux has-session -t "=$sid" 2>/dev/null && cl=running || cl=stopped
      if tmux has-session -t "=ide-$sid" 2>/dev/null; then
        port=$(grep -m1 -oE 'tcp://127\.0\.0\.1:[0-9]+' "/tmp/ide-$sid.log" 2>/dev/null | grep -oE '[0-9]+$'); ide="${port:-running}"
      else ide="-"; fi
      branch=$(git -C "$d" branch --show-current 2>/dev/null)
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$key" "$name" "$agent" "$cl" "$ide" "${branch:-?}"
    done
  )
  if [ -z "$rows" ]; then [ -t 1 ] && echo "(no sessions)"; return 0; fi
  if [ -t 1 ]; then
    { printf 'REPO\tNAME\tAGENT\tSTATE\tIDE\tBRANCH\n'; printf '%s\n' "$rows"; } | column -t -s "$(printf '\t')"
    printf '\n%d session(s), %d with IDE.\n' \
      "$(printf '%s\n' "$rows" | grep -c .)" \
      "$(printf '%s\n' "$rows" | awk -F'\t' '$5!="-"' | grep -c .)"
  else
    printf '%s\n' "$rows"
  fi
}

# wt-repos : show the configured repos (key -> owner/repo).
wt-repos() {
  case "${1:-}" in -h|--help) _wt_help wt-repos; return 0;; esac
  local k
  for k in "${!WT_REPOS[@]}"; do printf "  %-16s %s\n" "$k" "${WT_REPOS[$k]}"; done | sort
}
