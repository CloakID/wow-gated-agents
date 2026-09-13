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
assert_rejects "bare task ids parse to zero tasks — loud, not healthy-looking (F-13)" "$FIX" \
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
finish
