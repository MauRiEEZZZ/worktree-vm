#!/usr/bin/env bash
# 20-node.sh — Node.js from NodeSource, pinned to the v24 major for reproducible
# rebuilds/rollback (the setup script auto-detects the architecture).
set -eu -o pipefail
APT="sudo env DEBIAN_FRONTEND=noninteractive apt-get"

curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
$APT install -y nodejs
