#!/usr/bin/env bash
# parse-yaml.sh — flatten the worktree-vm YAML config subset into "path<TAB>value"
# lines (e.g. "github.review_owner<TAB>sonnet", "stacks.0<TAB>dotnet").
#
# Supported subset (documented in config.example.yaml): 2-space-indented maps,
# scalar values, inline lists ([a, b]) and dash lists. Comments (# ...) are
# stripped outside quotes; surrounding quotes are stripped from values.
# Dependency-free: POSIX awk only.

wt_yaml_flatten() {
  awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    # quoted: take the content up to the matching closing quote (anything after,
    # e.g. a trailing comment, is dropped). Unquoted: strip a trailing comment.
    function clean(v,   m) {
      v = trim(v)
      if (v ~ /^"/)      { m = index(substr(v, 2), "\""); return m ? substr(v, 2, m - 1) : substr(v, 2) }
      if (v ~ /^'\''/)   { m = index(substr(v, 2), "'\''"); return m ? substr(v, 2, m - 1) : substr(v, 2) }
      sub(/[[:space:]]#.*$/, "", v)
      return trim(v)
    }
    function joinpath(lvl,   i, p) {
      p = ""
      for (i = 0; i <= lvl; i++) { if (p != "") p = p "."; p = p key_at[i] }
      return p
    }
    {
      raw = $0; sub(/\r$/, "", raw)
      if (raw ~ /^[[:space:]]*$/ || raw ~ /^[[:space:]]*#/) next
      match(raw, /^ */); ind = RLENGTH
      lvl = int(ind / 2)
      s = substr(raw, ind + 1)

      if (s ~ /^- /) {                       # dash-list item under the open key
        v = clean(substr(s, 3))
        if (listpath != "" && v != "") { print listpath "." listidx "\t" v; listidx++ }
        next
      }

      pos = index(s, ":")
      if (pos == 0) next
      k = trim(substr(s, 1, pos - 1))
      v = substr(s, pos + 1)
      key_at[lvl] = k
      curpath = joinpath(lvl)
      vt = trim(v)
      if (vt !~ /^["'\'']/) { sub(/[[:space:]]#.*$/, "", vt); vt = trim(vt) }
      if (vt == "") {                        # opens a nested map or a dash list
        listpath = curpath; listidx = 0
        next
      }
      listpath = ""
      if (vt ~ /^\[.*\]$/) {                 # inline list
        inner = substr(vt, 2, length(vt) - 2)
        if (trim(inner) == "") next          # empty list -> no entries
        n = split(inner, arr, ",")
        for (i = 1; i <= n; i++) { item = clean(arr[i]); if (item != "") print curpath "." (i - 1) "\t" item }
        next
      }
      print curpath "\t" clean(vt)
    }
  ' "$1"
}
