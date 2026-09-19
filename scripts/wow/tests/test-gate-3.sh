#!/usr/bin/env bash
# GATE-3 negative test: a COMPLETED row without evidence, a FAILED row without
# evidence of failure, a reference-class status with no reference, a bare
# done-word used as a status, a status word outside the vocabulary and a
# malformed citation must all be rejected.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-3"

printf '| REQ-001 | thing | COMPLETED | |\n' > "$FIX/docs/r-noev.md"
assert_rejects "COMPLETED without ev:" "$FIX" "without an ev: citation" gate-3 --paths docs/r-noev.md

# FORMATS §4 promises "FAILED (ev of failure)". Gating only COMPLETED left half
# of the vocabulary's evidence rule unenforced.
printf '| REQ-001 | thing | FAILED | |\n' > "$FIX/docs/r-failed.md"
assert_rejects "FAILED without evidence of failure" "$FIX" "without an ev: citation" \
  gate-3 --paths docs/r-failed.md

printf '| REQ-001 | thing | PARKED | no reason given |\n' > "$FIX/docs/r-parked.md"
assert_rejects "PARKED with no park record ref" "$FIX" "park record ref" gate-3 --paths docs/r-parked.md

printf '| T01 | done | |\n' > "$FIX/docs/r-done.md"
assert_rejects "bare done-word as status" "$FIX" "done-word" gate-3 --paths docs/r-done.md

printf '| REQ-002 | thing | SHIPPED | |\n' > "$FIX/docs/r-synonym.md"
assert_rejects "status word outside the vocabulary" "$FIX" "not in the status vocabulary" gate-3 --paths docs/r-synonym.md

# The premise check: an ev: that cites nothing checkable satisfies the letter of
# the gate and defeats its purpose.
printf '| REQ-001 | thing | COMPLETED | ev:cmd{i ran it and it was fine} |\n' > "$FIX/docs/r-badev.md"
assert_rejects "COMPLETED with a malformed ev:cmd" "$FIX" "malformed citation" gate-3 --paths docs/r-badev.md

printf '| A | BLOCKED(cascade:) | see U1 |\n' > "$FIX/docs/r-cascade.md"
assert_rejects "malformed cascade form" "$FIX" "is not the cascade form" gate-3 --paths docs/r-cascade.md

printf '| REQ-001 | thing | COMPLETED | ev:commit{abc1234} |\n' > "$FIX/docs/r-ok.md"
assert_accepts "COMPLETED with ev:" "$FIX" gate-3 --paths docs/r-ok.md

printf '| REQ-003 | thing | OPEN | |\n' > "$FIX/docs/r-open.md"
assert_accepts "OPEN needs no ev:" "$FIX" gate-3 --paths docs/r-open.md

printf '| A | BLOCKED(cascade:U1) | blocked by PARK-U1-01 |\n' > "$FIX/docs/r-cascade-ok.md"
assert_accepts "well-formed cascade with a reference" "$FIX" gate-3 --paths docs/r-cascade-ok.md

# Checking every cell of every table made ordinary words in a Done-means or
# Verify column read as forbidden synonyms. With a header row, only the status
# column is checked.
printf '| Task | Verify | Status | Done-means |\n|---|---|---|---|\n| T01 | `test.sh` | COMPLETED ev:commit{abc1234} | exit 0, OK |\n' \
  > "$FIX/docs/r-header.md"
assert_accepts "'OK' in a Done-means column of a table with a Status header" "$FIX" \
  gate-3 --paths docs/r-header.md

# ---- PF-a (pilot #2, v0.6.1): inline code is a mention, not a claim ---------
# A self-describing doc (a registry documenting its own citation conventions in
# backticks) was red before any work existed. Templates in inline code must not
# be flagged...
printf 'Evidence citations follow FORMATS (`ev:cmd{... => ... @ISO}`, `ev:commit{sha}`, `ev:jira{KEY}`).\n' > "$FIX/docs/r-mention.md"
assert_accepts "backticked citation templates are mentions, not claims (PF-a)" "$FIX" \
  gate-3 --paths docs/r-mention.md

