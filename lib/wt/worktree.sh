# worktree.sh — clone/worktree plumbing shared by the wt-* commands.

_wt_ensure() {   # ensure repo <key> is cloned + fetched; echo its path on stdout
  local key="$1" full="${WT_REPOS[$key]:-}" dir
  [ -z "$full" ] && { echo "unknown repo: $key (see: wt-repos)" >&2; return 1; }
  dir="$(_wt_clonepath "$key")"
  if [ ! -d "$dir/.git" ]; then
    mkdir -p "$(dirname "$dir")"
    echo "cloning $full -> $dir ..." >&2
    gh repo clone "$full" "$dir" >&2 || return 1
  fi
  git -C "$dir" remote set-head origin -a >/dev/null 2>&1 || true
  git -C "$dir" fetch --quiet origin || true
  echo "$dir"
}
_wt_base() {     # default branch of the clone/worktree at $1 (falls back to config)
  local b
  b="$(git -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"
  echo "${b:-$WT_DEFAULT_BASE_BRANCH}"
}
# Gitignored local config in the main clone worth seeding into a worktree:
# .env*, appsettings.*.json (e.g. appsettings.Development.json), *.local.json,
# secrets.json, and Playwright storage-state under browser-contexts/*.json (the
# authenticated test session, so any wt session can run Playwright without
# re-login). Driven off git so we only take files git actually ignores -> a
# committed appsettings.Development.json is skipped (the worktree already has it),
# a gitignored one with local secrets is copied. Vendored dirs excluded.
_wt_local_files() {
  git -C "$1" ls-files --others --ignored --exclude-standard 2>/dev/null \
    | grep -Ev '(^|/)(node_modules|bin|obj|\.git)/' \
    | grep -E '(^|/)(\.env(\.[^/]*)?|appsettings\.[^/]*\.json|[^/]*\.[Ll]ocal\.json|secrets\.json|browser-contexts/[^/]+\.json)$'
}
_wt_seed_env() {  # copy gitignored local config from the main clone into a fresh worktree
  local repo="$1" dir="$2" f
  _wt_local_files "$repo" \
  | while IFS= read -r f; do
      [ -e "$dir/$f" ] && continue          # don't clobber a file already in the worktree
      mkdir -p "$dir/$(dirname "$f")"
      cp "$repo/$f" "$dir/$f" && echo "  inherited local config: $f"
    done
}
_wt_prepare() {  # best-effort dependency restore for a fresh worktree at $1
  local d="$1" sln
  sln="$(ls "$d"/*.slnx "$d"/*.sln 2>/dev/null | head -1)"
  if [ -n "$sln" ]; then ( cd "$d" && dotnet restore "$(basename "$sln")" ) || true
  elif [ -f "$d/package.json" ]; then
    ( cd "$d" && { if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null; then pnpm install;
                   elif [ -f yarn.lock ] && command -v yarn >/dev/null; then yarn install;
                   else npm install; fi; } ) || true
  fi
}

# _wt_pipe <cmd> "$@" : batch mode. When stdin is piped AND no <repo> argument was
#   given (first arg empty or a -flag), read tab-separated lines (e.g. from wt-ls)
#   and run <cmd> <repo> <name> <flags> per line. Returns 0 when it handled the
#   input (the caller then does `&& return`), else 1 (normal mode). This enables:
#   wt-ls | grep <filter> | wt-rm [-f] | wt-resume | wt-ide
_wt_pipe() {
  local cmd="$1"; shift
  [ -p /dev/stdin ] || return 1                          # only a REAL pipe -> batch
  { [ -n "${1:-}" ] && [[ "${1}" != -* ]]; } && return 1 # explicit <repo> -> normal mode
  local flags="$*" r n rest
  while IFS=$'\t' read -r r n rest; do
    [ -z "$r" ] && continue
    if [ -z "${WT_REPOS[$r]:-}" ]; then echo "skipping (not a wt repo): $r/$n" >&2; continue; fi
    "$cmd" "$r" "$n" $flags </dev/null
  done
  return 0
}
