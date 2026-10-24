#!/usr/bin/env bash
# Bug (found 2026-09-17, in place for weeks): the reviewer's independent second
# opinion had quietly stopped being one. Codex used to expose itself as an MCP
# server and provisioning registered `codex mcp-server`; that subcommand no longer
# exists, so the registration failed to connect and every review fell back to
# `codex exec` — a cold start of the whole CLI per call, 42 of them on one session.
# It still produced a review, which is exactly why nobody noticed.
#
# This test guards the SHAPE of the instruction, which is what CI can check without
# codex installed: the prompts must ask for `codex review`, must not send the
# reviewer looking for MCP tools that do not exist, and must not grant them either.
# provision/40-agents.sh additionally VERIFIES `codex review` exists at provision
# time rather than assuming it — the assumption is what expired here.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home

# Assert on what is SENT and RUN, not on whether a word appears in the file: the
# comments explaining this change necessarily name the old mechanism, and a test
# that counts strings would fail on its own documentation.
TASK="$(sed -n '/^  local task="You are an INDEPENDENT reviewer/p' "$T_REPO/lib/wt/commands.sh")"
CODEXCMD="$(sed -n '/codexcmd=/p' "$T_REPO/lib/wt/commands.sh" | grep -v '^\s*#')"
# Since 2026-10-07 the command is the helper lib/wt/codex-review.sh, which runs
# `codex review` itself (see tests/t/21 for what the helper guarantees).
HELPER="$(grep -v '^\s*#' "$T_REPO/lib/wt/codex-review.sh")"
assert_contains "$CODEXCMD" 'codex-review.sh' "wt-review hands the reviewer the helper, by absolute path"
assert_contains "$CODEXCMD" '--base origin/$defbr' "against the repo's own default branch"
assert_contains "$HELPER" 'codex review' "and the helper runs the first-class review subcommand"
assert_contains "$HELPER" 'sandbox_mode="read-only"' "read-only, so it cannot touch the worktree it reviews"
assert_contains "$TASK" '$codexcmd' "and the task hands the reviewer that exact command"
# The sentence used to continue with " . That is ..." and the reviewers ran the
# command WITH the full stop, which `codex review` took as its [PROMPT] and refused
# next to --base — the second opinion silently never ran.
assert_not_contains "$TASK" '$codexcmd .' "with no full stop glued to it"
assert_contains "$TASK" 'DID NOT RUN' "and tells the reviewer what a failed run looks like"
assert_not_contains "$TASK" 'mcp__codex__* tools' "it no longer sends the reviewer after MCP tools that do not exist"
assert_contains "$TASK" "do not fall back to 'codex exec'" "and forbids the cold-start fallback outright"

PROMPT="$(sed -n '/^function reviewPrompt/,/^}/p' "$T_REPO/dashboard/server.js" | grep -v '^\s*//')"
assert_contains "$PROMPT" 'codex review' "the watcher's prompt asks for the same thing"
assert_contains "$PROMPT" '${CODEX_REVIEW}' "through the same helper"
assert_contains "$(grep '^const CODEX_REVIEW' "$T_REPO/dashboard/server.js")" "'codex-review.sh'" "which is that file, next to the dashboard"
assert_not_contains "$(printf '%s' "$PROMPT" | grep codex-review.sh)" '} . ' "with no full stop glued to the command there either"
assert_not_contains "$PROMPT" 'mcp__codex' "and not for MCP tools"
assert_contains "$PROMPT" "do not fall back to 'codex exec'" "and forbids the fallback there too"
assert_contains "$(cat "$T_REPO/dashboard/server.js")" 'baseRefName' "it looks up the PR base, so codex reviews against the right ref"

ALLOW="$(sed -n '/allow=./p' "$T_REPO/lib/wt/perms.sh" | grep -v '^\s*#')"
assert_not_contains "$ALLOW" 'mcp__codex' "seeded sessions no longer get grants for tools that do not exist"

PROV="$(grep -v '^\s*#' "$T_REPO/provision/40-agents.sh")"
assert_not_contains "$PROV" 'mcp add' "provisioning no longer registers codex as an MCP server"
assert_contains "$PROV" 'codex review --help' "and proves the command it depends on exists instead of assuming it"
assert_contains "$PROV" 'mcp remove' "while cleaning up the stale registration earlier provisions left"

# The second opinion's model is configurable (github.review_codex_model ->
# PR_REVIEW_CODEX_MODEL). Empty must leave the command exactly as it was — the
# default path is what nearly every install runs — and a set value must reach the
# `codex review` line, with the recovery instruction that makes a stale slug visible.
assert_contains "$PROMPT" 'PR_REVIEW_CODEX_MODEL' "the watcher's prompt can carry a codex model"
assert_contains "$PROMPT" 'models_cache.json' "and tells the reviewer how to recover from a stale slug"
CFG="$(grep -v '^\s*#' "$T_REPO/lib/config/generate-env.sh")"
assert_contains "$CFG" 'github.review_codex_model' "the config key is parsed"
assert_contains "$CFG" 'PR_REVIEW_CODEX_MODEL' "and reaches the service environment"
assert_contains "$(cat "$T_REPO/config.example.yaml")" 'review_codex_model' "and is documented for the user"

# Shape of the line itself, so this guards server.js and not a copy of its logic:
# the override must be CONDITIONAL, so the default install's command is unchanged.
# Since the helper (#14) the watcher no longer runs `codex review` itself, and the
# helper reports and IGNORES any argument it does not know -- so a `-c model=...`
# carried over onto its command line would be dropped and the configured model
# quietly not used. The model has to travel as the helper's own --model option.
CODEXLINE="$(sed -n '/Also get an INDEPENDENT second opinion from Codex/p' "$T_REPO/dashboard/server.js")"
assert_contains "$CODEXLINE" 'PR_REVIEW_CODEX_MODEL ?' "the model override is conditional"
assert_contains "$CODEXLINE" '--model ${PR_REVIEW_CODEX_MODEL}' "a configured slug goes to the helper as --model"
assert_not_contains "$CODEXLINE" '-c model=' "not as a -c override the helper would drop as a stray argument"
assert_contains "$CODEXLINE" ": ''" "and an empty setting adds nothing to the command"
# The recovery must go back through the helper; calling codex directly is the path
# the helper exists to close.
RECOVER="$(printf '%s' "$PROMPT" | grep 'models_cache.json')"
assert_contains "$RECOVER" 'DID NOT RUN' "recovery keys on the helper's own failure line"
assert_contains "$RECOVER" 'SAME helper command again with --model' "and re-runs the helper with another slug"
assert_contains "$RECOVER" 'Never call codex review directly' "rather than calling codex itself"

t_end
