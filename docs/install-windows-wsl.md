# Install on Windows (WSL2)

> **Prefer to have an agent do it?** Load
> [`skills/guided-install`](../skills/guided-install/SKILL.md) in a Claude Code
> session (symlink it into `~/.claude/skills`, or just say *"read
> skills/guided-install/SKILL.md and follow it"*). It performs everything below
> except the few steps that genuinely need you (the elevated `wsl --install`,
> the `wsl --shutdown` restart, passwords and logins), verifies each phase, and
> records any fixes it had to make in
> [field-notes-wsl.md](field-notes-wsl.md).

On Windows the "VM" is a WSL2 Ubuntu distro. Everything the guest needs is the
same platform-agnostic `install.sh` used on macOS — WSL2 just needs systemd
switched on first. Requires Windows 10 build 19041+ or Windows 11 (Home
editions included).

Two things WSL2 gives you for free, so the setup is *simpler* than Lima:

- **No port forwarding**: `localhostForwarding` is on by default, so the
  dashboard and dev servers bound inside the distro are reachable at
  `localhost:<port>` in a Windows browser. (`networkingMode=mirrored` in
  `.wslconfig` is the cleaner modern option on Windows 11 22H2+ if you need
  more.)
- **No data-disk scheme**: the distro's ext4 vhdx is already durable — it
  survives reboots and WSL updates. There is nothing to bind-mount or symlink;
  `data-disk.sh` is Lima-only, and everything it exists to protect on Lima
  (worktrees, clones, agent auth, session metadata + tombstones, the `~/.wt-meta`
  markers and PR-review ledger, the `~/.claude.json` trust list) is just an
  ordinary durable file here — you are not missing a step. (The vhdx does NOT
  survive `wsl --unregister <distro>` — that is the WSL equivalent of throwing
  the machine away, backup first.)

## 1. Install WSL + Ubuntu (the one manual step)

From an **elevated** PowerShell (Start → type "powershell" → *Run as
administrator*):

```powershell
wsl --install -d Ubuntu-24.04
```

Reboot when asked. On first start of the distro, create your Linux username and
password. (`wsl --list --online` shows the available distros if you want a
different one.)

> **Why this step is yours:** Claude Code deliberately runs without elevation
> and cannot reboot the machine, so `wsl --install` is the one command you run
> yourself. Everything after this point can be delegated to a Claude session.
>
> Want a dedicated, disposable instance instead of your everyday Ubuntu? See
> `platform/wsl/import.ps1` — optional.

## 2. Enable systemd in the distro

Docker, the dashboard unit and the (optional) sshd need systemd as PID 1, which
is opt-in in WSL2. Inside the distro:

```bash
printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf
```

(or `sudo cp platform/wsl/wsl.conf /etc/wsl.conf` once the repo is cloned — same
content plus comments). Then from PowerShell:

```powershell
wsl --shutdown
```

and reopen the distro. `install.sh` checks this and refuses with these exact
instructions until systemd is PID 1 — so you can't get it wrong, at worst you
get told.

Resources (memory/CPU) are set on the **Windows** side in
`%UserProfile%\.wslconfig` — not in `wsl.conf`:

```ini
[wsl2]
memory=8GB
processors=4
```

## 3. Inside Ubuntu: git, Claude Code, this repo

```bash
sudo apt update && sudo apt install -y git      # sudo asks for your Linux password
curl -fsSL https://claude.ai/install.sh | bash  # Claude Code (native Linux)
git clone https://github.com/MauRiEEZZZ/worktree-vm && cd worktree-vm
cp config.example.yaml ~/.config/wt/config.yaml && $EDITOR ~/.config/wt/config.yaml
./install.sh
```

`install.sh` provisions docker, node, gh, the agents, tmux, your opt-in stacks,
the `wt-*` helpers and the dashboard — identical to the macOS guest. Note that
`sudo` inside the distro prompts for the password you created in step 1.

Then the same one-time auth as everywhere: `gh auth login`, `claude` (log in,
Ctrl-C), `codex login` if you use Codex.

## 4. Where the orchestrator session lives

The orchestrator is the Claude Code session you talk to, the one that
dispatches work via `wt-new` (see `skills/dev-sessions`). On Windows it can
live in two places:

1. **Inside the distro** (recommended start): open the distro, run `claude`
   anywhere outside `~/wt`. It calls the helpers directly
   (`bash -ic "wt-ls"` — the skill's LOCAL transport). Zero extra installs.
2. **Native Windows Claude Code**: in PowerShell,
   `irm https://claude.ai/install.ps1 | iex` (optionally install
   [Git for Windows](https://gitforwindows.org) so Claude Code gets a real Bash
   tool instead of PowerShell). It drives the distro with the skill's WSL
   transport: `wsl.exe -d Ubuntu-24.04 -- bash -ic "wt-ls"`.

Trade-off in two lines: *inside the distro* is the fewest moving parts and
behaves exactly like the macOS setup; *native Windows* keeps the orchestrator
alive across `wsl --shutdown` and feels more like a host-side control panel.

**sshd is optional.** Both transports above need no SSH server. If you prefer
the ssh model anyway (e.g. JetBrains Gateway, or to reuse ssh-based muscle
memory), run `platform/wsl/sshd-setup.sh [port]` — it configures a non-22 port
(default 2222) so it never clashes with a Windows OpenSSH server, reachable as
`ssh -p 2222 <you>@localhost`.

## 5. Use it

```bash
wt-repos
wt-new <repo> my-feature "optional opening task"
wt-ls
```

Dashboard: <http://localhost:7300> (or your configured port) in a Windows
browser — no forwarding needed. `wt-ide` with the `code-server` backend is
extra pleasant here: the printed `http://localhost:<port>` URL opens directly.
