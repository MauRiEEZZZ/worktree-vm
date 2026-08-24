---
name: guided-install
description: >-
  Perform the worktree-vm installation FOR the user, as their agent: detect the
  platform (WSL2 / Lima guest / plain Ubuntu), walk the install as verified
  steps, fix what breaks (editing this repo is allowed), and record every
  deviation in docs/field-notes-wsl.md. Use when the user says things like
  "install worktree-vm", "set this up on my machine", "help me get this
  running", "get the dev VM working", or points you at this repo and asks for a
  working setup.
---

# Guided install: you perform it, the user assists

You are the installer. The user's job is limited to the few steps that
genuinely need them (elevation, reboots, passwords, account logins). Your job is
everything else — including diagnosing and FIXING problems when the recipe does
not survive contact with this machine, and writing those fixes down so the next
person doesn't hit them.

Work sequentially. Verify every step before moving on. Never pretend a step
succeeded.

## Phase 0 — situate yourself (always first)

Run and record:

```bash
echo "${WSL_DISTRO_NAME:-not-wsl}"        # WSL2 distro? (non-empty = yes)
. /etc/os-release && echo "$ID $VERSION_ID"
uname -m                                   # arch — never assume
ps -p 1 -o comm=                           # systemd as PID 1?
git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null   # is the repo checked out here?
```

Decide which situation you are in:

- **A. WSL2 distro** (`$WSL_DISTRO_NAME` set) — the main path below. WSL interop
  lets you call Windows binaries **read-only** for diagnosis — `wsl.exe --status`,
  `wsl.exe -l -v`, `powershell.exe -NoProfile -Command ...` — never elevated,
  never state-changing on the Windows side.
- **B. Lima guest / plain Ubuntu** — same flow, minus everything WSL-specific
  (skip the wsl.conf/systemd dance if PID 1 is already systemd; on a Lima guest
  the platform recipe normally already ran `install.sh` — verify instead of
  re-installing).
- **C. Native Windows** (no `$WSL_DISTRO_NAME`, but you are in a Windows
  environment — `wsl.exe` resolves, or your shell is PowerShell/cmd): you are
  the OUTSIDE operator of the distro. This is a distinct mode with different
  powers than A/B — follow the **Windows bootstrap mode** section below instead
  of Phases 1–3 as written.

If the repo is not checked out where you are running (modes A/B): `sudo apt
update && sudo apt install -y git` (see the sudo note below), then
`git clone https://github.com/MauRiEEZZZ/worktree-vm && cd worktree-vm`.

## Windows bootstrap mode (you run natively on Windows)

You drive the distro from the outside. Everything inside it goes through:

```powershell
wsl.exe -d <distro> -- bash -c "<command>"     # plain commands
wsl.exe -d <distro> -- bash -ic "<command>"    # wt-* commands — REQUIRED once they exist
```

`-ic` matters as soon as the wt-* functions exist: they live in the distro's
`~/.bashrc`, which non-interactive shells skip — without `-ic` you get "command
not found" and might wrongly conclude the install failed. **PowerShell
quoting:** keep the inner command inside ONE pair of double quotes with no
nested double quotes; pass anything complex (tasks, file content) base64-encoded
(`[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s))`) and decode in
bash — base64 has no quoting-hostile characters.

**Powers in this mode — the reason it exists as a separate mode:**

- You **MAY run `wsl --shutdown` yourself.** You are NOT inside the distro
  being restarted, so unlike the in-guest mode (where it is absolutely
  forbidden because the agent would terminate its own session mid-install) it
  costs you nothing. Do not "helpfully" carry the in-guest ban over to this
  mode, and do not remove the in-guest ban because this mode allows it — the
  difference is WHERE the agent runs, and both rules are load-bearing.
- You still **CANNOT run `wsl --install -d Ubuntu-24.04`**: it needs elevation
  and a reboot, and you have neither. Inventory first, read-only:

  ```powershell
  wsl --status
  wsl -l -v
  ```

  If the distro is missing, print exactly this for the user and WAIT:

  > This one step is yours: in an **elevated** PowerShell (Start → "powershell"
  > → Run as administrator):
  >
  > ```powershell
  > wsl --install -d Ubuntu-24.04
  > ```
  >
  > Reboot when asked, open Ubuntu once to create your Linux username and
  > password, then come back to me.