# ...and fail-safe the other way: a backticked citation cannot SATISFY a status.
printf '| REQ-001 | thing | COMPLETED | `ev:commit{abc1234}` |\n' > "$FIX/docs/r-mention-ev.md"
assert_rejects "a backticked citation cannot satisfy a status (PF-a)" "$FIX" "without an ev: citation" \
  gate-3 --paths docs/r-mention-ev.md

# ---- F-10 (v0.6.2): a verdict is not a status -------------------------------
# P3 mandates the verifier grade; pre-fix, following the playbook produced 56
# GATE-3 hits. A Grade/Verdict column is checked against verdict_vocab.
printf '| Unit | Grade | Notes |\n|---|---|---|\n| U1 | PASS | clean |\n' > "$FIX/docs/r-verdict.md"
assert_accepts "PASS in a Grade column is a verdict, not a synonym (F-10)" "$FIX" gate-3 --paths docs/r-verdict.md

printf '| Unit | Grade | Notes |\n|---|---|---|\n| U1 | FAIL | broke |\n' > "$FIX/docs/r-vfail.md"
assert_rejects "FAIL verdict without a VF id" "$FIX" "without a verifier-finding reference" gate-3 --paths docs/r-vfail.md

printf '| Unit | Grade | Notes |\n|---|---|---|\n| U1 | FAIL | VF-U1-01 |\n' > "$FIX/docs/r-vfail-ok.md"
assert_accepts "FAIL verdict carrying its VF record" "$FIX" gate-3 --paths docs/r-vfail-ok.md

printf '| Unit | Grade | Notes |\n|---|---|---|\n| U1 | PASS-with-carry-forwards | see notes |\n' > "$FIX/docs/r-vcf.md"
assert_rejects "PASS-w-CF verdict without a CV id" "$FIX" "without a cannot-validate reference" gate-3 --paths docs/r-vcf.md

printf '| Unit | Grade | Notes |\n|---|---|---|\n| U1 | SHIPPED | - |\n' > "$FIX/docs/r-vbad.md"
assert_rejects "a non-verdict word in a Grade column" "$FIX" "not in the verdict vocabulary" gate-3 --paths docs/r-vbad.md

# PASS outside a Grade/Verdict column stays a forbidden synonym (control).
printf '| REQ-001 | thing | PASS | |\n' > "$FIX/docs/r-passloose.md"
assert_rejects "PASS outside a verdict column is still a synonym (control)" "$FIX" "not in the status vocabulary" gate-3 --paths docs/r-passloose.md

# ---- braces (v0.6.2): the body admits one level of balanced braces ----------
printf "| REQ-001 | thing | COMPLETED | ev:cmd{awk '{print \$2}' f => 3 rows @2026-08-24} |\n" > "$FIX/docs/r-awk.md"
assert_accepts "awk action block inside a citation body" "$FIX" gate-3 --paths docs/r-awk.md

printf '| REQ-001 | thing | COMPLETED | ev:cmd{jq -e picked {a:{b:1}} shape => ok @2026-08-24} |\n' > "$FIX/docs/r-nest2.md"
assert_rejects "two-level nesting: the diagnostic names the format, not the writer" "$FIX" "cannot be expressed" gate-3 --paths docs/r-nest2.md

# ---- F-05 (v0.6.3): the mask is document-wide — spans may wrap a line break --
printf '> span `id | tag | owner |\n> more` and templates (`ev:cmd{x => y @ISO}`, `ev:jira{KEY}`)\n' > "$FIX/docs/r-wrapspan.md"
assert_accepts "code span wrapping a line break stays a mention (F-05)" "$FIX" gate-3 --paths docs/r-wrapspan.md
# ...and a stray unpaired backtick must not mask a genuine bare malformed citation.
printf 'stray ` here\n| REQ-001 | x | COMPLETED | ev:cmd{no arrow here} |\n' > "$FIX/docs/r-stray.md"
assert_rejects "unpaired backtick does not hide a malformed citation (F-05 control)" "$FIX" "malformed citation" gate-3 --paths docs/r-stray.md

