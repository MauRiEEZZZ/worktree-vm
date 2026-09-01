#!/usr/bin/env bash
# Bug (2026-09-01): `pnpm` was not on PATH in the guest. Node ships corepack but
# without `corepack enable` only npm is reachable, so a session in a pnpm workspace
# fell back to `npm install`, got a node_modules without the project's test runner,
# and REASONED its revert-checks from the code instead of running them — the one check
# that cannot be done by reading. corepack honours each repo's package.json
# "packageManager", so enabling it imposes nothing on the npm repos.
# Both assertions guard lines that look like noise to anyone who does not know what
# they cost.
. "$(dirname "$0")/../lib.sh"

NODE_SH="$T_REPO/provision/20-node.sh"
assert_file "$NODE_SH" "the node provisioning step exists"
# match the COMMAND, not the prose: the comment above it also says "corepack enable",
# so grepping the whole file would pass with the command deleted (it did, first try)
assert_eq "$(grep -c '^sudo corepack enable$' "$NODE_SH")" "1" "provisioning puts pnpm/yarn on PATH"
assert_eq "$(grep -c 'COREPACK_ENABLE_DOWNLOAD_PROMPT=0' "$NODE_SH")" "1" "and never waits on the download prompt"

# corepack downloads each pinned package manager on first use; without the cache on the
# data disk every rebuild re-downloads them, and a session without network has no pnpm.
DISK_SH="$T_REPO/platform/lima/data-disk.sh"
LINKS_LINE="$(grep '^LINKS=' "$DISK_SH")"
assert_contains "$LINKS_LINE" ".cache/node" "corepack's download cache is persisted"
assert_contains "$LINKS_LINE" ".cache/ms-playwright" "the playwright cache still is too"

t_end
