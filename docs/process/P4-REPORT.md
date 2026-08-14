# P4 — REPORT & RECONCILE — DRAFT v0.5.0
Entry: `/wow-report <run-id>` · Output: SPEC v<N+1> (reconciled) + classified next actions · Gate: **G4 (PO sign-off)** → Jira bugs/transitions.
Load: RUN-REPORT, SPEC, `docs/GAPS.md`, `docs/TRACEABILITY.md`, status.mjs trigger counters.

## [ORCH] — prepare, then walk with PO
1. **GATE-10 divergence diff first** (`runs/<run-id>/divergence-G4.md`, checked with `scripts/wow/gates.sh gate-10 --run <run-id> --gate G4`): compare git technical statuses / sign-offs vs Jira workflow per FORMATS §10 mapping; every out-of-mapping pair classified with the PO (git wrong / Jira wrong / **real gap** → actionable item in this walk). Ticket-side scope discussion lands in the spec (content home), cited.
2. Walk the run report. Classify every failed/blocked/parked/defect item: **fix iteration** (→ `/wow-plan` on `r<N+1>`) · **spec wrong** (→ `/wow-spec` revision) · **defer** (DEFERRED row, successor + discharge) · **accept as gap** (→ `docs/GAPS.md`, taxonomy-tagged).
3. **Reconcile the spec:** every `DEV-U<n>-<nn>` is individually ratified into SPEC v<N+1> (referenced by its stable ID) or declared a defect to revert. The spec never silently diverges from the code.
4. Update single homes: REQUIREMENTS technical statuses for this run's REQ IDs (GATE-2 requires the row to be *updated in this run*, not merely present), GAPS, TRACEABILITY (new evidence artifacts). Then sweep: `scripts/wow/gates.sh sweep --run <run-id>`.
5. **Audit triggers** (counters from status.mjs, recorded here):
   - AT-1: mocks/fixtures added **>3 this run**
   - AT-2: remediation cycles **>5 cumulative on this spec since last audit**
   - AT-3: BLOCKERs **>1 this run**
   - AT-4: stale `file:line` refs found by sweep **in docs not modified this run** ≥3 (commit-time drift is GATE-5's job — no double role)
   - AT-5: **any** AC that passed for the wrong reason
   Any hit → schedule an audit phase before new feature work.

## [PO] — G4 sign-off checklist
Divergence classifications right · DEV ratifications acceptable · gap/defer decisions honest (no fake green, no silent drop) · audit-trigger outcome accepted.
Close: Jira epic transition + `signed: <date> ev:jira{…}` in SPEC v<N+1> header (GATE-9).

## [ORCH] — on sign-off
Jira: bugs from defects (linked to stories), workflow transitions to match the classified state. Fix iterations open as `runs/<YYMMDD>-<slug>-r<N+1>/`.
