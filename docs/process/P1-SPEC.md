# P1 — SPEC — DRAFT v0.5.0
Entry: `/wow-spec <feature>` · Output: `docs/spec/SPEC-<feature>-v1.md` (durable) · Gate: **G1 (PO sign-off)** → Jira epic.
Load: prior spec version (if any), `docs/REQUIREMENTS.md`, `docs/GAPS.md`, `docs/codebase/<area>.md`, open ADRs. Nothing else.

## [ORCH] — run the discussion
1. Elicit and draft iteratively with the PO: objectives · scope boundaries (in/out) · architecture approach + alternatives considered · dependencies (internal, external, new) · tooling.
2. **Acceptance criteria table:** executable wherever possible — columns: `AC-<n>` · check (`ev:cmd` template, test suite, script, measurement) · **harness-touching?** (verify uses mocks/fixtures/harness/simulated deps) · premise answer. A prose AC must name a manual-check owner.
3. **Premise check (blocking for flagged ACs):** for every harness-touching AC, answer in the table — *"can this AC pass for the wrong reason (mock, harness artifact, wrong component)?"* (Canonical failure: a capability checked off against a component that does a different job.) Non-flagged ACs: optional one-liner — do not ritualize.
4. Maintain inline: assumption table (`A-<nn>` rows per FORMATS §2) and open-questions list. The spec is not signable while a load-bearing assumption is unvalidated **and** unowned, or an open question blocks an AC.
5. Requirement changes land in `docs/REQUIREMENTS.md` (single home) as `REQ-<nnn>` rows; the spec references IDs.

## [PO] — G1 sign-off checklist
Objectives match intent · scope boundaries right · every AC has a check (+ premise answer where flagged) · assumption owners acceptable · dependencies acceptable.
Close: Jira epic created + transitioned, mirrored as `signed: <date> ev:jira{…}` in the spec header — verified by `scripts/wow/gates.sh gate-9 --gate G1 --spec docs/spec/<SPEC>.md`.

## [ORCH] — on sign-off
Open the run dir `runs/<YYMMDD>-<slug>-r1/`. GATE-10 divergence diff if a prior epic exists (`runs/<run-id>/divergence-G1.md`, checked with `scripts/wow/gates.sh gate-10 --run <run-id> --gate G1`); create the epic (spec summary + link), record `ev:jira{…}` in the spec header and HANDOFF. Sweep at the gate: `scripts/wow/gates.sh sweep --run <run-id>`.
