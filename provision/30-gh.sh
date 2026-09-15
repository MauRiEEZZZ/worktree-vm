#!/usr/bin/env bash
# 30-gh.sh — GitHub CLI from the official repo. Arch comes from dpkg.
set -eu -o pipefail
APT="sudo env DEBIAN_FRONTEND=noninteractive apt-get"
DPKG_ARCH="${DPKG_ARCH:-$(dpkg --print-architecture)}"

curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | sudo dd of=/etc/apt/keyrings/githubcli-archive-keyring.gpg status=none
sudo chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$DPKG_ARCH signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null

$APT update
$APT install -y gh

# ---------------------------------------------------------------------------
# Teach git to authenticate through gh.
#
# `gh auth login` offers this at the end, so a first, interactive setup gets it —
# but a REBUILD never runs that login: gh's own auth lives in ~/.config/gh, which
# is on the data disk and survives, while the credential helper lives in
# ~/.gitconfig, which does not. The result is a machine where `gh` works fine and
# every `git push`/`git fetch` over https fails on auth. Measured 2026-09-15: the
# first push after a rebuild did not reach GitHub at all.
#
# Only meaningful once gh has an account, so it is conditional rather than
# fatal: on a brand-new VM there is nothing to set up yet, and the interactive
# `gh auth login` that follows will do it.
if gh auth status >/dev/null 2>&1; then
  gh auth setup-git && echo "git credential helper: gh"
else
  echo "gh is not logged in yet — run 'gh auth login' (it sets up the git credential helper too)"
fi