# ---- F-27 (v0.6.3): unknown ev: kinds fail loudly; ev:attest exists ---------
printf '| T01 | COMPLETED | ev:po-attest{PO: approved @2026-08-24} |\n' > "$FIX/docs/r-unkind.md"
assert_rejects "an invented evidence kind is a loud failure, not invisible (F-27)" "$FIX" "unknown evidence kind" gate-3 --paths docs/r-unkind.md
printf '| T01 | COMPLETED | ev:attest{PO: read the row and declined the next statement @2026-08-24} |\n' > "$FIX/docs/r-attest.md"
assert_accepts "ev:attest records a human decision as itself (F-27)" "$FIX" gate-3 --paths docs/r-attest.md
printf '| T01 | COMPLETED | ev:attest{no who separator @2026-08-24} |\n' > "$FIX/docs/r-attest-bad.md"
assert_rejects "attest without the who: separator is malformed" "$FIX" "malformed citation" gate-3 --paths docs/r-attest-bad.md

# ---- F-14 (v0.6.3): an ungradeable status-shaped cell must not pass quietly --
printf '| T03 | COMPLETED — verdict NO on both instances | prose |\n' > "$FIX/docs/r-ungradeable.md"
assert_rejects "status token + trailing prose is ungradeable, not invisible (F-14)" "$FIX" "not a bare status" gate-3 --paths docs/r-ungradeable.md
# Sanctioned shapes stay legal: status + citation, status + reference id.
printf '| T04 | COMPLETED ev:commit{abc1234} | done cell |\n| T05 | PARKED PARK-U1-01 | note |\n' > "$FIX/docs/r-gradeable.md"
assert_accepts "status + citation / + reference in one cell stay legal (F-14 control)" "$FIX" gate-3 --paths docs/r-gradeable.md

# ---- F-20 residual: bare FAIL outside a verdict column is caught, with a map -
printf '| T01 | task went | FAIL | |\n' > "$FIX/docs/r-fail-loose.md"
assert_rejects "bare FAIL outside a Grade/Verdict column" "$FIX" "Grade/Verdict header" gate-3 --paths docs/r-fail-loose.md

# ---- F-41 (v0.7.1): a backticked cell in a checked-in-full table is a mention
# The run's most important comparison — "executor wrote COMPLETED, verifier
# graded FAIL" — was unwritable in any scanned doc: a verdict-comparison table
# has no Status header, so every cell was checked, and the quoted words read
# as forbidden synonyms.
printf '| 260813-x-r1.T04 | executor wrote | \x60COMPLETED\x60 | verifier graded | \x60FAIL\x60 |\n' > "$FIX/docs/r-vcomp.md"
assert_accepts "verdict-comparison table with backticked statuses is sayable (F-41)" "$FIX" \
  gate-3 --paths docs/r-vcomp.md
# Control 1: a Status COLUMN keeps claims-by-position — a backticked status
# cannot green a real row.
printf '| Task | Status | Notes |\n|---|---|---|\n| T01 | \x60COMPLETED\x60 | no ev anywhere |\n' > "$FIX/docs/r-vcomp-status.md"
assert_rejects "backticked status in a Status column is still a claim (F-41 control)" "$FIX" \
  "without an ev: citation" gate-3 --paths docs/r-vcomp-status.md
# Control 2: an UNbackticked status in a headerless table is still checked —
# the mention rule must not have opened a hole for real rows.
printf '| T09 | COMPLETED | no citation |\n' > "$FIX/docs/r-vcomp-bare.md"
assert_rejects "bare status in a headerless table is still a claim (F-41 control)" "$FIX" \
  "without an ev: citation" gate-3 --paths docs/r-vcomp-bare.md

