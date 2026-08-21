#!/usr/bin/env bash
# 90-stacks.sh — OPT-IN toolchains, driven by the config's `stacks:` list
# (WT_STACKS in the derived env). Nothing here installs unless listed.
set -eu -o pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/stacks"
if [ -z "${WT_STACKS:-}" ]; then
  echo "no stacks configured (config: stacks) — skipping"
  exit 0
fi
for s in $WT_STACKS; do
  if [ ! -f "$STACK_DIR/$s.sh" ]; then
    echo "WARN: unknown stack '$s' (no $STACK_DIR/$s.sh); skipping" >&2
    continue
  fi
  echo "--> stack: $s"
  bash "$STACK_DIR/$s.sh"
done
