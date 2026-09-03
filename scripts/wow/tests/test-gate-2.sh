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
# F-09 (v0.6.3): the sweep form is a consistency lint — at G2 no work has run
# and an un-updated row is the HONEST state, not a failure.
assert_accepts "sweep form: rows exist, none updated — legal before phase close (F-09)" "$FIX" \
  gate-2 --run 260813-x-r1
assert_rejects "close form: rows exist but none updated in the run" "$FIX" "never updated in run" \
  gate-2 --close --run 260813-x-r1

printf '| REQ | R | S |\n|---|---|---|\n| REQ-001 | a | COMPLETED ev:commit{abc1234} |\n| REQ-999 | b | COMPLETED ev:commit{abc1234} |\n' \
  > "$FIX/docs/REQUIREMENTS.md"
assert_accepts "close form: rows updated in the run" "$FIX" gate-2 --close --run 260813-x-r1
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


# ---- PF-d (pilot #2, v0.6.1): non-REQ requirement id schemes ----------------
# Pre-fix, a repo whose ids are not REQ-nnn produced an empty named-set and the
# empty set was permissive — GATE-2 green, permanently, for the wrong reason.
FIX2="$(setup_fixture_repo)"
mkdir -p "$FIX2/docs" "$FIX2/runs/260101-t-r1"
printf '| id | R | S |\n|---|---|---|\n| PLAT-M3-14 | a | COMPLETED ev:commit{abc1234} |\n' \
  > "$FIX2/docs/REQUIREMENTS.md"
printf '# PLAN\nWork on PLAT-M3-14 only.\n' > "$FIX2/runs/260101-t-r1/PLAN.md"
assert_rejects "unconfigured: id-shaped rows the pattern cannot read fail LOUDLY (PF-d/FR-1)" \
  "$FIX2" "requirement_id" gate-2 --run 260101-t-r1

# Configured via wow.config.json (repo-local truth): the real scheme binds.
printf '{"migrated_from_gsd": false, "requirement_id": "^PLAT-M3-[0-9]{2}$"}\n' \
  > "$FIX2/scripts/wow/wow.config.json"
printf '# PLAN\nWork on PLAT-M3-14 and PLAT-M3-99.\n' > "$FIX2/runs/260101-t-r1/PLAN.md"
assert_rejects "configured scheme: a named id with no row binds" "$FIX2" "has no row in" \
  gate-2 --run 260101-t-r1

# Positive control: named row exists, updated in the run; a backticked id in a
# notes row is a mention, not an unreadable row.
printf '# PLAN\nWork on PLAT-M3-14 only.\n' > "$FIX2/runs/260101-t-r1/PLAN.md"
( cd "$FIX2" && git add -A >/dev/null && git commit -qm "cfg [WOW:publish]" )
printf '| id | R | S |\n|---|---|---|\n| PLAT-M3-14 | a | COMPLETED ev:commit{def5678} |\n| `PLAT-M2-01` | historical, untracked mention | - |\n' \
  > "$FIX2/docs/REQUIREMENTS.md"
assert_accepts "configured scheme: updated row passes; backticked id is a mention (control)" \
  "$FIX2" gate-2 --run 260101-t-r1

# ---- F-17 (v0.6.4): declarations over scan ----------------------------------
FIX3="$(setup_fixture_repo)"
mkdir -p "$FIX3/docs/spec" "$FIX3/runs/260903-d-r1"
# Spec names its rows as a RANGE (the natural form); only the declaration
# enrolls all five.
printf '# SPEC\nrequirements: REQ-101, REQ-102, REQ-103, REQ-104, REQ-105\n\nSection 8 covers REQ-101 ... REQ-105 as a contiguous block.\n' \
  > "$FIX3/docs/spec/SPEC-d-v1.md"
printf '# PLAN\nspec: docs/spec/SPEC-d-v1.md\n' > "$FIX3/runs/260903-d-r1/PLAN.md"
printf '| id | R | S |\n|---|---|---|\n| REQ-101 | a | OPEN |\n| REQ-102 | a | OPEN |\n' \
  > "$FIX3/docs/REQUIREMENTS.md"
assert_rejects "a range enrolls every row it covers, via the declaration (F-17)" "$FIX3" \
  "has no row in" gate-2 --run 260903-d-r1
# ...and prose DISCUSSING an id does not adopt it: REQ-999 below is a mention.
printf '| id | R | S |\n|---|---|---|\n| REQ-101 | a | OPEN |\n| REQ-102 | a | OPEN |\n| REQ-103 | a | OPEN |\n| REQ-104 | a | OPEN |\n| REQ-105 | a | OPEN |\n' \
  > "$FIX3/docs/REQUIREMENTS.md"
printf '# PLAN\nspec: docs/spec/SPEC-d-v1.md\n\nNote: an earlier defect involved REQ-999, discussed here for the record.\n' \
  > "$FIX3/runs/260903-d-r1/PLAN.md"
assert_accepts "prose mention does not adopt an id when declarations exist (F-17)" "$FIX3" \
  gate-2 --run 260903-d-r1

# ---- F-36 (v0.6.4): a named run resolving to nothing is UNGRADED, red -------
assert_rejects "ghost run id reports ungraded, never passed (F-36)" "$FIX3" "UNGRADED" \
  gate-2 --run 260999-ghost-r9
# ...and an ARCHIVED run resolves its plan from the archive.
mkdir -p "$FIX3/runs/archive/260901-old-r1"
printf '# PLAN\nspec: docs/spec/SPEC-d-v1.md\n' > "$FIX3/runs/archive/260901-old-r1/PLAN.md"
assert_accepts "archived run resolves its governing plan from the archive (F-36)" "$FIX3" \
  gate-2 --run 260901-old-r1
finish
