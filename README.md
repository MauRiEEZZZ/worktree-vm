# worktree-vm

A ready-to-install Linux dev VM for running **many AI coding sessions in parallel** — each on its
own git worktree, in its own tmux session, with its own agent (Claude Code or OpenAI Codex) — plus a
small web dashboard to create, watch, triage and resume them.

You drive it from your host terminal; `tmux` runs inside the guest. The same setup works on
**macOS** (Lima VM) and **Windows** (WSL2 distro), because everything above the hypervisor is one
platform-agnostic `install.sh`.

## Why

Letting an AI agent work aggressively is much more comfortable on a disposable machine that is not
your laptop. Give each task its own worktree and branch, and several agents work at once without
stepping on each other. The whole machine is defined in version-controlled files, so you can throw
it away and rebuild it in minutes — while your worktrees, session history and logins survive.

## The model

- **One session = one worktree = one branch = one tmux window = one agent.**
  `wt-new <repo> pdf-export-fix "repro and fix the crash in ..."` clones the repo on demand, makes
  `~/wt/<repo>/<name>` on branch `feat/<name>`, seeds gitignored local config, restores
  dependencies, and launches Claude (with Remote Control, so it can ask you questions) or Codex.
- **`wt-*` commands** for everything: `wt-ls` (pipeable: `wt-ls | grep stopped | wt-resume`),
  `wt-resume`, `wt-rm` (safe by default, tombstones metadata), `wt-restore` (deleted session +
  its preserved conversation come back), `wt-review` (independent Claude+Codex second-opinion
  review of a session's work), `wt-seed-main`, `wt-env`, `wt-ide`. Tab completion included.
- **Dashboard** (localhost web UI): create sessions from a task or a pasted issue/PR URL; grouped
  into work-in-progress → waiting on review (derived from the PR state) → parked (one click,
  keeps everything running) → done/stopped, with priorities, working/waiting badges and an
  optional LLM attention digest that reads the idle panes for you; PR + CI badges, one-click
  resume/review/delete/restore, per-session copy-attach one-liners — and an optional watcher
  that auto-starts a review session for every PR where your review is requested.
- **Optional per-worktree IDE**: `wt-ide` with the `code-server` backend (VS Code in the browser,
  one instance per worktree) or JetBrains `rider` (Gateway remote-dev). Off by default.
- **Config + hooks, no forks**: everything project-specific (repo registry, base branch, secrets
  sources, certificates, review scoping, deploy-URL badges, toolchain stacks like
  dotnet/powershell/azure-cli/pulumi) comes from one `config.yaml` and four best-effort hook
  points — so a private overlay repo can tailor the VM without touching this one.

## Quick start

**macOS (Lima)** — [full guide](docs/install-macos-lima.md):

```bash
brew install lima
git clone https://github.com/MauRiEEZZZ/worktree-vm ~/worktree-vm && cd ~/worktree-vm
cp config.example.yaml ~/.config/wt/config.yaml && $EDITOR ~/.config/wt/config.yaml  # fill in repos:
./platform/lima/up.sh
```

**Windows (WSL2)** — [full guide](docs/install-windows-wsl.md):

```powershell
wsl --install -d Ubuntu-24.04    # elevated PowerShell, reboot, create your Linux user
```
```bash
# inside Ubuntu:
sudo apt update && sudo apt install -y git
printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf   # then from Windows: wsl --shutdown, reopen
git clone https://github.com/MauRiEEZZZ/worktree-vm && cd worktree-vm
cp config.example.yaml ~/.config/wt/config.yaml && $EDITOR ~/.config/wt/config.yaml
./install.sh
```

Then, in the guest: `gh auth login`, `claude` (log in once), and:

```bash
wt-new <repo> my-feature "optional opening task"
wt-ls
```

Dashboard at <http://localhost:7300> (configurable).

## Verified platforms

Both install paths have been run for real — one per architecture:

| Platform | Arch | Verified | Not yet verified there |
|---|---|---|---|
| macOS / Lima (vz), fresh instance | arm64 | `install.sh` exit 0 (1m19s first boot); dashboard + API up; full session lifecycle: `wt-new` → `wt-ls` → `wt-rm` (tombstone) → `wt-restore` back onto the same path/branch; config from a path outside `$HOME` lands correctly in the guest | — |
| Windows 11 / WSL2 Ubuntu 24.04 | x86_64 | install completed by a first external user **with zero fixes needed**; checklist green: 35 `wt-*` functions loaded, `wt-help`/`wt-repos` correct, `wt-dashboard` service active, `/api/meta` + `/api/sessions` OK, dashboard reachable at `localhost:7300` in a Windows browser without any port forwarding; Docker 29.7.2, Node v24.19.0, gh 2.98.0, tmux 3.4, `claude` and `codex` both installed | the interactive logins (`gh auth login`, `claude`, `codex login`) and the `wt-new`/`wt-ls`/`wt-rm` round trip, which requires gh auth |

Successful runs and any field fixes are tracked in
[docs/field-notes-wsl.md](docs/field-notes-wsl.md).

## Docs

- [Install on macOS (Lima)](docs/install-macos-lima.md) — includes the persistent-data-disk scheme
- [Install on Windows (WSL2)](docs/install-windows-wsl.md) — full from-bare-Windows onboarding
- [Config reference](docs/config-reference.md) — every key of `~/.config/wt/config.yaml`
- [Hooks](docs/hooks.md) — how a private overlay plugs in
- [skills/](skills/) — Claude Code skills: `guided-install` (an agent performs the install for
  you — see below), `dev-sessions` (orchestrate sessions from your main Claude, with
  LOCAL/SSH/WSL transports) and `self-review` (a session requests its own independent review)

### Prefer to have an agent do the install?

`skills/guided-install/SKILL.md` is written for a Claude Code session to *execute*: it detects
the platform, walks the install step-by-verified-step, fixes what breaks (recording every
deviation in [docs/field-notes-wsl.md](docs/field-notes-wsl.md)), and leaves you only the steps
that genuinely need a human (elevation, reboots, logins). To make it available, either symlink it
into your skills directory —

```bash
mkdir -p ~/.claude/skills && ln -s "$PWD/skills/guided-install" ~/.claude/skills/guided-install
```

— or simply tell Claude: *"read skills/guided-install/SKILL.md in this repo and follow it"*.

## License

MIT — see [LICENSE](./LICENSE).
