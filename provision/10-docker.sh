#!/usr/bin/env bash
# 10-docker.sh — Docker Engine from the official repo (free on Linux); the
# container runtime for the projects' dev stacks. Arch comes from dpkg — never
# hardcoded.
set -eu -o pipefail
APT="sudo env DEBIAN_FRONTEND=noninteractive apt-get"
DPKG_ARCH="${DPKG_ARCH:-$(dpkg --print-architecture)}"

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$DPKG_ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

$APT update
$APT install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable --now docker
sudo usermod -aG docker "$(id -un)"

# ---------------------------------------------------------------------------
# Make that membership USABLE, today, without a re-login.
#
# A process's supplementary groups are fixed when it logs in, and every
# long-lived login on this machine is opened BEFORE provisioning runs:
#   * Lima's ssh ControlMaster (`ControlPersist yes`) is established by the host
#     agent at VM start and reused by every `limactl shell` and `ssh lima-<inst>`
#     for the rest of the boot;
#   * the tmux server that hosts the agent sessions is forked from one of those.
# So `usermod -aG docker` alone is invisible where it matters. Measured on a live
# VM, 2026-09-03: /etc/group listed the user in `docker`, `getent` agreed, and
# every shell and every session still had to reach docker through `sudo` — the
# group had been in this script since day one and had never once taken effect.
#
# The fix is to stop depending on a login: own the socket with the user's PRIMARY
# group, which every process already carries. Same access the docker group grants
# (and which the line above grants anyway) on a single-user dev VM; nothing new is
# exposed. The drop-in makes it survive a reboot, the chgrp makes it true now —
# deliberately WITHOUT restarting docker, because a restart takes down the
# containers a running session is using.
DOCKER_GRP="$(id -gn)"
sudo mkdir -p /etc/systemd/system/docker.socket.d
printf '# written by worktree-vm provision/10-docker.sh\n[Socket]\nSocketGroup=%s\n' "$DOCKER_GRP" \
  | sudo tee /etc/systemd/system/docker.socket.d/10-socket-group.conf >/dev/null
sudo systemctl daemon-reload
[ -S /run/docker.sock ] && { sudo chgrp "$DOCKER_GRP" /run/docker.sock; sudo chmod 660 /run/docker.sock; }

if docker info >/dev/null 2>&1; then
  echo "docker: reachable without sudo"
else
  echo "WARNING: docker still needs sudo for this user — check 'ls -l /run/docker.sock' and the drop-in in /etc/systemd/system/docker.socket.d" >&2
fi
