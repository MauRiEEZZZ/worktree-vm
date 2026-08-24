# Config reference

One file — `~/.config/wt/config.yaml` (start from `config.example.yaml`) —
drives everything. It is read by `install.sh`, by `platform/lima/up.sh` on the
macOS host, and (via derived files) by the `wt-*` shell library and the
dashboard.

## Derived files

`lib/config/generate-env.sh` turns the config into:

| file | consumed by |
|---|---|
| `~/.config/wt/env.sh` | sourced by `lib/wt/config.sh` (every interactive shell) |
| `~/.config/wt/dashboard.env` | `EnvironmentFile=` of the `wt-dashboard` systemd unit |

`install.sh` runs the generator; the shell library also re-generates
automatically whenever `config.yaml` is newer than `env.sh`. After config edits
that affect the dashboard, restart it: `sudo systemctl restart wt-dashboard`.

**Applying host-side config edits to a Lima guest**: the guest keeps its own
copy of the config (seeded once at first boot, never overwritten), so editing
the host file alone changes nothing. Run `platform/lima/up.sh --sync-config`
to push the host config into the running guest, regenerate the derived env and
restart the dashboard — no VM restart. Provisioning-level changes (`stacks:`)
additionally need `bash ~/worktree-vm/install.sh` inside the guest (always via
`install.sh`, which loads the derived env — a standalone `provision/90-stacks.sh`
does not see your config). Platform facts (`lima:` cpus/memory/ports/disks)
always require `limactl delete` + `up.sh`. On WSL2 there is no host/guest
config split — edit `~/.config/wt/config.yaml` in the distro directly.

Precedence: repo defaults → your config → environment variables (the derived
env can be overridden per-invocation, e.g. `WT_SECRETS_SRC=... wt-seed-main`).

## Supported YAML subset

Two-or-three levels of 2-space-indented maps, scalar values, inline lists
(`[a, b]`) or 2-space-indented `- item` lists. Comments with `#`. Quote values
containing `#` or `:`. A leading `~/` in path values expands to `$HOME`.

## Keys

### Top level

