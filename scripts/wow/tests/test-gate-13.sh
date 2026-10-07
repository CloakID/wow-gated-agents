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
# prodsim/F-107 (v0.7.5): the freeze is the SIGNING COMMIT's. An uncommitted
# signature line freezes nothing — the row below is linted and refused.
assert_rejects "a signature not yet committed freezes nothing (prodsim/F-107)" "$FIX" \
  "inert idiom" gate-13 --run 260824-x-r1
( cd "$FIX" && git add -A >/dev/null && git commit -qm "sign [WOW:publish]" )
assert_output "signed plan: rows signed at G2 are frozen — no retroactive reds, zero subject" "$FIX" \
  "signed, nothing amended" gate-13 --run 260824-x-r1
assert_accepts "signed plan with nothing amended passes" "$FIX" gate-13 --run 260824-x-r1
# a row ADDED after signing is linted (its Verify is `true`, the canonical inert form)
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
| 260824-x-r1.T07 | added by PAM-01 | `set -e; ! grep worse out.txt` | always |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_rejects "a task row ADDED to a signed plan by an amendment is linted (prodsim/F-107)" "$FIX" \
  "task 260824-x-r1.T07 Verify matches inert idiom" gate-13 --run 260824-x-r1
OUT107="$(cd "$FIX" && bash scripts/wow/gates.sh gate-13 --run 260824-x-r1 2>&1)" || true
if printf '%s' "$OUT107" | grep -q "T01" ; then
  echo "  FAIL the frozen G2 row T01 was linted retroactively (F-107)"; FAIL=$((FAIL+1))
else
  echo "  ok   the frozen G2 row stays frozen while the amended row is linted (F-107)"; PASS=$((PASS+1))
fi


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

# ---- platform/F-69 (v0.7.3): a Verify that default-expands a credential-named
# variable into echo/printf prints the VALUE when the variable is set — the
# exact state a residue probe exists to detect. Shipped twice in one repo,
# both times from the fix for the previous finding in the same family.
printf 'w\n' > "$FIX/runs/260824-x-r1/w.txt"
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| 260824-x-r1.T01 | probe | `echo "left: ${ROOT_PW:-gone}"` | clean | rejects runs/260824-x-r1/w.txt |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_rejects "credential default-expansion into echo is refused naming safe forms (platform/F-69)" \
  "$FIX" "Safe forms" gate-13 --run 260824-x-r1
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| 260824-x-r1.T01 | probe | `echo "still set: ${ROOT_PW+yes}"` | clean | rejects runs/260824-x-r1/w.txt |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_accepts "the safe form passes (platform/F-69 control)" "$FIX" gate-13 --run 260824-x-r1
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| 260824-x-r1.T01 | probe | `echo "left: ${ROOT_PW:-gone}"` | clean | lint-ok: synthetic tenant, PO D-9; rejects runs/260824-x-r1/w.txt |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_accepts "lint-ok accepts the expansion deliberately and visibly (platform/F-69 escape)" \
  "$FIX" gate-13 --run 260824-x-r1
# ---- ADV-R9-11 (v0.7.3 R9): the credential tokens are letter-bounded — bare
# substring PW matched inside ${PWD:-unknown} and the lint claimed the working
# directory was a credential.
printf 'w\n' > "$FIX/runs/260824-x-r1/w.txt"
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| 260824-x-r1.T01 | probe | `echo "ran in ${PWD:-unknown}" && pytest a` | clean | rejects runs/260824-x-r1/w.txt |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_accepts "\${PWD:-...} is a working directory, not a credential (ADV-R9-11)" \
  "$FIX" gate-13 --run 260824-x-r1
# control: PASSWORD still carries the trailing letters PASS guards against losing
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| 260824-x-r1.T01 | probe | `echo "left: ${DB_PASSWORD:-gone}"` | clean | rejects runs/260824-x-r1/w.txt |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_rejects "\${DB_PASSWORD:-...} is still refused (ADV-R9-11 control)" \
  "$FIX" "Safe forms" gate-13 --run 260824-x-r1

# ---- DEV-R9-05 (v0.7.3 R9): an unescaped pipe in a Verify cell shifts the
# row into a different table — GATE-8 said so while GATE-13 blamed a healthy
# Non-vacuity cell under the wrong rule. Same guard, both gates.
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| 260824-x-r1.T01 | probe | `echo $X | wc -c` | clean | rejects runs/260824-x-r1/w.txt |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_rejects "pipe-shifted row is diagnosed as the pipe, not the Non-vacuity cell (DEV-R9-05)" \
  "$FIX" "unescaped '|'" gate-13 --run 260824-x-r1
