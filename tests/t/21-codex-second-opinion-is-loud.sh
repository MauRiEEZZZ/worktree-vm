#!/usr/bin/env bash
# Bug (2026-10-07): the pre-PR review's Codex second opinion had not run for weeks,
# and nothing said so. The task text ended its sentence right after the command —
# `codex review ... --base origin/<default> .` — and the reviewers ran it with the
# full stop, which `codex review` takes as its [PROMPT] positional and refuses next
# to --base (exit 2, no review). The reviewer then wrote "Codex: no findings" over an
# opinion that was never given; 134 such usage errors in one VM's transcripts. A base
# that does not exist in the clone (origin/main on a develop repo) loses it just as
# quietly: Codex exits 0 and picks a base of its own.
# The helper under test must therefore (1) never let a stray argument reach Codex,
# (2) review against a base that exists — the repo's real default branch when the
# given one does not — and (3) say on its FIRST line whether Codex ran, and exit
# non-zero when it did not, whatever Codex's own exit status was.
# Real git against a local bare remote whose default branch is `develop`; codex is a
# stub that records its argv and plays the scenario the test asks for.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home

HELPER="$T_REPO/lib/wt/codex-review.sh"
CODEX_LOG="$T_TMP/codex.argv"
CODEX_MODE="$T_TMP/codex.mode"      # ok | usage-error | silent
cat > "$T_STUBS/codex" <<STUB
#!/usr/bin/env bash
[ "\$1" = --version ] && { echo "codex-cli 0.0.0-stub"; exit 0; }
printf '%s\n' "\$*" >> "$CODEX_LOG"
case "\$(cat "$CODEX_MODE" 2>/dev/null)" in
  usage-error) echo "error: the argument '--base <BRANCH>' cannot be used with '[PROMPT]'" >&2; exit 2 ;;
  silent)      exit 0 ;;
  *)           echo "stub review: no actionable defects in the reviewed changes"; exit 0 ;;
esac
STUB
chmod +x "$T_STUBS/codex"
echo ok > "$CODEX_MODE"
first_line() { printf '%s\n' "$1" | head -1; }
last_argv()  { tail -1 "$CODEX_LOG" 2>/dev/null; }

# a remote whose default branch is develop, and a clone with a feature branch on it
git init -q --bare "$T_TMP/up.git"
git clone -q "$T_TMP/up.git" "$T_TMP/seed" 2>/dev/null
( cd "$T_TMP/seed" && git config user.email t@t && git config user.name t \
  && git checkout -q -b develop && echo hi > README.md && git add README.md && git commit -qm init \
  && git push -q origin develop )
git --git-dir="$T_TMP/up.git" symbolic-ref HEAD refs/heads/develop
WT="$T_TMP/work"
git clone -q "$T_TMP/up.git" "$WT" 2>/dev/null
( cd "$WT" && git config user.email t@t && git config user.name t \
  && git remote set-head origin -a >/dev/null && git checkout -q -b feat/x \
  && echo x > f && git add f && git commit -qm work )
assert_eq "$(git -C "$WT" symbolic-ref --short refs/remotes/origin/HEAD)" "origin/develop" "fixture: the clone knows develop is the default branch"

# ---- 1. Codex runs: the first line says so, Codex's words follow, exit 0 ----------
OUT="$(bash "$HELPER" --base origin/develop --dir "$WT")"; RC=$?
assert_eq "$RC" "0" "a review that ran exits 0"
assert_contains "$(first_line "$OUT")" "CODEX SECOND OPINION: ran" "and its first line says Codex ran"
assert_contains "$OUT" "stub review: no actionable defects" "followed by Codex's own words"
assert_contains "$(last_argv)" "review -c sandbox_mode=read-only --base origin/develop" "codex review ran read-only, against the asked base"

# ---- 2. a stray argument — the sentence's full stop — never reaches Codex -----------
: > "$CODEX_LOG"
OUT="$(cd "$WT" && bash "$HELPER" --base origin/develop .)"; RC=$?
assert_eq "$RC" "0" "a stray '.' does not break the review"
assert_contains "$OUT" "ignored argument" "and is reported as ignored"
assert_eq "$(last_argv)" "review -c sandbox_mode=read-only --base origin/develop" "codex never sees it as a [PROMPT]"

# ---- 3. a base that does not exist here -> the real default branch, said out loud ---
: > "$CODEX_LOG"
OUT="$(bash "$HELPER" --base origin/main --dir "$WT")"; RC=$?
assert_eq "$RC" "0" "a missing base is not fatal"
assert_contains "$OUT" "base 'origin/main' does not exist" "the asked base is named as missing"
assert_contains "$(last_argv)" "--base origin/develop" "and Codex reviews against the repo's default branch instead"
: > "$CODEX_LOG"
bash "$HELPER" --dir "$WT" >/dev/null
assert_contains "$(last_argv)" "--base origin/develop" "without --base, the default branch is the base"
# ... also when origin/HEAD was never set: the remote itself says which branch is default
git -C "$WT" symbolic-ref --delete refs/remotes/origin/HEAD
: > "$CODEX_LOG"
OUT="$(bash "$HELPER" --base origin/main --dir "$WT")"
assert_contains "$(last_argv)" "--base origin/develop" "with no origin/HEAD the remote's HEAD branch is used"
git -C "$WT" remote set-head origin -a >/dev/null

# ---- 4. Codex fails with a usage error -> DID NOT RUN, its status, its error ----------
echo usage-error > "$CODEX_MODE"
OUT="$(bash "$HELPER" --base origin/develop --dir "$WT")"; RC=$?
assert_eq "$RC" "2" "codex's own exit status is passed on"
assert_contains "$(first_line "$OUT")" "CODEX SECOND OPINION: DID NOT RUN" "the first line says Codex did not run"
assert_contains "$OUT" "cannot be used with '[PROMPT]'" "and shows Codex's error"
assert_contains "$OUT" "Do not write 'Codex: no findings'" "and tells the reviewer what not to write"
assert_not_contains "$OUT" "no actionable" "with no review text that could pass for an opinion"

# ---- 5. Codex exits 0 but says nothing -> still DID NOT RUN ---------------------------
echo silent > "$CODEX_MODE"
OUT="$(bash "$HELPER" --base origin/develop --dir "$WT")"; RC=$?
assert_eq "$RC" "1" "an exit 0 without a review is a failure, not a clean bill"
assert_contains "$(first_line "$OUT")" "DID NOT RUN" "and the first line says so"
assert_contains "$OUT" "no output" "naming the symptom"

# ---- 6. nothing to review: said, and Codex is not even started -----------------------
echo ok > "$CODEX_MODE"; : > "$CODEX_LOG"
git -C "$WT" checkout -q develop
OUT="$(bash "$HELPER" --base origin/develop --dir "$WT")"; RC=$?
assert_eq "$RC" "0" "an empty diff is not a failure"
assert_contains "$(first_line "$OUT")" "CODEX SECOND OPINION: NOTHING TO REVIEW" "but it is named for what it is"
assert_eq "$(wc -l < "$CODEX_LOG" | tr -d ' ')" "0" "and Codex is not started for it"
git -C "$WT" checkout -q feat/x

# ---- 7. no codex at all -> DID NOT RUN, naming it -------------------------------------
OUT="$(PATH="/usr/bin:/bin" bash "$HELPER" --base origin/develop --dir "$WT")"; RC=$?
assert_eq "$RC" "1" "a missing codex is a failure"
assert_contains "$(first_line "$OUT")" "DID NOT RUN: codex is not installed" "that says what is missing"
t_end
