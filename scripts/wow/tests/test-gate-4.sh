#!/usr/bin/env bash
# GATE-4 negative test: a run report declaring more invariants than non-vacuity
# proofs must be rejected; so must a "proof" that cites nothing runnable; and a
# gate with no test file, or a missing wiring test, must be rejected.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-4"

mkdir -p "$FIX/runs/260813-x-r1/reports"
proof() { cat > "$FIX/runs/260813-x-r1/reports/U1.md"; }

proof <<'R'
invariant: plans never overlap
invariant: tasks always verify
non-vacuity: ev:cmd{bash scripts/wow/tests/test-gate-8.sh => 1 @2026-08-13}
R
assert_rejects "2 invariants, 1 non-vacuity proof" "$FIX" "non-vacuity proof" gate-4 --run 260813-x-r1

# The premise check: "non-vacuity: yes" is not a proof, and neither is a proof
# that names a test file which does not exist.
proof <<'R'
invariant: plans never overlap
non-vacuity: proved by t.sh
R
assert_rejects "proof citing a file that does not exist" "$FIX" "cites nothing runnable" \
  gate-4 --run 260813-x-r1

proof <<'R'
invariant: plans never overlap
non-vacuity: ev:cmd{bash scripts/wow/tests/test-gate-8.sh => 1 @2026-08-13}
R
assert_accepts "1 invariant, 1 citing proof" "$FIX" gate-4 --run 260813-x-r1

proof <<'R'
invariant: plans never overlap
non-vacuity: disabling the check makes scripts/wow/tests/test-gate-8.sh fail
R
assert_accepts "proof naming an existing test file" "$FIX" gate-4 --run 260813-x-r1

rm "$FIX/scripts/wow/tests/test-gate-7.sh"
assert_rejects "a gate with no negative test" "$FIX" "has no negative test" gate-4

cp "$WOW_DIR/tests/test-gate-7.sh" "$FIX/scripts/wow/tests/test-gate-7.sh"
rm "$FIX/scripts/wow/tests/test-install.sh"
assert_rejects "no wiring test" "$FIX" "no wiring test" gate-4
finish
