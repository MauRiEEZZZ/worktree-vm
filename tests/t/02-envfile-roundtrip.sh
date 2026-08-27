#!/usr/bin/env bash
# Bug (2026-08-25, fix 1ce093d): systemd's EnvironmentFile treats a backslash in
# an UNQUOTED value as an escape, so a regex like \?\s*$ arrived in node as ?s*$
# — an invalid regex that crashed the dashboard on startup. The FILE looked
# right; the parse was the bug. So this test asserts what a CONSUMER receives:
# generate a dashboard.env from a config whose value has backslashes AND a
# single quote, let systemd itself parse it, and compare inside node.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home

command -v systemd-run >/dev/null 2>&1 || t_skip_all "systemd-run not available"
/usr/bin/sudo -n true 2>/dev/null || t_skip_all "passwordless sudo not available (needed for systemd-run)"

WANT='https?://x-(don'\''t)?-pr\d+\.\s*[^\s)\]]*'
# task_template travels the same road and carries the same two hazards: a
# backslash sequence (its \n line break, which node turns into a newline) and
# inner double quotes. A house rule that silently loses its \n reads as "the
# session ignored the workflow", so it is asserted here rather than assumed.
WANT_TPL='Read "the plan" at {meta_dir}/{sid}.plan.md.\nThen work it.'
mkdir -p "$T_HOME/.config/wt"
cat > "$T_HOME/.config/wt/config.yaml" <<EOF
dashboard:
  port: 7309
  deploy_url_regex: 'https?://x-(don''t)?-pr\d+\.\s*[^\s)\]]*'
  task_template: 'Read "the plan" at {meta_dir}/{sid}.plan.md.\nThen work it.'
EOF
bash "$T_REPO/lib/config/generate-env.sh" >/dev/null

GOT="$(/usr/bin/sudo -n systemd-run --wait --pipe --collect \
  -p EnvironmentFile="$T_HOME/.config/wt/dashboard.env" \
  "$(command -v node)" -e 'process.stdout.write(process.env.DEPLOY_RE || "")' 2>/dev/null)"
assert_eq "$GOT" "$WANT" "DEPLOY_RE survives config -> env file -> systemd -> node byte-for-byte"
# and it must compile as the regex it was meant to be
if DEPLOY_RE="$GOT" node -e 'new RegExp(process.env.DEPLOY_RE, "i")' 2>/dev/null; then
  t_pass "the received value compiles as a regex"
else t_fail "the received value no longer compiles"; fi

GOT_TPL="$(/usr/bin/sudo -n systemd-run --wait --pipe --collect \
  -p EnvironmentFile="$T_HOME/.config/wt/dashboard.env" \
  "$(command -v node)" -e 'process.stdout.write(process.env.TASK_TEMPLATE || "")' 2>/dev/null)"
assert_eq "$GOT_TPL" "$WANT_TPL" "TASK_TEMPLATE survives the same road byte-for-byte"
assert_contains "$GOT_TPL" '\n' "the \\n reaches node unescaped, so it can become a newline"
assert_contains "$GOT_TPL" '"the plan"' "inner double quotes survive the env-file quoting"
t_end
