# Shared harness for gate negative tests.
#
# Every test builds a fixture that SHOULD be rejected and asserts gates.sh rejects
# it. That is the non-vacuity proof GATE-4 requires: a gate whose negative test
# passes while the gate is disabled is an inert gate, which is itself a defect.
#
# Each test also runs a POSITIVE fixture, so a gate that rejects everything
# unconditionally fails too — rejecting all input is as useless as rejecting none.
#
# These tests call gates.sh directly, so they prove gate LOGIC. Gate WIRING —
# that something actually calls each gate, in a repo configured the way real
# repos are — is a separate claim, proved by test-install.sh.
set -uo pipefail
WOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$(cd "$WOW_DIR/../.." && pwd)"
GATES="$WOW_DIR/gates.sh"
PASS=0; FAIL=0; SKIP=0

# ---- portable fixture edits (v0.7.6, advisor/F-200) ---------------------------
# The fixtures used `sed -i '…'` (no suffix) and `touch -d '60 days ago'`, both
# GNU-only: BSD sed reads the expression as the backup suffix and the file as
# the script, BSD touch has no -d. On macOS the scenario was never built and 12
# assertions checked the wrong thing. python3 is already a prerequisite, so
# these helpers replace every shell-tool fixture edit (python3 heredoc blocks
# that rewrite a fixture stay as they are — they were never the problem); a
# tripwire in test-install.sh refuses the GNU forms it lists.
#
# A helper whose edit does not land COUNTS AS A FAILED ASSERTION (ADV-R14-01):
# a silent no-op is how the defect hid, and a stderr line nobody reads is still
# a no-op — the suite's exit code must move.
#
# replace_in_file FILE OLD NEW   — literal, every occurrence; OLD must occur
# resub_in_file   FILE REGEX REPL — python re.sub, MULTILINE; REPL is a python
#                                  replacement (\g<0> for the match, real \n ok)
# backdate_file   FILE DAYS      — set mtime (and atime) DAYS days into the past
replace_in_file() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
if old not in s:
    sys.stderr.write("replace_in_file: %r not found in %s\n" % (old, p)); sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  [ $? -eq 0 ] || { echo "  FAIL fixture edit did not land (replace_in_file on $1) — the scenario below is not built"; FAIL=$((FAIL+1)); return 1; }
}
resub_in_file() {
  python3 - "$1" "$2" "$3" <<'PY'
import re, sys
p, pat, rep = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
out, n = re.subn(pat, rep, s, flags=re.M)
if n == 0:
    sys.stderr.write("resub_in_file: %r matched nothing in %s\n" % (pat, p)); sys.exit(1)
open(p, "w", encoding="utf-8").write(out)
PY
  [ $? -eq 0 ] || { echo "  FAIL fixture edit did not land (resub_in_file on $1) — the scenario below is not built"; FAIL=$((FAIL+1)); return 1; }
}
backdate_file() {
  python3 - "$1" "$2" <<'PY'
import os, sys, time
t = time.time() - int(sys.argv[2]) * 86400
os.utime(sys.argv[1], (t, t))
PY
  [ $? -eq 0 ] || { echo "  FAIL fixture back-dating did not land (backdate_file on $1)"; FAIL=$((FAIL+1)); return 1; }
}

setup_fixture_repo() {
  FIX="$(mktemp -d)"
  ( cd "$FIX" \
    && git init -q . \
    && git config user.email t@t && git config user.name t \
    && mkdir -p scripts/wow docs runs \
    && cp "$WOW_DIR/gates.py" "$WOW_DIR/gates.sh" "$WOW_DIR/formats.json" scripts/wow/ \
    && cp -R "$WOW_DIR/tests" scripts/wow/tests \
    && printf '{"migrated_from_gsd": false}\n' > scripts/wow/wow.config.json \
    && git add -A >/dev/null && git commit -qm "fixture [WOW:publish]" )
  echo "$FIX"
}

# at_table_all — a complete `## audit triggers` section with a NOT-HIT row for
# every trigger the fixture's formats.json registers (ADV-R13-06, v0.7.5: the
# P5 escrow refuses a RUN-REPORT that records fewer). Reads the registry so a
# new trigger never leaves the fixtures short.
at_table_all() {
  printf '\n## audit triggers\n\n'
  python3 - "$WOW_DIR/formats.json" <<'PY'
import json, sys
F = json.load(open(sys.argv[1]))
for k, v in F["audit_triggers"].items():
    if isinstance(v, dict) and "threshold" in v:
        print("| %s %s | 0 — NOT HIT | ev:cmd{true => 0 @2026-10-07} |" % (k, v["metric"]))
PY
}

# assert_rejects <label> <workdir> <expected-substring> <args...>
#
# The expected substring is not decoration. A gate that rejects the fixture for
# an unrelated reason has not been proved to catch the defect the test is about
# — it has passed for the wrong reason. Requiring the cause to match is this
# harness's own premise check.
assert_rejects() {
  local label="$1"; shift; local dir="$1"; shift; local expect="$1"; shift
  local out rc
  out="$( cd "$dir" && "$dir/scripts/wow/gates.sh" "$@" 2>&1 )"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL not rejected: $label"; echo "$out" | sed 's/^/       /'; FAIL=$((FAIL+1))
  elif ! grep -qF -- "$expect" <<<"$out"; then
    echo "  FAIL rejected for the WRONG REASON: $label"
    echo "       expected cause: $expect"; echo "$out" | sed 's/^/       /'; FAIL=$((FAIL+1))
  else
    echo "  ok   REJECTED: $label"; PASS=$((PASS+1))
  fi
}

# assert_accepts <label> <workdir> <args...>
assert_accepts() {
  local label="$1"; shift; local dir="$1"; shift
  local out rc
  out="$( cd "$dir" && "$dir/scripts/wow/gates.sh" "$@" 2>&1 )"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  ok   accepted:  $label"; PASS=$((PASS+1))
  else
    echo "  FAIL rejected valid input: $label"; echo "$out" | sed 's/^/       /'; FAIL=$((FAIL+1))
  fi
}

# assert_output <label> <workdir> <expected-substring> <args...> — for checks
# whose point is what the gate SAYS, not whether it blocks (GATE-5's advisory
# half is the case: unmodified-doc drift must be reported and must not block).
assert_output() {
  local label="$1"; shift; local dir="$1"; shift; local expect="$1"; shift
  local out
  out="$( cd "$dir" && "$dir/scripts/wow/gates.sh" "$@" 2>&1 )"
  if grep -qF -- "$expect" <<<"$out"; then
    echo "  ok   reported:  $label"; PASS=$((PASS+1))
  else
    echo "  FAIL not reported: $label"
    echo "       expected: $expect"; echo "$out" | sed 's/^/       /'; FAIL=$((FAIL+1))
  fi
}

skip() { echo "  SKIP $1"; SKIP=$((SKIP+1)); }

finish() {
  [ -n "${FIX:-}" ] && rm -rf "$FIX"
  local tail=""; [ "$SKIP" -gt 0 ] && tail=", $SKIP skipped"
  if [ "$FAIL" -gt 0 ]; then echo "  -> $PASS passed, $FAIL FAILED$tail"; exit 1; fi
  echo "  -> $PASS passed$tail"; exit 0
}
