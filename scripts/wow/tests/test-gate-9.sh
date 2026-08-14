#!/usr/bin/env bash
# GATE-9 negative test: an artifact claiming SIGNED without a mirrored Jira
# sign-off record, a record with no SIGNED status, and a gate asked to close
# against an artifact carrying no record at all must all be rejected.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-9"

mkdir -p "$FIX/docs/spec"
printf '# SPEC\nstatus: SIGNED at G1\n\nbody\n' > "$FIX/docs/spec/SPEC-x-v1.md"
assert_rejects "SIGNED with no signed: ev:jira record" "$FIX" "no 'signed:" gate-9 --paths docs/spec/SPEC-x-v1.md

printf '# SPEC\nstatus: DRAFT\nsigned: 2026-08-13 ev:jira{ABC-1}\n\nbody\n' \
  > "$FIX/docs/spec/SPEC-x-v1.md"
assert_rejects "signed: record but status is not SIGNED" "$FIX" "status is not SIGNED" gate-9 --paths docs/spec/SPEC-x-v1.md

# The premise check: the sweep form is a consistency lint, so an artifact with no
# status line at all passes it. Closure is a different question, and asking it
# requires naming the gate that is closing.
printf '# SPEC — user auth\n\nBody with no header status at all.\n' > "$FIX/docs/spec/SPEC-z-v1.md"
assert_accepts "unsigned draft passes the sweep consistency lint" "$FIX" gate-9 --paths docs/spec/SPEC-z-v1.md
assert_rejects "G1 cannot close against an artifact with no record" "$FIX" "cannot close" \
  gate-9 --gate G1 --spec docs/spec/SPEC-z-v1.md

mkdir -p "$FIX/runs/260813-x-r1"
printf '# PLAN\nstatus: DRAFT\n' > "$FIX/runs/260813-x-r1/PLAN.md"
assert_rejects "G2 cannot close against a PLAN with no record" "$FIX" "cannot close" \
  gate-9 --gate G2 --run 260813-x-r1

printf '# PLAN\nstatus: SIGNED at G2\nsigned: 2026-08-13 ev:jira{ABC-2}\n' \
  > "$FIX/runs/260813-x-r1/PLAN.md"
assert_accepts "G2 closes with a mirrored record in the PLAN header" "$FIX" \
  gate-9 --gate G2 --run 260813-x-r1

printf '# SPEC\nstatus: SIGNED at G1\nsigned: 2026-08-13 ev:jira{ABC-1}\n\nbody\n' \
  > "$FIX/docs/spec/SPEC-x-v1.md"
assert_accepts "SIGNED with a mirrored record" "$FIX" gate-9 --paths docs/spec/SPEC-x-v1.md

# Regression: GATE-9 once read the prose "not signed" in a blocked draft's header
# as a sign-off claim, because it matched SIGNED case-insensitively.
printf '# SPEC\nstatus: **BLOCKED DRAFT — not signable, not signed.** Held pending the probe\n\nbody\n' \
  > "$FIX/docs/spec/SPEC-y-v1.md"
assert_accepts "blocked draft whose header says 'not signed'" "$FIX" gate-9 --paths docs/spec/SPEC-y-v1.md
finish
