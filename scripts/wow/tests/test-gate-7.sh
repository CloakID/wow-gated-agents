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

# ---- prodsim/F-69 (v0.7.3, ADV-3): the CV record is BORN in the verifier's
# report (FORMATS §5) and the escrow never opened that file — three genuine
# coverage limits reached no durable home while the escrow reported clean.
# The run's verify reports join the per-run aggregation.
mkdir -p "$FIX/runs/260816-x-r1/reports"
cat > "$FIX/runs/260816-x-r1/reports/U9-verify.md" << 'R'
Grade: PASS-with-carry-forwards

CV-260816-x-r1-U9-01: durable invariant blesses a destructive overwrite path
  reason: abort status is non-default in the harness
  successor: prod validation
  discharge: exercised in prod
R
assert_rejects "CV allocated ONLY in a verify report is escrow-demanded (F-69)" "$FIX" \
  "escrow" gate-7
printf '| CV-260816-x-r1-U9-01 | env_unverified | PO | advisory | prod | exercised | ev:file{runs/260816-x-r1/reports/U9-verify.md} |\n' >> "$FIX/docs/GAPS.md"
assert_accepts "verify-report CV escrowed into the registry (F-69 control)" "$FIX" gate-7

# Aggregation joins the run's WHOLE file set: allocated in the verify report,
# discharged in RUN-REPORT — a closed question (F-51 across files).
cat > "$FIX/runs/260816-x-r1/reports/U8-verify.md" << 'R'
CV-260816-x-r1-U8-02: contract wording pending
  reason: D-7 in flight
  successor: none
  discharge: G4 decision
R
cat >> "$FIX/runs/260816-x-r1/RUN-REPORT.md" << 'R'

CV-260816-x-r1-U8-02: contract wording pending
  discharged: 2026-09-19 ev:jira{WOW-77}
R
assert_accepts "CV allocated in a verify report, discharged in RUN-REPORT — closed (F-69/F-51)" \
  "$FIX" gate-7

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
# ---- ADV-R9-04 (v0.7.3 R9): discharge resolution is order-INDEPENDENT ------
# Allocation in RUN-REPORT (first block, open), discharge in a verify report
# (later in the aggregate) — the old first-block-only search demanded a
# registry row for a record the run itself closed.
cat >> "$FIX/runs/260816-x-r1/RUN-REPORT.md" << 'R'

CV-260816-x-r1-09: probe env pending at wave 2
  reason: env came up in wave 3
  successor: none
  discharge: wave-3 re-probe
R
cat > "$FIX/runs/260816-x-r1/reports/U7-verify.md" << 'R'
CV-260816-x-r1-09: probe env pending at wave 2
  discharged: 2026-09-19 ev:cmd{wave-3 re-probe, output pasted in U7 report}
R
assert_accepts "allocated in RUN-REPORT, discharged in a verify report (ADV-R9-04)" "$FIX" gate-7

# ---- ADV-R9-01 (v0.7.3 R9): a FENCED "example" discharge is a mention ------
# The forgery: record a real open CV, then "quote the record format" in a
# fence carrying a fabricated ev: — the old matcher read the fence as a claim.
cat >> "$FIX/runs/260816-x-r1/RUN-REPORT.md" << 'R'

CV-260816-x-r1-10: rollback path unexercised
  reason: destructive against shared env
  successor: prod validation
  discharge: game-day exercise

The record format, for reference:

```
CV-260816-x-r1-10: rollback path unexercised
  discharged: 2026-09-19 ev:jira{WOW-1}
```
R
assert_rejects "fenced example discharge does NOT close the CV (ADV-R9-01)" "$FIX" \
  "no ROW with that id" gate-7
python3 - "$FIX/runs/260816-x-r1/RUN-REPORT.md" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
# the SAME text outside the fence is a claim and closes it (control)
s = s.replace("""The record format, for reference:

```
CV-260816-x-r1-10: rollback path unexercised
  discharged: 2026-09-19 ev:jira{WOW-1}
```""", """CV-260816-x-r1-10: rollback path unexercised
  discharged: 2026-09-19 ev:jira{WOW-1}""")
open(p, 'w').write(s)
PY
assert_accepts "the same discharge outside the fence closes it (ADV-R9-01 control)" "$FIX" gate-7

# ---- ADV-R9-06 (v0.7.3 R9): the escrow never passes over nothing -----------
FIX6="$(setup_fixture_repo)"
assert_rejects "--run naming a missing directory is not a pass (ADV-R9-06)" "$FIX6" \
  "names no directory" gate-7 --run 260919-ghost-r1
