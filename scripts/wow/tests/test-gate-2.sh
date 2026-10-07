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
# DEV-R12-06 (R12b): the close form needs the RUN-REPORT it walks — a missing
# one at both paths is refused, never "nothing owed".
assert_rejects "close form with NO RUN-REPORT at either path is refused, not vacuously passed (DEV-R12-06)" "$FIX" \
  "no RUN-REPORT.md for run 260813-x-r1 at its path or the archive rewrite" gate-2 --close --run 260813-x-r1
printf '# RUN-REPORT\nall green\n' > "$FIX/runs/260813-x-r1/RUN-REPORT.md"
assert_accepts "close form: rows updated in the run" "$FIX" gate-2 --close --run 260813-x-r1

# ---- prodsim/F-86 (v0.7.4, R11b: the CLOSE form owns it — ADV-R11-04): G4
# close requires the walk artifact, one row per RUN-REPORT item, first cell = id.
printf '# RUN-REPORT\n\n| id | status | ref |\n|---|---|---|\n| 260813-x-r1.T02 | BLOCKED | PARK-U1-01 |\n| 260813-x-r1.T03 | FAILED | VF-U1-02 |\n| 260813-x-r1.T030 | FAILED | VF-U1-03 |\n\nDEF-plan-01 overlap found.\n' \
  > "$FIX/runs/260813-x-r1/RUN-REPORT.md"
assert_rejects "close with items and NO walk artifact is refused (prodsim/F-86)" "$FIX" \
  "no walk artifact" gate-2 --close --run 260813-x-r1
printf '| item | class | disposition |\n|---|---|---|\n| 260813-x-r1.T02 | parked | fold into r2 |\n| DEF-plan-01 | defect | amend AM-02 |\n| 260813-x-r1.T030 | failed | reconciled |\n' \
  > "$FIX/runs/260813-x-r1/walk-G4.md"
assert_rejects "walk missing T03 is refused — T030 does not satisfy T03 (F-86, ADV-R11-09)" "$FIX" \
  "absent from" gate-2 --close --run 260813-x-r1
printf '| 260813-x-r1.T03 | failed | VF-U1-02 reconciled into v2 |\n' >> "$FIX/runs/260813-x-r1/walk-G4.md"
assert_accepts "every item classified in the walk: close proceeds (F-86 control)" "$FIX" \
  gate-2 --close --run 260813-x-r1
assert_output "the PASS states the walk subject (DEV-R11-12)" "$FIX" "walk: 4/4" \
  gate-2 --close --run 260813-x-r1
# the sweep form does not demand a walk (P4 step 1 runs before step 2 writes it)
rm -f "$FIX/runs/260813-x-r1/walk-G4.md"
assert_accepts "sweep form never demands a walk artifact (ADV-R11-04 ordering)" "$FIX" \
  gate-2 --run 260813-x-r1
rm -f "$FIX/runs/260813-x-r1/RUN-REPORT.md"
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
# ---- platform/F-100 + prodsim/F-90 (v0.7.5): `requirements: none` is the EMPTY set
FIX5="$(setup_fixture_repo)"
mkdir -p "$FIX5/docs/spec" "$FIX5/runs/260929-aud-r1"
printf '# SPEC\nrequirements: none — an audit delivers findings, not product capability\n\nBackground: the migration row REQ-101 no longer stands in the way.\n' \
  > "$FIX5/docs/spec/SPEC-aud-v1.md"
printf '# PLAN\nspec: docs/spec/SPEC-aud-v1.md\n' > "$FIX5/runs/260929-aud-r1/PLAN.md"
printf '| id | R | S |\n|---|---|---|\n| REQ-101 | a | OPEN |\n' > "$FIX5/docs/REQUIREMENTS.md"
printf '# RUN-REPORT\nnothing failed\n' > "$FIX5/runs/260929-aud-r1/RUN-REPORT.md"
( cd "$FIX5" && git add -A >/dev/null && git commit -qm "aud [WOW:publish]" )
assert_accepts "requirements: none declares the EMPTY set — a background mention enrolls nothing, even at --close (platform/F-100, prodsim/F-90)" \
  "$FIX5" gate-2 --close --run 260929-aud-r1
assert_output "the empty declaration is reported as DECLARED and graded, not vacuous (F-100/F-83, ADV-R12-16)" "$FIX5" \
  "subject: 0 requirement row(s) — a declared empty set, graded as such" gate-2 --run 260929-aud-r1
printf '# SPEC\nrequirements: none — an audit; REQ-101 is background only\n' > "$FIX5/docs/spec/SPEC-aud-v1.md"
assert_output "an id mentioned in the sentinel's <why> is NOT declared (DEV-R12-05)" "$FIX5" \
  "— 0 id(s)" gate-2 --run 260929-aud-r1
printf '# SPEC\nrequirements: [] — an audit\n' > "$FIX5/docs/spec/SPEC-aud-v1.md"
assert_accepts "the [] sentinel matches (ADV-R12-04)" "$FIX5" gate-2 --run 260929-aud-r1
printf '# SPEC\nrequirements: none — an audit delivers findings, not product capability\n\nBackground: the migration row REQ-101 no longer stands in the way.\n' \
  > "$FIX5/docs/spec/SPEC-aud-v1.md"