# ---- F-14 addendum (v0.7.2): a DECLARED status section holding a table with
# no status column was graded by nothing — the cheapest silent shape, written
# by giving the table its most natural columns. The gate knows the section is
# a status section before it reads a row.
mkdir -p "$FIX/runs/260916-x-r1"
cat > "$FIX/runs/260916-x-r1/RUN-REPORT.md" <<'R'
## defects

| id | what |
|---|---|
| DEF-plan-01 | consolidated harness collided |
R
assert_rejects "status section whose table has no gradeable column (F-14 addendum)" "$FIX" \
  "graded by NOTHING" gate-3 --paths runs/260916-x-r1/RUN-REPORT.md
# Controls: the same section with a Status column is clean; a NON-status
# section keeps its natural columns without complaint.
cat > "$FIX/runs/260916-x-r1/RUN-REPORT.md" <<'R'
## defects

| id | status | reference |
|---|---|---|
| DEF-plan-01 | OPEN | |

## pointers

| id | what |
|---|---|
| M-1 | manifest ref |
R
assert_accepts "status column present / natural columns outside declared sections (controls)" \
  "$FIX" gate-3 --paths runs/260916-x-r1/RUN-REPORT.md

# ---- prodsim/F-68 / OBL-PKG-23 (v0.7.3): ev:commit shas RESOLVE, blocking in
# the run tree, advisory in durable docs. Four well-formed false citations
# shipped in one pilot run; git cat-file settles each in O(1).
GOODSHA="$( cd "$FIX" && git rev-parse --short=7 HEAD )"
printf '| T01 | COMPLETED | ev:commit{%s} |\n' "$GOODSHA" > "$FIX/runs/260916-x-r1/reports/ok.md" 2>/dev/null || { mkdir -p "$FIX/runs/260916-x-r1/reports"; printf '| T01 | COMPLETED | ev:commit{%s} |\n' "$GOODSHA" > "$FIX/runs/260916-x-r1/reports/ok.md"; }
assert_accepts "resolvable sha in a run report (F-68 control)" "$FIX" \
  gate-3 --paths runs/260916-x-r1/reports/ok.md
printf '| T02 | COMPLETED | ev:commit{beef042} |\n' > "$FIX/runs/260916-x-r1/reports/bad.md"
assert_rejects "dangling sha in a run report is BLOCKING (F-68)" "$FIX" \
  "does NOT resolve" gate-3 --paths runs/260916-x-r1/reports/bad.md
printf 'History: shipped in ev:commit{beef042} before the rewrite. | T03 | OPEN | |\n' > "$FIX/docs/old-history.md"
assert_accepts "dangling sha in a durable doc is ADVISORY, not blocking (F-68/ADV-2)" "$FIX" \
  gate-3 --paths docs/old-history.md
assert_output "the advisory names itself" "$FIX" "advisory outside runs/" \
  gate-3 --paths docs/old-history.md

# ---- prodsim/F-72 (v0.7.3): the doc-wide mask may not pair across table rows.
# One stray tick used to blank the NEXT row's citation, and GATE-3 reported
# real evidence as missing.
printf '| a\x60 | fine |\n| T04 | COMPLETED ev:commit{%s} |\n| b\x60 | fine |\n' "$GOODSHA" > "$FIX/docs/r-straytick.md"
assert_accepts "stray tick no longer eats the next row's citation (F-72)" "$FIX" \
  gate-3 --paths docs/r-straytick.md

# ---- prodsim/F-66 (v0.7.3): DEV-ORCH-<nn> is a legal reference id.
printf '| T05 | PARKED | DEV-ORCH-01 |\n' > "$FIX/docs/r-orchdev.md"
assert_accepts "DEV-ORCH id satisfies the reference rule (prodsim/F-66)" "$FIX" \
  gate-3 --paths docs/r-orchdev.md