# a run that died after verify: CVs in reports/*-verify.md, no RUN-REPORT.
# Explicitly named, it is under judgment — the CV is escrow-demanded.
mkdir -p "$FIX6/runs/260919-dead-r1/reports"
cat > "$FIX6/runs/260919-dead-r1/reports/U1-verify.md" << 'R'
Grade: PASS-with-carry-forwards

CV-260919-dead-r1-U1-01: integration env never came back
  reason: run died between verify and report assembly
  successor: none
  discharge: rerun
R
assert_rejects "verify-only run named with --run: CV is escrow-demanded (ADV-R9-06)" "$FIX6" \
  "no ROW with that id" gate-7 --run 260919-dead-r1
# unnamed, the F-36 shield holds (mid-flight siblings stay invisible) but the
# walk now SAYS what it skipped.
assert_output "unnamed walk names the verify-only dir it skipped (ADV-R9-06)" "$FIX6" \
  "verify reports but no RUN-REPORT" gate-7
# an existing dir with NEITHER a RUN-REPORT nor verify reports walks nothing —
# and an escrow that judged nothing over an explicit --run is not a pass.
mkdir -p "$FIX6/runs/260919-mid-r1"
printf 'position\n' > "$FIX6/runs/260919-mid-r1/HANDOFF.md"
assert_rejects "--run over a dir with nothing judgeable walks 0 and fails (ADV-R9-06)" "$FIX6" \
  "walked 0 runs" gate-7 --run 260919-mid-r1

# ---- ADV-R9-07 (v0.7.3 R9): one section regex, any heading level -----------
# '### audit triggers' used to derive a hit in status.mjs while the escrow
# (##-anchored) stayed silent — same value, two consumers, opposite answers.
mkdir -p "$FIX6/runs/260919-at3-r1"
printf '### audit triggers\n| AT-2 | 6 | ev:jira{WOW-3} |\n' > "$FIX6/runs/260919-at3-r1/RUN-REPORT.md"
assert_rejects "AT hit under a ### heading is seen by the escrow (ADV-R9-07)" "$FIX6" \
  "owed audit" gate-7 --run 260919-at3-r1
# ---- ADV-R10-01 (R9b): the forgery re-ran through the ADJACENT mention
# channels the day the ``` one closed — tilde fences and indented code.
FIXA="$(setup_fixture_repo)"
mkdir -p "$FIXA/runs/260920-tld-r1"
cat > "$FIXA/runs/260920-tld-r1/RUN-REPORT.md" << 'R'
CV-260920-tld-r1-01: rollback path unexercised
  reason: destructive against shared env
  successor: prod validation
  discharge: game-day exercise

The record format, for reference:

~~~
CV-260920-tld-r1-01: rollback path unexercised
  discharged: 2026-09-20 ev:jira{WOW-1}
~~~
R
assert_rejects "a ~~~-fenced example discharge does NOT close the CV (ADV-R10-01)" "$FIXA" \
  "no ROW with that id" gate-7 --run 260920-tld-r1
cat > "$FIXA/runs/260920-tld-r1/RUN-REPORT.md" << 'R'
CV-260920-tld-r1-01: rollback path unexercised
  reason: destructive against shared env
  successor: prod validation
  discharge: game-day exercise

The record format, for reference:

    CV-260920-tld-r1-01: rollback path unexercised
      discharged: 2026-09-20 ev:jira{WOW-1}
R
assert_rejects "an INDENTED-code example discharge does NOT close the CV (ADV-R10-01)" "$FIXA" \
  "no ROW with that id" gate-7 --run 260920-tld-r1

# ---- ADV-R10-04 (R9b): fence state resets per FILE — one unclosed fence in
# RUN-REPORT must not mark every verify report as fenced and hide a real
# cross-file discharge (the exact case ADV-R9-04 exists for).
mkdir -p "$FIXA/runs/260920-tld-r1/reports"
cat > "$FIXA/runs/260920-tld-r1/RUN-REPORT.md" << 'R'
CV-260920-tld-r1-02: probe env pending at wave 2
  reason: env came up in wave 3
  successor: none
  discharge: wave-3 re-probe

