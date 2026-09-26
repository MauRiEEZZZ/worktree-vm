# AGENTS.md — working on worktree-vm

Rules for anyone — agent or person — who changes this repository.

## What this repo is

The **public, generic core**: a Lima VM with one git worktree per feature session, the `wt-*`
helpers, the dashboard, and the hooks through which a **private overlay repository** tailors
the VM without touching this one (see `docs/hooks.md`). Anything specific to one organisation,
product or customer belongs in an overlay, never here.

## Git workflow

- **`main` only changes through a pull request.** The ruleset *main: pull requests only*
  enforces it: a PR, one approval, every review thread resolved, stale approvals dismissed on a
  new push, no force push, no deletion. There is no direct push — also not for administrators,
  who may skip the approval only inside a PR.
- **One branch per topic**, from `origin/main`. If other sessions share your checkout, work in a
  separate `git worktree` instead of checking out, resetting or stashing in it.
- **Review.** Request a review from a maintainer. Resolve findings with follow-up commits on the
  branch; say which findings you did not take and why. Merge after the approval.
- **Commits** — the title is one sentence that says what was wrong or what changed, in plain
  words, as in `git log` (e.g. *A rebuild leaves gh working and git unable to push*); the body
  says why, and how it was verified.
- **Pull requests** — a title that stands on its own, a description a newcomer can follow: what
  changes, why, how it was tested, and anything a reviewer should look at first.

## Before you open a PR

- `bash tests/run.sh` passes; CI runs `bash -n` on every shell file, `node --check`, shellcheck
  (error severity), the sanitation grep and the suite (see `.github/workflows/ci.yml`).
- **Nothing private.** `bash tests/sanitize.sh` passes, and you have read your diff for names of
  organisations, customers, products, internal hosts, issue numbers of private repositories and
  personal paths (`/Users/<name>`, `/home/<name>`). Copy generic code from a private repository
  as a fresh commit; never bring its history along.
- Tests use synthetic data only and run without access to any private repository.
- Vendored files carry their licence and attribution.

## Issues

- An issue says **why** (the problem, with a reproduction for a bug), **what** is to be done,
  what is **out of scope**, and how it is **accepted**.
- **Labels:** a larger piece of work is a `story`, with its parts as GitHub **sub-issues**;
  everything else is a `task` (or `bug` for a defect).
- Refer to issues in other repositories with their full prefix (`owner/repo#123`).

## Working with the VM

- **Never search `/` inside the VM** (`find /`, `grep -r /`, `du /`). The guest mounts the host's
  home directory read-only; on macOS a search that walks into protected folders (Documents,
  Music, other apps' data) makes the host wait for a privacy prompt, and until it is answered
  every file request through the mount blocks — every session in the VM hangs. Search the
  directory you mean.
- A VM-wide hang with processes in state `D` and wchan `request_wait_answer` is exactly that:
  look for a prompt on the host's screen.
