#!/usr/bin/env bash
# up.sh — macOS host: render vm.yaml.template from your config and start the
# Lima VM. Written for the stock macOS bash 3.2 (no assoc arrays / -gA).
#
#   usage: platform/lima/up.sh [--sync-config] [config.yaml]
#
# Reads (first that exists): the config argument, $WT_CONFIG_FILE,
# ~/.config/wt/config.yaml, the repo's config.example.yaml. Creates the
# persistent data disk when configured and missing.
#
# Lifecycle honesty:
#  - a STOPPED existing instance: `limactl start` boots it and re-runs
#    provisioning (idempotent);
#  - a RUNNING instance: `limactl start` would be a silent no-op (provisioning
#    only runs at boot), so up.sh REFUSES and prints the real options instead
#    of pretending;
#  - --sync-config: push the host config into a RUNNING guest, regenerate the
#    derived env and restart the dashboard — the way to apply config edits
#    without a VM restart. Provisioning-level changes (stacks) additionally
#    need install.sh in the guest; platform facts (cpus/memory/ports/disks)
#    always need `limactl delete` + up.sh (work survives on the data disk).
set -eu

LIMA_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$LIMA_DIR/../.." && pwd)"
# shellcheck source=../../lib/config/parse-yaml.sh
. "$REPO_DIR/lib/config/parse-yaml.sh"

command -v limactl >/dev/null || { echo "limactl not found — install Lima first (brew install lima)" >&2; exit 1; }

SYNC_CONFIG=0
CONFIG_ARG=""
for a in "$@"; do
  case "$a" in
    --sync-config) SYNC_CONFIG=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $a (usage: up.sh [--sync-config] [config.yaml])" >&2; exit 1 ;;
    *) CONFIG_ARG="$a" ;;
  esac
done

CONFIG="${CONFIG_ARG:-${WT_CONFIG_FILE:-$HOME/.config/wt/config.yaml}}"
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
META_REL=""

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
    sessions.meta_dir)    # session metadata + tombstones must persist too. Derived
      # HERE on the host — the data-disk step runs BEFORE the guest config is
      # seeded, so a guest-side derivation at that point can only ever find the
      # default (that gap silently left the real meta_dir unpersisted).
      p="$(expand_home "$val")"
      case "$p" in
        "$HOME"/*) META_REL="${p#"$HOME"/}" ;;
        *) echo "WARN: sessions.meta_dir = $val is outside \$HOME — not persisted on the data disk" >&2 ;;
      esac ;;
  esac
done <<EOF
$(wt_yaml_flatten "$CONFIG")
EOF

# ---- instance status (drives --sync-config, the honest-refusal and the start) --
# Same --json rule as everywhere: never silence the listing's stderr; abort
# loudly if we cannot tell.
INSTANCES_JSON="$(limactl list --json)" \
  || { echo "ERROR: 'limactl list --json' failed — cannot tell whether instance '$INSTANCE' exists; not guessing" >&2; exit 1; }
INSTANCE_LINE="$(printf '%s\n' "$INSTANCES_JSON" | grep "\"name\"[[:space:]]*:[[:space:]]*\"$INSTANCE\"" | head -1 || true)"
INSTANCE_STATUS=""
[ -n "$INSTANCE_LINE" ] && INSTANCE_STATUS="$(printf '%s' "$INSTANCE_LINE" | sed -E 's/.*"status"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"

# ---- --sync-config: apply host config edits to a RUNNING guest ------------------
if [ "$SYNC_CONFIG" = 1 ]; then
  [ -n "$INSTANCE_LINE" ] || { echo "ERROR: instance '$INSTANCE' does not exist — run up.sh without --sync-config to create it" >&2; exit 1; }
  if [ "$INSTANCE_STATUS" != "Running" ]; then
    echo "ERROR: instance '$INSTANCE' is ${INSTANCE_STATUS:-in an unknown state} — --sync-config needs a running guest." >&2
    echo "Start it first: limactl start $INSTANCE   (note: booting re-runs provisioning but never overwrites an existing guest config; run --sync-config after boot)" >&2
    exit 1
  fi
  echo "syncing $CONFIG -> ~/.config/wt/config.yaml in '$INSTANCE'"
  limactl shell "$INSTANCE" -- bash -c 'mkdir -p "$HOME/.config/wt" && cat > "$HOME/.config/wt/config.yaml"' < "$CONFIG"
  echo "regenerating the derived env + restarting the dashboard"
  limactl shell "$INSTANCE" -- bash -c 'bash "$HOME/worktree-vm/lib/config/generate-env.sh" && sudo systemctl restart wt-dashboard'
  echo
  echo "done — config-driven features (repos, clone_paths, dashboard settings) are live."
  echo "Provisioning-level changes (stacks:, agents) additionally need one idempotent run in the guest (no restart):"
  echo "  limactl shell $INSTANCE -- bash worktree-vm/install.sh"
  echo "Platform facts (cpus/memory/ports/disks) still require: limactl delete $INSTANCE, then up.sh (work survives on the data disk)."
  exit 0
fi

# ---- honest refusal: a RUNNING instance cannot be re-provisioned by 'start' -----
if [ "$INSTANCE_STATUS" = "Running" ]; then
  echo "instance '$INSTANCE' is already RUNNING — refusing to pretend otherwise:"
  echo "'limactl start' on a running instance is a silent no-op, and provisioning only runs at boot,"
  echo "so nothing would be applied. What you probably want instead:"
  echo
  echo "  config-only changes:      $0 --sync-config"
  echo "      (pushes the host config into the guest, regenerates the derived env, restarts the dashboard; no VM restart)"
  echo "  re-run full provisioning: limactl shell $INSTANCE -- bash worktree-vm/install.sh"
  echo "      (idempotent, applies stacks/agents changes; no VM restart)"
  echo "  full reboot + provision:  limactl stop $INSTANCE && limactl start $INSTANCE"
  echo "      (WARNING: restarts the VM — every running tmux/agent session is killed)"
  echo "  platform facts (cpus/memory/ports/disks): limactl delete $INSTANCE, then up.sh"
  echo "      (work, sessions and auth survive on the data disk)"
  exit 1
fi

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
  META_ENV=""
  [ -n "$META_REL" ] && META_ENV="      export WT_SESSIONS_DIR=\"\$HOME/$META_REL\"${NL}"
  PROVISION_DATA_DISK="  # ---- persistent data disk: bind ~/wt + symlink durable dirs (see data-disk.sh) ----${NL}  - mode: user${NL}    script: |${NL}      #!/bin/bash${NL}      set -eu${NL}      export WT_DATA_MOUNT=\"/mnt/lima-$DATA_DISK\"${NL}      export WT_DATA_EXTRA=\"$(echo "$EXTRA_LINKS" | sed 's/^ *//')\"${NL}${META_ENV}      bash \"\$HOME/worktree-vm/platform/lima/data-disk.sh\"${NL}"
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
# A RUNNING instance was already refused above, so an existing instance here is
# stopped: booting it genuinely re-runs provisioning.
if [ -n "$INSTANCE_LINE" ]; then
  echo "instance '$INSTANCE' exists (${INSTANCE_STATUS:-status unknown}) — booting re-runs provisioning (platform-fact changes need: limactl delete $INSTANCE, then up.sh; work survives on the data disk)"
  limactl start "$INSTANCE"
else
  limactl start --name "$INSTANCE" "$OUT"
fi
