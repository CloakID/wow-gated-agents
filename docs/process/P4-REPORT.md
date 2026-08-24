# P4 — REPORT & RECONCILE — DRAFT v0.6.3
Entry: `/wow-report <run-id>` · Output: SPEC v<N+1> (reconciled) + classified next actions · Gate: **G4 (PO sign-off)** → Jira bugs/transitions.
Load: RUN-REPORT, SPEC, `docs/GAPS.md`, status.mjs trigger counters. (v0.6.3, F-11: `docs/TRACEABILITY.md` is dropped — no phase produced it, no gate read it, and a Load line pointing at nothing makes operators invent formats mid-gate. The traceability home IS the RUN-REPORT plus the run's `reports/`, which survive archival.)

## [ORCH] — prepare, then walk with PO
1. **GATE-10 divergence diff first** (`runs/<run-id>/divergence-G4.md`, checked with `scripts/wow/gates.sh gate-10 --run <run-id> --gate G4`): compare git technical statuses / sign-offs vs Jira workflow per FORMATS §10 mapping; every out-of-mapping pair classified with the PO (git wrong / Jira wrong / **real gap** → actionable item in this walk). Ticket-side scope discussion lands in the spec (content home), cited.
2. Walk the run report. Classify every failed/blocked/parked/defect item: **fix iteration** (→ `/wow-plan` on `r<N+1>`) · **spec wrong** (→ `/wow-spec` revision) · **defer** (DEFERRED row, successor + discharge) · **accept as gap** (→ `docs/GAPS.md`, taxonomy-tagged).
3. **Reconcile the spec:** every `DEV-U<n>-<nn>` is individually ratified into SPEC v<N+1> (referenced by its stable ID) or declared a defect to revert. The spec never silently diverges from the code.
4. Update single homes: REQUIREMENTS technical statuses for this run's REQ IDs, GAPS. Then close GATE-2 in its close form — `scripts/wow/gates.sh gate-2 --close --run <run-id>` (v0.6.3, F-09: the updated-row requirement binds HERE, where the work that updates the row has happened; the sweep form is a consistency lint at every other gate) — and sweep: `scripts/wow/gates.sh sweep --run <run-id>`. P4 artifacts (reconciled SPEC v<N+1>, divergence-G4, RUN-REPORT) commit under the bare lane form `[T:<run-id>]` (F-10) — never a borrowed task id.
5. **Audit triggers** (counters from status.mjs, recorded here):
   - AT-1: mocks/fixtures added **>3 this run**
   - AT-2: remediation cycles **>5 cumulative on this spec since last audit**
   - AT-3: BLOCKERs **>1 this run**
   - AT-4: stale `file:line` refs found by sweep **in docs not modified this run** ≥3 (commit-time drift is GATE-5's job — no double role)
   - AT-5: **any** AC that passed for the wrong reason
   **The trigger outcome is an obligation, not a report line:** any hit is recorded at P4 as a GAPS.md record (FORMATS §12) — typically `effect: blocks-new-feature-work`, discharge = the audit phase completing — so it survives run archival and GATE-12 enforces it. The RUN-REPORT row merely cites the record.
   Any hit → schedule an audit phase before new feature work.

## [PO] — G4 sign-off checklist
Divergence classifications right · DEV ratifications acceptable · gap/defer decisions honest (no fake green, no silent drop) · audit-trigger outcome accepted.
Close: Jira epic transition + `signed: <date> ev:jira{…}` in SPEC v<N+1> header (GATE-9).

## [ORCH] — on sign-off
Jira: bugs from defects (linked to stories), workflow transitions to match the classified state. Fix iterations open as `runs/<YYMMDD>-<slug>-r<N+1>/`.
