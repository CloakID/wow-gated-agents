# LANES — quick & debug playbooks + precedence — DRAFT v0.6.1

## Lane refs (GATE-1) **[ORCH]**

Every commit carries exactly one lane ref; GATE-1 (commit-msg hook) blocks the rest. The full set — this list and `formats.json commit_trailers` are two declarations of the same set, and the parity sweep compares them both ways (v0.6.1, PF-b):

- `[T:<run-id>.T<nn>]` — main lane; must resolve to a task **row** in that run's `PLAN.md`.
- `[Q:runs/quick/<dir>]` — quick lane; the dir must exist.
- `[D:<slug>]` — debug lane; `runs/debug/<slug>.md` must exist (investigation is read-only, so a `[D:]` commit carries the debug record itself, never a fix).
- `[WOW:publish]` — package/process publishing commits (P5 and framework maintenance); resolves to nothing by design.
- `[WOW:migrate]` — migration-window commits only (lifting durables out of `.planning/`): legal **only** while `.planning/` exists AND `migrated_from_gsd` is still false. Greenfield repos and post-freeze repos reject it (added v0.6.0, PR-4).

## Precedence rules **[ORCH]**

1. Defect/anomaly discovered (any source: run, review, user report, monitoring) → **debug lane first**. Never straight to a fix, even a 1-line one.
2. Debug exits only through classification (INVESTIGATE-THEN-ASK): facts + impact captured → **PO classifies** → routine + all quick criteria hold → quick lane, NOTE.md references the debug file; otherwise → main lane (fix iteration `r<N+1>` on the affected spec, or `/wow-spec` if the spec itself is wrong).
3. Quick lane is only for changes whose **scope is known at start**. Scope grows past any quick criterion mid-work → stop, park the diff, reroute to main lane.
4. Read-only work needs no lane. Any change landing in git needs a lane (GATE-1 enforces).
5. **Recording a finding outside a run is quick-lane work** (added v0.5.2, PF-03): a gap, obligation, or feedback item discovered between runs goes into its durable home (GAPS.md, REQUIREMENTS, dep map) via `/wow-quick` — the framework should prompt this, not rely on someone thinking to ask.

## Quick lane **[ORCH]**

Criteria (all): ≤2 files · no interface/schema change · reversible · no new dependency · no prod config.
Steps: create `runs/quick/<YYMMDD>-<slug>/NOTE.md` → sections: `what` / `why` / `verify` (an `ev:cmd` you will run) / `result`. Implement. Run the verify command; record `ev:`. Commit with `[Q:…]`. Done — no other artifacts, no Jira item (unless the change touches a tracked story; then comment on it).
A NOTE.md with empty `result` older than 7 days is a stale stub — GC'd at next PUBLISH (listed, PO confirms deletion).

## Debug lane **[ORCH]**

Steps: create `runs/debug/<slug>.md` → capture: symptom (with `ev:`) · environment facts · impact facts · reproduction (or why not) · hypotheses (labeled INFERENCE) · **classification request to PO** (severity, urgency, scope). Investigation is **read-only** — no fixes from this lane.
On PO classification: record it, route per precedence rule 2, move file to `runs/debug/resolved/` when the routed work closes. Findings that change requirements → REQ update in its single home, cited.

## Audience note **[AGENT]**

Executor/verifier agents never open lanes. If an agent hits an anomaly mid-task: park it (blocker note in its report section) and continue per the autonomy contract. The ORCH routes parked anomalies through the debug lane after the run.
