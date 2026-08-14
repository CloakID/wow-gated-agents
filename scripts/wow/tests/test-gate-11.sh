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

# The premise check: the staged set filtered deletions out, so `git rm` on the
# frozen tree — erasing the history the gate exists to preserve — was allowed.
mkdir -p "$FIX/.planning"
printf 'history\n' > "$FIX/.planning/STATE.md"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "planning [WOW:publish]" \
  && git rm -q .planning/STATE.md )
assert_rejects "staged DELETION of frozen history" "$FIX" "frozen .planning/" gate-11 --staged
( cd "$FIX" && git reset -q --hard HEAD )

printf 'edited\n' > "$FIX/.planning/STATE.md"
( cd "$FIX" && git add -A >/dev/null )
assert_rejects "staged EDIT of frozen history" "$FIX" "frozen .planning/" gate-11 --staged
finish
