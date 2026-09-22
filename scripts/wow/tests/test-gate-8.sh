#!/usr/bin/env bash
# GATE-8 negative test: overlapping unit ownership, a unit claiming an ORCH-owned
# file, a task with no verify command, and a non-total coverage matrix must each
# block review.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-8"

mkdir -p "$FIX/docs/spec" "$FIX/runs/260813-x-r1" "$FIX/src"
printf '# SPEC\n\n| AC | Criterion | Check |\n|---|---|---|\n| AC-1 | a | `c` |\n| AC-2 | b | `c` |\n' \
  > "$FIX/docs/spec/SPEC-x-v1.md"
printf 'a\n' > "$FIX/src/a.py"; printf 'b\n' > "$FIX/src/b.py"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "src [WOW:publish]" )

plan() { cat > "$FIX/runs/260813-x-r1/PLAN.md"; }

plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | a works |

### U2 — second
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T02 | do b | `pytest b` | b works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T02 |
P
assert_rejects "two units own the same file" "$FIX" "both own" gate-8 --run 260813-x-r1

plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- runs/260813-x-r1/PLAN.md
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | a works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_rejects "unit claims an ORCH-owned file" "$FIX" "claims ORCH-owned path" gate-8 --run 260813-x-r1

plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | - | a works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_rejects "task with no verify command" "$FIX" "has no verify command" gate-8 --run 260813-x-r1

plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | a works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
P
assert_rejects "coverage matrix misses AC-2" "$FIX" "not total" gate-8 --run 260813-x-r1

plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | a works |

### U2 — second
owns:
- src/b.py
tier: mid
wave: 2
autonomy: park on cross-unit

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T02 | do b | `pytest b` | b works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T02 |
P
assert_accepts "well-formed plan" "$FIX" gate-8 --run 260813-x-r1

# The premise check: totality was measured against ACs parsed from spec tables.
# A spec that states its ACs as bullets yielded an empty AC set, and "every AC
# mapped" was then vacuously true.
printf '# SPEC\n\n## Acceptance criteria\n- AC-1: the thing works\n- AC-2: the other thing\n' \
  > "$FIX/docs/spec/SPEC-y-v1.md"
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-y-v1.md

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | a works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
P
assert_rejects "spec declares no parseable ACs" "$FIX" "declares no parseable AC rows" \
  gate-8 --run 260813-x-r1

# ...and the verify column was read by position, so a plan that ordered its
# columns differently shipped tasks with an empty Verify cell.
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Done-means | Verify |
|---|---|---|---|
| 260813-x-r1.T01 | do a | it works | |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_rejects "empty Verify column, columns not in schema order" "$FIX" "has no verify command" \
  gate-8 --run 260813-x-r1

plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py
tier: enormous
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | a works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_rejects "tier outside the schema enum" "$FIX" "is not one of" gate-8 --run 260813-x-r1

plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | a works |
P
assert_rejects "PLAN missing required sections" "$FIX" "required_sections" gate-8 --run 260813-x-r1

# ---- F-13 (v0.6.3): a plan with units and ZERO parsed tasks fails loudly ----
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means |
|---|---|---|---|
| T01 | do a | `pytest a` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | T01 |
| AC-2 | T01 |
P
# (engine round 6, OBL-PKG-20): admission is by TABLE MEMBERSHIP now, so the
# bare-id row is an INVALID TASK, loudly — strictly stronger than the old
# zero-guard: the row's verify is read instead of invisible.
assert_rejects "bare task id is an invalid task, not an invisible row (F-13/OBL-PKG-20)" "$FIX" \
  "is not a fully-qualified task id" gate-8 --run 260813-x-r1

# ...and the blind spot the audit named: a bare id NEXT TO valid siblings used
# to escape every task rule (admission-by-grammar admitted only the valid row).
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | works |
| T7 | stray half-id | `pytest b` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_rejects "malformed id beside valid siblings is caught (audit §5.4)" "$FIX" \
  "is not a fully-qualified task id" gate-8 --run 260813-x-r1

# The zero-guard still has a subject: a unit with NO task table at all.
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

prose instead of a task table

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | none |
| AC-2 | none |
P
assert_rejects "unit with no task table still hits the zero-guard (F-13)" "$FIX" \
  "ZERO parseable task" gate-8 --run 260813-x-r1

# ---- F-28 (v0.6.3): normative language outside units binds nobody ----------
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Amendments

AM-01: executors must never print the credential expansion.

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_rejects "normative rule in an amendment section reaches no manifest (F-28)" "$FIX" \
  "reaches NO executor manifest" gate-8 --run 260813-x-r1

plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Contracts

C-1: executors must never print the credential expansion.

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_accepts "the same rule in the Contracts block is delivered to every manifest (F-28 control)" \
  "$FIX" gate-8 --run 260813-x-r1

# ---- F-18 (v0.6.4): unescaped pipe named as the cause; escaped pipe legal ---
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `cat x.txt | grep -c ok` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_rejects "unescaped pipe reported with the REAL cause, not the wrong cell (F-18)" "$FIX" \
  "unescaped '|' in a cell" gate-8 --run 260813-x-r1

plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `cat x.txt \| grep -c ok` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_accepts "escaped pipe is cell content — a Verify may carry a pipeline (F-18)" "$FIX" \
  gate-8 --run 260813-x-r1

