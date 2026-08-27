# help.sh — wt-help [command] : explain the wt-* commands. <cmd> --help does the
# same per command. _wt_help holds all help texts (central).
_wt_help() {
  case "$1" in
    wt-new) cat <<'H'
wt-new <repo> <name> [--agent claude|codex] [--auto] [--deny-post] [--model <alias>] [--branch <existing>] [task... | --task-b64 <b64>]
  New worktree session: ~/wt/<repo>/<name> on branch feat/<name> from the repo's
  default branch (clone-on-demand). Restores dependencies (.slnx/.sln->dotnet,
  package.json->npm/pnpm), inherits gitignored local config (.env*,
  appsettings.*.json) from the main clone, and starts the chosen AI agent in tmux.
  --agent claude (default) starts Claude Code with Remote Control (wt/<repo>/<name>);
  --agent codex starts the OpenAI Codex CLI (drive it via tmux attach, no remote control).
  --auto runs the agent without permission prompts (unattended) so it doesn't hang
  on a first question. For claude this is NOT done via CLI flags (those show an
  interactive accept/trust dialog that hangs a detached tmux), but by pre-trusting
  the worktree (~/.claude.json) + writing a .claude/settings.local.json with a
  broad allow list; claude then starts normally with Remote Control. Codex uses
  --dangerously-bypass-approvals-and-sandbox. --deny-post adds (claude) an ASK rule
  for gh pr review/comment/merge to that same settings.local.json: the session
  first asks your confirmation (also via Remote Control) and only then posts — so
  nothing goes to GitHub without your approval, but you CAN approve it. The choice
  is remembered, so wt-resume relaunches with the same flags.
  --model <alias> overrides the model (aliases come from agents.model_choices in
  your config); the literal '--model default' forces the ACCOUNT default.
  Without --model, the configured agents.default_model applies (claude only);
  if that is empty too, the session runs on your account default — which may be
  your most expensive model. Change it later with wt-model.
  The optional task = opening prompt. --task-b64 <b64> = quoting-safe task.
  --branch <existing> checks out an existing branch (e.g. the branch of a PR you
  want to continue) instead of creating a new feat/<name>.
H
;;
    wt-resume) cat <<'H'
wt-resume <repo> <name>
  Reopen an existing (stopped) session in tmux and resume the conversation with
  the same agent it was created with (claude --continue + Remote Control, or
  codex resume --last). If the session still runs, you're simply attached.
H
;;
    wt-push) cat <<'H'
wt-push [<repo> <name>]
  Push that session's OWN branch to origin. Inside a worktree the repo and name
  are derived from the path, so a plain `wt-push` works. Refuses: a detached HEAD,
  the repo's default branch and release/hotfix/main/master/develop, and a worktree
  with uncommitted TRACKED changes (what is on the PR must be what the session
  actually has). Never force-pushes; there is no flag for it.
  This is an OUTWARD action and belongs to whoever is talking to the user — a
  session pushing on a relayed "yes" is not the user's approval. wt-new therefore
  seeds an ASK rule for this command into every session it launches.
H
;;
    wt-pr-draft) cat <<'H'
wt-pr-draft [<repo> <name>] [--title <t>] [--body-file <f>]
  Open the session's pull request as a DRAFT and request the Copilot review.
  Draft only, by design: taking a PR out of draft spends a person's day and stays
  a separate, deliberate act (gh pr ready). Refuses when the branch is missing on
  origin or origin is not at your HEAD (run wt-push first — a PR built on a stale
  remote branch shows a diff nobody reviewed), and when a PR is already open for
  the branch. Without --title/--body-file it falls back to gh's --fill.
  The Copilot request is best-effort: the PR exists either way, so a failed
  request reports itself instead of failing the command. The reviewer handle is
  github.copilot_reviewer in your config — GitHub's to change, not ours to bake in.
H
;;
    wt-restore) cat <<'H'
wt-restore <repo> <name> [--branch <b>] [--agent claude|codex] [--model <m>] [--auto] [--deny-post]
  Restore a DELETED session. wt-rm removes the worktree/branch/tmux/metadata, but
  the Claude conversation stays in ~/.claude/projects/<worktree-path>. wt-restore
  recreates the worktree at the SAME path (checkout branch, deps, markers) and then
  resumes with claude --continue, bringing the preserved conversation back. Pass
  --branch when it wasn't feat/<name> (e.g. a PR branch). Usually driven from the
  "Restore" panel on the dashboard.
H
;;
    wt-model) cat <<'H'
wt-model <repo> <name> <model|default>
  Change a session's model and relaunch it so the change takes effect. The
  relaunch KEEPS the conversation (claude --continue on the same worktree);
  what is NOT possible is switching the model of a live process without a
  relaunch — anything mid-generation at that moment is interrupted. On a
  stopped session it only records the model for the next wt-resume. 'default'
  clears the override. Typical use: the configured default is a cheap model
  and one session turns out to need more.
