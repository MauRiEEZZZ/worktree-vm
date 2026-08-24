# Field notes — WSL2 installs

Real-world deviations hit while installing worktree-vm, recorded by the agent
performing the install (see `skills/guided-install`). One entry per deviation,
newest first. Generic fixes should graduate into the scripts/docs via a PR;
machine-specific ones stay here as searchable symptoms.

## Entry template (copy below this block)

```markdown
## YYYY-MM-DD — <one-line summary>
- **Platform**: WSL2 <distro + version> on Windows <build>, arch <amd64/arm64>,
  WSL version (`wsl.exe --version`): <...>
- **Step that failed**: <script/phase, e.g. provision/10-docker.sh>
- **Exact command + output**:
  ```
  <verbatim, stderr included>
  ```
- **Diagnosis**: <what was actually wrong>
- **Change made**: <files touched + what changed; commit/PR link if any>
- **Scope**: generic (should be upstreamed) | machine-specific
```

---

_No entries yet._

# Known-good runs

"Nothing to report" is also a result: when a run succeeds, record it here so
someone debugging later knows which combinations are proven. One line of
context each: date, platform, arch, tool versions, which checklist items were
green, and whether anything had to be fixed.

## 2026-08-24 — Windows 11, WSL2 Ubuntu 24.04, x86_64 — clean install, zero fixes

- **Tool versions**: Docker 29.7.2, Node v24.19.0, gh 2.98.0, tmux 3.4;
  `claude` and `codex` both installed and found.
- **Checklist green**: 35 `wt-*` functions loaded; `wt-help` readable English;
  `wt-repos` correct; `wt-dashboard` service active; `/api/meta` and
  `/api/sessions` OK; dashboard reachable at `localhost:7300` in a Windows
  browser with no port forwarding.
- **Fixed along the way**: nothing — the recipe worked as written.
- **Not yet run**: the interactive logins (`gh auth login`, `claude`,
  `codex login`) and the `wt-new`/`wt-ls`/`wt-rm` round trip (needs gh auth).
- **Note**: first external user; install driven by a Claude Code session
  running natively on Windows operating the distro from outside (the pattern
  now codified as the guided-install skill's "Windows bootstrap mode").
