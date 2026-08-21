---
name: dev-sessions
description: >-
  Run and manage multiple parallel Claude (or Codex) dev sessions on the dev VM,
  each on its own git worktree of a configured repo, branched from that repo's
  default branch. Use when the user wants to spin up, dispatch work to, list, or
  tear down feature dev sessions on that VM — e.g. "start a session for X",
  "work on these in parallel", "what sessions are running", "clean up the auth
  session". Each session runs interactively with Remote Control on, so it can
  ask the user targeted questions about its feature.
---

# Dev sessions on the dev VM

Orchestrate parallel feature development on the dev VM, across the repos in its
`wt` config. Each "session" is a git worktree at `~/wt/<repo>/<name>` on its own
`feat/<name>` branch (from the repo's default branch), running an AI agent inside
a tmux session. By default the agent is **Claude with Remote Control enabled**,
labelled `wt/<repo>/<name>`; because it's interactive (not headless), it can ping
the user via Remote Control with targeted questions about the feature it's
building. Sessions can also run **Codex** instead (`--agent codex`).

The guest provides shell helpers (wired into its `~/.bashrc`): `wt-new`, `wt-ls`,
`wt-rm`, `wt-resume`, `wt-review`, `wt-repos` (plus `wt-ide`, `wt-env`). This
skill drives them through a transport (below).

## Transport: pick ONE mode, then use `RUN` everywhere

The helpers live in the guest's interactive `~/.bashrc`, which non-interactive
shells skip — so **every** invocation goes through `bash -ic "<helper>"`, no
matter the transport. Determine once where you (the orchestrator) run relative
to the guest, and from then on read every `RUN <helper command>` in this skill
as the corresponding concrete form:

| mode | you run... | `RUN <cmd>` means |
|---|---|---|
| **LOCAL** | inside the guest itself (e.g. a session in the Ubuntu distro/VM, outside `~/wt`) | `bash -ic "<cmd>"` |
| **SSH** | on macOS with a Lima VM, or against any remote VM | `ssh <vm-host> 'bash -ic "<cmd>"'` |
| **WSL** | natively on Windows, guest is a WSL2 distro | `wsl.exe -d <distro> -- bash -ic "<cmd>"` |

`<vm-host>` is the VM's SSH alias/hostname as reachable from this machine (for a
Lima VM the auto-generated `lima-<instance>` alias); `<distro>` is the WSL2
distro name (`wsl.exe -l`). A plain `ssh <vm-host> '<helper>'` (without
`bash -ic`) fails with "command not found".

**On Windows the orchestrator can live in two places:** natively on Windows
(mode WSL — note that native Claude Code only has a Bash tool when Git for
Windows is installed; otherwise you're composing these commands in PowerShell,
see the quoting notes below), or simply inside the Ubuntu distro outside the
worktrees (mode LOCAL — no `wsl.exe`, no ssh).

**PowerShell quoting (WSL mode):** the double-quoted `bash -ic "<cmd>"` form
above works unchanged from PowerShell as long as `<cmd>` contains no nested
double quotes — which is exactly why tasks are passed base64-encoded (see
"Dispatch a task"). Avoid embedding raw quotes/newlines in `<cmd>`.

First, confirm the guest is up:

```bash
RUN true
# if that errors — macOS/Lima: tell the user to run `limactl start <instance>`;
# Windows/WSL2: the distro starts automatically on first `wsl.exe` use.
```

## Choosing the repo (always explicit)

Every session belongs to ONE repo. The repo is **always an explicit choice** —
never inferred from an issue/PR URL, because issues are frequently filed in the
wrong repo (e.g. a front-end issue logged in the backend repo). If the user
didn't say which repo, ask. List the configured repos with:

```bash
RUN wt-repos   # key -> owner/repo
```

## Naming

Each session needs a short **kebab-case** `<name>` — it becomes the branch
`feat/<name>`, the worktree `~/wt/<repo>/<name>`, and (with the repo) the Claude
label `wt/<repo>/<name>`. Make it **recognizable**.

- **From a GitHub issue/PR** (used only as context/name — NOT to pick the repo):
  fetch the title and build `<number>-<short-title-slug>` (e.g. `2288-pdf-export-crash`):
  ```bash
  gh issue view <n> --repo <owner>/<repo> --json title -q .title   # or: gh pr view <n> ...
  ```
- **From a free-form task:** derive a concise slug from what it does (`oauth-login`).
- Always tell the user the repo + name you chose.
- **Fallback:** only if a title genuinely can't be fetched (API/network outage),
  use `issue-<n>` and say explicitly it's a fallback.

## wt-new options

```
wt-new <repo> <name> [--agent claude|codex] [--auto] [--deny-post]
       [--branch <existing>] [--from <ref>] [task... | --task-b64 <b64>]
```

- `--agent claude` (default) — Claude Code with Remote Control (`wt/<repo>/<name>`).
  `--agent codex` — the OpenAI Codex CLI instead (driven via `tmux attach`; Codex
  has no Remote Control).
- `--branch <existing>` — check out an existing branch (e.g. a PR branch) instead
  of creating `feat/<name>`.
- `--from <ref>` — branch the new `feat/<name>` off `<ref>` (e.g. a PR head) instead
  of the repo's default branch — lets two sessions work the same PR code without a
  branch conflict.
- `--auto` — run the agent **unattended** (no per-tool permission prompts) so it
  doesn't hang on a first question. `--deny-post` — make the session ask before
  `gh pr review/comment/merge`, so even an auto session can't post to GitHub
  without approval. These are for automated/review sessions; a normal user-driven
  session needs neither. The choice is remembered, so `wt-resume` relaunches with
  the same flags.
