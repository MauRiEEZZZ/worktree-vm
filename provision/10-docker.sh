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