H
;;
    wt-review) cat <<'H'
wt-review [<repo> <name>] [--scope committed|working|all] [--agent claude|codex] [--model <alias>]
  Start a separate, independent review session on the work-in-progress of dev
  session wt/<repo>/<name>. Omit <repo> <name> and they are derived from the
  current worktree — so a dev session can review itself with just `wt-review`.
  The reviewer inspects the LIVE dev worktree read-only (never touches the dev
  session) against the merge-base with the default branch, gets a second opinion
  from Codex (via the MCP server), consolidates, and REPORTS only — posts nothing
  to GitHub (--auto --deny-post). Read the findings via Remote Control.
  scope: committed = committed diff only; working (default) = + uncommitted
  tracked changes; all = + untracked files. Clean up with wt-rm <repo> <name>-review.
  The review runs on agents.review_model (empty = your account default — never
  the dev default_model); --model overrides per review. Tip: reviews are short
  bursts, and a finding your own review misses costs a day of external
  re-review round-trip — a strong review model usually pays for itself.
H
;;
    wt-ide) cat <<'H'
wt-ide <repo> <name>
  Start the configured IDE backend (ide.backend in ~/.config/wt/config.yaml:
  rider or code-server) on ~/wt/<repo>/<name>, in tmux session ide-<repo>--<name>,
  and print how to connect from your workstation. With the default backend `none`
  this explains how to enable one instead.
H
;;
    wt-ide-stop) cat <<'H'
wt-ide-stop [<repo> <name>]
  Stop the IDE backend. With <repo> <name>: that specific session. With no
  argument: the only running IDE backend. Pipeable:
  wt-ls | grep <filter> | wt-ide-stop.
H
;;
    wt-rm) cat <<'H'
wt-rm <repo> <name> [-f]
  Remove the worktree + branch and kill the tmux session. Safe by default
  (refuses on an unmerged or dirty worktree); -f forces (discards unsaved work).
H
;;
    wt-env) cat <<'H'
wt-env <repo> [name]
  (Re)copy gitignored local config (.env*, appsettings.*.json, *.local.json) from
  the main clone into worktree <name> (or all worktrees of <repo>). Use after
  adding/updating .env in the main clone.
H
;;
    wt-ls) cat <<'H'
wt-ls
  Show all sessions (all repos): repo · name · agent · state · ide(port) · branch.
  In a terminal an aligned table + summary; PIPED flat tab lines (greppable).
  Combines with the other commands, e.g.:
    wt-ls | grep myrepo   | wt-rm -f      (remove all myrepo sessions, forced)
    wt-ls | grep stopped  | wt-resume     (resume all stopped sessions)
    wt-ls | grep codex    | wt-rm -f      (remove all codex sessions)
    wt-ls | grep 2316     | wt-ide        (start the IDE for the filtered session)
H
;;
    wt-seed-main) cat <<'H'
wt-seed-main [<key>]
  Seed the MAIN clone(s) (~/repos/<key>) with local, gitignored config
  (appsettings.Development.json, .env, *.local.json) from a durable folder:
  $WT_SECRETS_SRC/<key>/ (config: secrets.source), with repo-relative paths, e.g.:
    <secrets.source>/myrepo/src/App/appsettings.Development.json
  Run this once after a fresh VM (secrets are never in git and don't survive a
  rebuild). wt-new then inherits them into every new worktree; wt-env <key>
  pushes them to existing worktrees. Without <key>: all repos that have a secrets
  folder. Also fires the seed-main hook per key (see hooks/README.md).
H
;;
    wt-repos) echo "wt-repos : show the configured repos (key -> owner/repo)." ;;
    *) cat <<'H'
wt — parallel AI dev sessions (Claude Code / OpenAI Codex) on git worktrees
  wt-repos                       show configured repos
  wt-new <repo> <name> [task]    new worktree session (default claude; --agent codex)
  wt-resume <repo> <name>        resume a stopped session (same agent)
  wt-restore <repo> <name>       restore a deleted session (worktree + preserved conversation)
  wt-ide <repo> <name>           start the configured IDE backend on a worktree
  wt-ide-stop [<repo> <name>]    stop the (only) running IDE backend
  wt-ls                          show all sessions
  wt-model <repo> <name> <m>     change a session's model (+relaunch, keeps the conversation)
  wt-env <repo> [name]           local config (.env*, appsettings.*.json) from main clone to worktree(s)
  wt-seed-main [<key>]           seed the main clone with local config from the secrets source
  wt-rm <repo> <name> [-f]       remove worktree + branch
Tip: <command> --help for details. Tab completion on repo keys + worktree names.
H
;;
  esac
}
wt-help() { _wt_help "${1:-}"; }
