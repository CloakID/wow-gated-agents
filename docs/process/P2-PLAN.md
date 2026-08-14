# P2 — PLAN — DRAFT v0.5.0
Entry: `/wow-plan <run-id>` · Output: `runs/<run-id>/PLAN.md` (ORCH-owned, machine-parseable per formats.json `plan_schema`) · Gate: **G2 = GATE-8 lint → adversarial review → PO sign-off** → Jira stories/tasks.
Load: signed SPEC, `docs/codebase/<area>.md`, CONVENTIONS, sibling-unit contracts if replanning.

## [ORCH] — decompose
1. Split into units `U<n>`, sized for **independent verifiability**, not minimality. Per unit:
   - **file-ownership list** `owns:` (paths it may write; ORCH-owned files excluded per FORMATS §9);
   - **`areas:`** — the codebase areas the unit touches (FORMATS §6) and **`deps:`** — the external dependencies it relies on (FORMATS §11). These are GATE-6's input: a plan that declares no `areas:` fails the gate rather than passing with nothing to check;
   - **interface contracts** (signatures/schemas/events), frozen at G2;
   - task list `T<nn>` — action · verify (`ev:cmd` template) · done-means;
   - **autonomy contract** (decide-and-log vs park; cross-unit/AC-touching/irreversible always park);
   - model tier and wave assignment.
2. Dependency/wave order; **serial integration wave last** with its own tasks + verifies; branch model per P3 (base/U<n>/int).
3. **AC↔task coverage matrix** (required — GATE-8 checks totality).
4. New invariants/checks ship with non-vacuity proofs (GATE-4).

## [ORCH] — G2a: lint, then review
1. Run **GATE-6** and **GATE-8**, in that order — both mechanical, both cheap:

   ```sh
   scripts/wow/gates.sh gate-6 --run <run-id>   # areas: + deps: freshness (FORMATS §6, §11)
   scripts/wow/gates.sh gate-8 --run <run-id>   # ownership, coverage totality, verify commands, schema
   ```

   GATE-8 checks ownership overlaps (incl. ORCH-owned files), coverage-matrix totality against the SPEC's AC rows, a verify command in every task's **Verify** column (located by header, not position), and that PLAN.md parses against `plan_schema`. Fix until green — reviewer time is not spent on grep-able defects.
2. Spawn reviewer AGENT (fresh context; input = SPEC + PLAN only). **Judgment scope only:** contract gaps between units · premise checks on plan-level verifies ("does this verify test the product or the harness?") · unit-sizing sanity · autonomy-contract adequacy vs risk. Findings → revise → delta re-review (FORMATS §7).

## [PO] — G2b sign-off checklist
Unit boundaries sensible · autonomy contracts match risk appetite · irreversible actions parked-by-design · tier assignments acceptable.
Close: Jira transition + `signed: <date> ev:jira{…}` in PLAN header, then verify it mechanically — `scripts/wow/gates.sh gate-9 --gate G2 --run <run-id>` (with `--gate`, the record is required, not merely consistent).

## [ORCH] — on sign-off
GATE-10 divergence diff first — write `runs/<run-id>/divergence-G2.md` (Item | Git | Jira | Classification) and check it with `scripts/wow/gates.sh gate-10 --run <run-id> --gate G2`; classify any git↔Jira difference per FORMATS §10. Then create stories per unit, tasks per task, parent-linked; bodies carry PLAN excerpts + links. Record `ev:jira{…}`. Run the gate sweep at the gate: `scripts/wow/gates.sh sweep --run <run-id>`.

## §tiers [ORCH]
Spec/plan/review/verify: top tier. Execution: mid. Mechanical: low. One-tier auto-escalation after a failed verify — applied by ORCH at wave boundaries; AGENTs never self-select tier.
