#!/usr/bin/env bash
# 99-dashboard.sh — install + start the dashboard as a systemd unit. The unit is
# rendered from dashboard/wt-dashboard.service.template; all feature config comes
# from ~/.config/wt/dashboard.env via EnvironmentFile= (regenerate with
# lib/config/generate-env.sh after editing the config, then
# `sudo systemctl restart wt-dashboard`).
set -eu -o pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WT_CONFIG_DIR="${WT_CONFIG_DIR:-$HOME/.config/wt}"
NODE_BIN="$(command -v node)"
[ -n "$NODE_BIN" ] || { echo "node not found (20-node.sh should have installed it)" >&2; exit 1; }
[ -f "$WT_CONFIG_DIR/dashboard.env" ] || bash "$REPO_DIR/lib/config/generate-env.sh"

sed -e "s|@USER@|$(id -un)|g" \
    -e "s|@HOME@|$HOME|g" \
    -e "s|@DASHBOARD_DIR@|$REPO_DIR/dashboard|g" \
    -e "s|@CONFIG_DIR@|$WT_CONFIG_DIR|g" \
    -e "s|@NODE@|$NODE_BIN|g" \
    "$REPO_DIR/dashboard/wt-dashboard.service.template" \
  | sudo tee /etc/systemd/system/wt-dashboard.service >/dev/null

sudo systemctl daemon-reload
sudo systemctl enable wt-dashboard
sudo systemctl restart wt-dashboard
echo "wt-dashboard: $(systemctl is-active wt-dashboard)"
