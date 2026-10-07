#!/usr/bin/env bash
# GATE-15 negative test (v0.7.5.1, PO trait "the ORCH is a router, not a reader"):
# an agent report must open with a bounded `## hand-back` (verdict · ids ·
# pointers · parked, ≤ max_lines / max_chars, no paste) that the ORCH reads
# INSTEAD of the body, and the hand-back must be FAITHFUL to the rows beneath
# it (R13b: ADV-R13-01..04, DEV-R13-01/03/04/08). A report without one, over
# the bound, missing a field, carrying a paste, naming ids the body lacks,
# omitting ids the body defines, or saying PASS over a FAIL row is refused; a
# conforming one passes; an archived run adds nothing outside --p5 and is
# graded from the archive at --p5; a missing run is never a pass.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-15"

RUN=261007-hb-r1
mkdir -p "$FIX/runs/$RUN/reports"
printf '# RUN-REPORT\n' > "$FIX/runs/$RUN/RUN-REPORT.md"
cat > "$FIX/runs/$RUN/reports/U1.md" <<'R'
# U1 — executor report

## hand-back
- verdict: all 3 tasks COMPLETED
- ids: DEV-U1-01, PARK-U1-01
- pointers: reports/U1.md#t01, evidence/U1/t01.log
- parked: PARK-U1-01 (cross-unit: U2's contract)

| id | Status | ev |
|---|---|---|
| 261007-hb-r1.T01 | COMPLETED | ev:cmd{pytest -q => 0 @2026-10-07T10:00:00Z} |

## deviations
- DEV-U1-01 — renamed the helper; no interface change
## parks
- PARK-U1-01 — U2's contract names a field the fixture lacks
R
assert_accepts "a report opening with a bounded hand-back passes; a table after a blank line is body (control, DEV-R13-01)" "$FIX" gate-15 --run $RUN
assert_output "the subject is stated" "$FIX" "subject: 1 agent report(s)" gate-15 --run $RUN

cat > "$FIX/runs/$RUN/reports/U2-verify.md" <<'R'
# U2 verify

## Findings
- VF-U2-01 — something
R
assert_rejects "a report with NO hand-back section is refused" "$FIX" \
  "U2-verify.md has no \`## hand-back\` section" gate-15 --run $RUN

printf '# U2 verify\n\n## Hand-Back (U2)\n- verdict: FAIL\n- ids: VF-U2-01\n- pointers: x\n- parked: none\n\n## Findings\n- VF-U2-01 — x\n' > "$FIX/runs/$RUN/reports/U2-verify.md"
assert_rejects "a near-miss heading is named with its line (DEV-R13-08)" "$FIX" \
  "line 3 \`## Hand-Back (U2)\` resembles one" gate-15 --run $RUN
printf '# U2 verify\n\n## Hand-back\n- verdict: FAIL\n- ids: VF-U2-01\n- pointers: x\n- parked: none\n\n## Findings\n- VF-U2-01 — x\n' > "$FIX/runs/$RUN/reports/U2-verify.md"
assert_accepts "the heading is case-insensitive (DEV-R13-08)" "$FIX" gate-15 --run $RUN

printf '# U2 verify\n\n## hand-back\n- verdict: FAIL (VF-U2-01)\n- ids: VF-U2-01\n- pointers: reports/U2-verify.md#findings\n\n## Findings\n- VF-U2-01 — x\n' > "$FIX/runs/$RUN/reports/U2-verify.md"
assert_rejects "a hand-back missing a required field is refused, naming it" "$FIX" \
  "has no \`parked:\` line" gate-15 --run $RUN

{ printf '# U2 verify\n\n## hand-back\n- verdict: FAIL\n- ids: VF-U2-01\n- pointers: x\n- parked: none\n'; for i in $(seq 1 20); do printf -- '- detail line %s\n' "$i"; done; printf '\n## Findings\n- VF-U2-01 — x\n'; } > "$FIX/runs/$RUN/reports/U2-verify.md"
assert_rejects "a hand-back over the line bound is refused" "$FIX" \
  "non-blank line(s), over the 20-line bound" gate-15 --run $RUN

python3 - "$FIX/runs/$RUN/reports/U2-verify.md" <<'PY'
import sys
p = sys.argv[1]
long = "x" * 600
open(p, "w").write("# U2 verify\n\n## hand-back\n- verdict: FAIL %s\n- ids: VF-U2-01 %s\n- pointers: %s\n- parked: none %s\n\n## Findings\n- VF-U2-01 — x\n" % (long, long, long, long))
PY
assert_rejects "a hand-back over the byte bound is refused — long lines are a body (ADV-R13-02)" "$FIX" \
  "bytes, over the 2000-byte bound" gate-15 --run $RUN

printf '# U2 verify\n\n## hand-back\n- verdict: FAIL\n- ids: VF-U2-01\n- pointers: x\n- parked: none\n```\n$ pytest\n1 failed\n```\n\n## Findings\n- VF-U2-01 — x\n' > "$FIX/runs/$RUN/reports/U2-verify.md"
assert_rejects "a paste (fence) inside the hand-back is refused" "$FIX" \
  "hand-back carries a fenced block" gate-15 --run $RUN

printf '# U2 verify\n\n## hand-back\n- verdict: FAIL\n- ids: VF-U2-01\n- pointers: x\n- parked: none\n\n    $ pytest\n    1 failed\n\n## Findings\n- VF-U2-01 — x\n' > "$FIX/runs/$RUN/reports/U2-verify.md"
assert_accepts "an indented paste after a blank line is BODY — the blank ends the section (ADV-R13-03 under the DEV-R13-01 end rule)" "$FIX" gate-15 --run $RUN

printf '# U2 verify\n\nSome preamble the ORCH would have to read.\nMore preamble.\n\n## hand-back\n- verdict: FAIL\n- ids: VF-U2-01\n- pointers: x\n- parked: none\n\n## Findings\n- VF-U2-01 — x\n' > "$FIX/runs/$RUN/reports/U2-verify.md"
assert_rejects "a hand-back not at the top is refused" "$FIX" \
  "is not at the top" gate-15 --run $RUN
printf -- '---\nunit: U2\nmode: re-derive\n---\n# U2 verify\n\n\n## hand-back\n- verdict: FAIL\n- ids: VF-U2-01\n- pointers: x\n- parked: none\n\n## Findings\n- VF-U2-01 — x\n' > "$FIX/runs/$RUN/reports/U2-verify.md"
assert_accepts "front matter and blank lines above the heading do not count (ADV-R13-12)" "$FIX" gate-15 --run $RUN

printf '# U2 verify\n\n<!--\n## hand-back\n- verdict: FAIL\n- ids: VF-U2-01\n- pointers: x\n- parked: none\n-->\n## Findings\n- VF-U2-01 — x\n' > "$FIX/runs/$RUN/reports/U2-verify.md"
assert_rejects "a hand-back inside an HTML comment renders as nothing and is no hand-back (ADV-R13-13)" "$FIX" \
  "has no \`## hand-back\` section" gate-15 --run $RUN

cat > "$FIX/runs/$RUN/reports/U2-verify.md" <<'R'
# U2 verify

## hand-back
**verdict**: FAIL (VF-U2-01)
**ids**: VF-U2-01
**pointers**: reports/U2-verify.md#findings
**parked**: none

## Grades
| unit | Grade | ref |
|---|---|---|
| U2 | FAIL | VF-U2-01 |

## Findings
- VF-U2-01 — x
R
assert_accepts "bold field names and no list markers are fine (control)" "$FIX" gate-15 --run $RUN
assert_accepts "--paths names the files directly (the agent's self-check)" "$FIX" \
  gate-15 --paths runs/$RUN/reports/U2-verify.md

# ---- R13b: fields are read, not only present (ADV-R13-04)
printf '# U2 verify\n\n## hand-back\n- verdict:\n- ids: VF-U2-01\n- pointers: x\n- parked: none\n\n## Findings\n- VF-U2-01 — x\n' > "$FIX/runs/$RUN/reports/U2-verify.md"
assert_rejects "an empty field value is refused — write none (ADV-R13-04)" "$FIX" \
  "\`verdict:\` is empty" gate-15 --run $RUN
printf '# U2 verify\n\n## hand-back\n- verdict: FAIL\n- ids: see below\n- pointers: x\n- parked: none\n\n## Findings\n- VF-U2-01 — x\n' > "$FIX/runs/$RUN/reports/U2-verify.md"
assert_rejects "ids: with prose and no id is refused (ADV-R13-04)" "$FIX" \
  "\`ids:\` names no deviation/park/verifier_finding/cannot_validate/plan_defect id" gate-15 --run $RUN
printf '# U2 verify\n\n## hand-back\n- verdict: FAIL\n- ids: VF-U2-01, CV-26\n- pointers: x\n- parked: none\n\n## Findings\n- VF-U2-01 — x (CV-26)\n' > "$FIX/runs/$RUN/reports/U2-verify.md"
assert_rejects "an id-shaped token matching no family (a shorthand) is refused (ADV-R13-04)" "$FIX" \
  "id-shaped token(s) that match no id family: CV-26" gate-15 --run $RUN
printf '# U1\n\n## hand-back\n- verdict: all COMPLETED\n- ids: none\n- pointers: x\n- parked: blocked on the PO\n\n## T01\n| id | Status | ev |\n|---|---|---|\n| 261007-hb-r1.T01 | COMPLETED | ev:cmd{true => 0 @2026-10-07} |\n' > "$FIX/runs/$RUN/reports/U1.md"
assert_rejects "parked: with prose and no PARK id is refused (ADV-R13-04)" "$FIX" \
  "\`parked:\` names no park id" gate-15 --paths runs/$RUN/reports/U1.md

# ---- R13b: fidelity to the rows beneath (ADV-R13-01, DEV-R13-03)
cat > "$FIX/runs/$RUN/reports/U2-verify.md" <<'R'
# U2 verify

## hand-back
- verdict: PASS
- ids: none
- pointers: reports/U2-verify.md#grades
- parked: none

## Grades
| unit | Grade | ref |
|---|---|---|
| U2 | FAIL | VF-U2-01 |

## Findings
- VF-U2-01 — the check passes on an empty input
- VF-U2-02 — the capture is not byte-equal
R
assert_rejects "PASS over a FAIL grade row is refused (ADV-R13-01)" "$FIX" \
  "body carries a FAIL row and the hand-back \`verdict:\` (PASS) does not say FAIL" gate-15 --run $RUN
assert_rejects "ids the body defines and the hand-back omits are named (ADV-R13-01)" "$FIX" \
  "body defines VF-U2-02 and the hand-back \`ids:\` does not name it" gate-15 --run $RUN
printf '# U2 verify\n\n## hand-back\n- verdict: FAIL\n- ids: VF-U2-01, VF-U2-09\n- pointers: x\n- parked: none\n\n## Grades\n| unit | Grade | ref |\n|---|---|---|\n| U2 | FAIL | VF-U2-01 |\n\n## Findings\n- VF-U2-01 — x\n' > "$FIX/runs/$RUN/reports/U2-verify.md"
assert_rejects "an id the hand-back names and the body never carries is refused (ADV-R13-01)" "$FIX" \
  "\`ids:\` names VF-U2-09 and the body never carries it" gate-15 --run $RUN
printf '# U1\n\n## hand-back\n- verdict: all COMPLETED\n- ids: none\n- pointers: x\n- parked: none\n\n## T01\n| id | Status | ev |\n|---|---|---|\n| 261007-hb-r1.T01 | COMPLETED | ev:cmd{true => 0 @2026-10-07} |\n| 261007-hb-r1.T02 | BLOCKED | PARK-U1-01 |\n' > "$FIX/runs/$RUN/reports/U1.md"
assert_rejects "all COMPLETED over a BLOCKED status row is refused (DEV-R13-03)" "$FIX" \
  "body carries a BLOCKED row and the hand-back \`verdict:\` (all COMPLETED) does not say BLOCKED" gate-15 --paths runs/$RUN/reports/U1.md
printf '# U1\n\n## hand-back\n- verdict: all COMPLETED\n- ids: none\n- pointers: x\n- parked: none\n| id | Status | ev |\n|---|---|---|\n| 261007-hb-r1.T02 | FAILED | ev:cmd{false => 1 @2026-10-07} |\n' > "$FIX/runs/$RUN/reports/U1.md"
assert_rejects "a status table left INSIDE the section (no blank line) is still rows: FAILED unnamed in verdict is refused" "$FIX" \
  "body carries a FAILED row and the hand-back \`verdict:\` (all COMPLETED) does not say FAILED" gate-15 --paths runs/$RUN/reports/U1.md
printf '# U2 verify\n\n## hand-back\n- verdict: PASS-with-carry-forwards\n- ids: CV-261007-hb-r1-U2-01\n- pointers: x\n- parked: none\n\n## Grades\n| unit | Grade | ref |\n|---|---|---|\n| U2 | PASS-with-carry-forwards | CV-261007-hb-r1-U2-01 |\n\n## cv\n- CV-261007-hb-r1-U2-01 — live leg unavailable\n' > "$FIX/runs/$RUN/reports/U2-verify.md"
printf '# U1\n\n## hand-back\n- verdict: all COMPLETED\n- ids: none\n- pointers: x\n- parked: none\n\n## T01\n| id | Status | ev |\n|---|---|---|\n| 261007-hb-r1.T01 | COMPLETED | ev:cmd{true => 0 @2026-10-07} |\n' > "$FIX/runs/$RUN/reports/U1.md"
assert_accepts "a faithful carry-forward hand-back passes (control)" "$FIX" gate-15 --run $RUN

# ---- delegate reports (FORMATS §14 home) are graded too (ADV-R13-07, DEV-R13-04)
mkdir -p "$FIX/runs/$RUN/orch"
printf '# triage 1\n\nfailures grouped by gate\n' > "$FIX/runs/$RUN/orch/triage-1.md"
assert_rejects "a delegate report under orch/<role>-<n>.md without a hand-back is refused" "$FIX" \
  "orch/triage-1.md has no \`## hand-back\`" gate-15 --run $RUN
printf '# cascade record\n\nU3 blocked on U1\n' > "$FIX/runs/$RUN/orch/cascade-2.md"
printf '# triage 1\n\n## hand-back\n- verdict: 3 failures, 2 gates\n- ids: none\n- pointers: orch/triage-1.md#by-gate\n- parked: none\n\n## by gate\n- gate-3: U1.md:12 — cite the capture\n' > "$FIX/runs/$RUN/orch/triage-1.md"
assert_accepts "an ORCH record under orch/ that is not a delegate role needs no hand-back (control)" "$FIX" gate-15 --run $RUN
assert_output "the subject counts delegate reports" "$FIX" "subject: 3 agent report(s)" gate-15 --run $RUN

# ---- DEV-R13-02 (R13b): `sweep --summary` withholds the failure list from the ORCH
printf '# other\nno hand-back here\n' > "$FIX/runs/$RUN/orch/triage-2.md"
SUM_OUT="$( cd "$FIX" && scripts/wow/gates.sh sweep --summary --run $RUN 2>&1 )"; SUM_RC=$?
LOGP="$( printf '%s\n' "$SUM_OUT" | sed -n 's/^full output: \([^ ]*\).*/\1/p' )"
if [ "$SUM_RC" -ne 0 ] && printf '%s' "$SUM_OUT" | grep -q "^FAIL gate-15" \
   && ! printf '%s' "$SUM_OUT" | grep -q "has no \`## hand-back\`" \
   && [ -n "$LOGP" ] && grep -q "has no \`## hand-back\`" "$LOGP"; then
  echo "  ok   sweep --summary prints PASS/FAIL + subject lines only; the failure list goes to the named log (DEV-R13-02)"; PASS=$((PASS+1))
else
  echo "  FAIL sweep --summary leaked or lost the failure list (DEV-R13-02)"; printf '%s\n' "$SUM_OUT" | sed 's/^/       /'; FAIL=$((FAIL+1))
fi
printf '%s' "$SUM_OUT" | grep -q "subject: 4 agent report(s)" \
  && { echo "  ok   --summary keeps the subject counts (vacuity stays visible)"; PASS=$((PASS+1)); } \
  || { echo "  FAIL --summary dropped the subject line"; FAIL=$((FAIL+1)); }
rm -f "$FIX/runs/$RUN/orch/triage-2.md"

# ---- scope
mkdir -p "$FIX/runs/archive/260901-old-r1/reports"
printf '# old\nno hand-back here\n' > "$FIX/runs/archive/260901-old-r1/reports/U1.md"
assert_accepts "an archived run adds nothing outside --p5 and says so (platform/F-65)" "$FIX" gate-15 --run 260901-old-r1
assert_rejects "at --p5 the archived run IS graded from the archive (DEV-R13-13)" "$FIX" \
  "archive/260901-old-r1/reports/U1.md has no" gate-15 --p5 --run 260901-old-r1
assert_rejects "a missing run is never a pass (ADV-R9-06)" "$FIX" "names no directory" gate-15 --run 269999-ghost-r1
assert_accepts "unscoped: every active run's reports" "$FIX" gate-15
mkdir -p "$FIX/runs/261007-other-r1/reports"
printf '# other\nno hand-back here\n' > "$FIX/runs/261007-other-r1/reports/U1.md"
assert_accepts "--run scopes to the named run: another active run's bad report is not its business" "$FIX" \
  gate-15 --run $RUN
assert_rejects "unscoped, the other run's report is refused and NAMED" "$FIX" \
  "261007-other-r1/reports/U1.md has no" gate-15
printf '# other\n## hand-back\n\n## body\nstuff\n' > "$FIX/runs/261007-other-r1/reports/U1.md"
assert_rejects "a hand-back heading with nothing under it is refused — all four fields named" "$FIX" \
  "has no \`verdict:\` line" gate-15 --paths runs/261007-other-r1/reports/U1.md
assert_rejects "… and the last field too" "$FIX" \
  "has no \`parked:\` line" gate-15 --paths runs/261007-other-r1/reports/U1.md
finish
