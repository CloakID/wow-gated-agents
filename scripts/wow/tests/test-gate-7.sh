#!/usr/bin/env bash
# GATE-7 negative test: an unresolved jira-queue op and a stale quick stub must
# both block publish.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-7"

mkdir -p "$FIX/runs/260813-x-r1"
printf -- '- [ ] transition ABC-1 to Done\n' > "$FIX/runs/260813-x-r1/jira-queue.md"
assert_rejects "unresolved queued Jira op" "$FIX" "unresolved queued op" gate-7

printf -- '- [x] transition ABC-1 to Done\n' > "$FIX/runs/260813-x-r1/jira-queue.md"
assert_accepts "all queued ops applied" "$FIX" gate-7

mkdir -p "$FIX/runs/quick/260701-old-thing"
printf '## what\nx\n## why\ny\n## verify\n`cmd`\n## result\n' \
  > "$FIX/runs/quick/260701-old-thing/NOTE.md"
touch -t 202601010000 "$FIX/runs/quick/260701-old-thing/NOTE.md"
assert_rejects "stale quick stub with an empty result" "$FIX" "stale stub" gate-7
rm -rf "$FIX/runs/quick"   # clear the stale-stub fixture; escrow cases need a clean base

# ---- obligation escrow (FORMATS §12, OBL-PKG-01) ----------------------------
# Nothing obligation-shaped may live only in the runs/ tree being archived.
mkdir -p "$FIX/runs/260816-x-r1" "$FIX/docs"
cat > "$FIX/runs/260816-x-r1/RUN-REPORT.md" << 'R'
## new-gaps
CV-260816-x-r1-01: cannot validate webhook ordering
  reason: sandbox lacks replay
  successor: prod validation phase
  discharge: replayed in prod
R
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n' > "$FIX/docs/GAPS.md"
assert_rejects "CV record only in an archivable run (escrow)" "$FIX" "escrow" gate-7

printf '| CV-260816-x-r1-01 | env_unverified | PO | advisory | prod phase | replayed | ev:file{runs/260816-x-r1/RUN-REPORT.md#new-gaps} |\n' >> "$FIX/docs/GAPS.md"
assert_accepts "CV record escrowed into GAPS.md" "$FIX" gate-7

cat >> "$FIX/runs/260816-x-r1/RUN-REPORT.md" << 'R'
| 260816-x-r1.T02 | DEFERRED | see successor |
R
assert_rejects "DEFERRED row with no registry counterpart (escrow)" "$FIX" "escrow" gate-7
# The durable home is a proper OBLIGATION row referencing the task — a task id
# cannot be a row id (v0.7.0, OBL-PKG-13: parsed rows, not raw-text substrings).
printf '| OBL-T-42 | impl_gap | run | advisory | r2 | 260816-x-r1.T02 done in r2 | ev:file{runs/260816-x-r1/RUN-REPORT.md} |\n' >> "$FIX/docs/GAPS.md"
assert_accepts "DEFERRED row escrowed" "$FIX" gate-7

# ---- engine round 6 (OBL-PKG-20, audit §5.2): the walk read status at
# cells[1] — a DEFERRED in a named Status column anywhere else retired
# silently with the archived run. Status-by-header is OBL-PKG-13's own rule,
# discharged onto gate-3 but never applied to the escrow's walk.
cat >> "$FIX/runs/260816-x-r1/RUN-REPORT.md" << 'R'

| Task | Notes | Status |
|---|---|---|
| 260816-x-r1.T03 | picked up next iteration | DEFERRED |
R
assert_rejects "DEFERRED in a third-position Status column is seen (OBL-PKG-20)" "$FIX" \
  "escrow" gate-7
printf '| OBL-T-43 | impl_gap | run | advisory | r2 | 260816-x-r1.T03 done in r2 | ev:file{runs/260816-x-r1/RUN-REPORT.md} |\n' >> "$FIX/docs/GAPS.md"
assert_accepts "third-position DEFERRED escrowed (control)" "$FIX" gate-7

