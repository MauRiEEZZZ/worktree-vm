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
assert_contains "$CODEXCMD" 'codex review' "wt-review runs the first-class review subcommand"
assert_contains "$CODEXCMD" 'sandbox_mode=' "read-only, so it cannot touch the worktree it reviews"
assert_contains "$TASK" '$codexcmd' "and the task hands the reviewer that exact command"
assert_not_contains "$TASK" 'mcp__codex__* tools' "it no longer sends the reviewer after MCP tools that do not exist"
assert_contains "$TASK" "do not fall back to 'codex exec'" "and forbids the cold-start fallback outright"

PROMPT="$(sed -n '/^function reviewPrompt/,/^}/p' "$T_REPO/dashboard/server.js" | grep -v '^\s*//')"
assert_contains "$PROMPT" 'codex review' "the watcher's prompt asks for the same thing"
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
CODEXLINE="$(sed -n '/Also get an INDEPENDENT second opinion from Codex/p' "$T_REPO/dashboard/server.js")"
assert_contains "$CODEXLINE" 'PR_REVIEW_CODEX_MODEL ?' "the model override is conditional"
assert_contains "$CODEXLINE" '-c model=' "a configured slug becomes a -c model override"
assert_contains "$CODEXLINE" ": ''" "and an empty setting adds nothing to the command"

t_end
