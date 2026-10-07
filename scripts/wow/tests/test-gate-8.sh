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

# ---- prodsim/F-104 (v0.7.5): a re-dispatched unit consumes at its later boundary
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — producer
owns:
- src/a.py
tier: mid
wave: 3
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | build | `pytest a` | works |

### U4 — re-dispatched
owns:
- src/d.py
inputs:
- src/a.py
tier: mid
wave: 1
dispatched_at_wave: 4
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T63 | use a | `pytest d` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T63 |
P
assert_accepts "a wave-1 unit re-dispatched at wave 4 may read a wave-3 output (prodsim/F-104)" "$FIX" \
  gate-8 --run 260813-x-r1
sed -i 's/^dispatched_at_wave: 4$/dispatched_at_wave: 3/' "$FIX/runs/260813-x-r1/PLAN.md"
assert_rejects "re-dispatched at wave 3 it cannot read a wave-3 output (F-104 control)" "$FIX" \
  "consuming at wave 3) declares input 'src/a.py' produced by U1 (wave 3) — not a STRICTLY LOWER" gate-8 --run 260813-x-r1
sed -i 's/^dispatched_at_wave: 3$/dispatched_at_wave: 1/' "$FIX/runs/260813-x-r1/PLAN.md"
assert_rejects "dispatched_at_wave not later than wave is refused (F-104)" "$FIX" \
  "not LATER than its wave" gate-8 --run 260813-x-r1
# ---- prodsim/F-108 (v0.7.5): ORCH-owned records are declarable inputs
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — reader
owns:
- src/a.py
inputs:
- runs/260813-x-r1/orch/B3-classification.md
tier: mid
wave: 2
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | read B3 | `cat runs/260813-x-r1/orch/B3-classification.md` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T01 |
P
assert_accepts "an input under runs/<id>/orch/ needs no producer unit (prodsim/F-108)" "$FIX" \
  gate-8 --run 260813-x-r1
assert_rejects "at the wave boundary with no int branch yet, the refusal says so (DEV-R12-23g)" "$FIX" \
  "integration branch wow/260813-x-r1/int does not exist yet" gate-8 --run 260813-x-r1 --boundary 2
( cd "$FIX" && git checkout -q -b wow/260813-x-r1/int && git checkout -q - )
assert_rejects "at the wave boundary the ORCH record must exist on int (F-108)" "$FIX" \
  "does not exist on wow/260813-x-r1/int" gate-8 --run 260813-x-r1 --boundary 2
( cd "$FIX" && git checkout -q wow/260813-x-r1/int && mkdir -p runs/260813-x-r1/orch \
  && printf 'B3: classified\n' > runs/260813-x-r1/orch/B3-classification.md \
  && git add runs/260813-x-r1/orch/B3-classification.md >/dev/null && git commit -qm "orch record [T:260813-x-r1]" --no-verify && git checkout -q - )
assert_accepts "ORCH record present on int: boundary check passes (F-108 control)" "$FIX" \
  gate-8 --run 260813-x-r1 --boundary 2
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — claimer
owns:
- runs/260813-x-r1/orch/notes.md
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T01 | x | `true` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
P
assert_rejects "a unit cannot CLAIM an orch/ path (F-108)" "$FIX" "claims ORCH-owned path" gate-8 --run 260813-x-r1
# ---- platform/F-95 (v0.7.5): a delta verifier's report is nobody's unit output
sed -i 's#^- runs/260813-x-r1/orch/notes.md#- runs/260813-x-r1/reports/AM-01-verify.md#' "$FIX/runs/260813-x-r1/PLAN.md"
assert_rejects "a unit cannot claim reports/AM-01-verify.md either (platform/F-95)" "$FIX" \
  "not an AGENT-writable path" gate-8 --run 260813-x-r1
# ---- platform/F-97 (v0.7.5): reads-vs-declarations — a clause pointing at nothing
mkdir -p "$FIX/src"
printf 'a\n' > "$FIX/src/a.py"
( cd "$FIX" && git add src/a.py >/dev/null && git commit -qm "src [WOW:publish]" --no-verify )
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md
reviews: 2

## Units

### U1 — reader
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T31 | compare | `diff runs/260813-x-r1/RUN-REPORT.md src/a.py` | same |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T31 |
| AC-2 | 260813-x-r1.T31 |
P
assert_rejects "a Verify naming an ORCH-owned file that does not exist during P3 is refused at G2 (platform/F-97, DEF-plan-02 replay)" "$FIX" \
  "names path 'runs/260813-x-r1/RUN-REPORT.md' which exists nowhere" gate-8 --run 260813-x-r1