- The session's tmux prompt bar gets a colour matching its card in the dashboard
  (automatic — no action needed).

## Actions

### List running sessions (all repos)
```bash
RUN wt-ls
```

### New interactive session (user drives it)
```bash
RUN wt-new <repo> <name>
```

### Dispatch a task (session starts working, can ask via Remote Control)
Encode the task as base64 to avoid all shell-quoting problems, then dispatch.
From bash (LOCAL/SSH, or WSL mode with Git for Windows' bash):
```bash
b64=$(printf '%s' "FULL TASK DESCRIPTION HERE" | base64 | tr -d '\n')
RUN wt-new <repo> <name> --task-b64 $b64
```
From PowerShell (WSL mode, native Windows without a Bash tool):
```powershell
$task = @'
FULL TASK DESCRIPTION HERE
'@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($task))
wsl.exe -d <distro> -- bash -ic "wt-new <repo> <name> --task-b64 $b64"
```
(base64 contains no quoting-hostile characters, so interpolating `$b64` inside
the double-quoted command is safe in both shells.)

Write a clear, self-contained task (what to build, context, constraints) — it is
the session's opening prompt. The first time a repo is used it is cloned on
demand (can take a bit). To dispatch several features in parallel, repeat the
block per feature; they run independently.

### Resume a stopped session
After a VM stop/restart the tmux process is gone but the worktree + agent
conversation history remain. Re-open it (Claude `--continue` + Remote Control, or
Codex `resume --last`), with the same agent + flags it was created with:
```bash
RUN wt-resume <repo> <name>
```

### Review the work currently in a session
Spin up a **separate, independent** review session for the work-in-progress in an
existing dev session `wt/<repo>/<name>` — fresh eyes, not the dev session grading
itself. It reviews the LIVE dev worktree **read-only** (never touches the dev
session) against the merge-base with the repo's default branch, gets a second
opinion from **Codex via MCP**, consolidates, and **reports only** (posts nothing;
runs `--auto --deny-post`). Findings come back via Remote Control.
```bash
RUN wt-review <repo> <name>                    # scope working (default)
RUN wt-review <repo> <name> --scope committed  # only committed diff vs base
RUN wt-review <repo> <name> --scope all        # + untracked files
```
Scope: `committed` = only committed diff; `working` (default) = committed + uncommitted
tracked changes; `all` = + untracked files. It creates a throwaway session
`wt/<repo>/<name>-review` — clean it up afterwards with `wt-rm <repo> <name>-review`.

### Tear down a session
```bash
RUN wt-rm <repo> <name>      # safe: refuses if unmerged/dirty
RUN wt-rm <repo> <name> -f   # force (discards unsaved work) — confirm first
```

### Other helpers
- `wt-ide <repo> <name>` — start the configured IDE backend for the worktree
  (see `ide.backend` in the guest's wt config; off by default).
- `wt-env <repo> [name]` — show/seed gitignored local config (`.env*`, `appsettings.*.json`).

## After dispatching, tell the user

- Which repo + sessions/branches you started and the task each got.
- That each Claude session may **ask questions via Remote Control** about its feature —
  watch the Remote Control app/notifications. (Codex sessions have no Remote Control;
  the user attaches to drive them.)
- They can also attach in the guest: open a guest shell (`ssh <vm-host>`,
  `wsl.exe -d <distro>`, or you're already there in LOCAL mode) and run
  `tmux attach -t <repo>--<name>` (detach with `Ctrl-b d`), or use the dashboard's
  copy-attach button on the configured dashboard port (default
  http://localhost:7300).

## Automated: PR-review watcher

The dashboard server runs a background watcher (only when a review owner is
configured): every few minutes it checks `gh search prs --review-requested=@me`
scoped to that owner and, for each PR in a configured repo, auto-starts **one**
review session `review-<n>` (`--auto --deny-post` + Remote Control). That session
reviews the PR itself AND gets an independent second opinion from **Codex via
the Codex MCP server** (`mcp__codex__*` tools), consolidates both, and — per
policy — **drafts but asks before posting** anything to GitHub. It's idempotent
(one session per PR). Service env toggles (in the dashboard env file):
`PR_REVIEW_WATCH=0` off, `PR_REVIEW_DRYRUN=1` log-only, `PR_REVIEW_POLL_MS`,
`PR_REVIEW_OWNER`. This runs on its own; you don't start it — but if the user asks
about auto-review sessions, this is where `review-<n>` sessions come from.

## Teaching sessions project conventions

Sessions read `~/.claude/CLAUDE.md` in the guest at startup — that is where
project conventions live (e.g. "no CHANGELOG.md; release notes come from the PR
title"). When the user reports a convention, append it to the guest's
`~/.claude/CLAUDE.md` (effective for new sessions) AND mirror it into whatever
seeds that file on a rebuild (typically the overlay's post-provision hook), then
commit there. Already-running sessions won't see new rules — tell the user to
correct those via Remote Control or restart them.

## Guardrails

- **Don't run an app from more than one worktree of the same repo at once** —
  the worktrees share the app's fixed ports and dev containers. Building/coding
  in parallel is fine.
- Use `wt-rm ... -f` only after confirming with the user — it discards
  unmerged/uncommitted work in that worktree.
- You orchestrate (create/dispatch/list/clean); you cannot type into a running
  session's agent. The user drives those via Remote Control or by attaching.