# Claims by position: where a Status column is NAMED, prose in other cells is
# not a status claim — gate-3's own convention, applied uniformly.
cat >> "$FIX/runs/260816-x-r1/RUN-REPORT.md" << 'R'
| 260816-x-r1.T04 | DEFERRED talk happened in review | OPEN |
R
assert_accepts "'DEFERRED' as prose outside the named Status column (control)" "$FIX" gate-7

# ---- F-51 (v0.7.2): a CV discharged IN-RUN is a closed question ------------
# Eight of eighteen records in one pilot run were closed before publish and
# the escrow demanded registry rows for all eighteen — the registry of open
# obligations accumulating records that owe nothing.
cat >> "$FIX/runs/260816-x-r1/RUN-REPORT.md" << 'R'

CV-260816-x-r1-07: harness absent during wave 1
  reason: built by U4
  successor: none
  discharge: U4 lands the harness
  discharged: 2026-09-17 ev:commit{abc1234}
R
assert_accepts "in-run discharged CV with evidence needs no registry row (F-51)" "$FIX" gate-7

cat >> "$FIX/runs/260816-x-r1/RUN-REPORT.md" << 'R'

CV-260816-x-r1-08: contract wording superseded
  reason: D-7 superseded it
  successor: none
  discharge: G4 decision
  discharged: it is fine now, trust us
R
assert_rejects "discharged WITHOUT an ev: citation stays demanded (F-51 control)" "$FIX" \
  "unevidenced closure is an assertion" gate-7
# make it evidenced so later cases stay isolated
python3 - "$FIX/runs/260816-x-r1/RUN-REPORT.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
open(p,'w').write(s.replace("discharged: it is fine now, trust us",
                            "discharged: 2026-09-17 ev:jira{WOW-99}"))
PY
assert_accepts "the same record with evidence is closed (F-51)" "$FIX" gate-7

# ---- F-63 (v0.7.2): archived runs must not leave wow/<run-id>/* refs -------
( cd "$FIX" && git checkout -qb wow/260816-y-r1/int && git checkout -q - )
mkdir -p "$FIX/runs/archive/260816-y-r1"
printf 'archived\n' > "$FIX/runs/archive/260816-y-r1/RUN-REPORT.md"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "archive [WOW:publish]" )
assert_rejects "archived run with surviving branch refs blocks publish (F-63)" "$FIX" \
  "branch refs survive" gate-7 --p5
( cd "$FIX" && git branch -qD wow/260816-y-r1/int )
assert_accepts "refs deleted: the archive is the only home again (F-63 control)" "$FIX" \
  gate-7 --p5
# a LIVE run's branches are legal — the check reads the archive set only
( cd "$FIX" && git checkout -qb wow/260816-x-r1/int && git checkout -q - )
assert_accepts "a live run's branches are not leaks (F-63 control)" "$FIX" gate-7 --p5
( cd "$FIX" && git branch -qD wow/260816-x-r1/int )   # the F-11 fixture below recreates it


# ---- S-6 (v0.6.2): a phantom run — an empty dir archiving strands -----------
mkdir -p "$FIX/runs/260820-ghost-r1/reports"
assert_rejects "empty run-id dir is a phantom, not an active run (S-6)" "$FIX" "phantom run" gate-7
rmdir "$FIX/runs/260820-ghost-r1/reports" "$FIX/runs/260820-ghost-r1"
# Control is the fixture itself: runs/260816-x-r1 holds files and stays legal.
assert_accepts "runs holding files are not phantoms (control)" "$FIX" gate-7

