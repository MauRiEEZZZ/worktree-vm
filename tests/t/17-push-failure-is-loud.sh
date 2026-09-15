#!/usr/bin/env bash
# Bug (2026-09-15, first push after a VM rebuild): wt-push announced "pushing … ->
# origin" BEFORE pushing and then let git's failure be the quiet part, so a push
# that never reached GitHub read exactly like one that did. The branch was simply
# not there; a 404 from `gh api` is what gave it away.
# Same run, same cause: wt-pr-draft piped ls-remote into cut and tested the
# PIPELINE's status — cut's, always 0 — so an unreachable origin came out as
# "origin/x is not at your HEAD (abc123 vs )", sending the reader after a stale
# remote instead of the missing git credential helper.
# Real git against a local bare "remote"; gh + claude stubbed.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home
t_use_stubs claude
export WT_NO_LAUNCH=1

cat > "$T_STUBS/gh" <<'G'
#!/usr/bin/env bash
echo '[]'
G
chmod +x "$T_STUBS/gh"

git init -q --bare "$T_TMP/up.git"
git clone -q "$T_TMP/up.git" "$T_TMP/seed" 2>/dev/null
( cd "$T_TMP/seed" && git config user.email t@t && git config user.name t \
  && echo hi > README.md && git add README.md && git commit -qm init && git push -q origin HEAD:main )
mkdir -p "$T_HOME/repos" "$T_HOME/.config/wt"
git clone -q "$T_TMP/up.git" "$T_HOME/repos/demo" 2>/dev/null
printf 'repos:\n  demo: example-org/demo-repo\n' > "$T_HOME/.config/wt/config.yaml"

run_wt() { bash -c ". '$T_REPO/lib/wt/wt.sh'; $1" 2>&1; }
WT="$T_HOME/wt/demo/feat-a"
run_wt "wt-new demo feat-a" >/dev/null 2>&1
( cd "$WT" && git config user.email t@t && git config user.name t && echo x > f && git add f && git commit -qm work )

# ---- a push that works says so, in the past tense ------------------------------
OUT="$(run_wt "wt-push demo feat-a")"; RC=$?
assert_eq "$RC" "0" "a good push succeeds"
assert_contains "$OUT" "pushed: feat/feat-a -> origin" "and reports the outcome, not the intention"
assert_eq "$(git -C "$T_HOME/repos/demo" ls-remote --heads origin refs/heads/feat/feat-a | wc -l | tr -d ' ')" "1" "the branch really is on the remote"

# ---- a push that cannot reach the remote must FAIL, loudly ---------------------
# The remote is gone: the same shape as an auth failure, which is what happened.
mv "$T_TMP/up.git" "$T_TMP/up.git.away"
OUT="$(run_wt "wt-push demo feat-a")"; RC=$?
assert_eq "$RC" "1" "a push that cannot reach origin returns non-zero"
assert_contains "$OUT" "push FAILED" "and says so"
assert_contains "$OUT" "NOT on origin" "in words that cannot be read as success"
assert_contains "$OUT" "gh auth setup-git" "and names the usual cause after a rebuild"

# ---- wt-pr-draft tells an unreachable origin from a stale one ------------------
OUT="$(run_wt "wt-pr-draft demo feat-a")"; RC=$?
assert_eq "$RC" "1" "wt-pr-draft refuses when origin cannot be reached"
assert_contains "$OUT" "cannot reach origin" "and says THAT, not that the remote is behind"
assert_not_contains "$OUT" "is not at your HEAD" "never the stale-remote message for an unreachable one"

# ---- with the remote back, a genuinely stale origin still reports as stale ----
mv "$T_TMP/up.git.away" "$T_TMP/up.git"
( cd "$WT" && echo y > f2 && git add f2 && git commit -qm "not pushed" )
OUT="$(run_wt "wt-pr-draft demo feat-a")"; RC=$?
assert_eq "$RC" "1" "a stale origin is still refused"
assert_contains "$OUT" "is not at your HEAD" "and that message is still the right one when it IS stale"
t_end
