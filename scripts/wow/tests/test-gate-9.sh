#!/usr/bin/env bash
# GATE-9 negative test: an artifact claiming SIGNED without a mirrored Jira
# sign-off record, and a record with no SIGNED status, must both be rejected.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-9"

mkdir -p "$FIX/docs/spec"
printf '# SPEC\nstatus: SIGNED at G1\n\nbody\n' > "$FIX/docs/spec/SPEC-x-v1.md"
assert_rejects "SIGNED with no signed: ev:jira record" "$FIX" "no 'signed:" gate-9 --paths docs/spec/SPEC-x-v1.md

printf '# SPEC\nstatus: DRAFT\nsigned: 2026-08-13 ev:jira{ABC-1}\n\nbody\n' \
  > "$FIX/docs/spec/SPEC-x-v1.md"
assert_rejects "signed: record but status is not SIGNED" "$FIX" "status is not SIGNED" gate-9 --paths docs/spec/SPEC-x-v1.md

printf '# SPEC\nstatus: SIGNED at G1\nsigned: 2026-08-13 ev:jira{ABC-1}\n\nbody\n' \
  > "$FIX/docs/spec/SPEC-x-v1.md"
assert_accepts "SIGNED with a mirrored record" "$FIX" gate-9 --paths docs/spec/SPEC-x-v1.md

# Regression: GATE-9 once read the prose "not signed" in a blocked draft's header
# as a sign-off claim, because it matched SIGNED case-insensitively.
printf '# SPEC\nstatus: **BLOCKED DRAFT — not signable, not signed.** Held pending the probe\n\nbody\n' \
  > "$FIX/docs/spec/SPEC-y-v1.md"
assert_accepts "blocked draft whose header says 'not signed'" "$FIX" gate-9 --paths docs/spec/SPEC-y-v1.md
finish
