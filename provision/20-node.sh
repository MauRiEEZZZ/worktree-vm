#!/usr/bin/env bash
# 20-node.sh — Node.js from NodeSource, pinned to the v24 major for reproducible
# rebuilds/rollback (the setup script auto-detects the architecture).
set -eu -o pipefail
APT="sudo env DEBIAN_FRONTEND=noninteractive apt-get"

curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
$APT install -y nodejs

# corepack: make `pnpm` and `yarn` reachable under their own names. Node ships
# corepack, but without `corepack enable` only `npm` is on PATH — so a session in a
# pnpm workspace finds no pnpm, falls back to `npm install`, and gets a node_modules
# without the project's test runner. Measured 2026-09-01 on a review of a pnpm repo:
# the reviewer could not RUN its revert-checks and reasoned them from the code
# instead, which is exactly the check that cannot be done by reading.
# corepack respects each repo's package.json "packageManager", so this imposes
# nothing: an npm repo keeps using npm.
sudo corepack enable

# Defensive, and measured rather than assumed: corepack's download prompt only appears
# on an INTERACTIVE tty, so a session (whose stdin is not a tty) already downloads a
# pinned version silently — verified with an empty COREPACK_HOME, both with and without
# this variable, exit 0 and no prompt either way. What it buys is that an interactive
# `ssh lima-vidara-dev` behaves the same as the sessions do, so a human debugging a
# review never sits in front of a question the automation never sees.
sudo tee /etc/profile.d/corepack.sh >/dev/null <<'EOF'
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
EOF

# ---------------------------------------------------------------------------
# Verify what this step promises, instead of assuming it.
# "npm was missing on a fresh instance" was reported on 2026-09-03. It could not
# be reproduced afterwards and the two obvious suspects are ruled out: on the VM
# it was reported from, /usr/bin/npm is the NodeSource symlink and dpkg still owns
# it, and `corepack enable` was measured on corepack 0.35.0 to create shims for
# pnpm/pnpx/yarn/yarnpkg ONLY — never npm — so corepack cannot have shadowed it.
# Rather than fix a cause we have not found, make a recurrence impossible to miss:
# a half-finished install stops provisioning here, loudly, instead of surfacing
# hours later as a session that cannot install anything.
_missing=""
for _c in node npm npx corepack pnpm yarn; do
  command -v "$_c" >/dev/null 2>&1 || _missing="$_missing $_c"
done
if [ -n "$_missing" ]; then
  echo "ERROR: the node step finished but these are not on PATH:$_missing" >&2
  echo "       (nodejs from NodeSource ships node+npm+npx; corepack enable adds pnpm/yarn)" >&2
  exit 1
fi
echo "node $(node -v), npm $(npm -v), corepack $(corepack --version); pnpm + yarn on PATH via corepack"
