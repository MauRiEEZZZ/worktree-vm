# Install on macOS (Lima)

The VM is a [Lima](https://lima-vm.io) guest running Ubuntu 24.04 on Apple's
Virtualization.framework (`vz`) — near-native speed on both Apple Silicon and
Intel Macs (the image is picked for your host architecture automatically).

## Prerequisites

```bash
brew install lima
```

## 1. Clone the repo — under your home directory

```bash
git clone https://github.com/MauRiEEZZZ/worktree-vm ~/worktree-vm
cd ~/worktree-vm
```

Keep the clone somewhere under `~`: the VM mounts your home read-only, and the
guest clones the repo from that checkout (so the guest runs exactly the ref you
have checked out). A clone outside `~` still works — the guest then falls back
to cloning from GitHub.

## 2. Configure

```bash
mkdir -p ~/.config/wt
cp config.example.yaml ~/.config/wt/config.yaml
$EDITOR ~/.config/wt/config.yaml
```

At minimum fill in `repos:` (which repos `wt-new` can target). The `lima:`
section sets the instance name, cpus/memory/disk and the persistent data disk.
See [config-reference.md](config-reference.md) for every key.

## 3. Start the VM

```bash
./platform/lima/up.sh
```

This renders the VM definition from your config (`limactl validate`s it),
creates the persistent data disk if configured and missing, and runs
`limactl start`. First boot downloads the Ubuntu image and provisions
everything (docker, node, gh, the agents, tmux, your opt-in stacks, the wt-*
helpers and the dashboard) — expect several minutes.

## 4. One-time auth (inside the VM)

```bash
limactl shell worktree-vm      # or: ssh lima-worktree-vm
gh auth login                  # GitHub (clone/PRs)
claude                         # log in to Claude Code, then Ctrl-C
codex login                    # only if you use --agent codex; on this headless VM
                               # tunnel the OAuth callback from the Mac:
                               #   ssh -t -L 1455:127.0.0.1:1455 lima-worktree-vm 'codex login'
```

Auth state lives on the persistent data disk (`~/.claude`, `~/.codex`,
`~/.config/gh`, `~/.azure` are symlinked onto it), so it survives rebuilds.

## 5. Use it

```bash
wt-repos                       # the repos from your config
wt-new <repo> my-feature "optional opening task"
wt-ls                          # wt-resume / wt-rm / wt-review / wt-help
```

Dashboard: <http://localhost:7300> (or your configured port) — it's
port-forwarded to the Mac automatically.

Set `dashboard.ssh_host: lima-worktree-vm` in your config so the dashboard's
copy-attach and port-forward buttons produce ready-to-paste one-liners.

## The persistent data disk (what survives what)

| lives on | examples | survives `limactl delete` |
|---|---|---|
| data disk | `~/wt` (worktrees), `~/repos` (clones), `~/.claude`, `~/.codex`, `~/.config/gh`, `~/.config/wt`, `~/.azure` | **yes** |
| VM disk | the OS, installed packages, `~/worktree-vm` (the repo clone) | no — reprovisioned on rebuild |

One deliberately subtle detail: `~/wt` is a **bind mount**, not a symlink.
Claude Code keys conversation history on the physical working-directory path, so
a symlink would break `claude --continue` after a rebuild. The provisioning
handles this (including a boot-race self-heal); don't "simplify" it to a
symlink.

## Updating / rebuilding

- **Update the tooling**: `git -C ~/worktree-vm pull`, then `./platform/lima/up.sh`
  (re-runs provisioning; idempotent).
- **Change config features** (repos, stacks, dashboard settings): edit
  `~/.config/wt/config.yaml`, re-run `up.sh` — or, inside the VM, re-run
  `~/worktree-vm/install.sh` and `sudo systemctl restart wt-dashboard`.
- **Change platform facts** (cpus/memory/ports/disks): those are baked into the
  instance at creation — `limactl delete worktree-vm`, then `up.sh`. Your work,
  sessions and auth survive on the data disk; `wt-resume` continues where you
  left off.
