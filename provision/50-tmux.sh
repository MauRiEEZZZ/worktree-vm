#!/usr/bin/env bash
# 50-tmux.sh — tmux hosts every dev session and IDE backend.
set -eu -o pipefail
APT="sudo env DEBIAN_FRONTEND=noninteractive apt-get"

command -v tmux >/dev/null || { $APT update && $APT install -y --no-install-recommends tmux; }