sed -i 's#`diff runs/260813-x-r1/RUN-REPORT.md src/a.py`#`diff runs/260813-x-r1/evidence/U1/out.txt src/a.py`#' "$FIX/runs/260813-x-r1/PLAN.md"
assert_accepts "a path under the unit's own evidence dir is the unit's to write (F-97 control)" "$FIX" gate-8 --run 260813-x-r1
sed -i 's#`diff runs/260813-x-r1/evidence/U1/out.txt src/a.py`#`test -f src/ghost.py \&\& echo PARK-U1-01`#' "$FIX/runs/260813-x-r1/PLAN.md"
assert_rejects "an untracked, unowned path is refused (F-97)" "$FIX" "names path 'src/ghost.py'" gate-8 --run 260813-x-r1
assert_rejects "an id no row allocates is refused (F-97 fix 2)" "$FIX" "names PARK-U1-01 and nothing" gate-8 --run 260813-x-r1
sed -i 's#`test -f src/ghost.py \&\& echo PARK-U1-01`#`test -f src/ghost.py` lint-ok: ghost is created by T31 itself#' "$FIX/runs/260813-x-r1/PLAN.md"
assert_accepts "lint-ok accepts the clause deliberately and visibly (F-97 escape)" "$FIX" gate-8 --run 260813-x-r1
# ---- R12b: ADV-R12-07 — a re-dispatched producer's outputs are available at its dispatched wave
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U2 — producer re-dispatched
owns:
- src/b.py
tier: mid
wave: 1
dispatched_at_wave: 2
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T02 | write b (AM-01 at wave 2) | `pytest b` | works |

### U3 — consumer
owns:
- src/c.py
inputs:
- src/b.py
tier: mid
wave: 2
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T03 | use b | `pytest c` | works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T02 |
| AC-2 | 260813-x-r1.T03 |
P
assert_rejects "a wave-2 consumer of a unit re-dispatched at wave 2 is the same-wave case (ADV-R12-07)" "$FIX" \
  "produced by U2 (wave 2) — not a STRICTLY LOWER" gate-8 --run 260813-x-r1
# ---- R12b: DEV-R12-09 — the reads lint is frozen with the signed rows
plan <<'P'
# PLAN — 260813-x-r1
spec: docs/spec/SPEC-x-v1.md
signed: 2026-08-13 ev:jira{WOW-1}

## Units

### U1 — reader
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T31 | compare | `diff runs/260813-x-r1/RUN-REPORT.md src/a.py` | same |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T31 |
| AC-2 | 260813-x-r1.T31 |
P
( cd "$FIX" && git add -A >/dev/null && git commit -qm "sign [WOW:publish]" --no-verify )
assert_accepts "a SIGNED and committed plan's rows are frozen for the reads lint (DEV-R12-09)" "$FIX" gate-8 --run 260813-x-r1
sed -i 's#^| 260813-x-r1.T31 | compare | `diff runs/260813-x-r1/RUN-REPORT.md src/a.py` | same |$#&\n| 260813-x-r1.T32 | added by AM-01 | `cat runs/260813-x-r1/RUN-REPORT.md` | read |#' "$FIX/runs/260813-x-r1/PLAN.md"
assert_rejects "a row ADDED after signing is linted (DEV-R12-09 control)" "$FIX" \
  "task 260813-x-r1.T32 names path 'runs/260813-x-r1/RUN-REPORT.md'" gate-8 --run 260813-x-r1
# ---- R12b: ADV-R12-09 — prior-run ids resolve in the archive; lower-wave evidence is deliverable
mkdir -p "$FIX/runs/archive/260801-prior-r1/reports"
printf '%s\n' '- CV-260801-prior-r1-U2-03: the probe could not run' > "$FIX/runs/archive/260801-prior-r1/reports/U2-verify.md"
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
| 260813-x-r1.T01 | discharge CV-260801-prior-r1-U2-03 | `test -f runs/260813-x-r1/evidence/U1/t01.log` | logged |

### U2 — second
owns:
- src/b.py
tier: mid
wave: 2
autonomy: decide-and-log

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-x-r1.T07 | read U1 log | `grep ok runs/260813-x-r1/evidence/U1/t01.log` | read |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-x-r1.T01 |
| AC-2 | 260813-x-r1.T07 |
P
assert_accepts "a prior run's CV id resolves in the archive and a lower-wave unit's evidence is deliverable (ADV-R12-09)" "$FIX" gate-8 --run 260813-x-r1
finish
