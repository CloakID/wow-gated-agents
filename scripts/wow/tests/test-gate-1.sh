#!/usr/bin/env bash
# GATE-1 negative test: a laneless commit message, a double lane ref, a lane ref
# pointing at a run with no plan, and a lane ref whose task id appears only in
# prose must all be rejected.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-1"

printf 'Add a thing\n\nNo lane here.\n' > "$FIX/msg-none"
assert_rejects "laneless message" "$FIX" "no lane reference" gate-1 msg-none

printf 'Two lanes [WOW:publish] [D:some-bug]\n' > "$FIX/msg-two"
assert_rejects "two lane refs" "$FIX" "expected exactly one" gate-1 msg-two

printf 'Do work [T:260813-nope-r1.T01]\n' > "$FIX/msg-ghost"
assert_rejects "lane ref to a run with no PLAN.md" "$FIX" "has no runs/260813-nope-r1/PLAN.md" \
  gate-1 msg-ghost

mkdir -p "$FIX/runs/260813-real-r1"
plan() { cat > "$FIX/runs/260813-real-r1/PLAN.md"; }

# The premise check: resolving a lane ref by substring means a task id mentioned
# in prose, or left behind in a comment for a task that was deleted, "resolves".
plan <<'P'
# PLAN — 260813-real-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py
tier: mid
wave: 1
autonomy: decide-and-log

<!-- dropped task 260813-real-r1.T01 during planning -->
Prose mentioning 260813-real-r1.T01 is not a task row.

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-real-r1.T02 |
P
printf 'Do work [T:260813-real-r1.T01]\n' > "$FIX/msg-prose"
assert_rejects "task id present only in prose/comments" "$FIX" "is not a task row" gate-1 msg-prose

plan <<'P'
# PLAN — 260813-real-r1
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
| 260813-real-r1.T01 | do a | `pytest a` | a works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-real-r1.T01 |
P
printf 'Do work [T:260813-real-r1.T01]\n' > "$FIX/msg-ok"
assert_accepts "resolvable task lane ref" "$FIX" gate-1 msg-ok

printf 'Framework change [WOW:publish]\n' > "$FIX/msg-pub"
assert_accepts "publish lane ref" "$FIX" gate-1 msg-pub

# Regression: `git commit -v` appends the diff below a scissors line. A trailer
# quoted in that diff was counted as a second lane ref and blocked the commit.
cat > "$FIX/msg-verbose" <<'M'
Update the plan [T:260813-real-r1.T01]

# Please enter the commit message for your changes.
# ------------------------ >8 ------------------------
diff --git a/runs/260813-real-r1/PLAN.md b/runs/260813-real-r1/PLAN.md
+| 260813-real-r1.T02 | do b | `pytest b` | b works |  see [T:260813-real-r1.T02]
M
assert_accepts "git commit -v message quoting a trailer in its diff" "$FIX" gate-1 msg-verbose
# ---- [WOW:migrate] validity window (verifier F6: shipped untested) -----------
MSGF="$(mktemp)"
printf 'lift REQUIREMENTS out of legacy [WOW:migrate]\n' > "$MSGF"
# greenfield: no .planning/ -> refused
assert_rejects "[WOW:migrate] in a greenfield repo" "$FIX" "outside a migration" gate-1 "$MSGF"
# mid-migration: .planning present, freeze unflipped -> legal
mkdir -p "$FIX/.planning"; printf 'legacy\n' > "$FIX/.planning/STATE.md"
assert_accepts "[WOW:migrate] mid-migration (.planning present, freeze false)" "$FIX" gate-1 "$MSGF"
# post-freeze: flag true -> refused
python3 - "$FIX/scripts/wow/wow.config.json" <<'PY'
import json,sys,io
p=sys.argv[1]; c=json.load(open(p)); c["migrated_from_gsd"]=True
io.open(p,"w",encoding="utf-8").write(json.dumps(c)+"\n")
PY
assert_rejects "[WOW:migrate] after the freeze flipped" "$FIX" "migration is over" gate-1 "$MSGF"
rm -f "$MSGF"


# ---- F-07 (v0.6.3): mentions are not claims, for trailers too ---------------
printf 'Drop lane addendum [WOW:publish]\n\nDocuments what `[WOW:migrate]` and `[Q:...]` used to mean.\n' > "$FIX/msg-mention"
assert_accepts "backticked trailer mentions in the body do not count (F-07)" "$FIX" gate-1 msg-mention
printf 'Explain [WOW:publish]\n\n```\n[WOW:migrate]\n```\n' > "$FIX/msg-fenced"
assert_accepts "fenced trailer does not count (F-07)" "$FIX" gate-1 msg-fenced
printf 'Both bare [WOW:publish]\n\nAnd also bare [D:some-bug] in prose.\n' > "$FIX/msg-twobare"
assert_rejects "two BARE trailers still reject (F-07 control)" "$FIX" "expected exactly one" gate-1 msg-twobare

