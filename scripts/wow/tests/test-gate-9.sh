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
printf '\nAM-01 — 2026-08-15 — PO (D-9) — widened scope; widens scope: yes\n' >> "$FIX/docs/spec/SPEC-am-v1.md"
assert_accepts "amendment record makes the post-signature change visible (F-29 control)" "$FIX" \
  gate-9 --paths docs/spec/SPEC-am-v1.md

# ---- prodsim/F-76 (v0.7.3): G4's governing spec is the RECONCILED v<N+1> —
# the plan's spec: header names v<N> by construction (P4 produces v<N+1>), so
# resolver and playbook disagreed by one version for every run that reached G4.
mkdir -p "$FIX/runs/260917-g4-r1"
printf '# PLAN — 260917-g4-r1\nspec: docs/spec/SPEC-g4-v1.md\n' > "$FIX/runs/260917-g4-r1/PLAN.md"
printf '# SPEC v1\nstatus: SIGNED\nsigned: G1 2026-09-17 ev:jira{WOW-1}\n' > "$FIX/docs/spec/SPEC-g4-v1.md"
printf '# SPEC v2 (reconciled)\nstatus: SIGNED\nsigned: G4 2026-09-19 ev:jira{WOW-2}\n' > "$FIX/docs/spec/SPEC-g4-v2.md"
assert_accepts "G4 resolves the reconciled v2, not the plan's v1 (prodsim/F-76)" "$FIX" \
  gate-9 --gate G4 --run 260917-g4-r1
# Control 1: a blocked-draft v2 must NOT be resolved — fall back to v1, whose
# G1 token then refuses with the --spec hint (never a silent pass).
printf '# SPEC v2\nstatus: blocked-draft\nsigned: G4 2026-09-19 ev:jira{WOW-2}\n' > "$FIX/docs/spec/SPEC-g4-v2.md"
assert_rejects "blocked-draft v2 is skipped; the refusal carries the --spec hint (ADV-5)" "$FIX" \
  "pass --spec" gate-9 --gate G4 --run 260917-g4-r1
# Control 2: G1 still resolves the plan's own spec — the v(N+1) rule is G4-only.
assert_accepts "G1 still closes against the plan's v1 (control)" "$FIX" \
  gate-9 --gate G1 --run 260917-g4-r1
# ---- ADV-R9-10 (v0.7.3 R9): the pre-0.7.3 layout (signed G4 record living in
# v1, v2 an ordinary draft) routes through the NO-RECORD branch, which used to
# refuse with no route — the --spec hint must fire there too.
printf '# SPEC v1\nstatus: SIGNED\nsigned: G4 2026-09-17 ev:jira{WOW-9}\n' > "$FIX/docs/spec/SPEC-g4-v1.md"
printf '# SPEC v2 (reconciled, unsigned)\nstatus: draft\n' > "$FIX/docs/spec/SPEC-g4-v2.md"
assert_rejects "unsigned v2 resolved at G4: refusal names the --spec route (ADV-R9-10)" "$FIX" \
  "pass --spec" gate-9 --gate G4 --run 260917-g4-r1
# ...and --spec with the file that carries the record closes it.
assert_accepts "--spec pointing at the record-carrying v1 closes G4 (ADV-R9-10 control)" "$FIX" \
  gate-9 --gate G4 --spec docs/spec/SPEC-g4-v1.md
# ---- platform/F-71 (v0.7.4): the drift check is per-MODIFICATION, not a
# one-time toll — the first amendment must not license every later change.
mkdir -p "$FIX/docs/spec"
printf '# SPEC drift\nstatus: SIGNED\nsigned: G1 2026-09-20 ev:jira{WOW-5}\n\nbody v1\n' > "$FIX/docs/spec/SPEC-drift-v1.md"
( cd "$FIX" && git add docs/spec/SPEC-drift-v1.md && git commit -qm "sign drift spec [WOW:publish]" --no-verify )
# first post-signature change WITH its amendment: passes
printf '\nAM-01 — 2026-09-21 — PO — records this change\nchanged body\n' >> "$FIX/docs/spec/SPEC-drift-v1.md"
( cd "$FIX" && git add -A && git commit -qm "amended change [WOW:publish]" --no-verify )
assert_accepts "post-signature change carrying its NEW amendment passes (F-71 control)" "$FIX" \
  gate-9
