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
