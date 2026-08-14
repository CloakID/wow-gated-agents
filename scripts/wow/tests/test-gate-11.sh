#!/usr/bin/env bash
# GATE-11 negative test. The gate is inert in greenfield repos, so the fixture
# flips migrated_from_gsd to true — otherwise this test would prove nothing,
# which is exactly the inert-gate defect the suite exists to catch.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-11"

assert_accepts "inert while migrated_from_gsd is false" "$FIX" gate-11 --paths .planning/STATE.md

printf '{"migrated_from_gsd": true}\n' > "$FIX/scripts/wow/wow.config.json"
assert_rejects "touching frozen .planning/ once migrated" "$FIX" "frozen .planning/" gate-11 --paths .planning/STATE.md
assert_accepts "touching anything else once migrated" "$FIX" gate-11 --paths docs/README.md
finish
