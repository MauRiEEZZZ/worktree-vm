# Hooks

Hooks are how a private overlay (or just you) plugs project-specific behaviour
into the generic core — secrets, certificates, extra seeding, anything the
public repo must not know about.

## Where they live

The hook directory comes from the config (`hooks: dir:`, default
`~/.config/wt/hooks`). Each hook is a single bash script named `<hook>.sh` in
that directory. No registration: if the file exists, it runs; if not, the step
is silently skipped. The `examples/` folder here contains documented no-op
templates — copy one into your hook directory and fill it in.

## Contract

- Hooks are **best-effort**: a failing hook prints a warning and the calling
  command continues. Never rely on a hook aborting anything.
- Hooks run with bash, as the same user as the caller, with the derived config
  env available when the caller had it loaded (the `wt-*` commands do). Keep
  them fast and idempotent — several fire on every session create/resume.
- Arguments are positional, per hook below.

## The hooks

| hook | fires | arguments | typical use |
|---|---|---|---|
| `after-worktree-create` | at the end of worktree setup in `wt-new` (after dependency restore, before the agent launches) | `<repo-key> <name> <worktree-dir> <branch>` | project-specific seeding beyond the generic gitignored-config copy |
| `agent-launch` | in `wt-new` and `wt-resume`, just before the agent starts in tmux | `<sid> <worktree-dir> <agent> <new\|resume>` | per-session environment prep, notifications |
| `seed-main` | per repo key in `wt-seed-main` (before the generic copy from `secrets.source`, which only runs when that config value is set) | `<repo-key> <main-clone-dir>` | copy secrets/local config into the main clone from wherever you keep them |
| `post-provision` | at the end of `install.sh` | (none) | import a dev certificate, seed `~/.claude/CLAUDE.md` with project conventions, merge host settings, install extra skills |
