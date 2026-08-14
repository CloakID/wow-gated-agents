# Shared harness for gate negative tests.
#
# Every test builds a fixture that SHOULD be rejected and asserts gates.sh rejects
# it. That is the non-vacuity proof GATE-4 requires: a gate whose negative test
# passes while the gate is disabled is an inert gate, which is itself a defect.
#
# Each test also runs a POSITIVE fixture, so a gate that rejects everything
# unconditionally fails too — rejecting all input is as useless as rejecting none.
set -uo pipefail
WOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATES="$WOW_DIR/gates.sh"
PASS=0; FAIL=0

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
  elif ! printf '%s' "$out" | grep -qF -- "$expect"; then
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

finish() {
  [ -n "${FIX:-}" ] && rm -rf "$FIX"
  if [ "$FAIL" -gt 0 ]; then echo "  -> $PASS passed, $FAIL FAILED"; exit 1; fi
  echo "  -> $PASS passed"; exit 0
}
