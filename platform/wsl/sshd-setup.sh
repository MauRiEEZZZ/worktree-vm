#!/usr/bin/env bash
# sshd-setup.sh — OPTIONAL: run an OpenSSH server inside the WSL2 distro.
#
# You do NOT need this to use worktree-vm on Windows: the orchestrator can use
# the WSL transport (wsl.exe -d <distro> -- bash -ic "...") or simply run inside
# the distro. Set sshd up only if you prefer the ssh model (e.g. to reuse the
# same skills/aliases as a remote VM, or for JetBrains Gateway).
#
# Uses a configurable NON-22 port so it never clashes with a Windows OpenSSH
# server on the host: first argument or WT_WSL_SSH_PORT, default 2222. Thanks to
# WSL2's default localhostForwarding, the server is reachable from Windows at
# localhost:<port> with no extra forwarding.
# Requires systemd as PID 1 (see wsl.conf). Idempotent.
set -eu

PORT="${1:-${WT_WSL_SSH_PORT:-2222}}"
case "$PORT" in ''|*[!0-9]*) echo "invalid port: $PORT" >&2; exit 1;; esac

if [ "$(ps -p 1 -o comm= 2>/dev/null)" != "systemd" ]; then
  echo "systemd is not PID 1 — install platform/wsl/wsl.conf and run 'wsl --shutdown' from Windows first" >&2
  exit 1
fi

sudo env DEBIAN_FRONTEND=noninteractive apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssh-server

sudo tee /etc/ssh/sshd_config.d/60-worktree-vm.conf >/dev/null <<EOF
# worktree-vm: non-22 port to avoid clashing with a Windows sshd on the host.
Port $PORT
EOF
sudo systemctl enable --now ssh
sudo systemctl restart ssh

echo
echo "sshd listening on port $PORT. From Windows:"
echo "  ssh -p $PORT $(id -un)@localhost"
echo "Key-based login (recommended) — from PowerShell on Windows:"
echo "  type \$env:USERPROFILE\\.ssh\\id_ed25519.pub | wsl.exe -d <distro> -- bash -c 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys'"