# ---- F-08/F-10 (v0.6.3): bare [T:<run-id>] carries phase artifacts ----------
printf 'P1 spec signed at G1 [T:260813-real-r1]\n' > "$FIX/msg-barerun"
assert_accepts "bare [T:<run-id>] resolves to the run directory" "$FIX" gate-1 msg-barerun
printf 'P1 spec [T:260899-ghost-r1]\n' > "$FIX/msg-barerun-ghost"
assert_rejects "bare run form still requires the directory to exist" "$FIX" "does not exist" gate-1 msg-barerun-ghost

# ---- F-46/F-39 (v0.7.1): a zero-hit message with a trailer-SHAPED token is
# diagnosed with the real cause, never reported as "no lane reference" — that
# message about a reference the operator HAD written cost a full cycle.
SLUG49="$(printf 'a%.0s' {1..49})"
SLUG48="$(printf 'a%.0s' {1..48})"
printf 'Work [T:260913-%s-r1.T01]\n' "$SLUG49" > "$FIX/msg-longslug"
assert_rejects "over-cap slug named as the cause, not 'missing lane ref' (F-46)" "$FIX" \
  "cap 48" gate-1 msg-longslug
printf 'Work [T:260813-real-r1.T1]\n' > "$FIX/msg-badtail"
assert_rejects "inexpressible task tail named as the cause (F-39)" "$FIX" \
  "task tail must be .T<nn>" gate-1 msg-badtail
# The laneless control still says exactly that — the diagnosis must not replace
# the plain message when no trailer-shaped token exists.
assert_rejects "genuinely laneless message keeps the plain error (F-46 control)" "$FIX" \
  "no lane reference" gate-1 msg-none

# 48 chars is the cap, not past it: a maximal slug works END TO END — plan row,
# task trailer, bare run trailer.
RID48="260913-$SLUG48-r1"
mkdir -p "$FIX/runs/$RID48"
cat > "$FIX/runs/$RID48/PLAN.md" <<P
# PLAN — $RID48
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means |
|---|---|---|---|
| $RID48.T01 | do a | \`pytest a\` | a works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | $RID48.T01 |
P
printf 'Work [T:%s.T01]\n' "$RID48" > "$FIX/msg-slug48"
assert_accepts "48-char slug task trailer resolves (F-46 boundary)" "$FIX" gate-1 msg-slug48
printf 'P1 spec [T:%s]\n' "$RID48" > "$FIX/msg-slug48-bare"
assert_accepts "48-char slug bare run trailer resolves (F-46 boundary)" "$FIX" gate-1 msg-slug48-bare

# ---- F-39 (v0.7.1): the letter-suffix task id resolves end to end -----------
plan <<'P'
# PLAN — 260813-real-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — first
owns:
- src/a.py

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260813-real-r1.T07 | do a | `pytest a` | a works |
| 260813-real-r1.T07a | split half | `pytest a2` | split works |

## Coverage matrix
| AC | Tasks |
|---|---|
| AC-1 | 260813-real-r1.T07a |
P
printf 'Split work [T:260813-real-r1.T07a]\n' > "$FIX/msg-suffix"
assert_accepts "letter-suffix trailer resolves to its plan row (F-39)" "$FIX" gate-1 msg-suffix

# ---- check-id (v0.7.1, F-46): refuse an inexpressible run id at run OPEN ----
assert_accepts "check-id: legal run id" "$FIX" check-id 260913-user-auth-r1
assert_accepts "check-id: 48-char slug is within the cap" "$FIX" check-id "$RID48"
assert_rejects "check-id: 49-char slug refused naming the cap" "$FIX" "caps it at 48" \
  check-id "260913-$SLUG49-r1"
assert_rejects "check-id: shapeless id refused naming ids.run" "$FIX" "does not match ids.run" \
  check-id "sprint-7-work"

# ---- prodsim/F-65 (v0.7.3): check-id --base asserts the run base carries the
# plan — 'from main' produced a base on which the run did not exist, and the
# failure surfaced hours later as a confusing mutation result, not a refusal.
( cd "$FIX" && git add -A >/dev/null && git commit -qm "plans [WOW:publish]" >/dev/null 2>&1 )
assert_accepts "check-id --base: base carrying the plan passes (F-65)" "$FIX" \
  check-id 260813-real-r1 --base HEAD
( cd "$FIX" && git checkout -qb stale-main HEAD~1 2>/dev/null && git checkout -q - )
assert_rejects "check-id --base: base without the plan is refused (F-65)" "$FIX" \
  "does not exist on --base" check-id 260813-real-r1 --base stale-main
assert_rejects "check-id --base: unresolvable ref refused (F-65)" "$FIX" \
  "not a ref this repo can resolve" check-id 260813-real-r1 --base no-such-branch
finish
