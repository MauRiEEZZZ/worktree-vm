# worktree-vm

A ready-to-install Linux dev VM for running **many AI coding sessions in parallel** — each on its
own git worktree, in its own tmux session, with its own agent (Claude Code or OpenAI Codex) — plus a
small web dashboard to create, watch and resume them.

You drive it from your host terminal: `ssh` into the VM, `tmux` runs inside it. Nothing but an SSH
client is needed on the host, so the same setup works on **macOS** (via Lima) and **Windows** (via
WSL2).

> **Status: under construction.** The generic core is being extracted from a working private
> single-file setup. Not yet usable — see the roadmap below.

## Why

Letting an AI agent work aggressively is much more comfortable on a disposable machine that is not
your laptop. Give each task its own worktree and branch, and several agents can work at once without
stepping on each other. The whole machine is defined in version-controlled files, so you can throw it
away and rebuild it in minutes.

## Roadmap

- [ ] `install.sh` + `provision/` — platform-agnostic provisioning for any Ubuntu 24.04 guest
- [ ] `lib/wt/` — the `wt-*` worktree/tmux/agent session commands
- [ ] `dashboard/` — session dashboard (create, attach, resume, triage, restore)
- [ ] `platform/lima/` (macOS) and `platform/wsl/` (Windows) recipes
- [ ] `ide/` — optional per-worktree IDE backend (code-server or JetBrains Rider)
- [ ] Docs: install guides, config reference, hooks

## License

MIT — see [LICENSE](./LICENSE).
