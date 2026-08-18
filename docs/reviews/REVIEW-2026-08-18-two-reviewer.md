# Two-reviewer framework review — 2026-08-18 (engine-v0.5.x, v0.6.0-draft)

Method: two independent fresh-context reviewers, one per consuming repo, each RUNNING the
v0.6.0 engine against that repo's real artifacts (copies; nothing mutated). Dispositions
recorded per finding; fixes landed in branch commit 39c3da0; the rest registered as
OBL-PKG-13..16. This file is the durable home for the findings (LANES rule 5 — a finding
outside a run is quick-lane work; it must not live only in a conversation).

## Reviewer A — frisbii-subscriptions standpoint (greenfield pilot, installed v0.5.1-era)

FR-1 (breaks-upgrade → FIXED 39c3da0): frisbii's real GAPS.md (5 columns, G-nn ids) parsed as an
EMPTY registry — gate-12 reported "0 open rows" and status.mjs "nothing blocks". Green-because-empty:
the subject-MALFORMED sibling of subject-absent. Fix: any letter-prefixed id-shaped row the gap_row
schema cannot read is a loud failure; frisbii's exact table shape is now a negative test.
ev:cmd{gates.sh gate-12 --kind feature (pre-fix, frisbii GAPS) => GATE-12 PASS "0 open row(s)"}

FR-2 (misleads → REGISTERED OBL-PKG-13, blocks-new-feature-work): report_row regex matched only
table HEADERS in the pilot's real RUN-REPORT ("Check","Tasks","Record","Defect" read as statuses);
the pilot's short-form CV-01..05 never match the cannot_validate regex; the escrow's substring
match is defeated by GAPS-side ellipsis abbreviations. GATE-3 + escrow vacuous on real artifacts.
Fix direction: status located by COLUMN HEADER (as GATE-8's Verify fix), escrow parses ids, CV id
policy reconciled.

FR-3 (breaks-upgrade → REGISTERED OBL-PKG-14, blocks-install scope: frisbii-subscriptions):
no reconciliation step exists for present-but-nonconforming durable homes; plain install would
overwrite drifted files (drift-refusal = OBL-PKG-12, open). The package now refuses to upgrade
frisbii until a tested row-migration recipe exists.

FR-4 (misleads → FIXED): gate-12 had engine + tests but no invoker. Now P1 step 0. Kind
classification stays judgment; the invocation lands as ev:cmd in the spec header.

FR-5 (misleads → FIXED): blocks-install consult hardened — fails CLOSED on registry/parse errors
("never silently non-blocking"), --check now REPORTS a pending refusal instead of hiding it.
Residual accepted: scope matches basename(target); wow.config `repo:` field not consulted (nit,
revisit with OBL-PKG-14).

FR-6 (misleads → REGISTERED OBL-PKG-15): pilot defects G-12 (probes run shell=True), G-13, G-14,
G-16 (archived-empty run dirs listed active) unaddressed and previously chased nowhere durable.

FR-7 / G-15 (misleads → FIXED, OBL-PKG-06 discharged): "Enforced" claim for GATE-3 corrected —
it is sweep-checked (gate close + P5), not commit-enforced; a bad citation lands and is caught at
the next gate.

FR-8 (nit → FIXED): parity's version-authority half silently skipped in consumer repos; it now
says so explicitly ("package-repo check — skipped here").

FR-9 (friction → REGISTERED OBL-PKG-16, PO): docs/pilot-feedback.md PF/F ids are load-bearing
upstream but no FORMATS section defines the log; FINDINGS.md (audit verdict table) and GLOSSARY
are unnamed artifact classes; frisbii HANDOFF at 81 lines (repo-fix).

Credited right: the 79KB real PLAN.md parses and GATE-8 passes non-vacuously; G-11 merged
upstream with tests rather than advised; status.mjs derives correctly from real artifacts
including blocked-draft recognition.

## Reviewer B — cloakid-platform standpoint (brownfield, pre-install)

PR-1 (breaks-install → FIXED): copy_as silently skipped missing package sources; an incomplete
package installed with dangling stubs, no router, and --check said "no drift". (Trigger was the
review scratch environment, but the engine defect was real.) Fix: pre-copy self-integrity —
every stub-target playbook, the CLAUDE section source, and engine files must exist; missing ⇒
REFUSED exit 5; --check reports MISSING-IN-PACKAGE.

PR-2 (misleads → covered by PR-1 fix): status.mjs and --check could disagree about install
completeness (dual-consumer drift the parity sweep didn't cover).

PR-3 (misleads → doc-FIXED; automation stays OBL-PKG-09): day-one sweep is 7/7 vacuous green in a
homeless brownfield repo; INSTALL asserted the vacuity artifact in present tense. Now: the operator
WRITES docs/install-vacuity.md by hand as a mandatory step until OBL-PKG-09 automates it.

PR-4 (friction/misleads → FIXED): migration commits had no legal lane ref, training operators that
[WOW:publish] is a skip token. New [WOW:migrate] ref, valid ONLY while .planning/ exists AND
migrated_from_gsd is false — it dies with the migration. Negative-tested.

PR-5 (misleads → REGISTERED OBL-PKG-16, PO): effect cells are ungoverned — a silent one-word edit
(blocks-new-feature-work → advisory) unblocks feature work with no gate, no ev, no sign-off;
GAPS.md is outside scan_targets. Options: require ev: on any effect transition / add GAPS.md to
scan_targets / diff-gate effect changes at gate open.

PR-6 (friction → doc-FIXED as named risk): until the freeze flips nothing blocks /gsd:* writing
.planning/. Window is now named in the Migration playbook: accept consciously, keep it short.

PR-7 (nit → platform-side): OBL-PLAT-21 discharged in prose but its id not struck — engine counts
it open forever. Also: escaped pipes are safe only in the trailing ev cell (now a FORMATS §12 rule).

PR-8 (friction → doc-FIXED): Migration step 2 wasn't executable as written ("surface index"
undefined, .planning/codebase/ absent on platform, TRACEABILITY had no formats.json home). Step now
demands a per-artifact source→destination list per repo before day one.

Credited right: GATE-11 verified blocking edits/deletions/worktree commits, inert-by-config
pre-flip; day-one gate-12 against platform's real registry is loud and useful (exactly the 7
intended blockers, named, with the --ref discharge path); migration step 4 precisely anticipates
check_21/41/43 going inert-green.
