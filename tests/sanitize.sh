#!/usr/bin/env bash
# tests/sanitize.sh — grep every tracked file for strings that must never appear
# in this public repo (private org/product names, private hosts and paths,
# project-specific ports) and for source-language leftovers.
#
# The patterns are BASE64-ENCODED on purpose: written out in plain text, this
# check would itself introduce every string it exists to forbid. Decode them
# locally if you need to read or extend the lists:
#   printf '%s' '<blob>' | base64 -d
set -u
cd "$(dirname "$0")/.."

FORBIDDEN="$(printf '%s' 'd29ydGVsbHx2aWRhcmF8L1VzZXJzL21hdXJpY2V8bGltYS12aWRhcmEtZGV2fHZpZGFyYS1kYXRhfGF6dXJld2Vic2l0ZXN8YXp1cmVzdGF0aWNhcHBzfGZhYmxlfDcyMTV8MTcwMDF8NTE3M3w1MTc0fHBvcnRhbC0=' | base64 -d)"
LEFTOVERS="$(printf '%s' 'c2Vzc2llfHZlcndpamRlcnxnZWVuIHxhYW5tYWtlbnxiZXN0YWF0fG1pc2x1a3R8aGVydmF0fG9wZHJhY2h0fCB0YWFrfG9uYmVrZW5kZXxvdmVyc2xhYW4=' | base64 -d)"

fail=0
if git grep -nIiE "$FORBIDDEN" -- .; then
  echo "FAIL: forbidden strings found (see above)"; fail=1
else
  echo "ok: no forbidden strings"
fi
if git grep -nIiE "$LEFTOVERS" -- .; then
  echo "FAIL: source-language leftovers found (see above)"; fail=1
else
  echo "ok: no source-language leftovers"
fi
exit $fail
