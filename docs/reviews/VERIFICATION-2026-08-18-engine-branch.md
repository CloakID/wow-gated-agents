# Independent verification — branch engine-v0.5.x — 2026-08-18

**Verdict: PASS-with-carry-forwards**, conditional on re-opening two discharged rows and fixing
one shipped guard. Every condition was addressed in the same-day fix round (see CHANGELOG
v0.6.0-draft, "Independent verification round"); a delta re-verification precedes merge.

Method: fresh-context verifier, no reported result taken on faith — 54 shell commands, 18
targeted mutations (each turned exactly the intended assertion red and nothing else), every
discharged OBL row's condition re-derived by running its evidence commands.

Confirmed green independently: run-all (140 assertions at review time; 104→140 growth exact),
sweep 6/6 and --p5 7/7 with parity first, version authority (formats.json == CHANGELOG top; all
11 headers match their last-modifying commits), registry self-application (gate-12 blocks the
package on OBL-PKG-13; audit --ref passes), the live blocks-install refusal against
frisbii-subscriptions, the [WOW:migrate] three-state window.

## Findings → dispositions (all closed or registered in the fix round)

- **F1 (must-fix, FIXED):** install.sh's exit-5 "refusal" fired AFTER the copy loop, the
  CLAUDE.md rewrite, the stubs and both hooks — the refused target kept dangling stubs and a live
  enforcement layer, the verbatim PR-1 outcome. Refusal moved before any write; new test asserts
  the refused target is untouched.
- **F2 (discharge invalid, FIXED):** OBL-PKG-07's "with tests" did not hold — reverting the G-11
  scope fix left the whole suite green. Scope tests added (HANDOFF pointer to a foreign spec must
  not widen GATE-2's REQ set; governing spec's own REQ still binds); mutation now yields 2 red.
- **F3 (fail-open, FIXED):** the blocks-install consult was a diverging private copy of
  _gap_rows: legacy tables, unknown effects and an absent registry all installed (exit 0). Now
  all three refuse (CONSULT-ERROR, exit 4), with wiring tests + the advisory-row control
  OBL-PKG-11's condition had promised.
- **F4 (discharge partial, FIXED):** parity never compared named schemas. Implemented (schema
  tokens in GATES-SPEC must exist as formats.json keys) with a planted-fake-schema negative test.
- **F5 (single-home violation, FIXED + OBL-PKG-17):** check_parity's doc set and spec locations
  were inline literals — the parity function violated layer parity; a live stale stamp
  (CLAUDE-WOW-SECTION v0.5.0) sat in its blind spot. Doc set/spec locations now live in
  formats.json `parity`; escrow's RUN-REPORT literal now reads report_row_schema.file; stamp
  fixed. The no-inline-literals rule's own enforcement test is registered as OBL-PKG-17.
- **F6 (untested guard, FIXED):** [WOW:migrate] gained its three-state tests (greenfield refused,
  mid-migration legal, post-freeze refused).
- **F7 (spec/engine divergence, FIXED):** GATES-SPEC's subject-absent list said "an empty
  registry"; the engine (correctly) treats an empty TABLE as a valid registry — the absence that
  never passes is the file or its readability. Spec sentence corrected.
- **F8 (missing escrow class, REGISTERED):** audit-trigger hits are the escrow's third declared
  obligation class and are unchecked — folded into OBL-PKG-13's discharge condition.
- **F9 (narrow loudness, FIXED):** FR-1's check caught only uppercase-id rows; lowercase/numeric
  tables and prose registries parsed as empty. Now any table the schema cannot read, and any
  table-less registry with content, refuses; only a genuinely empty table passes (control kept).
- Nits fixed: OBL-PKG-06's dead ev anchor; install.sh's eval-masked manifest guard.

Post-fix state: 154 assertions, all suites green, sweep --p5 7/7 including parity.

## Delta re-verification at 4b94a58 — PASS

All nine findings re-tested with the original reproductions. F1: refused targets untouched across
all three defect classes (0 files, 0 hooks; complete-package control installs 42). F2: the G-11
revert mutation now goes red. F3: all three fail-open registries refuse (exit 4, 1 file), advisory
control installs. F6/F9: mutation-proven, all shapes. F5 stamp watched, not just corrected.
F8's registration judged adequate ("the layer-parity contract, satisfied"). All 11 round-1
mutations still red; live checks hold.

Accepted residuals, closed in the wording round that followed: F4's schema check covers the
three suffix families (6/21 named keys) — spec sentence aligned to the mechanism, full
both-direction coverage folded into OBL-PKG-17; N1 bash-3.2 guard fixed (`${VAR+set}`); N2
mutation-count claim corrected (1 red, not 2); N3 two mutation cause-strings shadowed by F9's
catch-all — cosmetic under mutation only, accepted.
