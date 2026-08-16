# P1 — SPEC — DRAFT v0.5.1
Entry: `/wow-spec <feature>` · Output: `docs/spec/SPEC-<feature>-v1.md` (durable) · Gate: **G1 (PO sign-off)** → Jira epic.
Load: prior spec version (if any), `docs/REQUIREMENTS.md`, `docs/GAPS.md`, `docs/codebase/<area>.md`, open ADRs. Nothing else.

## [ORCH] — run the discussion
1. Elicit and draft iteratively with the PO: objectives · scope boundaries (in/out) · architecture approach + alternatives considered · dependencies (internal, external, new) · tooling.
2. **Acceptance criteria table:** executable wherever possible — columns: `AC-<n>` · check (`ev:cmd` template, test suite, script, measurement) · **harness-touching?** (verify uses mocks/fixtures/harness/simulated deps) · premise answer. A prose AC must name a manual-check owner.
3. **Premise check (blocking for flagged ACs):** for every harness-touching AC, answer in the table — *"can this AC pass for the wrong reason (mock, harness artifact, wrong component)?"* (Canonical failure: a capability checked off against a component that does a different job.) Non-flagged ACs: optional one-liner — do not ritualize.
4. Maintain inline: assumption table (`A-<nn>` rows per FORMATS §2) and open-questions list. The spec is not signable while a load-bearing assumption is unvalidated **and** unowned, or an open question blocks an AC.
5. Requirement changes land in `docs/REQUIREMENTS.md` (single home) as `REQ-<nnn>` rows; the spec references IDs.

## [ORCH] — when the spec cannot be written yet (added v0.5.1, pilot feedback PF-02/F-5)

If step 4 blocks signability, classify each blocking open question — this is **judgment, not a gate** (GATES-SPEC not-gates list): a **decision** (what to build, scope, tier — the PO can settle it in discussion) re-enters step 1; a **fact** (a property of a system outside this repo: what a vendor API permits, what an environment contains, whether a feature exists) cannot be settled by any amount of discussion and takes the probe route:

1. Write `docs/spec/SPEC-<feature>-probe-v1.md`. Its deliverable is an **evidence-backed answer set, not product**. Its ACs govern answer quality: every question answered or explicitly recorded unanswered with its reason · every claim `ev:`-cited · the probed environment left in a known state. It is an ordinary spec — own G1, small plan (usually one unit), normal run.
2. Hold the original as a **blocked draft**: header carries `status: blocked-draft`, the blocking question IDs, and a note that its ACs are provisional and unsigned. It preserves every decision already taken. GATE-9 already prevents a blocked draft from ever being treated as signed.
3. **Durable facts land in their single home, not only in the answer set:** external-surface findings update `docs/deps/<name>.md` (FORMATS §11, refreshed probe hash included); environment facts update the codebase map. The answer set is a run artifact that *cites* those homes — otherwise the probe route creates a second home for external facts.
4. On probe close, rewrite the held draft against the findings and take it to its own G1. Facts contradicting the draft are **corrections, not deviations** — the draft was never signed, so nothing is being ratified and no DEV record is owed.

**The trap, named because it will be hit:** a probe that answers nothing still produces a well-formed document — "unanswered" twelve times satisfies the AC shape. No mechanical check separates a thorough probe from an empty one. The mitigation is not another gate: the **unanswered count is reported to the PO at the probe's G4 as a number**, and PO acceptance of that number is the real gate. Mechanics enforce only that nothing is silently blank.

**Guardrail:** never open a probe for a question the PO can simply answer — a probe spec for a decision is procedure theatre costing two extra gate walks. The classification step above exists to prevent exactly that.

## [PO] — G1 sign-off checklist
Objectives match intent · scope boundaries right · every AC has a check (+ premise answer where flagged) · assumption owners acceptable · dependencies acceptable.
Close: Jira epic created + transitioned, mirrored as `signed: <date> ev:jira{…}` in the spec header — verified by `scripts/wow/gates.sh gate-9 --gate G1 --spec docs/spec/<SPEC>.md`.

## [ORCH] — on sign-off
Open the run dir `runs/<YYMMDD>-<slug>-r1/`. GATE-10 divergence diff if a prior epic exists (`runs/<run-id>/divergence-G1.md`, checked with `scripts/wow/gates.sh gate-10 --run <run-id> --gate G1`); create the epic (spec summary + link), record `ev:jira{…}` in the spec header and HANDOFF. Sweep at the gate: `scripts/wow/gates.sh sweep --run <run-id>`.
