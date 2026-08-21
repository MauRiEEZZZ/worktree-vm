#!/usr/bin/env bash
# data-disk.sh — Lima-only: put work + sessions + auth on the persistent data
# disk so they survive `limactl delete` + rebuild (the VM's native disk does not).
# Runs inside the guest, early (before the dashboard + wt-* helpers use these
# paths). Idempotent; handles both a rebuilt VM (data already on the disk) and a
# first migration (real dirs in home -> moved to the disk).
#
# WHY ~/wt IS A BIND MOUNT AND NOT A SYMLINK (the single subtlest thing here):
#   Claude Code keys conversation history on the PHYSICAL working-directory path
#   (Node's process.cwd() resolves symlinks). With a symlink, a session started
#   in ~/wt/<repo>/<name> would record its history under /mnt/.../wt/... — and
#   `claude --continue` (and wt-restore) could never find the per-worktree
#   conversation again. A bind mount keeps the physical path /home/<user>/wt, so
#   it matches byte-for-byte across rebuilds. The bind is persisted via fstab.
#   The other dirs are plain symlinks: they are fixed-path lookups
#   ($HOME/.claude etc.), unaffected by cwd resolution.
#
# Env:
#   WT_DATA_MOUNT  (required) the disk's mount point, /mnt/lima-<disk-name>
#   WT_DATA_LINKS  dirs (relative to ~) to move to the disk and symlink back
#   WT_DATA_EXTRA  extra such dirs (up.sh passes clone_paths that live under ~)
set -eu

D="${WT_DATA_MOUNT:?set WT_DATA_MOUNT to the data disk mount point (/mnt/lima-<disk>)}"
LINKS="${WT_DATA_LINKS:-repos .claude .codex .config/gh .config/wt .azure}"
EXTRA="${WT_DATA_EXTRA:-}"

for i in $(seq 1 30); do mountpoint -q "$D" && break; sleep 1; done
if ! mountpoint -q "$D"; then echo "WARN: $D not mounted; skipping data-disk setup"; exit 0; fi
sudo chown "$(id -un):$(id -gn)" "$D"

# ~/wt via bind mount (physical path stays /home so claude --continue / process.cwd() work)
mkdir -p "$D/wt"
grep -q " $HOME/wt " /etc/fstab || \
  echo "$D/wt $HOME/wt none bind,nofail,x-systemd.requires-mounts-for=$D 0 0" | sudo tee -a /etc/fstab >/dev/null
[ -L "$HOME/wt" ] && rm "$HOME/wt"                # replace a legacy symlink
if [ -d "$HOME/wt" ] && ! mountpoint -q "$HOME/wt" && [ -n "$(ls -A "$HOME/wt" 2>/dev/null)" ] && [ -z "$(ls -A "$D/wt" 2>/dev/null)" ]; then
  mv "$HOME/wt"/* "$HOME/wt"/.[!.]* "$D/wt"/ 2>/dev/null || true   # first migration
fi
mkdir -p "$HOME/wt"
# Self-heal a boot-race: on an unclean shutdown the fstab bind can attach BEFORE
# the data disk is mounted, capturing the empty placeholder on the root disk
# (source subpath $D/wt on the root device instead of /wt on the data disk).
# Detect that stale bind and re-point it — provisioning re-runs on every
# `limactl start`, so this self-heals.
if mountpoint -q "$HOME/wt" && findmnt -no SOURCE "$HOME/wt" | grep -q "$D/wt"; then
  echo "wt: stale bind (boot race) detected -> re-pointing to the data disk"
  sudo umount "$HOME/wt"
fi
mountpoint -q "$HOME/wt" || sudo mount --bind "$D/wt" "$HOME/wt"

# the rest: symlinks
for item in $LINKS $EXTRA; do
  src="$HOME/$item"; dst="$D/$item"
  [ -L "$src" ] && continue
  mkdir -p "$(dirname "$dst")" "$(dirname "$src")"
  if [ -e "$src" ] && [ ! -e "$dst" ]; then
    mv "$src" "$dst"
  elif [ -e "$src" ] && [ -e "$dst" ]; then
    mv "$src" "$src.pre-disk.$$"
  fi
  [ -e "$dst" ] || mkdir -p "$dst"
  ln -s "$dst" "$src"
done
echo "data-disk: ~/wt bound to $D/wt; linked: $LINKS $EXTRA"
