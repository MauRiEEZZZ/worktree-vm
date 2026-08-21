#!/usr/bin/env bash
# install.sh — the ONE entrypoint: provision this Ubuntu guest (a Lima VM on
# macOS, a WSL2 distro on Windows, or any plain Ubuntu) as a worktree-vm.
#
#   git clone https://github.com/MauRiEEZZZ/worktree-vm && cd worktree-vm && ./install.sh
#
# Detects platform + architecture, loads/validates the config, runs the
# provision/ steps in order, then runs your post-provision hook (if any).
# Idempotent: safe to re-run after editing the config or pulling updates.
set -eu -o pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_DIR

# ---- sanity ----------------------------------------------------------------
if [ "$(id -u)" = 0 ]; then
  echo "Run install.sh as your normal user — it uses sudo where root is needed." >&2
  exit 1
fi
command -v sudo >/dev/null || { echo "sudo is required" >&2; exit 1; }
if [ -r /etc/os-release ]; then . /etc/os-release; fi
case "${ID:-}" in
  ubuntu) : ;;
  *) echo "WARNING: this is tested on Ubuntu 24.04; detected '${ID:-unknown}'. Continuing anyway." >&2 ;;
esac

# ---- platform + architecture -----------------------------------------------
# Never hardcode an architecture: thread these through every apt source line
# and download URL.
DPKG_ARCH="$(dpkg --print-architecture)"
UNAME_ARCH="$(uname -m)"
export DPKG_ARCH UNAME_ARCH

if [ -n "${WSL_DISTRO_NAME:-}" ]; then
  WT_PLATFORM=wsl
  # Docker, sshd and the dashboard unit need systemd as PID 1. In WSL2 that is
  # opt-in: /etc/wsl.conf [boot] systemd=true, then `wsl --shutdown` from Windows.
  if [ "$(ps -p 1 -o comm= 2>/dev/null)" != "systemd" ]; then
    echo "systemd is not PID 1 in this WSL distro. Enable it first:" >&2
    echo '  printf "[boot]\nsystemd=true\n" | sudo tee /etc/wsl.conf' >&2
    echo "  then from Windows: wsl --shutdown   (and reopen the distro)" >&2
    exit 1
  fi
elif [ -e /mnt/lima-cidata ] || [ -d /Users ]; then
  WT_PLATFORM=lima
else
  WT_PLATFORM=linux
fi
export WT_PLATFORM
echo "platform: $WT_PLATFORM   arch: $DPKG_ARCH ($UNAME_ARCH)"

# ---- config ------------------------------------------------------------------
WT_CONFIG_DIR="${WT_CONFIG_DIR:-$HOME/.config/wt}"
export WT_CONFIG_DIR
mkdir -p "$WT_CONFIG_DIR"
if [ ! -f "$WT_CONFIG_DIR/config.yaml" ]; then
  cp "$REPO_DIR/config.example.yaml" "$WT_CONFIG_DIR/config.yaml"
  echo "seeded $WT_CONFIG_DIR/config.yaml from config.example.yaml — edit it (repos!) and re-run install.sh, or continue for a bare install"
fi
bash "$REPO_DIR/lib/config/generate-env.sh"
# shellcheck source=/dev/null
. "$WT_CONFIG_DIR/env.sh"

# validate the enum-ish values so a typo fails here, not at first use
case "$WT_IDE_BACKEND" in none|rider|code-server) ;; *)
  echo "config error: ide.backend must be none|rider|code-server (got '$WT_IDE_BACKEND')" >&2; exit 1 ;; esac
case "$WT_AGENT_DEFAULT" in claude|codex) ;; *)
  echo "config error: agents.default must be claude|codex (got '$WT_AGENT_DEFAULT')" >&2; exit 1 ;; esac
for s in $WT_STACKS; do
  [ -f "$REPO_DIR/provision/stacks/$s.sh" ] || { echo "config error: unknown stack '$s' (no provision/stacks/$s.sh)" >&2; exit 1; }
done

# ---- provision ----------------------------------------------------------------
for script in "$REPO_DIR"/provision/[0-9]*.sh; do
  echo
  echo "==> $(basename "$script")"
  bash "$script"
done

# ---- post-provision hook (overlay/private extras: certs, extra seeds, ...) ----
if [ -f "$WT_HOOKS_DIR/post-provision.sh" ]; then
  echo
  echo "==> hook: post-provision"
  bash "$WT_HOOKS_DIR/post-provision.sh" || echo "warning: post-provision hook failed — continuing" >&2
fi

# ---- summary -------------------------------------------------------------------
echo
echo "=== versions ==="
docker --version 2>/dev/null || echo "docker: not available (log out/in for group membership)"
node --version
gh --version | head -1
command -v claude >/dev/null && claude --version || echo "claude: install manually"
command -v codex >/dev/null && echo "codex: $(codex --version 2>/dev/null | head -1)" || echo "codex: install manually"
for s in $WT_STACKS; do
  case "$s" in
    dotnet)     dotnet --version 2>/dev/null || echo "dotnet: install failed?";;
    powershell) pwsh --version 2>/dev/null || echo "pwsh: install failed?";;
    azure-cli)  az version --output yaml 2>/dev/null | head -1 || echo "az: install failed?";;
    pulumi)     PATH="$PATH:/opt/pulumi/bin" pulumi version 2>/dev/null || echo "pulumi: install failed?";;
  esac
done
echo
echo "Done. Open a NEW shell (or 'source ~/.bashrc') and try: wt-help, wt-repos"
echo "One-time auth (interactive, stays on this machine): gh auth login; claude; codex login"
[ -n "$WT_DASHBOARD_PORT" ] && echo "Dashboard: http://localhost:$WT_DASHBOARD_PORT"
