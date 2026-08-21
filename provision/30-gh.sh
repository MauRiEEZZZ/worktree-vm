#!/usr/bin/env bash
# 30-gh.sh — GitHub CLI from the official repo. Arch comes from dpkg.
set -eu -o pipefail
APT="sudo env DEBIAN_FRONTEND=noninteractive apt-get"
DPKG_ARCH="${DPKG_ARCH:-$(dpkg --print-architecture)}"

curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | sudo dd of=/etc/apt/keyrings/githubcli-archive-keyring.gpg status=none
sudo chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$DPKG_ARCH signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null

$APT update
$APT install -y gh
