#!/usr/bin/env bash
# Bug (2026-08-25, orchestrator-side): a greedy regex edit truncated half of the
# example/overlay config — sessions.meta_dir, stacks, hooks, ports and lima all
# gone — and it was pushed before anyone noticed. Trivial-looking, but this is
# the only test that would have caught it: assert the example config still
# carries every expected top-level key and that key defaults parse.
. "$(dirname "$0")/../lib.sh"

CFG="$T_REPO/config.example.yaml"
for key in repos clone_paths default_base_branch github agents dashboard ide secrets sessions hooks stacks stack_options ports lima; do
  if grep -qE "^${key}:" "$CFG"; then t_pass "top-level key present: $key"; else t_fail "top-level key MISSING: $key"; fi
done

. "$T_REPO/lib/config/parse-yaml.sh"
FLAT="$(wt_yaml_flatten "$CFG")"
assert_contains "$FLAT" "default_base_branch	main" "default_base_branch parses to main"
assert_contains "$FLAT" "sessions.meta_dir	~/.wt-sessions" "sessions.meta_dir parses to the default"
assert_contains "$FLAT" "ide.backend	none" "ide.backend defaults to none (feature off)"
assert_contains "$FLAT" "github.review_owner	" "review_owner defaults to empty (watcher off)"
assert_contains "$FLAT" "lima.instance	worktree-vm" "lima.instance parses"
t_end
