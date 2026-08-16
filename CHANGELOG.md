# Changelog

Draft-stage repo: versions move fast pre-1.0, and process docs may run ahead of the engine **only** when the debt is marked in the gate table and recorded as an open obligation in `docs/GAPS.md` (the layer-parity rule, v0.5.3). Run `./install.sh --check` in a consuming repo to see what an upgrade changes. Tags land only at doc/engine parity milestones.

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
