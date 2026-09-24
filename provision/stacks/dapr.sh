#!/usr/bin/env bash
# stacks/dapr.sh — Dapr CLI from the project's GitHub releases (there is no apt
# package). Installs the CLI ONLY. `dapr init` is deliberately not run here: it
# starts four always-on containers (placement, scheduler, redis, zipkin) that
# together idle around 310 MB — zipkin alone is ~260 MB of that — and most
# sessions never touch Dapr. Run it yourself when a project needs the runtime:
#   dapr init          # the full local runtime, with those containers
#   dapr init --slim   # runtime binaries only, no containers
# Version precedence: WT_DAPR_VERSION env var > stack_options.dapr_version from
# the config (WT_DAPR_VERSION_DEFAULT in the derived env) > the latest release.
set -eu -o pipefail
DPKG_ARCH="${DPKG_ARCH:-$(dpkg --print-architecture)}"

VERSION="${WT_DAPR_VERSION:-${WT_DAPR_VERSION_DEFAULT:-}}"
if [ -z "$VERSION" ]; then
  VERSION="$(curl -fsSL https://api.github.com/repos/dapr/cli/releases/latest \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$VERSION" ]; then
  echo "WARN: could not determine a dapr CLI version (no pin, and the release lookup failed); skipping" >&2
  exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if curl -fsSL -o "$TMP/dapr.tar.gz" \
     "https://github.com/dapr/cli/releases/download/${VERSION}/dapr_linux_${DPKG_ARCH}.tar.gz"; then
  tar xzf "$TMP/dapr.tar.gz" -C "$TMP" dapr
  sudo install -m755 "$TMP/dapr" /usr/local/bin/dapr
  echo "dapr CLI ${VERSION} installed — run 'dapr init' when a project needs the runtime"
else
  echo "WARN: dapr ${VERSION} download failed for ${DPKG_ARCH}; install manually" >&2
fi
