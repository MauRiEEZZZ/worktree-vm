# commands.sh — the user-facing wt-* commands.

# wt-new <repo> <name> [--agent claude|codex] [task... | --task-b64 <b64>] : create
#   worktree ~/wt/<repo>/<name> on branch feat/<name> from the repo's default
#   branch, prepare dependencies, and start the chosen AI agent in tmux (default
#   claude with Remote Control; codex = OpenAI Codex CLI).
wt-new() {
  case "${1:-}" in -h|--help) _wt_help wt-new; return 0;; esac
  if [ $# -lt 2 ]; then echo "usage: wt-new <repo> <name> [--agent claude|codex] [--branch <existing>] [task... | --task-b64 <b64>]"; return 1; fi
  local key="$1" name="$2"; shift 2
  local task="" existing="" fromref="" agent="$WT_AGENT_DEFAULT" auto=0 denypost=0 model="" priority="" readdirs=""
  # options: --agent <claude|codex>, --branch <existing branch> (check out a PR
  #   branch instead of creating a new one), --from <ref> (new feat/<name> branch
  #   off <ref> instead of the default branch — e.g. a PR head, so two sessions can
  #   work the same PR code without a branch conflict), --auto, --deny-post,
  #   --model <alias> (override the default model; empty = your own default),
  #   --read-dir <path> (repeatable: a directory OUTSIDE the worktree the session
  #   must reach — a reviewer needs the dev worktree it reviews, and a session that
  #   keeps its plan in $WT_META needs that; without it the first read there is
  #   refused and an unattended session stops dead),
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
      --read-dir) readdirs="$readdirs ${2:-}"; shift 2;;
      --task-b64) task=$(printf '%s' "${2:-}" | base64 -d 2>/dev/null); shift 2;;
      *)          task="$*"; break;;
    esac
  done
  readdirs="${readdirs# }"

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
  _wt_readdirs_set "$sid" "$readdirs"   # and the outside-the-worktree dirs, so resume re-seeds them
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
  [ "$agent" = claude ] && _wt_seed_perms "$dir" "$auto" "$denypost" "$readdirs"  # trust + settings.local so an --auto/--deny-post session launches unattended
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

