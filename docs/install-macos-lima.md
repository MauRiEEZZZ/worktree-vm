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

### If `limactl start` times out ("did not receive an event with the running status")

On slower machines or networks, first-boot provisioning can outlast Lima's
startup window, and `limactl start` gives up with that message and exit 1. The
VM is usually **not broken — it is still provisioning**: cloud-init keeps
running in the background and typically finishes on its own. Diagnose, don't
delete:

```bash
limactl shell <instance> -- cloud-init status   # "running" = still provisioning, wait;
                                                # "done" = it finished after the timeout;
                                                # "error" = look at the log below
limactl shell <instance> -- sudo cat /var/log/cloud-init-output.log | tail -50
```

Re-running `limactl start <instance>` is **safe** — all provisioning here is
idempotent, so it simply re-runs/completes the steps and this time reaches the
running state.

### Sizing (honest minimums)

The defaults (2 cpus / 4 GiB) are the realistic floor: enough for the base
install, the dashboard, and a couple of agent sessions on a small laptop. For
several parallel sessions, the `dotnet` stack, or docker-heavy dev loops, give
it 4 cpus / 8 GiB or more in the `lima:` config section. The 100 GiB disk is
sparse — it only occupies what's actually used.

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
| data disk | `~/wt` (worktrees), `~/repos` (clones), `~/.claude`, `~/.codex`, `~/.config/gh`, `~/.config/wt`, `~/.azure`, `~/.wt-meta` (session markers **and** the PR-review watcher's `review-seen.json` ledger), the session-metadata dir from `sessions.meta_dir` (dashboard metadata + restore tombstones), `~/.claude.json` (folder-trust list; persisted by copy, see below) | **yes** |
| VM disk | the OS, installed packages, `~/worktree-vm` (the repo clone) | no — reprovisioned on rebuild |

Why those last three matter: without the session metadata + tombstones nothing
is restorable with fidelity after a rebuild; without the `review-seen.json`
ledger the PR-review watcher would **re-spawn a review session for every PR it
had already handled** — the least obvious consequence; and without the
`~/.claude.json` trust list every worktree re-prompts for folder trust, which
hangs exactly the unattended (`--auto`) sessions.

`~/.claude.json` is the deliberate odd one out, layered in two mechanisms
because no single one is sound: it is a file Claude Code rewrites *atomically*
(rename replaces a symlink, so symlinking cannot work) and a provision-time
copy alone is one-way (the snapshot goes stale the moment Claude writes). So:
the file is copied opportunistically (restored on rebuild, snapshot refreshed
on every `limactl start`) for its non-critical state, and the part that must
never be lost — **folder trust** — is not synchronised at all but *re-asserted
from scratch* for every existing worktree on every provision run
(`provision/96-worktree-trust.sh`). Trust is therefore self-healing: even an
empty restored file is harmless, and worktrees created later get trust the
normal way (at unattended launch, or via the one-time dialog).

(WSL2 users: none of this applies to you — there is no data disk because the
distro's vhdx is already durable, so all of the above are ordinary durable
files there.)

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