printf '# SPEC\nrequirements: nonne — typo\n\nBackground: REQ-101.\n' > "$FIX5/docs/spec/SPEC-aud-v1.md"
assert_rejects "an id-less declaration that is not the sentinel is refused loudly (F-90: a typo is never read as none)" \
  "$FIX5" "not the empty-set sentinel" gate-2 --run 260929-aud-r1
printf '# SPEC\nBackground: REQ-101.\n' > "$FIX5/docs/spec/SPEC-aud-v1.md"
assert_output "with NO declaration line the text scan still applies (F-90 control)" "$FIX5" \
  "TEXT SCAN" gate-2 --run 260929-aud-r1
assert_output "a PASS over named rows states its subject count (platform/F-83)" "$FIX5" \
  "subject: 1 requirement row(s)" gate-2 --run 260929-aud-r1
# ---- platform/F-98 (v0.7.5): the walk enrols DEF-plan ids from ROWS, not tokens
FIX6="$(setup_fixture_repo)"
mkdir -p "$FIX6/docs/spec" "$FIX6/runs/260920-walk-r1"
printf '# SPEC\nrequirements: none — audit\n' > "$FIX6/docs/spec/SPEC-w-v1.md"
printf '# PLAN\nspec: docs/spec/SPEC-w-v1.md\n' > "$FIX6/runs/260920-walk-r1/PLAN.md"
printf '| id | R | S |\n|---|---|---|\n' > "$FIX6/docs/REQUIREMENTS.md"
printf '# RUN-REPORT\n\n| id | status | ev |\n|---|---|---|\n| 260920-walk-r1.T09 | COMPLETED | amended below (DEF-plan-01) ev:commit{abc1234} |\n| DEF-plan-01 … DEF-plan-05 | COMPLETED | repaired at G2a ev:commit{abc1234} |\n' \
  > "$FIX6/runs/260920-walk-r1/RUN-REPORT.md"
( cd "$FIX6" && git add -A >/dev/null && git commit -qm "w [WOW:publish]" )
assert_output "DEF-plan ids in COMPLETED rows are not walk items (platform/F-98)" "$FIX6" \
  "walk: 0 failed/blocked/parked/defect items" gate-2 --close --run 260920-walk-r1
printf '# RUN-REPORT\n\n| id | status | ev |\n|---|---|---|\n| DEF-plan-01 … DEF-plan-03 | FAILED | still open |\n' \
  > "$FIX6/runs/260920-walk-r1/RUN-REPORT.md"
assert_rejects "a FAILED range enrols every id it covers (F-98 fix 2)" "$FIX6" \
  "3 failed/blocked/parked/defect item(s) (DEF-plan-01, DEF-plan-02, DEF-plan-03)" gate-2 --close --run 260920-walk-r1
printf '# RUN-REPORT\n\nProse: DEF-plan-07 was noticed and has no row yet.\n' > "$FIX6/runs/260920-walk-r1/RUN-REPORT.md"
assert_rejects "a DEF-plan id with NO row anywhere is still enrolled from prose (F-98 fail-safe)" "$FIX6" \
  "DEF-plan-07" gate-2 --close --run 260920-walk-r1
printf '| item | class | disposition |\n|---|---|---|\n| DEF-plan-07 | resolved-in-run | fixed before wave 1 |\n' > "$FIX6/runs/260920-walk-r1/walk-G4.md"
assert_rejects "a resolved-in-run walk row WITHOUT an ev: citation is refused (F-98 fix 3)" "$FIX6" \
  "resolved-in-run\` carry no ev: citation: DEF-plan-07" gate-2 --close --run 260920-walk-r1
printf '| item | class | disposition |\n|---|---|---|\n| DEF-plan-07 | resolved-in-run | fixed before wave 1 ev:commit{abc1234} |\n' > "$FIX6/runs/260920-walk-r1/walk-G4.md"
assert_accepts "a resolved-in-run walk row WITH a citation closes (F-98 control)" "$FIX6" \
  gate-2 --close --run 260920-walk-r1
# ---- R12b: DEV-R12-06 — the close form reads an ARCHIVED run's RUN-REPORT and walk
mkdir -p "$FIX6/runs/archive"
( cd "$FIX6" && mv runs/260920-walk-r1 runs/archive/260920-walk-r1 && rm -f runs/archive/260920-walk-r1/walk-G4.md )
assert_rejects "an archived run with walk items and no walk is still refused at --close (DEV-R12-06)" "$FIX6" \
  "no walk artifact" gate-2 --close --run 260920-walk-r1
printf '| item | class | disposition |\n|---|---|---|\n| DEF-plan-07 | resolved-in-run | fixed ev:commit{abc1234} |\n' > "$FIX6/runs/archive/260920-walk-r1/walk-G4.md"
assert_accepts "the archived walk satisfies the archived RUN-REPORT (DEV-R12-06 control)" "$FIX6" gate-2 --close --run 260920-walk-r1
# ---- R12b: DEV-R12-18 — a `## defects` row with status OPEN is a walk item
( cd "$FIX6" && mv runs/archive/260920-walk-r1 runs/260920-walk-r1 && rm -f runs/260920-walk-r1/walk-G4.md )
printf '# RUN-REPORT\n\n## defects\n| id | what | status |\n|---|---|---|\n| DEF-plan-01 | overlap | OPEN |\n' > "$FIX6/runs/260920-walk-r1/RUN-REPORT.md"
assert_rejects "an OPEN defect row is a walk item (DEV-R12-18)" "$FIX6" "DEF-plan-01" gate-2 --close --run 260920-walk-r1
finish