# wt-resume <repo> <name> [--task <text> | --task-b64 <b64>] : reopen an existing
#   worktree session in tmux and resume the last conversation (claude --continue)
#   with Remote Control + the wt/<repo>/<name> name. Use after a VM restart (tmux
#   gone) or on a 'stopped' session. If the tmux session still runs, this simply
#   attaches to it. --task hands the resumed session its next step in the same
#   launch, instead of starting it idle and waking it up afterwards.
wt-resume() {
  case "${1:-}" in -h|--help) _wt_help wt-resume; return 0;; esac
  _wt_pipe wt-resume "$@" && return   # batch: wt-ls | grep ... | wt-resume
  if [ $# -lt 2 ]; then echo "usage: wt-resume <repo> <name> [--task <text> | --task-b64 <b64>]"; return 1; fi
  local key="$1" name="$2"
  shift 2
  local task=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --task)     shift; task="$*"; break;;
      --task-b64) task=$(printf '%s' "${2:-}" | base64 -d 2>/dev/null); shift 2;;
      *) echo "unknown option: $1 (usage: wt-resume <repo> <name> [--task <text> | --task-b64 <b64>])"; return 1;;
    esac
  done
  local dir="$WT_TREES/$key/$name" sid label agent flags auto=0 denypost=0 model readdirs
  sid="$(_wt_sid "$key" "$name")"; label="wt/$key/$name"
  agent="$(_wt_agent_get "$sid")"   # resume with the same agent it was created with
  flags="$(_wt_flags_get "$sid")"   # and the same launch flags (auto / deny-post)
  model="$(_wt_model_get "$sid")"   # and the same model override (if any)
  readdirs="$(_wt_readdirs_get "$sid")"   # and the same outside-the-worktree read access
  [[ "$flags" == *auto* ]] && auto=1; [[ "$flags" == *denypost* ]] && denypost=1
  [ -d "$dir" ] || { echo "no worktree: $dir (use wt-new to create one)"; return 1; }
  # `claude --continue` KEEPS the model of the ORIGINAL conversation — the
  # settings.json default is NOT applied on resume (measured on a live VM:
  # default changed to a cheaper model, markers removed, session restarted —
  # the next turn still ran the old expensive model; only an explicit --model
  # switched it). So resume is the SECOND decision point and must pass the
  # effective model explicitly: the per-session marker wins; where there is no
  # marker, agents.default_model fills in and is RECORDED, so the dashboard
  # shows what actually runs (marker and UI otherwise disagree with reality).
  # Both empty = no flag: --continue then keeps the conversation's own model.
  # wt-restore, the dashboard's resume route and wt-model all funnel through
  # here, so this covers every resume path.
  if [ -z "$model" ] && [ "$agent" = claude ] && [ -n "$WT_DEFAULT_MODEL" ]; then
    model="$WT_DEFAULT_MODEL"
    _wt_model_set "$sid" "$model"
  fi
  if tmux has-session -t "=$sid" 2>/dev/null; then
    echo "session already running: $sid"
    # A task can only ride along with a LAUNCH. Say that rather than dropping it:
    # a silently ignored --task is how work goes missing.
    [ -n "$task" ] && echo "  (--task ignored: the session is already running — talk to it over Remote Control)"
  elif [ -n "${WT_NO_LAUNCH:-}" ]; then
    echo "would resume: $label ($agent${model:+, model $model}) in $dir${task:+   (task: $task)} [no-launch]"; return 0
  else
    [ "$agent" = claude ] && _wt_seed_perms "$dir" "$auto" "$denypost" "$readdirs"  # idempotent: re-assert trust + settings.local before relaunch
    _wt_hook agent-launch "$sid" "$dir" "$agent" resume
    tmux new-session -d -s "$sid" -c "$dir" "$(_wt_agent_cmd "$agent" "$label" resume "$task" "$auto" "$denypost" "$model")"
    _wt_apply_color "$sid" "$agent"   # re-apply the prompt-bar colour (it isn't persisted)
    echo "resumed: $label ($agent)  (tmux $sid)${task:+   (task: $task)}"
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
  # agents.review_model governs PRE-PR SELF-REVIEW sessions: this command, both
  # manual and via the dashboard's review button (which spawns wt-review). The
  # PR-review WATCHER has its own key (github.review_model) on purpose — three
  # model keys, three uses, three failure economics; see config-reference.md
  # before merging anything. An explicit --model wins; claude only.
  # When the key is empty, reviews run on the ACCOUNT default ('default'
  # sentinel) — deliberately NOT on agents.default_model: a self-review must
  # never silently inherit whatever tier the dev sessions were pushed to (a
  # weak reviewer stamping "no findings" is worse than no reviewer).
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
  # --read-dir $devdir: the reviewer's whole job is to read a worktree that is not
  # its own. Without it Claude refuses the first read/grep there and an unattended
  # reviewer stops on "3 consecutive actions were blocked" (measured 2026-09-03).
  if [ -n "$model" ]; then
    wt-new "$key" "$rname" --agent "$agent" --model "$model" --auto --deny-post --read-dir "$devdir" --from "$devhead" --task-b64 "$b64"
  else
    wt-new "$key" "$rname" --agent "$agent" --auto --deny-post --read-dir "$devdir" --from "$devhead" --task-b64 "$b64"
  fi
}

# --- outward actions (the ORCHESTRATOR's, not a session's) -------------------
# A dev session must not push its own work or open its own PR: it would be acting
# on a relayed "yes" instead of the user's. These two helpers exist so the person
# (or orchestrating session) doing it has a NAMED, narrow command to run instead
# of arbitrary remote shell — easier to authorise once, and impossible to widen by
# accident. wt-new seeds an ASK rule for both into every session it launches.

# _wt_resolve <cmd> <pos...> : shared "<repo> <name> or derive from cwd" resolution.
# Echoes "<key> <name>"; non-zero (with a message) when neither works.
_wt_resolve() {
  local cmd="$1"; shift
  if [ "$#" -ge 2 ]; then echo "$1 $2"; return 0; fi
  if [ "$#" -eq 0 ]; then
    local rel="${PWD#$WT_TREES/}"
    if [ "$rel" = "$PWD" ] || [ "$rel" = "${rel%%/*}" ]; then
      echo "no <repo> <name> given and not inside a worktree (~/wt/<repo>/<name>)" >&2; return 1
    fi
    local key="${rel%%/*}"; rel="${rel#*/}"; echo "$key ${rel%%/*}"; return 0
  fi
  echo "usage: $cmd [<repo> <name>]" >&2; return 1
}

