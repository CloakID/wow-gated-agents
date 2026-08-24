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

# ---- F-15 (v0.6.3): resolve through the named run, never a sorted glob ------
mkdir -p "$FIX/runs/260814-real-r1" "$FIX/docs/spec"
printf '# SPEC zzz\n' > "$FIX/docs/spec/SPEC-zzz-sorts-last-v1.md"
printf '# SPEC own\nstatus: SIGNED at G4\nsigned: G4 2026-08-14 ev:jira{ABC-9}\n' > "$FIX/docs/spec/SPEC-own-v1.md"
printf '# PLAN\nspec: docs/spec/SPEC-own-v1.md\n' > "$FIX/runs/260814-real-r1/PLAN.md"
assert_accepts "G4 --run grades the RUN'S spec, not whichever sorts last (F-15)" "$FIX" \
  gate-9 --gate G4 --run 260814-real-r1
mkdir -p "$FIX/runs/260814-noplan-r1"
assert_rejects "G4 --run with no resolvable spec REFUSES to guess (F-15)" "$FIX" "refusing to guess" \
  gate-9 --gate G4 --run 260814-noplan-r1

# ...and the record names the gate it attests: a G1 record cannot close G4.
printf '# SPEC g1\nstatus: SIGNED at G1\nsigned: G1 2026-08-14 ev:jira{ABC-3}\n' > "$FIX/docs/spec/SPEC-g1-v1.md"
assert_rejects "a G1 sign-off does not satisfy G4 (F-15)" "$FIX" "signs G1, not G4" \
  gate-9 --gate G4 --spec docs/spec/SPEC-g1-v1.md
assert_accepts "legacy tokenless record still closes (compat)" "$FIX" \
  gate-9 --gate G1 --spec docs/spec/SPEC-x-v1.md

# ---- F-29 (v0.6.3): a signed artifact modified after signing carries AM-<nn> -
printf '# SPEC am\nstatus: SIGNED at G1\nsigned: G1 2026-08-14 ev:jira{ABC-4}\n\nbody v1\n' > "$FIX/docs/spec/SPEC-am-v1.md"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "sign [WOW:publish]" )
printf '\nbody v2 — widened after signature\n' >> "$FIX/docs/spec/SPEC-am-v1.md"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "amend [WOW:publish]" )
assert_rejects "signed artifact modified with no amendment record (F-29)" "$FIX" "AM-" \
  gate-9 --paths docs/spec/SPEC-am-v1.md
printf '\nAM-01: 2026-08-15 PO widened scope (D-9); scope-widening: yes\n' >> "$FIX/docs/spec/SPEC-am-v1.md"
assert_accepts "amendment record makes the post-signature change visible (F-29 control)" "$FIX" \
  gate-9 --paths docs/spec/SPEC-am-v1.md
finish
