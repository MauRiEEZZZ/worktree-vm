#!/usr/bin/env bash
# 00-base.sh — base packages + apt keyring dir. Platform-agnostic (any Ubuntu 24.04).
set -eu -o pipefail
APT="sudo env DEBIAN_FRONTEND=noninteractive apt-get"

$APT update
$APT install -y --no-install-recommends \
  ca-certificates curl wget gnupg lsb-release apt-transport-https \
  git build-essential unzip jq bubblewrap

sudo install -m 0755 -d /etc/apt/keyrings
