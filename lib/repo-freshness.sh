# repo-freshness.sh — "am I provisioning the core you think I am?"
#
# install.sh deliberately does NOT pull. The boot-time provision step pulls before
# it calls install.sh, and pulling mid-run would rewrite the script under itself
# and fight anyone testing a local edit in the guest clone. But provisioning a
# STALE core while believing you upgraded is worse than either.
#
# Measured 2026-09-07: "merge to main, then run install.sh in the guest" left the
# guest clone four commits behind, because nothing between those two steps pulls.
# Provisioning then re-installed the OLDER dashboard unit over the newer one and
# silently undid a fix that keeps a restart from killing every session.

# wt_warn_if_behind <dir> : print a loud, actionable warning when <dir> is behind
# its upstream. Never fails the caller — a checkout with no origin, no upstream
# branch or no network is normal, not an error.
wt_warn_if_behind() {
  local dir="$1" br behind
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || return 0
  br="$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [ -n "$br" ] || return 0                      # detached HEAD: nothing to compare against
  git -C "$dir" fetch --quiet origin 2>/dev/null || true
  behind="$(git -C "$dir" rev-list --count "HEAD..origin/$br" 2>/dev/null || echo 0)"
  [ "${behind:-0}" -gt 0 ] || return 0
  echo "WARNING: $dir is $behind commit(s) behind origin/$br." >&2
  echo "         This run provisions the OLD core. Pull first, then run this again:" >&2
  echo "           git -C $dir pull --ff-only" >&2
  echo >&2
}
