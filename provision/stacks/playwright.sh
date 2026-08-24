#!/usr/bin/env bash
# stacks/playwright.sh — Playwright browsers for end-to-end testing. HEADLESS-ONLY
# by deliberate policy (see below).
#
# Browsers: BOTH chromium and firefox by default, and that order of priority is
# not arbitrary — firefox is the browser the product's users actually use, so it
# is the first-class citizen here and must not silently drop off as an optional
# extra; chromium is there for quick checks. Configure the set with
# stack_options.playwright_browsers (e.g. only chromium to skip firefox's
# system packages).
#
# System packages come from `playwright install-deps` — playwright-core's own
# canonical per-distro list (identical for x64 and arm64 on ubuntu24.04: the
# arm64 entry is a spread of the x64 entry in the source). Never hand-maintain
# a package list here. install-deps wraps apt in a single sudo call itself.
#
# HEADLESS-ONLY policy (explicit owner decision):
#  - NO --no-sandbox anywhere, ever, as a default: autonomous agents open web
#    pages on this machine, and the browser sandbox is exactly the protection
#    you want to keep there.
#  - NO AppArmor profile for chromium is shipped. Ubuntu 24.04's
#    kernel.apparmor_restrict_unprivileged_userns=1 makes HEADED chromium die
#    with "No usable sandbox!"; headless works fine. If you truly need headed,
#    write your own AppArmor profile granting userns to the chrome binary (see
#    provision/60-bwrap-apparmor.sh for what such a profile looks like) — we
#    consciously do not do that by default.
#
# Version: stack_options.playwright_version (empty = latest); the
# WT_PLAYWRIGHT_VERSION env var overrides. NOTE on version drift: playwright
# pins browsers per revision (e.g. firefox-1538). A version bump installs a NEW
# revision dir next to the old one and cleans nothing up — reclaim space with
# `npx playwright uninstall --all` (then reinstall). Projects that pin a
# different playwright version download their own matching revisions into the
# same cache, which the (Lima) persistence makes cheap instead of repeated.
#
# Cache: the DEFAULT path ~/.cache/ms-playwright on purpose — no
# PLAYWRIGHT_BROWSERS_PATH env var every consumer would have to know about. On
# macOS/Lima that path is persisted on the data disk; on WSL2 it is durable by
# itself. Budget roughly 1.2 GB for chromium + headless shell + firefox.
set -eu -o pipefail

command -v node >/dev/null 2>&1 || { echo "node missing (20-node.sh should have run first)" >&2; exit 1; }

BROWSERS="${WT_PLAYWRIGHT_BROWSERS:-chromium firefox}"
VERSION="${WT_PLAYWRIGHT_VERSION:-${WT_PLAYWRIGHT_VERSION_DEFAULT:-}}"
PW="playwright@${VERSION:-latest}"
echo "playwright stack: $PW, browsers: $BROWSERS"

# 1) system packages (playwright batches them into one sudo apt-get call)
# shellcheck disable=SC2086
npx -y "$PW" install-deps $BROWSERS

# 2) the browsers themselves, per-user into ~/.cache/ms-playwright (idempotent:
#    already-present revisions are skipped)
# shellcheck disable=SC2086
npx -y "$PW" install $BROWSERS
