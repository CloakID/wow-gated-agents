# Changelog

Draft-stage repo: versions move fast pre-1.0, and process docs may run ahead of the engine **only** when the debt is marked in the gate table and recorded as an open obligation in `docs/GAPS.md` (the layer-parity rule, v0.5.3). Run `./install.sh --check` in a consuming repo to see what an upgrade changes. Tags land only at doc/engine parity milestones. **The top entry of this file is the package version — the single authority (v0.5.5, pilot N2).** File headers carry the version of the commit that last modified them — checked against git history (`git log -1 -- <file>`), not merely against the entry list, or every stale stamp passes (pilot D2); `formats.json`'s stamp must equal the top entry. Both checks join the parity sweep (OBL-PKG-08).

## v0.6.0-draft — 2026-08-18
- **The engine session.** Doc/engine parity restored: registry worked down from 12 open rows to 7 (all advisory). Discharged: OBL-PKG-07 (G-11 `_governing_sources` gate_2 scope repair merged upstream — step zero), OBL-PKG-02 (gate-6 refuses missing/unparseable plans; subject-absent tests + positive control, non-vacuity proven by disabling the fix), OBL-PKG-01 (gate_12 obligation block with closed-enum validation and audit/fix/probe exemptions; GATE-7 obligation escrow; status.mjs reads GAPS.md and reports what the state requires next; `gap_row` schema), OBL-PKG-08 (layer-parity check runs first in every sweep: spec table vs engine registry vs formats.json, DESIGNED-NOT-IMPLEMENTED markers must name open obligations, version authority incl. the D2 git-history header predicate), OBL-PKG-11 (install.sh refuses on an open scope-matched `blocks-install` row, exit 4).
- TF-01: the test harness's own `| grep -q` under pipefail was a SIGPIPE race — passed on one machine, failed deterministically on another; all pipelines now read to EOF.
- Still open (advisory): OBL-PKG-03 (subject-absent audit across remaining gates), -04/-05/-06 (await pilot F-4/F-7/G-15 texts), -09 (vacuity report), -10 (--uninstall), -12 (install modes + drift-refusal).

## v0.5.6 — 2026-08-17
- Pilot round-3 findings: D1 — `blocks-install` consumer clause marked DESIGNED-NOT-IMPLEMENTED and registered as OBL-PKG-11 (v0.5.5 had repeated the layer-parity violation inside the release marking the parity rule; OBL-PKG-07 read as protected while nothing consumed it); scoping decided: install.sh reads the package's own registry, rows carry `scope:` (OBL-PKG-07 = `*` — canonical gate_2 is defective for every target until G-11 merges). D2 — version-stamp predicate corrected to header == version of last-modifying commit (the prior wording passed every stale stamp); stale headers corrected (README, INSTALL, GATES-SPEC, FORMATS). D3 — README status now points at the CHANGELOG authority instead of embedding a version that goes stale. Install modes added (PO design question): `--mode fresh|upgrade|migrate` as declared intent verified against derived target state, refusing on mismatch; drift-refusal guard (never silently overwrite locally-modified files) generalizes the G-11 protection — OBL-PKG-12.

## v0.5.5 — 2026-08-17
- Pilot #2 reassessment residuals + N-findings: parity claim in GATES-SPEC now carries its own DESIGNED-NOT-IMPLEMENTED marker (OBL-PKG-08); install vacuity check is a committed artifact (`docs/install-vacuity.md`), not a mental note; version authority defined (this file's top entry; enforced via parity sweep); `effect` vocabulary closed and widened to `blocks-install` (consumer: install.sh; unrecognized values fail loudly) — OBL-PKG-07 reclassified accordingly; migration steps cited by name, not number.

## v0.5.4 — 2026-08-17 (entry added retroactively in v0.5.5 — its omission was pilot finding N1)
- Pilot #2 (brownfield) plan-review adoptions: OBL-PKG-08 (layer-parity sweep unregistered — the rule violated itself), OBL-PKG-09 (install vacuity report), OBL-PKG-10 (--uninstall); migration gains legacy-invariant re-homing before the GATE-11 freeze (hard stop), permissions regeneration as reviewed merge, brownfield vacuity warning, rollback recipe.

## v0.5.3 — 2026-08-16
- **Subject-absent rule** (from pilot feedback PF-04): every gate now requires two negative tests — violation-present and subject-absent; an absent or unparseable subject is never a pass. Origin: GATE-6 returned PASS for a run with no PLAN.md.
- **Layer-parity rule** (PF-05): spec-first changes are legal only with a paired open obligation in `docs/GAPS.md`; the sweep compares doc-declared gates/schemas against the engine registry.
- GATE-12 and the GATE-7 escrow clause explicitly marked **designed-not-implemented** pending OBL-PKG-01.
- `docs/GAPS.md` added: this repo now uses its own obligation registry (OBL-PKG-01…07).
- Known engine debt (open, blocking new feature work on this package): GATE-12, GATE-7 escrow, status.mjs GAPS derivation, `gap_row` schema, gate-6 subject-absent fix.

## v0.5.2 — 2026-08-16 (spec-only; engine debt tracked as OBL-PKG-01)
- **Obligations get a home** (PF-03): FORMATS §12 — `docs/GAPS.md` is the obligation registry (gap records + `owner` + `effect: advisory | blocks-new-feature-work` + successor + discharge). No new artifact class, no narrative state.
- GATE-12 (obligation block at `/wow-spec`) and GATE-7 obligation escrow **specified** (implementation pending — see v0.5.3 markings).
- P4: audit-trigger hits recorded as durable obligations, not report lines. LANES rule 5: recording findings between runs is quick-lane work.

## v0.5.1 — 2026-08-14
- **Probe-spec route** (PF-02): P1 gains "when the spec cannot be written yet" — decision/fact classification (judgment, not a gate), `SPEC-<feature>-probe-v1` whose ACs govern answer quality, blocked-draft convention, corrections-not-deviations on reopening, the empty-probe trap named (unanswered count PO-accepted at G4), and the no-probes-for-decisions guardrail.

## v0.5.0-draft — 2026-08-14
- **Runnable enforcement engine**: gates.sh (+gates.py), formats.json, status.mjs, install.sh, permissions-policy template; per-gate negative tests + install/wiring tests (19 passing).

## v0.4.1 — 2026-08-13
- **External-dependency maps** (PF-01): FORMATS §11 — `docs/deps/<name>.md` with probe-hash freshness (max_age fallback); GATE-6 extended to declared deps; P0 probe-refresh step.

## v0.4 — 2026-08-10
- Initial public draft: thin CLAUDE.md router, phase playbooks P0–P5 (audience-labeled), LANES, FORMATS, GATES-SPEC (GATE-1…11), INSTALL with three-layer reliability model and GSD coexistence (GATE-11).
