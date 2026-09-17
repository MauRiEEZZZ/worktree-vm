#!/usr/bin/env bash
# 40-agents.sh — the coding agents (Claude Code + OpenAI Codex), installed
# PER-USER. A user-owned npm prefix (~/.npm-global) makes the global bin writable
# by the user, so the agents' built-in auto-updater works (a root-owned /usr
# causes "no write permission to npm prefix"). They self-update in place — no
# re-provision needed for newer versions.
# NOTE: agents are intentionally NOT version-pinned here (they float via
# auto-update). To pin or roll back a bad release:
# `npm i -g @anthropic-ai/claude-code@<v>` (writable), or set DISABLE_AUTOUPDATER=1.
# Idempotent.
set -eu -o pipefail

export PATH="$HOME/.npm-global/bin:$PATH"
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
npm install -g @anthropic-ai/claude-code @openai/codex \
  || echo "WARN: agent install failed; install manually with the user npm prefix"
# Drop any root-installed copies, then symlink the user copies into /usr/local/bin
# (already on PATH for every shell — interactive, login AND non-interactive
# `ssh host cmd`). The npm prefix stays user-owned, so the auto-updater can write.
sudo npm rm -g @anthropic-ai/claude-code @openai/codex >/dev/null 2>&1 || true
sudo ln -sf "$HOME/.npm-global/bin/claude" /usr/local/bin/claude
sudo ln -sf "$HOME/.npm-global/bin/codex"  /usr/local/bin/codex

# The second opinion comes from `codex review`, NOT from an MCP server.
#
# Codex used to expose itself as one (`codex mcp-server`) and this step registered
# it. That subcommand is gone — codex 0.154.0 has `mcp` for *consuming* external
# servers and nothing that serves. The registration survived the removal, so every
# session that asked for the second opinion got CONNECTION_CLOSED, fell back to
# `codex exec`, and paid a cold CLI start per call. It still produced a review, so
# nobody noticed: measured 2026-09-17 on a single review session, 42 `codex exec`
# calls against 7 failed MCP attempts.
#
# Remove a stale registration from an earlier provision, and verify the command we
# now depend on actually exists instead of assuming it does.
if claude mcp list 2>/dev/null | grep -q '^codex:'; then
  claude mcp remove --scope user codex >/dev/null 2>&1 \
    && echo "removed the stale codex MCP registration (codex no longer serves MCP)"
fi
if codex review --help >/dev/null 2>&1; then
  echo "codex review: available (the second-opinion path)"
else
  echo "WARN: 'codex review' is not available in $(codex --version 2>/dev/null || echo 'codex') —" >&2
  echo "      the reviewer's second opinion will not work. Check the CLI's subcommands." >&2
fi
# Run Codex UNATTENDED as the review second-opinion: no per-command Accept/Decline
# prompt, but sandboxed to the worktree (workspace-write) with network for restores.
# Idempotent TOML merge (top-level keys must precede the first [table], so prepend).
node -e 'const fs=require("fs"),os=require("os");const f=os.homedir()+"/.codex/config.toml";let t="";try{t=fs.readFileSync(f,"utf8")}catch{};let pre="";if(!/^approval_policy\s*=/m.test(t))pre+="approval_policy = \"never\"\n";if(!/^sandbox_mode\s*=/m.test(t))pre+="sandbox_mode = \"workspace-write\"\n";t=pre+t;if(!/\[sandbox_workspace_write\]/.test(t))t=t.replace(/\s*$/,"")+"\n\n[sandbox_workspace_write]\nnetwork_access = true\n";fs.mkdirSync(require("path").dirname(f),{recursive:true});fs.writeFileSync(f,t);' 2>/dev/null \
  || echo "WARN: could not set codex unattended config"
