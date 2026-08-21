# import.ps1 — OPTIONAL: create a DEDICATED WSL2 instance for worktree-vm from an
# Ubuntu rootfs tarball, instead of using your everyday `wsl --install -d
# Ubuntu-24.04` distro. A dedicated instance keeps the dev VM disposable: you can
# `wsl --unregister` it without touching anything else.
#
# Most users do NOT need this — the standard path in docs/install-windows-wsl.md
# (wsl --install -d Ubuntu-24.04) is simpler. Use this when you want a second,
# isolated instance.
#
# Get a rootfs first (Ubuntu publishes WSL rootfs tarballs for 24.04 at
# https://cloud-images.ubuntu.com/wsl/ — pick the amd64/arm64 file matching your
# machine), then run from PowerShell:
#   .\import.ps1 -RootfsPath C:\path\to\ubuntu-24.04-wsl.rootfs.tar.gz -UserName you
param(
  [Parameter(Mandatory = $true)] [string]$RootfsPath,
  [string]$Name = "worktree-vm",
  [string]$InstallDir = "$env:LOCALAPPDATA\wsl\worktree-vm",
  [Parameter(Mandatory = $true)] [string]$UserName
)
$ErrorActionPreference = "Stop"

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  Write-Error "wsl.exe not found. Install WSL first (elevated PowerShell): wsl --install"
}
if (-not (Test-Path $RootfsPath)) { Write-Error "rootfs not found: $RootfsPath" }
if (wsl.exe --list --quiet | Where-Object { $_ -eq $Name }) {
  Write-Error "a distro named '$Name' already exists (wsl --unregister $Name to remove it)"
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Write-Host "importing $RootfsPath as '$Name' (WSL2) into $InstallDir ..."
wsl.exe --import $Name $InstallDir $RootfsPath --version 2

# Create the default user and enable systemd (required by install.sh), then
# restart the distro so both take effect.
Write-Host "creating user '$UserName' (you will be asked to set a password) ..."
wsl.exe -d $Name -u root -- bash -c "useradd -m -G sudo -s /bin/bash '$UserName' && passwd '$UserName' && printf '[user]\ndefault=%s\n\n[boot]\nsystemd=true\n' '$UserName' > /etc/wsl.conf"
wsl.exe --terminate $Name

Write-Host ""
Write-Host "Done. Continue with docs/install-windows-wsl.md from the 'inside the distro' step:"
Write-Host "  wsl.exe -d $Name"
Write-Host "  sudo apt update && sudo apt install -y git"
Write-Host "  curl -fsSL https://claude.ai/install.sh | bash"
Write-Host "  git clone https://github.com/MauRiEEZZZ/worktree-vm && cd worktree-vm && ./install.sh"
