#!/usr/bin/env bash
# stacks/azure-cli.sh — Azure CLI from the official Microsoft repo (multi-arch
# debs are available). Authenticate once with `az login`.
set -eu -o pipefail
APT="sudo env DEBIAN_FRONTEND=noninteractive apt-get"
DPKG_ARCH="${DPKG_ARCH:-$(dpkg --print-architecture)}"

curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
  | sudo gpg --dearmor --yes -o /etc/apt/keyrings/microsoft.gpg
sudo chmod a+r /etc/apt/keyrings/microsoft.gpg
echo "deb [arch=$DPKG_ARCH signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
  | sudo tee /etc/apt/sources.list.d/azure-cli.list >/dev/null
$APT update
$APT install -y azure-cli || echo "WARN: azure-cli install failed; install manually"
