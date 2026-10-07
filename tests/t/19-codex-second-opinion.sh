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
t_end
