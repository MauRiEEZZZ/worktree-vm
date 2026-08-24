# ide/rider.sh — JetBrains Rider remote-dev backend, reached via JetBrains
# Gateway ("Connect to a Running IDE"). Sourced by lib/wt/ide.sh; implements the
# ide_install / ide_start / ide_stop / ide_url contract.
#
# GENUINE limitation: only ONE backend at a time. JetBrains shares the
# config/system dir per Rider install, so a second backend hangs on a lock —
# ide_start refuses with a clear message instead. Requires a one-time Gateway
# SSH connect (registers your JetBrains account on the VM).

RIDER_HOME="${RIDER_HOME:-$HOME/.local/rider}"

ide_install() {  # install the Rider remote-dev backend on first use (~2 GB, once)
  [ -x "$RIDER_HOME/bin/remote-dev-server.sh" ] && return 0
  local ver="${WT_IDE_RIDER_VERSION:-2026.1.3}" tarball
  # JetBrains naming: the x64 Linux tarball has no arch suffix; aarch64 does.
  case "${UNAME_ARCH:-$(uname -m)}" in
    aarch64|arm64) tarball="JetBrains.Rider-$ver-aarch64.tar.gz" ;;
    x86_64|amd64)  tarball="JetBrains.Rider-$ver.tar.gz" ;;
    *) echo "unsupported architecture for Rider: $(uname -m)" >&2; return 1 ;;
  esac
  echo "downloading Rider $ver ($tarball, ~2 GB, one-time)..." >&2
  mkdir -p "$RIDER_HOME"
  curl -fsSL "https://download.jetbrains.com/rider/$tarball" \
    | tar -xz -C "$RIDER_HOME" --strip-components=1 || { echo "Rider download failed" >&2; return 1; }
}

ide_start() {  # $1=key $2=name $3=dir $4=sid(ide-<key>--<name>)
  local key="$1" name="$2" dir="$3" sid="$4"
  # one IDE backend at a time (see header). Refuse with a clear message.
  local other; other=$(tmux ls 2>/dev/null | sed -E 's/:.*//' | grep -E '^ide-' | grep -vx "$sid" | head -1)
  if [ -n "$other" ] && ! tmux has-session -t "=$sid" 2>/dev/null; then
    echo "An IDE backend is already running: $other"
    echo "JetBrains allows only one at a time. Stop it first:"
    echo "  wt-ide-stop   (or: tmux kill-session -t =$other)"
    return 1
  fi
  if tmux has-session -t "=$sid" 2>/dev/null; then
    echo "IDE backend already running: $sid"
  else
    local log="/tmp/$sid.log"; : > "$log"
    tmux new-session -d -s "$sid" "$RIDER_HOME/bin/remote-dev-server.sh run $(printf %q "$dir") 2>&1 | tee $(printf %q "$log")"
    echo "starting IDE backend on $dir  (Rider startup ~30-60s)..."
  fi
  local link="" i
  for i in $(seq 1 40); do
    link=$(ide_url "$sid")
    [ -n "$link" ] && break; sleep 3
  done
  [ -z "$link" ] && { echo "no Join link found (check: tmux attach -t =$sid)"; return 1; }
  local port; port=$(echo "$link" | sed -E 's#tcp://127.0.0.1:([0-9]+).*#\1#')
  echo
  echo "1) Forward the port from your workstation:"
  echo "     ssh -N -L $port:127.0.0.1:$port ${WT_SSH_HOST:-<vm-host>}"
  echo "2) Paste into JetBrains Gateway > Connect to a Running IDE:"
  echo "     $link"
  echo "(tmux: $sid   |   stop: wt-ide-stop $key $name)"
}

ide_stop() { tmux kill-session -t "=$1" 2>/dev/null || true; }

ide_url() { grep -m1 -oE 'tcp://127\.0\.0\.1:[0-9]+#[^ ]+' "/tmp/$1.log" 2>/dev/null; }
