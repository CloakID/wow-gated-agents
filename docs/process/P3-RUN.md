# P3 — RUN — DRAFT v0.5.0
Entry: `/wow-run <run-id>` · Output: `runs/<run-id>/RUN-REPORT.md` + commits · No human in the loop by design.

## [ORCH] — branch & merge model (the parallel-execution contract)

- Create `wow/<run-id>/base` from main at run start; `wow/<run-id>/int` from base; one worktree + branch `wow/<run-id>/U<n>` per unit, from base.
- Executors commit **only** to their unit branch. **Only the ORCH merges.** After a unit's verifier PASS: rebase `U<n>` onto `int`, merge into `int` — sequentially, in wave order. No force-push anywhere; `main` is never touched mid-run.
- **Conflict policy:** conflicts inside a unit's owned paths are impossible by construction (GATE-8 partitioned them) — if one occurs it is a **plan defect** `DEF-plan-<nn>`: log it, ORCH resolves (owner unit's version wins unless integration contract says otherwise), record `ev:commit`. Conflicts in generated/lock files: resolve by regeneration, never hand-merge.
- Integration wave executes on `int` (same executor/verifier discipline). Run reaches `main` only after integration verify passes — PR or fast-forward per `wow.config.json`.

## [ORCH] — orchestrate

1. Start 3–4 concurrent executors, fresh context each. Executor manifest = its unit's PLAN section + interface contracts + CONVENTIONS + the `[AGENT]` sections of this file. **Nothing else.**
2. After each unit's executor finishes → spawn its **verifier AGENT** (fresh context; different model where possible; manifest = that unit's SPEC ACs + contracts + verify commands + `[AGENT] verifier` section; **never the implementer transcript**).
3. Verifier findings (`VF-U<n>-<nn>`) → fix wave in executor context → **re-validate every fix** (verifier context, delta scope). Loop until clean or parked (FORMATS §7).
4. **Wave boundaries — cascade rule (ORCH only, never executors):** mark every task downstream of a PARKED/BLOCKED task as `BLOCKED(cascade:<source-id>)`; independent tasks proceed. **If >50% of the next wave is cascade-blocked, terminate the run early → P4.**
5. Tier escalation per P2 §tiers at wave boundaries. Assemble RUN-REPORT.md from `reports/*.md`; maintain HANDOFF.md. (PLAN, RUN-REPORT, HANDOFF, jira-queue are ORCH-owned — FORMATS §9.)

## [AGENT] — executor

- Do only your task list, in order, on **your unit branch only** — never merge, rebase, push shared branches, or touch files outside your ownership list.
- One atomic commit per task, message with `[T:<task-id>]`. Each task: implement → run its verify command → record `ev:cmd` in your report file.
- **Autonomy contract:** in-contract deviation → decide, implement, log `DEV-U<n>-<nn>` (what/why/impact). Cross-unit, AC-touching, or irreversible → **park**: `PARK-U<n>-<nn>` blocker note (facts only), skip, continue. Never ask questions; anomalies are parked, not investigated (the ORCH routes them to the debug lane after the run).
- Write only `runs/<run-id>/reports/U<n>.md`: per-task status (FORMATS §4 + `ev:`), deviations, parks, observations.

## [AGENT] — verifier

- Re-derive pass/fail per AC and per task verify command — run them yourself; record your own `ev:`. Do not trust recorded results.
- Attempt the premise failure on flagged ACs: check the thing the AC is *about*, not the harness.
- Grade: PASS / PASS-with-carry-forwards (CV records, FORMATS §5) / FAIL (`VF-U<n>-<nn>` with evidence). Write only `reports/U<n>-verify.md`. If you need context, read code and contracts, not transcripts.

## RUN-REPORT.md structure [ORCH]
`completed / failed / blocked / parked / deviations / defects / new-gaps` — rows per FORMATS §4–5, every completion row evidence-cited (GATE-3), one line per row.