# ---- ADV-R10-06 (R9b): every credential token is letter-bounded.
plan <<'P'
# PLAN — 260824-x-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| 260824-x-r1.T01 | probe | `echo "model: ${TOKENIZER_MODEL:-bert} credit ${CREDIT_LIMIT:-0}"` | clean | rejects runs/260824-x-r1/w.txt |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260824-x-r1.T01 |
P
assert_accepts "TOKENIZER/CREDIT are not credentials (ADV-R10-06)" \
  "$FIX" gate-13 --run 260824-x-r1
# ---- platform/F-86 (v0.7.5): `||` is not a merge-base guard
FIX86="$(setup_fixture_repo)"
mkdir -p "$FIX86/runs/260925-mb-r1" "$FIX86/docs/spec"
printf '# SPEC\n' > "$FIX86/docs/spec/SPEC-m-v1.md"
cat > "$FIX86/runs/260925-mb-r1/PLAN.md" <<'P'
# PLAN — 260925-mb-r1
spec: docs/spec/SPEC-m-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| 260925-mb-r1.T01 | order | `git merge-base --is-ancestor $(git log -1 --format=%H -- p) HEAD \|\| echo NOT-ANCESTOR` | ordered | MANUAL |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260925-mb-r1.T01 |
P
assert_rejects "'|| echo' after merge-base collapses exit 128/129 into the verdict — not a guard (platform/F-86)" "$FIX86" \
  "inert idiom 'unguarded-merge-base'" gate-13 --run 260925-mb-r1
sed -i 's/HEAD \\|\\| echo NOT-ANCESTOR/HEAD; rc=$?; case $rc in 0\\|1) echo $rc;; *) exit 2;; esac/' "$FIX86/runs/260925-mb-r1/PLAN.md"
assert_accepts "capturing the exit code on the same line IS a guard (F-86 control)" "$FIX86" gate-13 --run 260925-mb-r1
# ---- prodsim/F-111 (v0.7.5): verify-cmd prints the RUNNABLE Verify
cat > "$FIX86/runs/260925-mb-r1/PLAN.md" <<'P'
# PLAN — 260925-mb-r1
spec: docs/spec/SPEC-m-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means | Non-vacuity |
|---|---|---|---|---|
| 260925-mb-r1.T31 | count | `printf 'a\|b' \| grep -c a` | one | MANUAL |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260925-mb-r1.T31 |
P
VC="$( cd "$FIX86" && bash scripts/wow/gates.sh verify-cmd 260925-mb-r1.T31 2>&1 )"
if [ "$VC" = "printf 'a|b' | grep -c a" ]; then
  echo "  ok   verify-cmd prints the Verify with its escapes removed (prodsim/F-111)"; PASS=$((PASS+1))
else
  echo "  FAIL verify-cmd printed: $VC (prodsim/F-111)"; FAIL=$((FAIL+1))
fi
VR="$( cd "$FIX86" && bash -c "$(bash scripts/wow/gates.sh verify-cmd 260925-mb-r1.T31)" 2>&1 )"
[ "$VR" = "1" ] && { echo "  ok   the printed command runs and gives the signed result (F-111)"; PASS=$((PASS+1)); } \
  || { echo "  FAIL running the printed command gave '$VR' (F-111)"; FAIL=$((FAIL+1)); }
( cd "$FIX86" && bash scripts/wow/gates.sh verify-cmd 260925-mb-r1.T99 >/dev/null 2>&1 ) \
  && { echo "  FAIL verify-cmd on an unknown task exited 0 (F-111)"; FAIL=$((FAIL+1)); } \
  || { echo "  ok   verify-cmd on an unknown task is refused (F-111)"; PASS=$((PASS+1)); }
# ---- R12b: ADV-R12-17 — verify-cmd strips the lint-ok marker
sed -i 's#| `printf .a\\|b. \\| grep -c a` |#| `printf '"'"'a\\|b'"'"' \\| grep -c a` lint-ok: deliberate |#' "$FIX86/runs/260925-mb-r1/PLAN.md"
VC2="$( cd "$FIX86" && bash scripts/wow/gates.sh verify-cmd 260925-mb-r1.T31 2>&1 )"
[ "$VC2" = "printf 'a|b' | grep -c a" ] && { echo "  ok   verify-cmd drops the lint-ok marker (ADV-R12-17)"; PASS=$((PASS+1)); } \
  || { echo "  FAIL verify-cmd kept the marker: $VC2 (ADV-R12-17)"; FAIL=$((FAIL+1)); }
finish
