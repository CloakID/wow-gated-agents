# Design rationale — what six months of GSD taught us

This process was not designed on a whiteboard. It came from auditing two production repos that ran [GSD (get-shit-done)](https://github.com/gsd-build/get-shit-done) — heavily customized — for about six months, then keeping what demonstrably worked and rebuilding what demonstrably failed. Origin details are anonymized; the evidence patterns are reported as found.

## Why replace GSD at all

GSD's core mechanics are sound and we kept them: fresh-context executors, small per-task context loads, one atomic commit per task, dependency-ordered waves, discuss-before-plan. But three structural problems compounded over months, consistent with the public criticism record ([HN thread](https://news.ycombinator.com/item?id=47417804), [patch write-ups](https://rogs.me/2026/04/i-patched-gsd-and-why-you-should-patch-it-too/)): documentation lock-in to `.planning/`, weak self-graded verification, and no evolution path for specs after execution deviates. Separately, the upstream project was archived in June 2026 after its creator abandoned it — a reminder that a team's process should be plain files it owns, not a third-party installer.

## The evidence (from our field retrospectives)

**E-1. Prose rules fail; mechanical gates work.** One milestone retrospective logged nine process lapses with a single shape: *"a load-bearing claim entered an artifact without an evidence citation paired with it."* Its meta-observation: *"prose rules depend on the orchestrator catching itself… that's exactly the failure mode the rules warn against. Mechanical gates close the loop by being orchestrator-independent."* An evidence-citation gate added afterward caught its first real error within one cycle. → GATES-SPEC exists; every rule that matters is a gate; each gate ships with a negative test (we watched gates go silently inert three times — a gate that cannot fail is decoration).

**E-2. Every drift is a copy-sync failure.** Requirement statuses and decisions were lockstep-edited across 4–6 files. Every documented doc-drift incident was one copy diverging from another; a "tick checkboxes in lockstep" rule failed across three consecutive milestones. → Single home per fact; derived views; the FORMATS/formats.json split (human semantics vs machine schemas, one machine home consumed by both the gate script and the status script).

**E-3. Persistent narrative state rots.** A 169KB STATE.md — 57% append-only session narrative — was found naming the wrong "next phase" two months stale; its progress counters needed six hand-corrections because a tool rewriter kept regressing them. → No persistent narrative state: status is computed on demand; continuity is a per-run, ≤80-line, overwritten handoff; history is git.

**E-4. Independent verification and fix re-validation both earn their cost.** After all executors self-reported green, an independent review found 10 findings including 2 critical ("the entire failure-detection substrate is broken"). The fix pass then produced 2 wrong fixes out of 10, caught only by a re-validation pass. → Verifier agents with fresh context, never shown implementer reasoning, re-running checks themselves; mandatory re-validation of every fix.

**E-5. Green gates can be worthless.** One milestone "built the honesty apparatus end-to-end and it all passes, but the real capability stayed at zero… the thing to redesign is the milestone premise, not the phases." A success criterion took 12 days to be recognized as unprovable because it could be satisfied by the harness's own mock injection. → The premise check: for every harness-touching acceptance criterion, answer in writing *"can this pass for the wrong reason?"* — plus an audit trigger on any occurrence.

**E-6. Unbounded autonomy config accretes.** The permission allowlist grew to 233 entries (zero deny) of click-through sediment, including deploy and cluster-mutation grants. → Permissions regenerated from a designed policy at every publish; long-run autonomy via scoped pre-approval + gates, never blanket skip.

**E-7. Ceremony must pass a value test.** Manual UAT was withdrawn as "theatrical" by the operator; a discussion-log artifact self-declared "audit trail only, never an input"; ad-hoc task stubs were created and never filled. → Fewer artifacts, each load-bearing; stale stubs are garbage-collected at publish with human confirmation; the explicit "not gates" list in GATES-SPEC keeps judgment calls out of mechanical checks (a gate that pretends to check judgment is theater).

## Decisions that need the most outside challenge

1. **Park-don't-ask** (no human checkpoints mid-run, even for irreversible actions — those are parked by design at plan time). Alternative rejected: checkpoint tasks, because they break long unattended runs.
2. **Merge model**: unit branches, orchestrator-only sequential rebase-and-merge in wave order, conflicts in owned paths treated as plan defects. Is sequential merging too conservative for large runs?
3. **Cascade threshold**: >50% of the next wave blocked → terminate the run early to the report phase. Arbitrary; needs field calibration.
4. **Git/tracker split with divergence-as-signal** (git owns content, tracker owns workflow; differences are classified, never auto-merged). Does this survive contact with teams that live in the tracker?
5. **Audit-trigger windows** (mocks >3/run; remediation cycles >5 cumulative per spec; stale refs ≥3 sweep-found in unmodified docs; any premise failure). Are these the right denominators?
6. **Two-layer packaging** (thin always-resident router + on-demand phase playbooks + hooks as backstop, optional enforcement hook off by default). Is the three-layer reliability model sufficient without the blocking hook?
