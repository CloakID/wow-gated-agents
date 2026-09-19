# P4 — REPORT & RECONCILE — DRAFT v0.7.3
Entry: `/wow-report <run-id>` · Output: SPEC v<N+1> (reconciled) + classified next actions · Gate: **G4 (PO sign-off)** → Jira bugs/transitions.
Load: RUN-REPORT, SPEC, `docs/GAPS.md`, status.mjs trigger counters. (v0.6.3, F-11: `docs/TRACEABILITY.md` is dropped — no phase produced it, no gate read it, and a Load line pointing at nothing makes operators invent formats mid-gate. The traceability home IS the RUN-REPORT plus the run's `reports/`, which survive archival.)

## [ORCH] — prepare, then walk with PO
1. **GATE-10 divergence diff first** (`runs/<run-id>/divergence-G4.md`, checked with `scripts/wow/gates.sh gate-10 --run <run-id> --gate G4`): compare git technical statuses / sign-offs vs Jira workflow per FORMATS §10 mapping; every out-of-mapping pair classified with the PO (git wrong / Jira wrong / **real gap** → actionable item in this walk). Ticket-side scope discussion lands in the spec (content home), cited.
2. Walk the run report. Classify every failed/blocked/parked/defect item: **fix iteration** (→ `/wow-plan` on `r<N+1>`) · **spec wrong** (→ `/wow-spec` revision) · **defer** (DEFERRED row, successor + discharge) · **accept as gap** (→ `docs/GAPS.md`, taxonomy-tagged).
3. **Reconcile the spec:** every `DEV-U<n>-<nn>` is individually ratified into SPEC v<N+1> (referenced by its stable ID) or declared a defect to revert. **`VF-U<n>-<nn>` findings are reconciled the same way** (v0.7.3, platform/F-67): a verifier finding that changed a contract, a command, or a prohibition lands in v<N+1>'s reconciliation section by its stable id — the signed spec is what P2 loads, so this is the ONLY door through which a run's hardest-won knowledge reaches the next planner. The one measured miss shipped the same credential-disclosure defect twice, a month apart, from the same corrective intent, past the reviewer who proposed it. The spec never silently diverges from the code.
4. Update single homes: REQUIREMENTS technical statuses for this run's REQ IDs, GAPS. Then close GATE-2 in its close form — `scripts/wow/gates.sh gate-2 --close --run <run-id>` (v0.6.3, F-09: the updated-row requirement binds HERE, where the work that updates the row has happened; the sweep form is a consistency lint at every other gate) — and sweep: `scripts/wow/gates.sh sweep --run <run-id>`. P4 artifacts (reconciled SPEC v<N+1>, divergence-G4, RUN-REPORT) commit under the bare lane form `[T:<run-id>]` (F-10) — never a borrowed task id.
5. **Audit triggers** (counters from status.mjs, recorded here). The table must parse back (v0.7.3, prodsim/F-74 — the natural row shape was unreadable by the deriver, which then said 'not recorded' about a recorded table; the pattern now accepts prose beside the id and a verdict beside the number, but the AT-id must LEAD cell 1 and an integer must LEAD cell 2). A literal example row:

   `| AT-1 mocks/fixtures committed, excluding controls | 0 — threshold >3, NOT HIT | ev:cmd{git diff --diff-filter=A base..int -- fixtures/ => 0 @2026-09-19} |`

   - AT-1: mocks/fixtures added **>3 this run**
   - AT-2: remediation cycles **>5 cumulative on this spec since last audit**
   - AT-3: BLOCKERs **>1 this run**
   - AT-4: stale `file:line` refs found by sweep **in docs not modified this run** ≥3 (commit-time drift is GATE-5's job — no double role)
   - AT-5: **any** AC that passed for the wrong reason
   **The trigger outcome is an obligation, not a report line:** any hit is recorded at P4 as a GAPS.md record (FORMATS §12) — typically `effect: blocks-new-feature-work`, discharge = the audit phase completing — so it survives run archival and GATE-12 enforces it. The RUN-REPORT row merely cites the record.
   Any hit → schedule an audit phase before new feature work.

## [PO] — G4 sign-off checklist
Divergence classifications right · DEV ratifications acceptable · gap/defer decisions honest (no fake green, no silent drop) · audit-trigger outcome accepted.
Close: Jira epic transition + `signed: <date> ev:jira{…}` in SPEC v<N+1> header — and GATE-9 with `--run` now RESOLVES v<N+1> itself (v0.7.3, prodsim/F-76: the plan's `spec:` header names v<N> by construction, so resolver and playbook disagreed by one version for every G4 ever closed; a blocked-draft v<N+1> is skipped and the refusal names the `--spec` route).

## [ORCH] — on sign-off
Jira: bugs from defects (linked to stories), workflow transitions to match the classified state. Fix iterations open as `runs/<YYMMDD>-<slug>-r<N+1>/`.
