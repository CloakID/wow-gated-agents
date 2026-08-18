#!/usr/bin/env bash
# GATE-2 negative test: a spec naming a REQ id that has no row in REQUIREMENTS.md
# must be rejected, and so must a REQ whose row exists but was never updated in
# the run — "an updated technical-status row" is the check, not "a row exists".
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-2"

mkdir -p "$FIX/docs/spec"
printf '# SPEC\nCovers REQ-001 and REQ-999.\n' > "$FIX/docs/spec/SPEC-x-v1.md"
printf '| REQ | R | S |\n|---|---|---|\n| REQ-001 | a | OPEN |\n' > "$FIX/docs/REQUIREMENTS.md"
assert_rejects "REQ named by spec with no row" "$FIX" "has no row in" gate-2 --spec docs/spec/SPEC-x-v1.md

printf '| REQ | R | S |\n|---|---|---|\n| REQ-001 | a | OPEN |\n| REQ-999 | b | OPEN |\n' \
  > "$FIX/docs/REQUIREMENTS.md"
assert_accepts "all REQs have rows" "$FIX" gate-2 --spec docs/spec/SPEC-x-v1.md

# Phase close, scoped to a run: the rows are committed and untouched since.
mkdir -p "$FIX/runs/260813-x-r1"
printf '# PLAN\nspec: docs/spec/SPEC-x-v1.md\nCovers REQ-001 and REQ-999.\n' \
  > "$FIX/runs/260813-x-r1/PLAN.md"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "reqs [WOW:publish]" )
assert_rejects "rows exist but none updated in the run" "$FIX" "never updated in run" \
  gate-2 --run 260813-x-r1

printf '| REQ | R | S |\n|---|---|---|\n| REQ-001 | a | COMPLETED ev:commit{abc1234} |\n| REQ-999 | b | COMPLETED ev:commit{abc1234} |\n' \
  > "$FIX/docs/REQUIREMENTS.md"
assert_accepts "rows updated in the run" "$FIX" gate-2 --run 260813-x-r1
# ---- G-11 (OBL-PKG-07): scope is the GOVERNING spec/plan, never widened -----
# Pre-fix, gate_2 walked every .md under runs/<id>/ and followed spec references
# out to other specs — a HANDOFF pointer to an unsigned draft pulled that
# draft's REQ ids into this run's mandatory set. These cases turn red if the
# old walk comes back (verifier F2: the merged fix was inert-by-test).
printf '# DRAFT SPEC (unsigned)\nCovers REQ-777.\n' > "$FIX/docs/spec/SPEC-foreign-v1.md"
printf 'position: mid-run\npointers: see docs/spec/SPEC-foreign-v1.md for the blocked draft\n' \
  > "$FIX/runs/260813-x-r1/HANDOFF.md"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "handoff [WOW:publish]" ) >/dev/null 2>&1
# fresh working-tree update so "updated in run" holds (different sha than committed)
printf '| REQ | R | S |\n|---|---|---|\n| REQ-001 | a | COMPLETED ev:commit{def5678} |\n| REQ-999 | b | COMPLETED ev:commit{def5678} |\n' \
  > "$FIX/docs/REQUIREMENTS.md"
assert_accepts "HANDOFF pointer to a foreign spec does NOT widen the REQ scope (G-11)" "$FIX" \
  gate-2 --run 260813-x-r1

# Violation control on the same fixture: the GOVERNING spec's own REQ still binds.
printf '# SPEC\nCovers REQ-001, REQ-999 and REQ-555.\n' > "$FIX/docs/spec/SPEC-x-v1.md"
assert_rejects "governing spec's own new REQ still binds (positive control)" "$FIX" "no row in" \
  gate-2 --run 260813-x-r1

finish
