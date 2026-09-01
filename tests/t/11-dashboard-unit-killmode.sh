#!/usr/bin/env bash
# Bug (2026-09-01): the dashboard spawns the tmux SERVER that runs the sessions, and
# node's spawn(detached:true) does not move that child out of the unit's cgroup. With
# systemd's default KillMode=control-group, `systemctl restart wt-dashboard` killed
# every running session — five of them, 320 tasks and 2.0 GB, on one `up.sh
# --sync-config`. Nothing was lost (the data disk held the worktrees and the
# conversation history), but every session had to be resumed by hand.
# The unit must therefore stop only its own process. Asserted on the rendered unit,
# the way provision/99-dashboard.sh renders it, because that is the artifact systemd
# actually reads.
. "$(dirname "$0")/../lib.sh"
t_sandbox_home

TPL="$T_REPO/dashboard/wt-dashboard.service.template"
assert_file "$TPL" "the unit template exists"

# render exactly as provision/99-dashboard.sh does
UNIT="$T_TMP/wt-dashboard.service"
sed -e "s|@USER@|testuser|g" \
    -e "s|@HOME@|$T_HOME|g" \
    -e "s|@DASHBOARD_DIR@|$T_REPO/dashboard|g" \
    -e "s|@CONFIG_DIR@|$T_HOME/.config/wt|g" \
    -e "s|@NODE@|/usr/bin/node|g" \
    "$TPL" > "$UNIT"

# sanity: rendering worked at all, so a missing KillMode below is a real finding
# and not a broken substitution
assert_contains "$(grep '^ExecStart=' "$UNIT")" "/usr/bin/node" "rendering substituted @NODE@"
assert_not_contains "$(cat "$UNIT")" "@USER@" "no placeholder is left unsubstituted"

# the actual guard: systemd must not reap the cgroup on restart
KM="$(grep '^KillMode=' "$UNIT" | cut -d= -f2)"
assert_eq "$KM" "process" "the unit stops only its own process, leaving sessions alive"

# and the reason must stay next to it: this line looks removable to anyone who does
# not know what it protects
assert_contains "$(cat "$UNIT")" "tmux" "the unit explains WHY (the tmux server lives in this cgroup)"

t_end