# ---- F-11 (v0.6.2, --p5 only): the run branch may not be behind main --------
( cd "$FIX" && git add -A >/dev/null && git commit -qm "base [WOW:publish]" \
  && git branch -M main && git checkout -qb wow/260816-x-r1/int \
  && git checkout -q main && printf 'grant\n' > grant.txt && git add grant.txt \
  && git commit -qm "grant lands on main [WOW:publish]" \
  && git checkout -q wow/260816-x-r1/int )
assert_rejects "run branch behind main at --p5 (F-11)" "$FIX" "BEHIND" gate-7 --p5
assert_accepts "same branch, no --p5: mid-run being behind is legal" "$FIX" gate-7
( cd "$FIX" && git merge -q --no-edit main >/dev/null 2>&1 )
assert_accepts "main merged in: publish may proceed (control)" "$FIX" gate-7 --p5

# ---- F-36 (v0.6.4): escrow scoped to --run; archive exemption really fires --
FIX7="$(setup_fixture_repo)"
mkdir -p "$FIX7/runs/260903-pub-r1" "$FIX7/runs/260903-other-r1" "$FIX7/docs"
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n' > "$FIX7/docs/GAPS.md"
printf '## new-gaps\nCV-260903-other-r1-01: cannot validate X\n' > "$FIX7/runs/260903-other-r1/RUN-REPORT.md"
printf '## completed\nall done ev:commit{abc1234}\n' > "$FIX7/runs/260903-pub-r1/RUN-REPORT.md"
assert_accepts "escrow scoped to the published run — another run's CV is not this publish's debt (F-36)" \
  "$FIX7" gate-7 --run 260903-pub-r1
assert_rejects "the other run still owes its escrow when IT publishes (control)" "$FIX7" "escrow" \
  gate-7 --run 260903-other-r1
# Archived runs are exempt — the old exemption compared against a TEMPLATE and never fired.
mkdir -p "$FIX7/runs/archive/260801-done-r1"
printf '## new-gaps\nCV-260801-done-r1-01: was judged at its own G4\n' > "$FIX7/runs/archive/260801-done-r1/RUN-REPORT.md"
assert_accepts "archived run reports are not re-scanned at every future P5 (F-36)" "$FIX7" \
  gate-7 --run 260903-pub-r1

# ---- S-6 addendum (v0.6.4): only-ignored files are a leftover, not a run ----
mkdir -p "$FIX7/runs/260902-left-r1"
printf '.DS_Store\n' > "$FIX7/.gitignore"
printf 'junk\n' > "$FIX7/runs/260902-left-r1/.DS_Store"
assert_rejects "dir holding only ignored files is a leftover (S-6 addendum)" "$FIX7" \
  "only git-IGNORED" gate-7 --run 260903-pub-r1
rm -rf "$FIX7/runs/260902-left-r1"
# ...but an untracked-unignored file is a run mid-creation and must stay legal.
mkdir -p "$FIX7/runs/260903-new-r1"
printf 'drafting\n' > "$FIX7/runs/260903-new-r1/HANDOFF.md"
assert_accepts "untracked real file = run mid-creation, not a phantom (control)" "$FIX7" \
  gate-7 --run 260903-pub-r1

# ---- F-37 (v0.6.4): feedback log owes write-ups at publish ------------------
printf '| id | source | state | upstream-ref |\n|---|---|---|---|\n| F-01 | run | open | - |\n' \
  > "$FIX7/docs/pilot-feedback.md"
assert_rejects "logged finding with no write-up blocks publish (F-37)" "$FIX7" "no write-up" \
  gate-7 --p5 --run 260903-pub-r1
mkdir -p "$FIX7/docs/upstream"
printf '# Findings\n## F-01 — the finding, written up\ndetail\n' > "$FIX7/docs/upstream/ISSUE-x.md"
( cd "$FIX7" && git add -A >/dev/null && git commit -qm "wire [WOW:publish]" && git branch -M main ) >/dev/null 2>&1
assert_accepts "write-up present: publish proceeds (F-37 control)" "$FIX7" gate-7 --p5 --run 260903-pub-r1

