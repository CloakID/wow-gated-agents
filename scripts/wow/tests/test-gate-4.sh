#!/usr/bin/env bash
# GATE-4 negative test: a run report declaring more invariants than non-vacuity
# proofs must be rejected; a gate with no test file must be rejected.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-4"

mkdir -p "$FIX/runs/260813-x-r1/reports"
printf 'invariant: plans never overlap\ninvariant: tasks always verify\nnon-vacuity: proved by t.sh\n' \
  > "$FIX/runs/260813-x-r1/reports/U1.md"
assert_rejects "2 invariants, 1 non-vacuity proof" "$FIX" "non-vacuity proof" gate-4 --run 260813-x-r1

printf 'invariant: plans never overlap\nnon-vacuity: proved by t.sh\n' \
  > "$FIX/runs/260813-x-r1/reports/U1.md"
assert_accepts "1 invariant, 1 non-vacuity proof" "$FIX" gate-4 --run 260813-x-r1

rm "$FIX/scripts/wow/tests/test-gate-7.sh"
assert_rejects "a gate with no negative test" "$FIX" "has no negative test" gate-4
finish
