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

# Register Codex as an MCP server in Claude Code (user scope, ~/.claude.json) so a
# Claude session can consult Codex for a second-opinion review. Uses the same
# `codex login` auth. Idempotent.
claude mcp list 2>/dev/null | grep -q '^codex' \
  || claude mcp add --transport stdio --scope user codex -- codex mcp-server \
  || echo "WARN: could not add codex MCP server"
# Allow the codex MCP tools without a per-call prompt in EVERY session (not just
# --auto ones, which get it via .claude/settings.local.json). Idempotent patch of
# the user settings.
node -e 'const fs=require("fs"),os=require("os");const f=os.homedir()+"/.claude/settings.json";let j={};try{j=JSON.parse(fs.readFileSync(f,"utf8"))}catch{}; j.permissions=j.permissions||{}; j.permissions.allow=j.permissions.allow||[]; for(const r of ["mcp__codex","mcp__codex__*"]) if(!j.permissions.allow.includes(r)) j.permissions.allow.push(r); fs.mkdirSync(require("path").dirname(f),{recursive:true}); fs.writeFileSync(f,JSON.stringify(j,null,2));' 2>/dev/null \
  || echo "WARN: could not add codex MCP allow to user settings"
# Run Codex UNATTENDED as the review second-opinion: no per-command Accept/Decline
# prompt, but sandboxed to the worktree (workspace-write) with network for restores.
# Idempotent TOML merge (top-level keys must precede the first [table], so prepend).
node -e 'const fs=require("fs"),os=require("os");const f=os.homedir()+"/.codex/config.toml";let t="";try{t=fs.readFileSync(f,"utf8")}catch{};let pre="";if(!/^approval_policy\s*=/m.test(t))pre+="approval_policy = \"never\"\n";if(!/^sandbox_mode\s*=/m.test(t))pre+="sandbox_mode = \"workspace-write\"\n";t=pre+t;if(!/\[sandbox_workspace_write\]/.test(t))t=t.replace(/\s*$/,"")+"\n\n[sandbox_workspace_write]\nnetwork_access = true\n";fs.mkdirSync(require("path").dirname(f),{recursive:true});fs.writeFileSync(f,t);' 2>/dev/null \
  || echo "WARN: could not set codex unattended config"
