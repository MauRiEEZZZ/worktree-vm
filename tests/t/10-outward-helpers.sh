#!/usr/bin/env bash
# wt-push / wt-pr-draft exist to make the orchestrator's outward actions a NAMED,
# narrow command instead of arbitrary remote shell (`ssh vm 'git push'`), so it can
# be authorised once without widening anything else. That only holds while the
# guards hold, so there is one test per guard:
#   * a shared branch is never pushed (main / default / release/* / hotfix/*)
#   * uncommitted tracked changes block the push — otherwise the PR shows a diff
#     the session does not actually have
#   * no PR on a branch that is missing from origin, or where origin is behind HEAD
#   * no second PR for a branch that already has one
#   * the draft flag and the Copilot request actually reach gh
#   * wt-new seeds an ASK rule for both, so a session cannot run them unattended
# Real git against a local bare "remote"; gh is a recording stub.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home
export WT_NO_LAUNCH=1

GH_LOG="$T_TMP/gh.log"
PR_OPEN="$T_TMP/pr-open"          # presence = "a PR exists for the branch"
cat > "$T_STUBS/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GH_LOG"
case "\$1 \$2" in
  "pr list")   [ -f "$PR_OPEN" ] && echo 77; exit 0 ;;
  "pr create") touch "$PR_OPEN"; echo "https://github.test/example-org/demo-repo/pull/77"; exit 0 ;;
  "pr view")   echo "https://github.test/example-org/demo-repo/pull/77"; exit 0 ;;
  "pr edit")   exit 0 ;;
  "api")       exit 0 ;;
esac
exit 0
EOF
chmod +x "$T_STUBS/gh"

# a local "remote" + pre-seeded clone so nothing talks to GitHub
git init -q --bare "$T_TMP/up.git"
git clone -q "$T_TMP/up.git" "$T_TMP/seed" 2>/dev/null
(
  cd "$T_TMP/seed" && git config user.email t@t && git config user.name t \
  && echo hi > README.md && git add README.md && git commit -qm init \
  && git push -q origin HEAD:main \
  && git push -q origin HEAD:release/1.0
)
mkdir -p "$T_HOME/repos" "$T_HOME/.config/wt"
git clone -q "$T_TMP/up.git" "$T_HOME/repos/demo" 2>/dev/null
( cd "$T_HOME/repos/demo" && git config user.email t@t && git config user.name t )
printf 'repos:\n  demo: example-org/demo-repo\n' > "$T_HOME/.config/wt/config.yaml"

run_wt() { bash -c ". '$T_REPO/lib/wt/wt.sh'; $1" 2>&1; }

# ---- shared branches are never pushed ---------------------------------------
run_wt "wt-new demo onmain --branch main" >/dev/null 2>&1
OUT="$(run_wt "wt-push demo onmain")"
assert_contains "$OUT" "refusing to push 'main'" "wt-push refuses the default branch"

run_wt "wt-new demo onrel --branch release/1.0" >/dev/null 2>&1
OUT="$(run_wt "wt-push demo onrel")"
assert_contains "$OUT" "refusing to push 'release/1.0'" "wt-push refuses a release branch"

# ---- a session's own branch ---------------------------------------------------
run_wt "wt-new demo feat-a" >/dev/null 2>&1
WT="$T_HOME/wt/demo/feat-a"
( cd "$WT" && git config user.email t@t && git config user.name t \
  && echo one > a.txt && git add a.txt && git commit -qm "item 1" )

# uncommitted TRACKED changes block it; untracked ones only warn
echo dirty >> "$WT/a.txt"
echo scratch > "$WT/notes.tmp"
OUT="$(run_wt "wt-push demo feat-a")"
assert_contains "$OUT" "uncommitted tracked changes" "wt-push refuses a dirty worktree"
assert_eq "$(git -C "$T_TMP/up.git" rev-parse --verify --quiet refs/heads/feat/feat-a || echo none)" "none" \
  "nothing reached the remote"

( cd "$WT" && git checkout -q -- a.txt )
OUT="$(run_wt "wt-push demo feat-a")"
assert_contains "$OUT" "notes.tmp" "untracked files are reported, not fatal"
assert_eq "$(git -C "$T_TMP/up.git" rev-parse refs/heads/feat/feat-a)" "$(git -C "$WT" rev-parse HEAD)" \
  "wt-push put the branch on the remote at HEAD"

# ---- wt-pr-draft: origin must match HEAD -------------------------------------
: > "$GH_LOG"
( cd "$WT" && echo two > b.txt && git add b.txt && git commit -qm "item 2" )
OUT="$(run_wt "wt-pr-draft demo feat-a")"
assert_contains "$OUT" "is not at your HEAD" "no PR while origin is behind HEAD"
assert_eq "$(wc -l < "$GH_LOG" | tr -d ' ')" "0" "it refused before calling gh at all"

run_wt "wt-push demo feat-a" >/dev/null 2>&1

# ---- wt-pr-draft: the happy path ---------------------------------------------
: > "$GH_LOG"
printf 'body from the session\n' > "$T_TMP/body.md"
OUT="$(run_wt "wt-pr-draft demo feat-a --title 'Show the rejection reason' --body-file $T_TMP/body.md")"
GH="$(cat "$GH_LOG")"
assert_contains "$GH" "pr create --repo example-org/demo-repo --draft --base main --head feat/feat-a" \
  "gh was asked for a DRAFT pr on the session's branch"
assert_contains "$GH" "--title Show the rejection reason" "the title reaches gh"
assert_contains "$GH" "--body-file $T_TMP/body.md" "the body file reaches gh"
assert_not_contains "$GH" "--fill" "an explicit title+body does not also get --fill"
assert_contains "$GH" "--add-reviewer copilot-pull-request-reviewer[bot]" "the Copilot review is requested"
assert_contains "$OUT" "https://github.test/example-org/demo-repo/pull/77" "the PR url is reported back"

# ---- wt-pr-draft: never a second PR for the same branch ----------------------
OUT="$(run_wt "wt-pr-draft demo feat-a")"
assert_contains "$OUT" "PR #77 already open" "a branch with an open PR is refused"

# ---- and no session may run either unattended -------------------------------
# wt-new seeds the permissions on the LAUNCH path (WT_NO_LAUNCH skips it, no session
# to protect), so the seeding itself is what gets exercised here.
run_wt "_wt_seed_perms '$WT' 1 0" >/dev/null 2>&1
SETTINGS="$WT/.claude/settings.local.json"
assert_file "$SETTINGS" "an --auto session gets seeded permissions"
ASK="$(node -e 'const j=require(process.argv[1]);console.log((j.permissions.ask||[]).join(" "))' "$SETTINGS")"
assert_contains "$ASK" "Bash(wt-push:*)" "wt-push is an ASK for a seeded session"
assert_contains "$ASK" "Bash(wt-pr-draft:*)" "wt-pr-draft is an ASK for a seeded session"

t_end
