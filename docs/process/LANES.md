# LANES — quick & debug playbooks + precedence — DRAFT v0.7.4

## Lane refs (GATE-1) **[ORCH]**

Every commit carries exactly one lane ref; GATE-1 (commit-msg hook) blocks the rest. Trailers in backticks or fenced/indented blocks are mentions and do not count (F-07) — a commit about lane behaviour can name the trailers it discusses. The full set — this list and `formats.json commit_trailers` are two declarations of the same set, and the parity sweep compares them both ways (v0.6.1, PF-b):

- `[T:<run-id>.T<nn>]` — main lane; must resolve to a task **row** in that run's `PLAN.md`.
- `[T:<run-id>]` — bare form (v0.6.3, F-08/F-10): a run's **phase-level artifacts and ORCH-owned run bookkeeping at ANY phase** (P1 spec + HANDOFF, mid-P3 HANDOFF updates and `runs/<id>/orch/*` records, P4 reconciled spec / divergence / RUN-REPORT — clarified v0.7.2 per the F-08 addendum: a pilot improvised a `T00` task row and then a faked publish trailer because the wording read as P1/P4-only; the mechanism always resolved the run directory, so the bare form IS the lane for ORCH bookkeeping whenever it happens); resolves to the run directory, which may exist before its plan. Task work still uses the fully-qualified form — a borrowed task id on phase work is the improvisation this form exists to end.
- `[Q:runs/quick/<dir>]` — quick lane; the dir must exist.
- `[D:<slug>]` — debug lane; `runs/debug/<slug>.md` must exist (investigation is read-only, so a `[D:]` commit carries the debug record itself, never a fix).
- **Merge commits** (the ORCH's `merge --no-ff U<n>` into `int`, base→unit after an amendment, `main` into the run branch at P5 step 0) commit under the bare `[T:<run-id>]`; a merge carries no authored diff, so GATE-1's phase-artifact scope rule (v0.7.4, platform/F-72) does not apply to it — the gate detects `MERGE_HEAD` (ADV-R11-02).
- `[WOW:publish]` — package/process publishing commits (P5 and framework maintenance); resolves to nothing by design.
- `[WOW:migrate]` — migration-window commits only (lifting durables out of `.planning/`): legal **only** while `.planning/` exists AND `migrated_from_gsd` is still false. Greenfield repos and post-freeze repos reject it (added v0.6.0, PR-4).

## Precedence rules **[ORCH]**

1. Defect/anomaly discovered (any source: run, review, user report, monitoring) → **debug lane first**. Never straight to a fix, even a 1-line one.
2. Debug exits only through classification (INVESTIGATE-THEN-ASK): facts + impact captured → **PO classifies** → routine + all quick criteria hold → quick lane, NOTE.md references the debug file; otherwise → main lane (fix iteration `r<N+1>` on the affected spec, or `/wow-spec` if the spec itself is wrong).
3. Quick lane is only for changes whose **scope is known at start**. Scope grows past any quick criterion mid-work → stop, park the diff, reroute to main lane.
4. Read-only work needs no lane. Any change landing in git needs a lane (GATE-1 enforces).
5. **Recording a finding outside a run is quick-lane work** (added v0.5.2, PF-03): a gap, obligation, or feedback item discovered between runs goes into its durable home (GAPS.md, REQUIREMENTS, dep map) via `/wow-quick` — the framework should prompt this, not rely on someone thinking to ask. **Look before filing** (v0.7.4, platform/F-81 — the same reasoning, one step earlier): search the durable home for a row that already covers the finding before creating one; a duplicate was once filed `advisory` against a row that predated it and carried `blocks-new-feature-work`, weaker as well as redundant, by an author who wrote *"filed for this before the registry was searched"*. Four independent authors in one repo hand-wrote a *"so a successor need not rediscover"* guard into rows because the framework offered no carrier for it; this sentence is the carrier.

## Quick lane **[ORCH]**

Criteria (all): **≤2 files the change chooses, plus any co-edit an existing gate or check makes mandatory** (v0.7.2, platform/F-64: a suite with a denominator sentinel FORCES a third file per added check — counting forced co-edits priced a one-check change at a full main-lane run, which is the shape that gets rules quietly bent; the mechanical test that stops the exception becoming a loophole: make the change alone, run the gate set, and the files it turns red are the co-edits — anything else is scope and reroutes as before) · no interface/schema change · reversible · no new dependency · no prod config.
Steps: create `runs/quick/<YYMMDD>-<slug>/NOTE.md` → sections: `what` / `why` / `verify` (an `ev:cmd` you will run) / `result`. Implement. Run the verify command; record `ev:`. Commit with `[Q:…]`. Done — no other artifacts, no Jira item (unless the change touches a tracked story; then comment on it).
A NOTE.md with empty `result` older than 7 days is a stale stub — GC'd at next PUBLISH (listed, PO confirms deletion).

## Debug lane **[ORCH]**

**Two artifacts for two readers** (v0.7.4, prodsim/F-80 — raised by a PO: *"you are asking for a decision without proper structure in place; I will not examine the records and the repo"*). The old shape put the PO's decision at the BOTTOM of the implementer's investigation, so deciding was conditional on reading it, and four well-formed records were together undecidable.

**1. The investigation** — `runs/debug/<slug>.md`, for whoever implements the disposition: symptom (with `ev:`) · environment facts · impact facts · reproduction (or why not) · hypotheses (labeled INFERENCE). Investigation is **read-only** — no fixes from this lane. **Measure the exposure before asking**: where severity turns on *has this already caused harm?*, answer it in the record (run the absent gate over the committed evidence, count the affected rows) — one such fact was worth more to the decision than the 156 lines around it.

**2. The decision surface** — `runs/debug/classification-request.md` (`runs_layout.debug_decision`; commits under `[D:classification-request]` — the file exists under `runs/debug/`, so the debug trailer resolves; `status.mjs` never counts it as an open record), for the PO: **one page, one table, one row per open record** — what is true · severity · act now? · **the ORCH's PROPOSED disposition** (the PO accepts or rejects risk and priority; deriving severity from a stack trace is not the PO's job) · what happens if deferred — followed by what the ORCH will do on blanket approval, an explicit list of what approval does NOT cover, and a decision line. It states in its own header that deciding from it requires reading no record and no repo state. Rewritten, not appended, whenever the set of open records changes; `status.mjs` names it while open records exist and reports its absence, so a batch with no decision surface is mechanically visible rather than a matter of ORCH taste.

On PO classification: record it in the investigation, route per precedence rule 2, move the record to `runs/debug/resolved/` when the routed work closes — **move, never copy** (platform/F-81: a record present at both paths is a phantom the derived view now names). Findings that change requirements → REQ update in its single home, cited.

## Audience note **[AGENT]**

Executor/verifier agents never open lanes. If an agent hits an anomaly mid-task: park it (blocker note in its report section) and continue per the autonomy contract. The ORCH routes parked anomalies through the debug lane after the run.