| key | default | meaning |
|---|---|---|
| `repos` | `{}` | registry: short key → GitHub `owner/repo`. The key names the clone (`~/repos/<key>`), worktrees (`~/wt/<key>/<name>`) and session ids (`<key>--<name>`). |
| `clone_paths` | `{}` | key → absolute path of the main clone, when it must live somewhere other than `~/repos/<key>`. An entry wins unconditionally (bash and dashboard both honour it). On Lima, paths under `~` are also persisted onto the data disk. |
| `default_base_branch` | `main` | branch used when a clone's `origin/HEAD` cannot be resolved (wt-new base, wt-review merge-base). |
| `stacks` | `[]` | opt-in toolchains installed by `provision/90-stacks.sh`: `dotnet`, `powershell`, `azure-cli`, `pulumi`, `playwright`. |
| `stack_options.dotnet_version` | `""` | exact .NET SDK version for the dotnet stack (e.g. `10.0.301`), for when a project's `global.json` demands a specific band. Empty = latest LTS channel. The `WT_DOTNET_VERSION` env var overrides the config value. |
| `stack_options.playwright_browsers` | `[chromium, firefox]` | browsers the playwright stack installs (system packages via playwright's own `install-deps`, browsers into the default `~/.cache/ms-playwright`). Firefox is deliberately in the default set — it is the browser the product's users actually use; list only `chromium` to skip firefox's system packages. **Headless-only by policy**: no `--no-sandbox` default and no chromium AppArmor profile are shipped — headed chromium fails with "No usable sandbox!" under Ubuntu 24.04's `apparmor_restrict_unprivileged_userns=1`; if you need headed, write your own AppArmor profile (see `provision/60-bwrap-apparmor.sh` for the shape). |
| `stack_options.playwright_version` | `""` | playwright version for the stack; empty = latest. `WT_PLAYWRIGHT_VERSION` env var overrides. Playwright pins browsers per revision (e.g. `firefox-1538`): a version bump installs a new revision next to the old one and cleans nothing — reclaim space with `npx playwright uninstall --all`. |
| `ports` | `[]` | extra guest ports to expose to the host. Lima: rendered as portForwards. WSL2: informational (localhost forwarding is automatic). |

### `github`

| key | default | meaning |
|---|---|---|
| `review_owner` | `""` | GitHub org/user the dashboard's PR-review watcher scopes its `--review-requested=@me` search to. **Empty = watcher off.** |
| `review_model` | `sonnet` | model for auto-started review sessions; empty = the agent's default. |

### `agents`

| key | default | meaning |
|---|---|---|
| `default` | `claude` | agent `wt-new` launches without `--agent`: `claude` or `codex`. |
| `model_choices` | `[opus, sonnet, haiku]` | model aliases offered in the dashboard's model dropdown (Claude only; "default" is always offered too). |

### `dashboard`

| key | default | meaning |
|---|---|---|
| `port` | `7300` | dashboard HTTP port (bound to 127.0.0.1 in the guest; forwarded on Lima, localhost-forwarded on WSL2). |
| `deploy_url_regex` | `""` | regex that recognises deploy/preview URLs in PR bodies/comments; first match becomes the card's "deploy" link. **Empty = feature off** (and no extra `gh` calls). |
| `ssh_host` | `""` | this VM's ssh alias as reachable *from your workstation*; used in the copy-attach / port-forward one-liners. Empty = plain `tmux attach` commands without the ssh hop. |
| `attention.needs_re` | `""` | override for the "needs you" classifier (case-insensitive JS regex over the session's last pane line). Empty = built-in English default. Set this if your sessions converse in another language. |
| `attention.done_re` | `""` | same, for the "done" classifier. |

### `ide`

| key | default | meaning |
|---|---|---|
| `backend` | `none` | `wt-ide` backend: `none` (feature off), `rider` (JetBrains Gateway remote-dev; one backend at a time), `code-server` (VS Code in the browser; one instance per worktree). |
| `port_base` | `6000` | first port for per-worktree code-server instances (first free port from here is used). |
| `rider_version` | `2026.1.3` | Rider version downloaded on first `wt-ide` use (arch-appropriate tarball). |

### `secrets`

| key | default | meaning |
|---|---|---|
| `source` | `""` | durable folder holding per-repo gitignored config, repo-relative under `<source>/<key>/`. `wt-seed-main` copies from here into the main clones. Empty = `wt-seed-main` only fires the `seed-main` hook. |

### `sessions`

| key | default | meaning |
|---|---|---|
| `meta_dir` | `~/.wt-sessions` | where the dashboard keeps per-session metadata JSON; tombstones of deleted sessions live in `<dir>/archive`. Point at an existing directory when migrating from an older setup. On macOS/Lima this directory is persisted on the data disk automatically (derived from the config, wherever you point it, as long as it is under `~`); on WSL2 it is durable by itself. |

### `hooks`

| key | default | meaning |
|---|---|---|
| `dir` | `~/.config/wt/hooks` | directory with your hook scripts. See [hooks.md](hooks.md). |

### `lima` (macOS host only — read by `platform/lima/up.sh`)

| key | default | meaning |
|---|---|---|
| `instance` | `worktree-vm` | Lima instance name (ssh alias becomes `lima-<instance>`). |
| `cpus` / `memory` / `disk` | `2` / `4GiB` / `100GiB` | VM sizing (defaults fit a small laptop; 4/8GiB+ recommended for parallel sessions or heavy stacks). Baked in at instance creation — changing them needs `limactl delete` + `up.sh` (work survives on the data disk). The disk is sparse. |
| `data_disk` | `worktree-data` | persistent Lima data disk name; created by `up.sh` when missing. Persists `~/wt`, `~/repos`, `clone_paths` under `~`, agent/CLI auth (`~/.claude`, `~/.codex`, `~/.config/gh`, `~/.azure`), `~/.config/wt`, `~/.wt-meta` (markers + the PR-review `review-seen.json` ledger), the `sessions.meta_dir` directory, `~/.cache/ms-playwright` (browser binaries, ~1.2 GB for chromium+firefox), and `~/.claude.json` (by copy). **Empty = no persistence.** |
| `data_disk_size` | `60GiB` | size used when creating the data disk. |
