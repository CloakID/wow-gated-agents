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
finish