# ---- OBL-PKG-13 (v0.7.0): the escrow parses rows, resolves shorthands, and
# ---- treats an audit-trigger hit as an owed row --------------------------
FIX13="$(setup_fixture_repo)"
mkdir -p "$FIX13/runs/260903-cv-r1" "$FIX13/docs"
HDR13='| id | tag | owner | effect | successor | discharge | ev |
|---|---|---|---|---|---|---|'
# (1) a CV id mentioned in another row's PROSE is not a row — substring
#     matching called this escrowed; parsing does not.
printf '%s\n| OBL-T-50 | impl_gap | m | advisory | r2 | relates to CV-260903-cv-r1-01 somehow | ev:commit{abc1234} |\n' "$HDR13" > "$FIX13/docs/GAPS.md"
printf '## new-gaps\nCV-260903-cv-r1-01: cannot validate X\n' > "$FIX13/runs/260903-cv-r1/RUN-REPORT.md"
assert_rejects "CV mentioned in another row's prose is NOT a row (OBL-PKG-13)" "$FIX13" \
  "no ROW with that id" gate-7 --run 260903-cv-r1
printf '%s\n| CV-260903-cv-r1-01 | env_unverified | PO | advisory | later | replayed | ev:commit{abc1234} |\n' "$HDR13" > "$FIX13/docs/GAPS.md"
assert_accepts "a real row with the id escrows it (control)" "$FIX13" gate-7 --run 260903-cv-r1

# (2) shorthand CV-<nn> in the run's own report resolves to the full id —
#     frisbii's real CV-01..05 were invisible to the long regex.
printf '## carry-forwards\n`CV-03` the control is real but invisible to the checker.\n' \
  > "$FIX13/runs/260903-cv-r1/RUN-REPORT.md"
assert_rejects "shorthand CV-03 demands its full-form registry row (OBL-PKG-13)" "$FIX13" \
  "shorthand" gate-7 --run 260903-cv-r1
printf '%s\n| CV-260903-cv-r1-03 | env_unverified | PO | advisory | later | replayed | ev:commit{abc1234} |\n' "$HDR13" > "$FIX13/docs/GAPS.md"
assert_accepts "full-form row satisfies the shorthand (control)" "$FIX13" gate-7 --run 260903-cv-r1
# ...and the unit-scoped full form satisfies it too.
printf '%s\n| CV-260903-cv-r1-U2-03 | env_unverified | PO | advisory | later | replayed | ev:commit{abc1234} |\n' "$HDR13" > "$FIX13/docs/GAPS.md"
assert_accepts "unit-scoped full form also satisfies (control)" "$FIX13" gate-7 --run 260903-cv-r1

# (3) F8 third class: an audit-trigger HIT in a RUN-REPORT is an owed audit.
printf '## audit triggers\n| AT-2 | 6 | ev:commit{abc1234} |\n' > "$FIX13/runs/260903-cv-r1/RUN-REPORT.md"
printf '%s\n' "$HDR13" > "$FIX13/docs/GAPS.md"
assert_rejects "AT-2 over threshold with no open row naming it (F8)" "$FIX13" \
  "owed audit" gate-7 --run 260903-cv-r1
printf '%s\n| OBL-T-51 | audit_owed | PO | advisory | audit run | AT-2 remediation audit performed | ev:commit{abc1234} |\n' "$HDR13" > "$FIX13/docs/GAPS.md"
assert_accepts "open row naming AT-2 escrows the hit (control)" "$FIX13" gate-7 --run 260903-cv-r1
printf '## audit triggers\n| AT-2 | 3 | ev:commit{abc1234} |\n' > "$FIX13/runs/260903-cv-r1/RUN-REPORT.md"
printf '%s\n' "$HDR13" > "$FIX13/docs/GAPS.md"
assert_accepts "under-threshold trigger owes nothing (control)" "$FIX13" gate-7 --run 260903-cv-r1
finish