# ---- platform/F-65 (v0.7.3): runs/archive is out of gate-3's scan by default
# — an archived run is graded under the vocabulary of its time (492 of 512
# findings in one upgrade were archive-only noise).
mkdir -p "$FIX/runs/archive/250101-old-r1"
printf '| T01 | SHIPPED | no citation |\n' > "$FIX/runs/archive/250101-old-r1/RUN-REPORT.md"
assert_accepts "archived run is not re-graded under a newer vocabulary (platform/F-65)" "$FIX" \
  gate-3 --paths runs/archive/250101-old-r1/RUN-REPORT.md

# ---- prodsim/F-70 fix 2 (v0.7.3): a PASS states its subject count.
assert_output "PASS reports its subject count" "$FIX" "subject: 1 document(s)" \
  gate-3 --paths docs/r-ok.md
assert_output "a green over an empty set says VACUOUS" "$FIX" "VACUOUS" \
  gate-3 --paths runs/archive/250101-old-r1/RUN-REPORT.md
# ---- ADV-R9-03 (v0.7.3 R9): a FENCED ev:commit quote is a mention -----------
# The F-43 paste rule tells operators to quote gate output verbatim, and the
# F-68 refusal itself contains a literal ev:commit{...} — pasting it used to
# block the commit that quoted it, forever.
mkdir -p "$FIX/runs/260916-x-r1/reports"
cat > "$FIX/runs/260916-x-r1/reports/quoted.md" << R
| T09 | COMPLETED | ev:commit{$GOODSHA} |

The gate refused an earlier draft; its output, verbatim:

\`\`\`
| T99 | COMPLETED | ev:commit{beef0421} |

reports/bad.md:1 cites ev:commit{beef0421} which does NOT resolve
\`\`\`
R
assert_accepts "fenced quote of a dangling sha does not block (ADV-R9-03)" "$FIX" \
  gate-3 --paths runs/260916-x-r1/reports/quoted.md
# control: the same dangling sha OUTSIDE the fence still blocks
printf '| T10 | COMPLETED | ev:commit{beef0421} |\n' >> "$FIX/runs/260916-x-r1/reports/quoted.md"
assert_rejects "the same sha outside the fence still blocks (ADV-R9-03 control)" "$FIX" \
  "does NOT resolve" gate-3 --paths runs/260916-x-r1/reports/quoted.md
rm -f "$FIX/runs/260916-x-r1/reports/quoted.md"

# ---- ADV-R9-08 (v0.7.3 R9): a wrapped code span whose next line is a shell
# pipe (not a table row) stays MASKED — the F-72 boundary demands a second
# unescaped pipe before it refuses to pair across the line break.
printf 'Cited template mention: \`ev:cmd{x\n| y}\` is the shape.\n' > "$FIX/docs/r-wrapped-pipe.md"
assert_accepts "wrapped span crossing onto a shell-pipe line stays a mention (ADV-R9-08)" "$FIX" \
  gate-3 --paths docs/r-wrapped-pipe.md
# control: the F-72 case itself — crossing onto a real TABLE ROW still refuses
# to pair, so a stray tick cannot eat the next row's citation.
assert_accepts "stray tick still cannot eat a real table row (F-72 control)" "$FIX" \
  gate-3 --paths docs/r-straytick.md
# ---- ADV-R10-07 (R9b): tilde fences and indented code are mention channels
# for the ev:commit resolver too.
cat > "$FIX/runs/260916-x-r1/reports/quoted2.md" << R
| T11 | COMPLETED | ev:commit{$GOODSHA} |

The refusal, verbatim:

~~~
reports/bad.md:1 cites ev:commit{beef0421} which does NOT resolve
~~~

And the offending row, indented as code:

    | T99 | COMPLETED | ev:commit{beef0421} |
R
assert_accepts "~~~-fenced and indented dangling-sha quotes do not block (ADV-R10-07)" "$FIX" \
  gate-3 --paths runs/260916-x-r1/reports/quoted2.md
rm -f "$FIX/runs/260916-x-r1/reports/quoted2.md"
finish