# second change with NO new amendment: the old any-AM-anywhere test passed this
printf '\nfifty more silent words\n' >> "$FIX/docs/spec/SPEC-drift-v1.md"
( cd "$FIX" && git add -A && git commit -qm "silent drift [WOW:publish]" --no-verify )
assert_rejects "a later change with no NEW amendment fails — count-and-compare (platform/F-71)" \
  "$FIX" "did not grow" gate-9
printf '\nAM-02 — 2026-09-22 — PO — records the second change too\n' >> "$FIX/docs/spec/SPEC-drift-v1.md"
assert_accepts "adding AM-02 for the second change clears it (F-71 control)" "$FIX" gate-9
( cd "$FIX" && git add -A && git commit -qm "am-02 [WOW:publish]" --no-verify )
# ---- platform/F-103 + prodsim/F-106 (v0.7.5): records, not tokens
printf '\nCites the spec amendment AM-07 and the plan PAM-03 for context.\n' >> "$FIX/docs/spec/SPEC-drift-v1.md"
assert_rejects "citing another document's AM-07 (or PAM-03) does not count as this document's amendment (platform/F-103, prodsim/F-106)" \
  "$FIX" "did not grow" gate-9
printf '\nAM-03 — 2026-10-06 — PO (D-9) — §2 adds the citation above; widens scope: no\n' >> "$FIX/docs/spec/SPEC-drift-v1.md"
assert_accepts "a record line in the FORMATS §1 block form counts (F-103 control)" "$FIX" gate-9
( cd "$FIX" && git add -A && git commit -qm "am-03 [WOW:publish]" --no-verify )
# ---- platform/F-85 (v0.7.5): the unscoped form states its subject; --gate does not
assert_output "unscoped gate-9 states how many artifacts it walked (platform/F-85)" "$FIX" \
  "subject: 13 signed artifact(s)" gate-9
FIX85="$(setup_fixture_repo)"
assert_output "unscoped gate-9 over no specs and no plans is VACUOUS, loudly (F-85)" "$FIX85" \
  "subject: 0 signed artifact(s) — VACUOUS" gate-9
# ---- R12b: ADV-R12-11 — decorated and table-form amendment records count
printf '\nfurther silent words\n' >> "$FIX/docs/spec/SPEC-drift-v1.md"
( cd "$FIX" && git add -A && git commit -qm "drift 3 [WOW:publish]" --no-verify )
printf '\n**AM-04** — 2026-10-06 — PO — the third change\n' >> "$FIX/docs/spec/SPEC-drift-v1.md"
assert_accepts "a bold-id amendment record counts (ADV-R12-11)" "$FIX" gate-9
( cd "$FIX" && git add -A && git commit -qm "am-04 [WOW:publish]" --no-verify )
printf '\nmore words\n' >> "$FIX/docs/spec/SPEC-drift-v1.md"
( cd "$FIX" && git add -A && git commit -qm "drift 4 [WOW:publish]" --no-verify )
printf '\n| AM-05 | 2026-10-06 | PO | the fourth change |\n' >> "$FIX/docs/spec/SPEC-drift-v1.md"
assert_accepts "a table-form amendment record counts (ADV-R12-11)" "$FIX" gate-9
( cd "$FIX" && git add -A && git commit -qm "am-05 [WOW:publish]" --no-verify )
printf '\nstill more\n' >> "$FIX/docs/spec/SPEC-drift-v1.md"
assert_output "the refusal prints the record shape (DEV-R12-20)" "$FIX" "record LINE \`AM-" gate-9
finish
