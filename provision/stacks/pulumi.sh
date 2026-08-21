#!/usr/bin/env bash
# stacks/pulumi.sh — Pulumi CLI via the official installer (architecture is
# auto-detected). Heavier ops tooling (kubectl/helm/k9s/...) is deliberately not
# installed here — add it per-session if needed.
set -eu -o pipefail

curl -fsSL https://get.pulumi.com | sudo bash -s -- --install-root /opt/pulumi --no-edit-path \
  || echo "WARN: pulumi install failed; install manually"
echo 'export PATH="$PATH:/opt/pulumi/bin"' | sudo tee /etc/profile.d/pulumi.sh >/dev/null
