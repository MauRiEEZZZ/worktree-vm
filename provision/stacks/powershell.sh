#!/usr/bin/env bash
# stacks/powershell.sh — PowerShell as a dotnet global tool (architecture-
# independent; the Microsoft apt feed's `powershell` package is amd64-only, which
# breaks on arm64). Requires the dotnet stack.
set -eu -o pipefail

if ! command -v dotnet >/dev/null 2>&1; then
  echo "WARN: the powershell stack needs the dotnet stack (dotnet not found); skipping" >&2
  exit 0
fi
command -v pwsh >/dev/null 2>&1 && { echo "pwsh already installed"; exit 0; }
sudo env DOTNET_ROOT=/usr/share/dotnet /usr/local/bin/dotnet tool install --tool-path /usr/local/bin PowerShell \
  || echo "WARN: PowerShell tool install failed; install manually"
