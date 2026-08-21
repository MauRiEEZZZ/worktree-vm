#!/usr/bin/env bash
# 60-bwrap-apparmor.sh — let Codex's sandbox (bubblewrap) create user namespaces.
#
# Ubuntu 24.04 hardens unprivileged user namespaces
# (kernel.apparmor_restrict_unprivileged_userns=1). Codex sandboxes every command
# with bubblewrap, which needs a userns, so `bwrap` fails with "setting up uid
# map: Permission denied" and Codex falls back to another path — which is why a
# Codex review would error and only succeed on a retry.
# Fix surgically: keep the hardening ON system-wide and grant the capability to
# bwrap ALONE via an AppArmor profile. (Do NOT set
# kernel.apparmor_restrict_unprivileged_userns=0 — that disables the protection
# for every process; this profile is the targeted equivalent.)
# bubblewrap itself is installed in 00-base, so Codex uses /usr/bin/bwrap instead
# of its bundled copy.
set -eu -o pipefail

command -v bwrap >/dev/null || { echo "bwrap missing; skip"; exit 0; }
sudo tee /etc/apparmor.d/bwrap >/dev/null <<'PROF'
abi <abi/4.0>,
include <tunables/global>

profile bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,
  include if exists <local/bwrap>
}
PROF
sudo apparmor_parser -r /etc/apparmor.d/bwrap 2>/dev/null || echo "WARN: could not load bwrap AppArmor profile"
bwrap --dev-bind / / true 2>/dev/null && echo "bwrap can create user namespaces (Codex sandbox OK)" \
  || echo "WARN: bwrap still cannot create a userns — Codex sandboxing may be flaky"
