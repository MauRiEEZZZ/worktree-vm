#!/usr/bin/env bash
# stacks/dotnet.sh — .NET SDK via the official install script (architecture is
# auto-detected). NOT from apt: Ubuntu's dotnet-sdk package can lag behind what a
# project's global.json requires.
# Version precedence: WT_DOTNET_VERSION env var > stack_options.dotnet_version
# from the config (WT_DOTNET_VERSION_DEFAULT in the derived env) > latest LTS
# channel.
set -eu -o pipefail

DOTNET_VERSION="${WT_DOTNET_VERSION:-${WT_DOTNET_VERSION_DEFAULT:-}}"
curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
if [ -n "$DOTNET_VERSION" ]; then
  sudo bash /tmp/dotnet-install.sh --version "$DOTNET_VERSION" --install-dir /usr/share/dotnet
else
  sudo bash /tmp/dotnet-install.sh --channel LTS --install-dir /usr/share/dotnet
fi
sudo ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet
sudo tee /etc/profile.d/dotnet.sh >/dev/null <<'EOF'
export DOTNET_ROOT=/usr/share/dotnet
export PATH="$PATH:/usr/share/dotnet:/usr/local/bin"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
EOF

# Make interactive shells (incl. the dashboard's `bash -ic`) see the trusted
# ASP.NET dev-cert dir when present, so Kestrel and dev processes consider the
# dev cert trusted. Keep the system cert dir too so normal CA verification still
# works. Marker-guarded; idempotent.
if ! grep -q "worktree-vm dotnet stack" ~/.bashrc 2>/dev/null; then
  cat >> ~/.bashrc <<'EOF'

# --- worktree-vm dotnet stack ----------------------------------------------
[ -d "$HOME/.aspnet/dev-certs/trust" ] && export SSL_CERT_DIR="$HOME/.aspnet/dev-certs/trust:/usr/lib/ssl/certs"
# ---------------------------------------------------------------------------
EOF
fi