A truncated paste left this fence unclosed:
```
some quoted output
R
cat > "$FIXA/runs/260920-tld-r1/reports/U1-verify.md" << 'R'
CV-260920-tld-r1-02: probe env pending at wave 2
  discharged: 2026-09-20 ev:cmd{wave-3 re-probe, output pasted in U1 report}
R
assert_accepts "unclosed fence in RUN-REPORT does not hide the verify-file discharge (ADV-R10-04)" \
  "$FIXA" gate-7 --run 260920-tld-r1

# ---- ADV-R10-03 (R9b): a fenced '# comment' inside the audit-triggers
# section must not terminate it — the recorded hit stays escrowed.
mkdir -p "$FIXA/runs/260920-cmt-r1"
cat > "$FIXA/runs/260920-cmt-r1/RUN-REPORT.md" << 'R'
## audit triggers

```sh
# count BLOCKED rows in the report
grep -c BLOCKED reports/*.md
```

| AT-2 | 6 | ev:jira{WOW-3} |
R
assert_rejects "AT hit below a fenced # comment is still seen by the escrow (ADV-R10-03)" "$FIXA" \
  "owed audit" gate-7 --run 260920-cmt-r1

# ---- ADV-R10-09 (R9b): naming an archived run says ARCHIVED, not 'missing'.
mkdir -p "$FIXA/runs/archive/260101-done-r1"
printf 'archived\n' > "$FIXA/runs/archive/260101-done-r1/RUN-REPORT.md"
assert_rejects "--run on an archived run names the archive and F-36 (ADV-R10-09)" "$FIXA" \
  "ARCHIVED" gate-7 --run 260101-done-r1
# ---- platform/F-77 + prodsim/F-88 (v0.7.4): at --p5 the named run is graded
# FROM THE ARCHIVE — P5 step 3 archives, step 6 names the run, and the phase's
# own documented command must pass on a clean publish and still bite on debt.
FIXP="$(setup_fixture_repo)"
( cd "$FIXP" && git branch -M main ) >/dev/null 2>&1
mkdir -p "$FIXP/runs/archive/260921-pub-r1"
printf '# RUN-REPORT\n\n## completed\n| id | status | ev |\n|---|---|---|\n| T01 | COMPLETED | ev:jira{WOW-1} |\n' \
  > "$FIXP/runs/archive/260921-pub-r1/RUN-REPORT.md"
assert_accepts "P5 sweep grades the just-archived named run and passes clean (F-77/F-88)" "$FIXP" \
  gate-7 --p5 --run 260921-pub-r1
# grading is REAL: an open CV in the archived run's report is still demanded
cat >> "$FIXP/runs/archive/260921-pub-r1/RUN-REPORT.md" << 'R'

## new-gaps
CV-260921-pub-r1-01: rollback unexercised
  reason: destructive
  successor: none
  discharge: game-day
R
assert_rejects "archived named run's open CV is still escrow-demanded at --p5 (F-88)" "$FIXP" \
  "no ROW with that id" gate-7 --p5 --run 260921-pub-r1
printf '| CV-260921-pub-r1-01 | env_unverified | PO | advisory | later | game-day | ev:jira{WOW-2} |\n' >> "$FIXP/docs/GAPS.md"
assert_accepts "registry row escrows it; publish proceeds (F-88 control)" "$FIXP" \
  gate-7 --p5 --run 260921-pub-r1
# ...and surviving branch refs still fail the same invocation (F-77 non-vacuity)
( cd "$FIXP" && git branch wow/260921-pub-r1/int ) >/dev/null 2>&1
assert_rejects "archived named run with surviving refs still fails at --p5 (F-63/F-77)" "$FIXP" \
  "branch refs survive" gate-7 --p5 --run 260921-pub-r1
assert_output "the leak message states its count before its sample (prodsim/F-79)" "$FIXP" \
  "refs survive (1):" gate-7 --p5 --run 260921-pub-r1
( cd "$FIXP" && git branch -D wow/260921-pub-r1/int ) >/dev/null 2>&1
# outside --p5 the archived refusal holds (F-36/F-65 unchanged)
assert_rejects "outside --p5 an archived --run is still refused (F-36 control)" "$FIXP" \
  "ARCHIVED" gate-7 --run 260921-pub-r1

# ---- platform/F-80 (v0.7.4): a registry row's deleted proof refuses publish.
printf '| OBL-T-90 | impl_gap | PO | advisory | later | fixed | ev:file{runs/quick/260910-note/NOTE.md:3} |\n' >> "$FIXP/docs/GAPS.md"
assert_rejects "registry citation to a GC-deleted file refuses publish (platform/F-80)" "$FIXP" \
  "proof has been deleted" gate-7 --p5 --run 260921-pub-r1
# the archive rewrite of a moved run file is not a loss
python3 - "$FIXP/docs/GAPS.md" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, 'w').write(s.replace("ev:file{runs/quick/260910-note/NOTE.md:3}",
                             "ev:file{runs/260921-pub-r1/RUN-REPORT.md:2}"))
PY
assert_accepts "citation into the archived run resolves via the archive rewrite (F-80 control)" \
  "$FIXP" gate-7 --p5 --run 260921-pub-r1
# ---- prodsim/F-87b/d (v0.7.4): a fenced grep paste is not a table, and a
# finding names the file it was read from.
FIX87="$(setup_fixture_repo)"
mkdir -p "$FIX87/runs/260922-esc-r1/reports"
printf '# RUN-REPORT\n\n| id | status | ev |\n|---|---|---|\n| T01 | COMPLETED | ev:jira{WOW-1} |\n' \
  > "$FIX87/runs/260922-esc-r1/RUN-REPORT.md"
cat > "$FIX87/runs/260922-esc-r1/reports/U1-verify.md" << 'R'
Probing the registry, pasted verbatim:

```
32:| REQ-PROBE-SIGNAL | DEFERRED | later |
33:| REQ-OTHER | OPEN | now |
```

| id | Status | note |
|---|---|---|
| REQ-REAL-THING | DEFERRED | genuinely deferred |
R
OUT87="$( cd "$FIX87" && ./scripts/wow/gates.sh gate-7 --run 260922-esc-r1 2>&1 )"; RC87=$?
if [ "$RC87" -ne 0 ] && printf '%s' "$OUT87" | grep -q "defers REQ-REAL-THING" \
   && ! printf '%s' "$OUT87" | grep -q "defers 32:"; then
  echo "  ok   real deferral demanded under its REAL id; fenced grep rows ignored (F-87b)"; PASS=$((PASS+1))
else
  echo "  FAIL phantom grep-prefix id or missed real deferral (F-87b)"; printf '%s\n' "$OUT87" | head -4; FAIL=$((FAIL+1))
fi
if printf '%s' "$OUT87" | grep -q "U1-verify.md defers"; then
  echo "  ok   the finding names the verify report it was read from (F-87d)"; PASS=$((PASS+1))
else
  echo "  FAIL finding attributed to the wrong file (F-87d)"; printf '%s\n' "$OUT87" | head -3; FAIL=$((FAIL+1))
fi
# ---- prodsim/F-87a: a malformed registry row is loud at the escrow too -----
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n| OBL-T-99 | x | PO | not-a-real-effect | s | d | ev:jira{W-1} |\n' \
  > "$FIX87/docs/GAPS.md"
assert_rejects "malformed registry row is loud at the escrow, not silently non-blocking (F-87a)" \
  "$FIX87" "cannot fully parse" gate-7 --run 260922-esc-r1
# ---- ADV-R11-03 (R11b): a status table INSIDE a fence is still an obligation
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n' > "$FIX87/docs/GAPS.md"
cat > "$FIX87/runs/260922-esc-r1/reports/U1-verify.md" << 'R'
Quoted from the plan:

```markdown
| id | Status | note |
|---|---|---|
| REQ-HIDDEN-THING | DEFERRED | tucked into a fence |
```
R
assert_rejects "a DEFERRED row inside a fence is still escrow-demanded (ADV-R11-03)" "$FIX87" \
  "defers REQ-HIDDEN-THING" gate-7 --run 260922-esc-r1
# ---- DEV-R11-09 (R11b): a CITED stale stub is retained, an uncited one listed
FIXQ="$(setup_fixture_repo)"
mkdir -p "$FIXQ/runs/quick/260701-cited" "$FIXQ/runs/quick/260701-orphan" "$FIXQ/runs/260922-q-r1"
printf '## what\nx\n## result\n\n' > "$FIXQ/runs/quick/260701-cited/NOTE.md"
printf '## what\nx\n## result\n\n' > "$FIXQ/runs/quick/260701-orphan/NOTE.md"
touch -d '60 days ago' "$FIXQ/runs/quick/260701-cited/NOTE.md" "$FIXQ/runs/quick/260701-orphan/NOTE.md"
printf '# RUN-REPORT\n' > "$FIXQ/runs/260922-q-r1/RUN-REPORT.md"
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n| OBL-T-80 | x | PO | advisory | s | d | ev:file{runs/quick/260701-cited/NOTE.md} |\n' > "$FIXQ/docs/GAPS.md"
assert_rejects "an UNCITED stale stub is still listed for deletion (DEV-R11-09 control)" "$FIXQ" \
  "260701-orphan" gate-7 --run 260922-q-r1
assert_output "a CITED stale stub is retained and says who cites it (DEV-R11-09)" "$FIXQ" \
  "260701-cited/NOTE.md is empty and 60 days old but CITED by docs/GAPS.md:3" gate-7 --run 260922-q-r1
finish
