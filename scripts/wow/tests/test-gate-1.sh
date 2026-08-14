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
finish
