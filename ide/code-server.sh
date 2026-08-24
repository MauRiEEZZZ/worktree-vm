# ide/code-server.sh — code-server (Coder, MIT): VS Code in the browser. Sourced
# by lib/wt/ide.sh; implements the ide_install / ide_start / ide_stop / ide_url
# contract.
#
# Unlike Rider there is NO shared lock: one instance runs PER WORKTREE, in tmux
# session ide-<key>--<name>, bound to 127.0.0.1 on a port allocated from
# ide.port_base upward (first free). No connection token (--auth none): access
# is already gated by loopback + the ssh tunnel (or, on WSL2, by localhost
# forwarding to the Windows host only).

ide_install() {
  command -v code-server >/dev/null 2>&1 && return 0
  echo "installing code-server (official installer; auto-detects the architecture)..." >&2
  curl -fsSL https://code-server.dev/install.sh | sh || { echo "code-server install failed" >&2; return 1; }
}

_wt_ide_free_port() {  # first free port from WT_IDE_PORT_BASE upward (probe loopback)
  local base="${WT_IDE_PORT_BASE:-6000}" p
  for p in $(seq "$base" $((base + 99))); do
    if ! (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null; then echo "$p"; return 0; fi
  done
  echo "no free IDE port in $base..$((base + 99))" >&2; return 1
}

ide_start() {  # $1=key $2=name $3=dir $4=sid(ide-<key>--<name>)
  local key="$1" name="$2" dir="$3" sid="$4" port
  local log="/tmp/$sid.log"
  if tmux has-session -t "=$sid" 2>/dev/null; then
    echo "IDE already running: $sid"
    port="$(cat "$WT_META/$sid.ide-port" 2>/dev/null)"
    [ -n "$port" ] || { echo "(no recorded port — check: tmux attach -t =$sid)"; return 1; }
  else
    port="$(_wt_ide_free_port)" || return 1
    mkdir -p "$WT_META"; printf '%s\n' "$port" > "$WT_META/$sid.ide-port"
    # Marker line FIRST: wt-ls and the dashboard read the IDE port (and link)
    # from this log with the same tcp://127.0.0.1:<port>#... pattern as the
    # Rider Join link, so both backends light up the same UI.
    printf 'tcp://127.0.0.1:%s#code-server\n' "$port" > "$log"
    tmux new-session -d -s "$sid" "code-server --bind-addr 127.0.0.1:$(printf %q "$port") --auth none $(printf %q "$dir") 2>&1 | tee -a $(printf %q "$log")"
    echo "code-server starting on 127.0.0.1:$port for $dir"
  fi
  echo
  echo "Open the worktree in your browser:"
  echo "  over ssh:  ssh -N -L $port:127.0.0.1:$port ${WT_SSH_HOST:-<vm-host>}   then open http://localhost:$port"
  echo "  on WSL2:   just open http://localhost:$port on Windows (localhost forwarding is on by default)"
  echo "(tmux: $sid   |   stop: wt-ide-stop $key $name   |   several worktrees can run their own instance)"
}

ide_stop() { tmux kill-session -t "=$1" 2>/dev/null || true; rm -f "$WT_META/$1.ide-port"; }

ide_url() { local p; p="$(cat "$WT_META/$1.ide-port" 2>/dev/null)"; [ -n "$p" ] && echo "http://127.0.0.1:$p"; }
