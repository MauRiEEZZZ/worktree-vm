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
# WHAT must persist and why (losing any of these on a rebuild hurts):
#   ~/repos, clone_paths   the main clones
#   ~/.claude ~/.codex ~/.config/gh ~/.azure   agent + CLI auth/state
#   ~/.microsoft/usersecrets  .NET user-secrets — the same category as the auth above,
#                          and the one that bites hardest: Aspire AppHosts take secrets
#                          (a SQL password) as required parameters, so a rebuild without
#                          them means the app does not start at all. Worse, the password
#                          was baked into a persisted SQL Server data volume, so
#                          regenerating it is not a fix either (measured 2026-09-03 on
#                          vidara.portal).
#   ~/.config/wt           the wt config + derived env
#   ~/.wt-meta             per-session markers (agent/flags/model/priority)
#   ~/.cache/node          corepack's package-manager downloads (pnpm/yarn per repo
#                          pin) — without it every rebuild re-downloads them on first
#                          use, and a session with no network has no pnpm at all
#                          AND the PR-review watcher's review-seen.json ledger —
#                          lose that and the watcher re-spawns a review session
#                          for every PR it had already handled
#   sessions.meta_dir      dashboard session metadata + tombstones in archive/ —
#                          lose it and nothing is restorable with fidelity
#   ~/.claude.json (FILE)  Claude Code's folder-trust list — without it every
#                          worktree re-prompts for trust after a rebuild, which
#                          hangs exactly the unattended (--auto) sessions
#
# Env:
#   WT_DATA_MOUNT  (required) the disk's mount point, /mnt/lima-<disk-name>
#   WT_DATA_LINKS  dirs (relative to ~) to move to the disk and symlink back
#   WT_DATA_FILES  FILES (relative to ~) to persist by copy — see below
#   WT_DATA_EXTRA  extra dirs (up.sh passes clone_paths that live under ~)
#   WT_SESSIONS_DIR  overrides the sessions.meta_dir derivation
set -eu

D="${WT_DATA_MOUNT:?set WT_DATA_MOUNT to the data disk mount point (/mnt/lima-<disk>)}"
#   .cache/ms-playwright: browser binaries at Playwright's DEFAULT cache path —
#   left off the disk they vanish on rebuild ("Failed to launch firefox because
#   executable doesn't exist"), and at ~1.2 GB for chromium+firefox re-downloads
#   are not free. Persisting the default path (instead of introducing a
#   PLAYWRIGHT_BROWSERS_PATH env var every consumer would need to know) also
#   lets an ad-hoc `npx playwright install` land on the disk automatically.
LINKS="${WT_DATA_LINKS:-repos .wt-meta .claude .codex .config/gh .config/wt .azure .microsoft/usersecrets .cache/ms-playwright .cache/node}"
FILES="${WT_DATA_FILES:-.claude.json}"
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

# ---- directories: move-once + symlink -----------------------------------------
_wt_link_dir() {  # $1 = path relative to $HOME
  local item="$1" src dst
  src="$HOME/$item"; dst="$D/$item"
  [ -L "$src" ] && return 0
  mkdir -p "$(dirname "$dst")" "$(dirname "$src")"
  if [ -e "$src" ] && [ ! -e "$dst" ]; then
    mv "$src" "$dst"
  elif [ -e "$src" ] && [ -e "$dst" ]; then
    mv "$src" "$src.pre-disk.$$"
  fi
  [ -e "$dst" ] || mkdir -p "$dst"
  ln -s "$dst" "$src"
}
for item in $LINKS $EXTRA; do _wt_link_dir "$item"; done

# The session-metadata dir (dashboard metadata + tombstones) is CONFIGURABLE
# (sessions.meta_dir). The AUTHORITATIVE value arrives via the WT_SESSIONS_DIR
# env, derived on the HOST by up.sh: this step runs BEFORE the guest config is
# seeded, so on a first provision a config read here finds nothing and would
# silently persist only the default. The config read below is a FALLBACK for
# later re-provisions / standalone runs; skip the dir when it already lives
# under a path linked above.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META_DIR="${WT_SESSIONS_DIR:-}"
if [ -z "$META_DIR" ] && [ -f "$HOME/.config/wt/config.yaml" ] && [ -f "$SELF_DIR/../../lib/config/parse-yaml.sh" ]; then
  # shellcheck source=../../lib/config/parse-yaml.sh
  . "$SELF_DIR/../../lib/config/parse-yaml.sh"
  META_DIR="$(wt_yaml_flatten "$HOME/.config/wt/config.yaml" | awk -F'\t' '$1=="sessions.meta_dir"{print $2}')"
  case "$META_DIR" in "~"|"~/"*) META_DIR="$HOME${META_DIR#\~}";; esac
fi
META_DIR="${META_DIR:-$HOME/.wt-sessions}"
META_NOTE=""
case "$META_DIR" in
  "$HOME"/*)
    rel="${META_DIR#"$HOME"/}"
    covered=0
    for item in $LINKS $EXTRA; do
      case "$rel" in "$item"|"$item"/*) covered=1; break;; esac
    done
    if [ "$covered" = 1 ]; then META_NOTE="(sessions.meta_dir already under a linked path)"
    else _wt_link_dir "$rel"; META_NOTE="$rel"; fi
    ;;
  *) echo "WARN: sessions.meta_dir ($META_DIR) is outside \$HOME — not persisted on the data disk" >&2 ;;
esac

# ---- FILES: restore-on-rebuild + refresh-on-every-provision --------------------
# Files are COPIED, not symlinked, on purpose: Claude Code (and our own
# _wt_seed_perms) replace ~/.claude.json ATOMICALLY via rename(2), and rename
# replaces a symlink itself with a regular file — the disk copy would silently
# go stale after the first write, and the next rebuild would then restore a
# first-day snapshot over newer state. So instead: on a rebuild (file missing
# in home) restore it from the disk; then refresh the disk copy on every
# provision run (= every `limactl start`). Loss window = changes since the last
# VM start, and Claude Code never sees anything but a regular file.
# NOTE this copy is only an OPPORTUNISTIC net for non-critical state: the part
# that must never be lost — folder trust for the worktrees — is re-asserted
# from scratch by provision/96-worktree-trust.sh right after any restore, so
# even an empty or stale snapshot here is harmless for trust.
for f in $FILES; do
  src="$HOME/$f"; dst="$D/$f"
  mkdir -p "$(dirname "$dst")" "$(dirname "$src")"
  [ -L "$src" ] && rm "$src"                     # heal a symlink from an older scheme
  if [ ! -e "$src" ] && [ -f "$dst" ]; then
    cp -p "$dst" "$src" && echo "  restored file from data disk: ~/$f"
  fi
  # a brand-new setup: seed an empty JSON object — NEVER mkdir here (a
  # directory named .claude.json breaks Claude Code outright)
  [ -e "$src" ] || printf '{}\n' > "$src"
  cp -p "$src" "$dst.tmp.$$" && mv "$dst.tmp.$$" "$dst"
done

echo "data-disk: ~/wt bound to $D/wt; linked: $LINKS $EXTRA $META_NOTE; files (copy): $FILES"
