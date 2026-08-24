---
name: self-review
description: >-
  Get an independent, second-opinion code review of the work-in-progress in THIS
  dev session (the current git worktree on the dev VM). Use when the user asks to
  review, sanity-check, or get a second opinion on the changes made in this
  session before opening a PR — e.g. "review my work", "second opinion on these
  changes", "review this branch". It spawns a SEPARATE, independent Claude+Codex
  review session; this session does not grade its own work.
---

# Self-review: independent review of this session's work

You are running inside a dev session on the dev VM — a git worktree at
`~/wt/<repo>/<name>`. This skill starts a **separate, independent** review of the
work you've been doing, so it gets fresh eyes plus a second opinion from Codex —
not you reviewing yourself.

## How to start it

Run the VM helper through an **interactive** bash (the `wt-*` helpers live in
`~/.bashrc`, which a non-interactive shell skips):

```bash
bash -ic "wt-review"                    # scope working (default): committed + uncommitted changes
bash -ic "wt-review --scope committed"  # only what's committed on the branch, vs the base
bash -ic "wt-review --scope all"        # + untracked files
```

Called with no `<repo> <name>`, `wt-review` derives them from the current worktree
— so from inside your session, plain `wt-review` reviews **this** session. Pick the
scope from what the user wants checked; default to `working`. The command prints
the review session it created, e.g. `-> wt/<repo>/<name>-review`.

## What it does

- Creates a throwaway session `wt/<repo>/<name>-review` running a fresh Claude with
  Remote Control, which reviews **your worktree read-only** (it never edits your
  files) against the merge-base with the repo's default branch.
- That reviewer also gets an **independent second opinion from Codex** (via the
  Codex MCP server), consolidates both, and **reports only** — it posts nothing to
  GitHub and changes no code (`--auto --deny-post`).

## Tell the user (important)

The findings appear in the **new review session**, not here — this session cannot
see the other session's output. So relay:

- The review session name it printed (`wt/<repo>/<name>-review`) and that they can
  watch it via its own **Remote Control** link, or attach in the VM with
  `tmux attach -t =<repo>--<name>-review` (the `=` forces an exact match; detach
  `Ctrl-b d`), or via the dashboard
  on the configured dashboard port (default http://localhost:7300).
- That when they're done they can clean it up with
  `bash -ic "wt-rm <repo> <name>-review"`.

## Notes

- For a cleaner `committed` review, commit meaningful work first; `working` (default)
  also catches uncommitted changes, so it's fine to run mid-flight.
- Don't run this from a session that is itself a `*-review` session.
- The review is deliberately independent — your job is only to start it and point
  the user to it, not to review your own changes yourself.
