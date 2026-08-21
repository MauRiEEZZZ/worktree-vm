# Hooks

The core stays generic; anything project- or company-specific plugs in through
**config values** (see [config-reference.md](config-reference.md)) and **hooks**
— plain bash scripts the core calls at fixed points. A private "overlay" repo
is typically just: a `config.yaml`, a directory of hook scripts, and whatever
secrets/certs those hooks copy in.

## Mechanics

- Location: the directory from config `hooks.dir` (default `~/.config/wt/hooks`).
- One script per hook, named `<hook>.sh`. If the file exists it runs; if not,
  the step is skipped silently. No registration.
- **Best-effort**: a failing hook prints `warning: hook '<name>' failed —
  continuing` and the calling command carries on. Never rely on a hook aborting
  anything.
- Hooks run with `bash <script> <args>`, as the calling user. The `wt-*`
  commands have the derived config env loaded when they fire hooks, so `WT_*`
  variables are available.
- Keep hooks **fast and idempotent** — several fire on every session
  create/resume, and `post-provision` re-runs on every `install.sh`.
- Copyable no-op templates live in [`hooks/examples/`](../hooks/examples/).

## The four hooks

### `after-worktree-create` — `<repo-key> <name> <worktree-dir> <branch>`

Fires at the end of worktree setup in `wt-new` (and in the recreate path of
`wt-restore`): after the branch checkout, the generic gitignored-config seeding
and the dependency restore — before the agent launches. Use it for
project-specific seeding the generic copy can't know about.

### `agent-launch` — `<sid> <worktree-dir> <agent> <new|resume>`

Fires in `wt-new` and `wt-resume` just before the agent starts in tmux. Use it
for per-session environment prep or notifications.

### `seed-main` — `<repo-key> <main-clone-dir>`

Fires per repo key in `wt-seed-main`, *before* the generic copy from
`secrets.source` (which only runs when that config value is non-empty). Use it
to place secrets/local config into the main clone from wherever you keep them —
`wt-new` then inherits them into every new worktree.

### `post-provision` — (no arguments)

Fires at the end of `install.sh`, after all provision steps. This is the big
one for overlays. Typical contents:

```bash
#!/usr/bin/env bash
set -eu
# 1. import a stable ASP.NET dev certificate from the secrets store
# 2. seed ~/.claude/CLAUDE.md with project conventions (create-if-missing)
# 3. merge host Claude settings into the guest's ~/.claude/settings.json
# 4. copy extra skills into ~/.claude/skills
```

## A worked overlay layout

```
my-overlay/
├── config.yaml            # repos, clone_paths, review_owner, stacks, ports, ...
└── hooks/
    ├── post-provision.sh
    └── seed-main.sh
```

Install = clone both repos, point the config at the hooks:

```bash
cp my-overlay/config.yaml ~/.config/wt/config.yaml   # contains: hooks: dir: ~/my-overlay/hooks
worktree-vm/install.sh
```
