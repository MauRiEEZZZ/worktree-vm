#!/usr/bin/env bash
# up.sh — macOS host: render vm.yaml.template from your config and start the
# Lima VM. Written for the stock macOS bash 3.2 (no assoc arrays / -gA).
#
#   usage: platform/lima/up.sh [config.yaml]
#
# Reads (first that exists): $1, $WT_CONFIG_FILE, ~/.config/wt/config.yaml,
# the repo's config.example.yaml. Creates the persistent data disk when
# configured and missing. For an EXISTING instance it just re-runs provisioning
# (`limactl start <instance>`); platform-fact changes (cpus/memory/ports/disks)
# need `limactl delete <instance>` + up.sh — work survives on the data disk.
set -eu

LIMA_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$LIMA_DIR/../.." && pwd)"
# shellcheck source=../../lib/config/parse-yaml.sh
. "$REPO_DIR/lib/config/parse-yaml.sh"

command -v limactl >/dev/null || { echo "limactl not found — install Lima first (brew install lima)" >&2; exit 1; }

CONFIG="${1:-${WT_CONFIG_FILE:-$HOME/.config/wt/config.yaml}}"
if [ ! -f "$CONFIG" ]; then
  echo "no config at $CONFIG — using the repo's config.example.yaml (bare defaults)" >&2
  CONFIG="$REPO_DIR/config.example.yaml"
fi

# ---- defaults + config -------------------------------------------------------
# Defaults sized for a small laptop (they must boot within Lima's startup
# window there); raise them in the config for heavier stacks — see
# docs/install-macos-lima.md for honest minimums.
INSTANCE=worktree-vm
CPUS=2
MEMORY=4GiB
DISK=100GiB
DATA_DISK=worktree-data
DATA_DISK_SIZE=60GiB
DASH_PORT=7300
PORTS=""
EXTRA_LINKS=""

expand_home() { case "$1" in "~"|"~/"*) printf '%s%s' "$HOME" "${1#\~}";; *) printf '%s' "$1";; esac; }

while IFS="$(printf '\t')" read -r key val; do
  case "$key" in
    lima.instance)        INSTANCE="$val" ;;
    lima.cpus)            CPUS="$val" ;;
    lima.memory)          MEMORY="$val" ;;
    lima.disk)            DISK="$val" ;;
    lima.data_disk)       DATA_DISK="$val" ;;
    lima.data_disk_size)  DATA_DISK_SIZE="$val" ;;
    dashboard.port)       DASH_PORT="$val" ;;
    ports.[0-9]*)         PORTS="$PORTS $val" ;;
    clone_paths.*)        # clones outside ~/repos must persist too: symlink them onto the data disk
      p="$(expand_home "$val")"
      case "$p" in
        "$HOME"/*) EXTRA_LINKS="$EXTRA_LINKS ${p#"$HOME"/}" ;;
        *) echo "WARN: clone_paths ${key#clone_paths.} = $val is outside \$HOME — not persisted on the data disk" >&2 ;;
      esac ;;
  esac
done <<EOF
$(wt_yaml_flatten "$CONFIG")
EOF

# ---- image by HOST architecture (never hardcoded) ------------------------------
case "$(uname -m)" in
  arm64|aarch64)
    IMAGE_ARCH=aarch64
    IMAGE_LOCATION="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img" ;;
  x86_64|amd64)
    IMAGE_ARCH=x86_64
    IMAGE_LOCATION="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img" ;;
  *) echo "unsupported host architecture: $(uname -m)" >&2; exit 1 ;;
esac

# ---- blocks -------------------------------------------------------------------
NL='
'
PORT_FORWARDS="  - guestPort: $DASH_PORT${NL}    hostPort: $DASH_PORT"
for p in $PORTS; do
  PORT_FORWARDS="$PORT_FORWARDS${NL}  - guestPort: $p${NL}    hostPort: $p"
done

ADDITIONAL_DISKS=""
PROVISION_DATA_DISK=""
if [ -n "$DATA_DISK" ]; then
  ADDITIONAL_DISKS="# Persistent data disk — survives \`limactl delete\` + rebuild.${NL}additionalDisks:${NL}  - name: \"$DATA_DISK\"${NL}"
  PROVISION_DATA_DISK="  # ---- persistent data disk: bind ~/wt + symlink durable dirs (see data-disk.sh) ----${NL}  - mode: user${NL}    script: |${NL}      #!/bin/bash${NL}      set -eu${NL}      export WT_DATA_MOUNT=\"/mnt/lima-$DATA_DISK\"${NL}      export WT_DATA_EXTRA=\"$(echo "$EXTRA_LINKS" | sed 's/^ *//')\"${NL}      bash \"\$HOME/worktree-vm/platform/lima/data-disk.sh\"${NL}"
  # Existence check via --json: `limactl disk ls` does NOT support -q (unlike
  # `limactl list`), and an earlier `-q 2>/dev/null` variant swallowed exactly
  # that hard error — empty output, so up.sh tried to create the disk on every
  # run and died fatally ("disk already exists") on the second run. Both the
  # disk and instance checks now lean on --json (one JSON object per line with
  # a "name" key), and stderr stays VISIBLE: if the listing itself fails we
  # abort with a clear message instead of guessing.
  DISKS_JSON="$(limactl disk ls --json)" \
    || { echo "ERROR: 'limactl disk ls --json' failed — cannot tell whether data disk '$DATA_DISK' exists; not guessing" >&2; exit 1; }
  if ! printf '%s\n' "$DISKS_JSON" | grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$DATA_DISK\""; then
    echo "creating Lima data disk '$DATA_DISK' ($DATA_DISK_SIZE)"
    limactl disk create "$DATA_DISK" --size "$DATA_DISK_SIZE"
  fi
