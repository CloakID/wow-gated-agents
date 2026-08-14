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
printf '# PLAN\nCovers REQ-001 and REQ-999. spec: docs/spec/SPEC-x-v1.md\n' \
  > "$FIX/runs/260813-x-r1/PLAN.md"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "reqs [WOW:publish]" )
assert_rejects "rows exist but none updated in the run" "$FIX" "never updated in run" \
  gate-2 --run 260813-x-r1

printf '| REQ | R | S |\n|---|---|---|\n| REQ-001 | a | COMPLETED ev:commit{abc1234} |\n| REQ-999 | b | COMPLETED ev:commit{abc1234} |\n' \
  > "$FIX/docs/REQUIREMENTS.md"
assert_accepts "rows updated in the run" "$FIX" gate-2 --run 260813-x-r1
finish
