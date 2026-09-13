#!/usr/bin/env bash
# GATE-13 negative test (F-9, pilot #1): a task's Verify is the sole mechanical
# arbiter of COMPLETED, and nothing required it to be shown failing — nine
# inert verifies shipped in one run, three past adversarial review. The gate
# demands a Non-vacuity cell per task and lints Verify cells for idioms that
# each shipped a real vacuous check. It binds on UNSIGNED plans only: a signed
# plan is frozen, and a gate that rejects everything (or reaches into frozen
# history) is as useless as one that rejects nothing.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-13"

mkdir -p "$FIX/runs/260824-x-r1"
plan() { cat > "$FIX/runs/260824-x-r1/PLAN.md"; }

# Subject-absent: a missing plan is not a pass.
assert_rejects "no PLAN.md" "$FIX" "not a pass" gate-13 --run 260824-x-r1
printf 'prose, not a plan\n' > "$FIX/runs/260824-x-r1/PLAN.md"
assert_rejects "plan the schema cannot read" "$FIX" "parses into no units" gate-13 --run 260824-x-r1

# The founding failure: a task table with no Non-vacuity column at all.
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260824-x-r1.T01 | do a | `pytest a` | a works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_rejects "task table without a Non-vacuity column" "$FIX" "no 'Non-vacuity' column" \
  gate-13 --run 260824-x-r1

# Column present, cell empty.
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| 260824-x-r1.T01 | do a | `pytest a` | a works | |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_rejects "empty Non-vacuity cell" "$FIX" "empty Non-vacuity cell" gate-13 --run 260824-x-r1

# Cell present but citing nothing runnable — GATE-4's own proof rule.
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| 260824-x-r1.T01 | do a | `pytest a` | a works | trust me, it fails on bad input |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_rejects "Non-vacuity cell cites nothing runnable" "$FIX" "cites nothing runnable" \
  gate-13 --run 260824-x-r1

# The lint half: a Verify carrying an idiom that shipped a real inert check.
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| 260824-x-r1.T01 | do a | `set -e; ! grep bad out.txt` | clean | fails on planted 'bad' ev:cmd{grep bad fixtures => 1 @2026-08-24} |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_rejects "bang under set -e (the idiom behind PARK-U5-01)" "$FIX" "bang-under-set-e" \
  gate-13 --run 260824-x-r1

plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| 260824-x-r1.T01 | do a | `jq -e '.status // 200' out.json` | 200 | fails on error body ev:cmd{jq . err.json => 1 @2026-08-24} |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_rejects "jq // default swallows an absent key (the T19 idiom)" "$FIX" \
  "jq-default-on-absent-key" gate-13 --run 260824-x-r1

# lint-ok accepts one idiom deliberately and VISIBLY.
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| 260824-x-r1.T01 | do a | `jq -e '.status // 200' out.json` | 200 | lint-ok: key guaranteed by T00 schema check; fails on error body ev:cmd{jq . err.json => 1 @2026-08-24} |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_accepts "lint-ok with a reason accepts the idiom deliberately" "$FIX" \
  gate-13 --run 260824-x-r1

# Positive controls: a well-formed plan (citing an existing file), and MANUAL.
printf 'fixture\n' > "$FIX/runs/260824-x-r1/wrong-answer.txt"
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| 260824-x-r1.T01 | do a | `pytest a` | a works | rejects runs/260824-x-r1/wrong-answer.txt |
| 260824-x-r1.T02 | PO reviews | MANUAL | signed | MANUAL |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_accepts "proven verifies + MANUAL exemption (positive control)" "$FIX" \
  gate-13 --run 260824-x-r1

# A SIGNED plan is frozen: the gate binds at G2, not retroactively.
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md
signed: 2026-08-24 ev:jira{WOW-42}

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260824-x-r1.T01 | do a | `set -e; ! grep bad out.txt` | clean |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_accepts "signed plan is frozen — no retroactive reds" "$FIX" gate-13 --run 260824-x-r1


# F-13's founding failure at full strength (engine round 6, OBL-PKG-20):
# admission is by table membership, so a bare-id row's VACUOUS VERIFY is now
# read and linted — the 29-unread-verifies case cannot recur even when the
# ids are unreadable.
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| T01 | do a | `set -e; ! grep bad x` | works | bare id, unreadable |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | T01 |
P
assert_rejects "a bare-id row's vacuous verify is READ and linted (F-13/OBL-PKG-20)" "$FIX" \
  "bang-under-set-e" gate-13 --run 260824-x-r1

# The zero-guard keeps its subject: units with no task table lint nothing,
# and that is not a pass.
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

prose instead of a task table

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | none |
P
assert_rejects "no task table cannot pass the verify lint (F-13)" "$FIX" \
  "ZERO task rows" gate-13 --run 260824-x-r1
finish
