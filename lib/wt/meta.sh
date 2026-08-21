# meta.sh — per-session markers under $WT_META, keyed by session id.

# Per-session AI agent (claude | codex). wt-new records the choice; wt-resume/wt-ls
# and the dashboard read it back. Default (and pre-existing sessions) = the
# configured default agent.
_wt_agent_set() { mkdir -p "$WT_META"; printf '%s\n' "$2" > "$WT_META/$1.agent"; }
_wt_agent_get() { local a; a="$(cat "$WT_META/$1.agent" 2>/dev/null)"; echo "${a:-$WT_AGENT_DEFAULT}"; }
# Per-session launch flags (e.g. "auto denypost") so wt-resume relaunches the same way.
_wt_flags_set() { mkdir -p "$WT_META"; printf '%s\n' "$2" > "$WT_META/$1.flags"; }
_wt_flags_get() { cat "$WT_META/$1.flags" 2>/dev/null; }
# Optional per-session model override (empty = inherit the user's default).
_wt_model_set() { mkdir -p "$WT_META"; if [ -n "$2" ]; then printf '%s\n' "$2" > "$WT_META/$1.model"; else rm -f "$WT_META/$1.model"; fi; }
_wt_model_get() { cat "$WT_META/$1.model" 2>/dev/null; }
# Per-session priority (p1|p2|p3, default p2) for the dashboard triage/sort. Editable anytime.
_wt_priority_set() { mkdir -p "$WT_META"; printf '%s\n' "$2" > "$WT_META/$1.priority"; }
_wt_priority_get() { local p; p="$(cat "$WT_META/$1.priority" 2>/dev/null)"; echo "${p:-p2}"; }
