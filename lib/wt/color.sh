# color.sh — per-session prompt-bar colour (Claude's /color). Deterministic from
# the sid, matching the dashboard card. Keep these 8 names + order + hash IN SYNC
# with SESSION_COLORS in the dashboard (public/index.html) so a card and its
# session's prompt bar are the same colour.
WT_COLORS=(red blue green yellow purple orange pink cyan)
_wt_color() { local s="$1" h=0 i c; for ((i=0;i<${#s};i++)); do printf -v c '%d' "'${s:i:1}"; h=$(( (h*31 + c) & 0xFFFFFFFF )); done; echo "${WT_COLORS[$(( h % ${#WT_COLORS[@]} ))]}"; }
# /color is per-session + in-memory (not persisted, no launch flag), so we type it
# into the session shortly after it starts, on every launch AND resume. Detached so
# it survives the caller exiting; best-effort; claude only (codex has no /color).
_wt_apply_color() {  # $1=sid $2=agent
  [ "${2:-claude}" = claude ] || return 0
  local sid="$1" col; col="$(_wt_color "$sid")"
  nohup bash -c "sleep 5; tmux send-keys -t $(printf %q "$sid") $(printf %q "/color $col") Enter" >/dev/null 2>&1 &
}