# _wt_pushable <dir> : echo the branch checked out at <dir> if it may be pushed;
# non-zero with a reason otherwise. Refuses a detached HEAD, the repo's default
# branch and the usual shared branches — those are never a session's own work.
_wt_pushable() {
  local dir="$1" br defbr
  br="$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null)" || {
    echo "detached HEAD in $dir — nothing that can be pushed as a branch" >&2; return 1; }
  defbr="$(_wt_base "$dir")"
  case "$br" in
    "$defbr"|main|master|develop|release/*|hotfix/*)
      echo "refusing to push '$br': shared branch, not a session's own work" >&2; return 1;;
  esac
  echo "$br"
}

# wt-push [<repo> <name>] : push that session's OWN branch to origin (never a
#   shared branch, never a force-push, never with uncommitted tracked changes —
#   what is on the PR must be what the session actually has).
wt-push() {
  case "${1:-}" in -h|--help) _wt_help wt-push; return 0;; esac
  local rk; rk="$(_wt_resolve wt-push "$@")" || return 1
  local key="${rk%% *}" name="${rk##* }"
  local dir="$WT_TREES/$key/$name"
  { [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; } || { echo "no worktree: $dir (see: wt-ls)"; return 1; }
  local br; br="$(_wt_pushable "$dir")" || return 1
  if [ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]; then
    echo "uncommitted tracked changes in $dir — commit them first, or the PR will not"
    echo "show what this session actually has:"
    git -C "$dir" status --short --untracked-files=no | sed 's/^/  /'
    return 1
  fi
  if [ -n "$(git -C "$dir" ls-files --others --exclude-standard | head -1)" ]; then
    echo "note: untracked files stay behind (not pushed):"
    git -C "$dir" ls-files --others --exclude-standard | head -5 | sed 's/^/  /'
  fi
  echo "pushing $key/$name: $br -> origin"
  git -C "$dir" push --set-upstream origin "$br"
}

# wt-pr-draft [<repo> <name>] [--title <t>] [--body-file <f>] : open the session's
#   PR as a DRAFT and request the Copilot review. Draft only — taking a PR out of
#   draft spends a person's time and stays a separate, deliberate act.
wt-pr-draft() {
  case "${1:-}" in -h|--help) _wt_help wt-pr-draft; return 0;; esac
  local title="" bodyfile="" pos=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --title)     title="${2:-}"; shift 2;;
      --body-file) bodyfile="${2:-}"; shift 2;;
      --*) echo "unknown option: $1 (see: wt-pr-draft --help)"; return 1;;
      *) pos+=("$1"); shift;;
    esac
  done
  local rk; rk="$(_wt_resolve wt-pr-draft ${pos[@]+"${pos[@]}"})" || return 1
  local key="${rk%% *}" name="${rk##* }"
  local dir="$WT_TREES/$key/$name" repo="${WT_REPOS[$key]:-}"
  [ -n "$repo" ] || { echo "unknown repo key: $key (see: wt-repos)"; return 1; }
  { [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; } || { echo "no worktree: $dir (see: wt-ls)"; return 1; }
  local br; br="$(_wt_pushable "$dir")" || return 1
  # The branch must be on the remote AND match it: a PR opened from a stale remote
  # branch shows a diff nobody reviewed.
  local remote_sha local_sha
  remote_sha="$(git -C "$dir" ls-remote --exit-code origin "refs/heads/$br" 2>/dev/null | cut -f1)" \
    || { echo "branch '$br' is not on origin yet — run: wt-push $key $name"; return 1; }
  local_sha="$(git -C "$dir" rev-parse HEAD)"
  [ "$remote_sha" = "$local_sha" ] || { echo "origin/$br is not at your HEAD (${local_sha:0:12} vs ${remote_sha:0:12}) — run: wt-push $key $name"; return 1; }
  local existing; existing="$(gh pr list --repo "$repo" --head "$br" --state open --json number -q '.[0].number' 2>/dev/null)"
  [ -n "$existing" ] && { echo "PR #$existing already open for $br — this command only OPENS a draft: $(gh pr view "$existing" --repo "$repo" --json url -q .url 2>/dev/null)"; return 1; }
  [ -n "$bodyfile" ] && [ ! -f "$bodyfile" ] && { echo "no such body file: $bodyfile"; return 1; }
  local defbr; defbr="$(_wt_base "$dir")"
  local args=(pr create --repo "$repo" --draft --base "$defbr" --head "$br")
  [ -n "$title" ] && args+=(--title "$title")
  [ -n "$bodyfile" ] && args+=(--body-file "$bodyfile")
  { [ -z "$title" ] || [ -z "$bodyfile" ]; } && args+=(--fill)
  echo "opening DRAFT pr: $repo  $br -> $defbr"
  gh "${args[@]}" || return 1
  local num; num="$(gh pr list --repo "$repo" --head "$br" --state open --json number -q '.[0].number' 2>/dev/null)"
  [ -n "$num" ] || { echo "draft opened, but could not read its number back — request the Copilot review yourself"; return 0; }
  # Copilot's review is requested best-effort: the PR already exists, so a failure
  # here must not look like the whole command failed (re-running would refuse, and
  # rightly so). The reviewer handle is configurable because it is GitHub's to change.
  local rev="${WT_COPILOT_REVIEWER:-copilot-pull-request-reviewer[bot]}"
  if [ -n "$rev" ]; then
    if gh pr edit "$num" --repo "$repo" --add-reviewer "$rev" >/dev/null 2>&1 \
    || gh api "repos/$repo/pulls/$num/requested_reviewers" -X POST -f "reviewers[]=$rev" >/dev/null 2>&1; then
      echo "requested review from $rev"
    else
      echo "could not request '$rev' automatically — ask for the Copilot review in the PR UI,"
      echo "or set github.copilot_reviewer in your config if the handle changed."
    fi
  fi
  gh pr view "$num" --repo "$repo" --json url -q .url
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
    rm -f "$WT_META/$sid.agent" "$WT_META/$sid.flags" "$WT_META/$sid.model" "$WT_META/$sid.priority" "$WT_META/$sid.idle_since" "$WT_META/$sid.parked" "$WT_META/$sid.readdirs" "$WT_META/$sid.handoff"
  else
    # safe: try to remove FIRST; only kill the sessions if the worktree is clean and removed
    git -C "$repo" worktree remove "$dir" || return 1
    tmux kill-session -t "=$sid" 2>/dev/null || true
    tmux kill-session -t "=ide-$sid" 2>/dev/null || true
    git -C "$repo" branch -d "$branch" 2>/dev/null
    rm -f "$WT_META/$sid.agent" "$WT_META/$sid.flags" "$WT_META/$sid.model" "$WT_META/$sid.priority" "$WT_META/$sid.idle_since" "$WT_META/$sid.parked" "$WT_META/$sid.readdirs" "$WT_META/$sid.handoff"
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

# wt-handoff [<repo> <name>] "<one line>" | --clear : say that this session is
#   finished with everything it may do itself and is now blocked on an OUTWARD step
#   (a push, a draft PR) that belongs to whoever is talking to the user.
#
#   It writes one line to $WT_META/<sid>.handoff, and the dashboard lifts the session
#   into its own section at the top until someone clears it. That indirection is the
#   point: a session announcing "I am ready" in its own pane is not a signal anybody
#   sees. Measured 2026-09-03: two sessions did exactly that and correctly refused to
#   push on their own — one waited 3 hours, the other 16.
#   Inside a worktree the repo and name come from the path, so a session just runs
#   `wt-handoff "ready for wt-push + draft PR: <title>"`.
wt-handoff() {
  case "${1:-}" in -h|--help) _wt_help wt-handoff; return 0;; esac
  local clear=0 pos=() a
  for a in "$@"; do case "$a" in --clear) clear=1;; *) pos+=("$a");; esac; done
  # <repo> <name> only when BOTH are given and neither looks like prose: the common
  # call is a bare message from inside the worktree.
  local key name msg
  if [ "${#pos[@]}" -ge 2 ] && [ -n "${WT_REPOS[${pos[0]}]:-}" ] && [ -d "$WT_TREES/${pos[0]}/${pos[1]}" ]; then
    key="${pos[0]}"; name="${pos[1]}"; msg="${pos[*]:2}"
  else
    read -r key name <<<"$(_wt_resolve wt-handoff)" || return 1
    msg="${pos[*]}"
  fi
  local sid; sid="$(_wt_sid "$key" "$name")"
  if [ "$clear" = 1 ]; then
    rm -f "$WT_META/$sid.handoff"; echo "handoff cleared: $sid"; return 0
  fi
  [ -n "$msg" ] || { echo 'usage: wt-handoff [<repo> <name>] "<one line: what you need done>"  |  wt-handoff --clear'; return 1; }
  mkdir -p "$WT_META"
  printf '%s\n' "${msg//$'\n'/ }" > "$WT_META/$sid.handoff"
  echo "handed over: $sid — $msg"
  echo "(it is at the top of the dashboard now; do not do the outward step yourself)"
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