**The sequence that works** (verified in practice on real hardware):

1. **Inventory**: `wsl --status`, `wsl -l -v`.
2. **Distro missing?** → the user installs it (elevated command above); wait,
   then re-inventory.
3. **Enable systemd**:
   `wsl.exe -d <distro> -- bash -c "printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf"`.
4. **Restart the distro yourself**: `wsl --shutdown` (allowed in THIS mode).
5. **Verify**: `wsl.exe -d <distro> -- bash -c "ps -p 1 -o comm="` → `systemd`.
6. **git + Claude Code in the distro**:
   `wsl.exe -d <distro> -- bash -c "sudo apt update && sudo apt install -y git"`,
   then `wsl.exe -d <distro> -- bash -c "curl -fsSL https://claude.ai/install.sh | bash"`.
7. **Clone the repo in the LINUX home** (`~/worktree-vm`) — explicitly NOT
   under `/mnt/c`: the Windows filesystem bridge is slow and has odd
   permission semantics that break builds and git hygiene.
8. **Config + install**: continue with Phase 2 (interview the user for repos)
   and Phase 3 (`./install.sh`), running each command through the transport.
9. **Verify**: the Phase 4 checklist, each command via
   `wsl.exe -d <distro> -- bash -ic "..."`. The dashboard is directly reachable
   in a Windows browser at `http://localhost:<port>` — no forwarding.

**sudo**: commands inside the distro prompt for the user's LINUX password on
the distro's console — warn the user before the first sudo call and batch the
sudo work (steps 3, 6 and install.sh) rather than being surprised per command.

**Afterwards**, tell the user where their orchestrator session can live from
here: stay native on Windows and drive sessions over this same WSL transport,
or run Claude inside the distro (outside `~/wt`) — `skills/dev-sessions`
documents both (its LOCAL and WSL transports) and the trade-off.

## Phase 1 — the systemd gate (WSL2 only)

`install.sh` refuses until systemd is PID 1 — Docker, the dashboard unit and
optional sshd need it. If `ps -p 1 -o comm=` is not `systemd`:

```bash
sudo cp platform/wsl/wsl.conf /etc/wsl.conf    # or printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf
```

Then STOP and tell the user, verbatim:

> I've enabled systemd, but the distro must restart for it to take effect —
> and **I must not restart it myself**: `wsl --shutdown` would kill the very
> distro I'm running in, terminating this session mid-install. Please run, from
> a Windows PowerShell:
>
> ```powershell
> wsl --shutdown
> ```
>
> then reopen Ubuntu and message me again.

On the next turn, re-check `ps -p 1 -o comm=` before proceeding. **NEVER run
`wsl --shutdown`, `wsl --terminate`, or anything equivalent yourself** — this
ban is about WHERE you run: an agent inside the distro would terminate itself.
An agent running natively on Windows (the "Windows bootstrap mode" below) is
outside the distro and MAY run `wsl --shutdown`; keep both rules, they are two
sides of the same reason.

## Phase 2 — config (ask, don't invent)

```bash
mkdir -p ~/.config/wt
[ -f ~/.config/wt/config.yaml ] || cp config.example.yaml ~/.config/wt/config.yaml
```

Then **interview the user** — never invent values:

1. **repos** (required for anything useful): "Which GitHub repos should
   sessions work on? Give me `key: owner/repo` pairs." Write them under
   `repos:`. An empty registry is acceptable for a smoke install; say so.
2. **stacks**: only if their projects need dotnet/powershell/azure-cli/pulumi.
   Default `[]`.
3. Leave `ide.backend: none`, `github.review_owner: ""` etc. at their defaults
   unless the user asks; point them at docs/config-reference.md for later.

Edit `~/.config/wt/config.yaml` accordingly and show the user a diff-style
summary of what you set.