# ---- F-39 (v0.7.1): a task id the trailer grammar cannot express is refused
# at G2 — an edit — not at the first commit, a wave later. `T012` contains a
# legal task id as a substring (so the row IS parsed), but no [T:] trailer can
# ever carry it.
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T012 | do a | `pytest a` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T012 |
| AC-2 | 260813-x-r1.T012 |
P
assert_rejects "task id the trailer grammar cannot express (F-39)" "$FIX" \
  "cannot be expressed as a [T:] trailer" gate-8 --run 260813-x-r1

# Control: the letter-suffix form is exactly what a mid-run split needs, and it
# is now legal — refusing it would re-create the finding the fix answers.
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T07 | do a | `pytest a` | works |
| 260813-x-r1.T07a | split half | `pytest a2` | split works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T07 |
| AC-2 | 260813-x-r1.T07a |
P
assert_accepts "letter-suffix task id is committable and legal (F-39 control)" "$FIX" \
  gate-8 --run 260813-x-r1

# ---- F-58 (v0.7.2): declared cross-unit inputs must be deliverable ----------
# The branch model gives a wave-N unit only waves <N, so an input needs a
# producer at a strictly lower wave — the same-wave case passed seven
# adversarial review rounds before an executor would have hit a missing path.
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — harness
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | build harness | `pytest a` | works |

### U2 — consumer
owns:
- src/b.py
inputs:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T02 | use harness | `bash src/a.py` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T02 |
P
assert_rejects "same-wave producer: input unreachable by construction (F-58)" "$FIX" \
  "not a STRICTLY LOWER wave" gate-8 --run 260813-x-r1

plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | works |

### U2 — consumer
owns:
- src/b.py
inputs:
- src/ghost.py
tier: mid
wave: 2
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T02 | use ghost | `pytest b` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T02 |
P
assert_rejects "input with NO producing unit (F-58)" "$FIX" \
  "NO other unit owns" gate-8 --run 260813-x-r1

# Control: producer a wave earlier — the shape the wave ordering exists for.
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — producer
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | works |

### U2 — consumer
owns:
- src/b.py
inputs:
- src/a.py
tier: mid
wave: 2
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T02 | consume a | `pytest b` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T02 |
P
assert_accepts "input produced a strictly lower wave is deliverable (F-58 control)" "$FIX" \
  gate-8 --run 260813-x-r1

# ---- platform/F-70 (v0.7.3): the F-28 scan read the plan's own HEADER FIELDS
# as stranded normative prose — a signed plan failed its own gate,
# unsatisfiably, from the signing commit on. The scanned region begins at the
# first ## heading; the same sentence in the BODY must still fail.
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md
story-continuity: the framework never offered this choice, so it was never declined

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_accepts "normative word in a HEADER FIELD value is schema, not a rule (platform/F-70)" \
  "$FIX" gate-8 --run 260813-x-r1
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Notes

executors must never print the credential expansion.

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_rejects "the same normative sentence in the BODY still fails (platform/F-70 control)" \
  "$FIX" "reaches NO executor manifest" gate-8 --run 260813-x-r1
# ---- ADV-R9-05 (v0.7.3 R9): the F-70 exemption is header-SHAPED, not
# positional — a normative PROSE paragraph in the preamble (above the first
# ##) reaches no executor either, and skipping the whole preamble had
# reintroduced exactly the F-28 class there.
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

Executors must never write outside their owns list, whatever the brief says.

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_rejects "normative PROSE in the preamble still fails (ADV-R9-05)" \
  "$FIX" "reaches NO executor manifest" gate-8 --run 260813-x-r1
# ---- ADV-R10-05 (R9b): the preamble exemption is by NAME — a rule wearing an
# unlisted 'key: value' costume is still scanned, and the message names the
# preamble_fields remedy for a genuinely descriptive field.
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md
constraint: executors must never write outside their owns list

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_rejects "a rule wearing an unlisted 'key:' costume is scanned (ADV-R10-05)" \
  "$FIX" "preamble_fields" gate-8 --run 260813-x-r1
# ---- platform/F-79 (v0.7.4): a named field's wrapped VALUE stays exempt ----
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md
story-continuity: the framework never offered this choice, so it was
  never declined, only never raised; putting it to the PO is the repair
  and this run must never be read as having skipped it

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_accepts "wrapped named-field value with normative words passes (platform/F-79)" \
  "$FIX" gate-8 --run 260813-x-r1
# control: a prose paragraph AFTER a blank line is not a continuation
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md
story-continuity: a wrapped
  field value

Executors must never write outside their owns list, whatever the brief says.

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_rejects "prose after a blank line is not a continuation (F-79/ADV-R9-05 control)" \
  "$FIX" "reaches NO executor manifest" gate-8 --run 260813-x-r1
# ---- ADV-R11-06 (R11b): an UNINDENTED sentence right after a field is prose
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md
tier: mid
Executors must never write outside their owns list, whatever the brief says.

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | do a | `pytest a` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_rejects "unindented prose directly after a named field is scanned, not swallowed (ADV-R11-06)" \
  "$FIX" "reaches NO executor manifest" gate-8 --run 260813-x-r1
finish