fi

# The repo checkout is visible in the guest only when it lives under your home
# (the home mount); otherwise the guest falls back to a public clone.
case "$REPO_DIR" in
  "$HOME"/*) : ;;
  *) echo "NOTE: $REPO_DIR is outside \$HOME — the guest will clone from GitHub instead of this checkout" >&2 ;;
esac
REPO_URL="https://github.com/MauRiEEZZZ/worktree-vm.git"
HOST_CONFIG="$CONFIG"
# Embed the resolved config VERBATIM into the seeding provision step (indented
# to the YAML block-scalar level), so the guest always receives exactly the
# config up.sh rendered from — wherever it lives on the host. Depending on the
# guest seeing the host path would silently fall back to repo defaults when the
# config is outside the mounted home.
CONFIG_CONTENT="$(sed 's/^/      /' "$CONFIG")"

# ---- render --------------------------------------------------------------------
TPL="$(cat "$LIMA_DIR/vm.yaml.template")"
TPL="${TPL//@CPUS@/$CPUS}"
TPL="${TPL//@MEMORY@/$MEMORY}"
TPL="${TPL//@DISK@/$DISK}"
TPL="${TPL//@IMAGE_LOCATION@/$IMAGE_LOCATION}"
TPL="${TPL//@IMAGE_ARCH@/$IMAGE_ARCH}"
TPL="${TPL//@ADDITIONAL_DISKS@/$ADDITIONAL_DISKS}"
TPL="${TPL//@PORT_FORWARDS@/$PORT_FORWARDS}"
TPL="${TPL//@PROVISION_DATA_DISK@/$PROVISION_DATA_DISK}"
TPL="${TPL//@REPO_HOST_DIR@/$REPO_DIR}"
TPL="${TPL//@REPO_URL@/$REPO_URL}"
TPL="${TPL//@CONFIG_CONTENT@/$CONFIG_CONTENT}"
TPL="${TPL//@HOST_CONFIG@/$HOST_CONFIG}"
TPL="${TPL//@INSTANCE@/$INSTANCE}"
TPL="${TPL//@DASH_PORT@/$DASH_PORT}"

OUT="${WT_LIMA_OUT:-$HOME/.config/wt/lima-$INSTANCE.yaml}"
mkdir -p "$(dirname "$OUT")"
printf '%s\n' "$TPL" > "$OUT"
echo "rendered $OUT"
limactl validate "$OUT"

# ---- start ----------------------------------------------------------------------
# Same --json existence check as the data disk above (and same rule: never
# silence stderr on the listing — a swallowed flag error is how the disk check
# broke).
INSTANCES_JSON="$(limactl list --json)" \
  || { echo "ERROR: 'limactl list --json' failed — cannot tell whether instance '$INSTANCE' exists; not guessing" >&2; exit 1; }
if printf '%s\n' "$INSTANCES_JSON" | grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$INSTANCE\""; then
  echo "instance '$INSTANCE' exists — re-running provisioning (config/template changes to platform facts need: limactl delete $INSTANCE, then up.sh; work survives on the data disk)"
  limactl start "$INSTANCE"
else
  limactl start --name "$INSTANCE" "$OUT"
fi