## Phase 3 — run the install

Warn first: "install.sh uses sudo for the system packages — you'll be prompted
for your Linux password once." Batch all sudo work into this one run rather
than sprinkling it around.

```bash
./install.sh
```

Watch the output per provision step (00-base … 99-dashboard). It is idempotent:
after fixing a failure, re-run the whole script rather than hand-completing
steps.

## Phase 4 — verify (concrete checklist, all of it)

```bash
bash -ic 'declare -F | grep -cE " (wt-|_wt_)"'   # expect ~35 functions
bash -ic 'wt-help | head -3'                      # readable English help
bash -ic 'wt-repos'                               # the repos from Phase 2
systemctl is-active wt-dashboard                  # active
PORT=$(bash -ic 'echo $WT_DASHBOARD_PORT')
curl -sf "http://127.0.0.1:$PORT/api/meta" && echo OK
curl -sf "http://127.0.0.1:$PORT/api/sessions" >/dev/null && echo OK
docker --version && node --version && gh --version | head -1 && tmux -V
command -v claude && command -v codex
```

If the user has run `gh auth login` (ask — don't run account logins uninvited),
do a full round trip against one configured repo:

```bash
bash -ic 'WT_NO_LAUNCH=1 wt-new <key> smoke'   # worktree + branch, no agent
bash -ic 'wt-ls'                                # shows <key> smoke
bash -ic 'wt-rm <key> smoke'                    # clean removal
```

Report the checklist results to the user, pass/fail per line. On WSL, also tell
them the dashboard is directly reachable in a Windows browser at
`http://localhost:$PORT` (no forwarding needed).

Remaining user-owned steps to hand over at the end: `gh auth login`, `claude`
(login, Ctrl-C), `codex login` (only if they'll use Codex).

## Known failure patterns (check these BEFORE concluding a step failed)

- **Lima: `limactl start` exits 1 with "did not receive an event with the
  running status".** This is a startup-window timeout, NOT a broken install:
  first-boot provisioning on a slow machine/network can outlast Lima's window
  while cloud-init keeps running and usually finishes on its own. Do not delete
  the instance and do not report failure yet. Diagnose:

  ```bash
  limactl shell <instance> -- cloud-init status      # running = wait; done = it finished; error = read the log
  limactl shell <instance> -- sudo cat /var/log/cloud-init-output.log | tail -50
  ```

  On `running`: wait and poll. On `done`: verify Phase 4 directly — the
  install likely succeeded despite the exit code. Either way, re-running
  `limactl start <instance>` is safe (provisioning is idempotent) and normally
  reaches the running state on the second attempt.

## Failure protocol (this is the whole point of this skill)

When any step fails:

1. **Capture** the exact command and its FULL output (stderr included). Not a
   paraphrase.
2. **Diagnose** on this machine — read the failing script, check versions,
   paths, arch (`dpkg --print-architecture`), network. Use the read-only
   Windows-side probes on WSL if relevant.
3. **Fix it.** You are explicitly allowed to change files in this repo to make
   the install work here. Prefer the smallest generic fix; keep scripts
   idempotent; re-run `./install.sh` to prove the fix.
4. **Record it** in `docs/field-notes-wsl.md` — one entry per deviation, using
   the template at the top of that file (date, platform/arch/WSL version, what
   failed, exact output, what you changed, generic vs machine-specific).
5. **Feed it back**: if `git push` to a fork works from this checkout, commit
   the fix + field note there and offer to open a PR upstream (`gh pr create`
   — ask before posting). Otherwise, hand the user the field-notes entries and
   the diff (`git diff`) to pass along.

## Ask, don't guess

Always ask the user before: anything destructive (removing worktrees/branches,
overwriting an existing `~/.config/wt/config.yaml`, `wsl --unregister`),
account-related steps (`gh auth login`, `claude`/`codex` logins), sudoers or
PATH changes beyond what install.sh already does, and picking an alternative
port when the configured one is already in use (`ss -ltn` first, then propose).
Never elevate, never reboot, never restart the distro you run in.
