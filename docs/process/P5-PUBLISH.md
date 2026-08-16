# P5 — PUBLISH — DRAFT v0.5.2
Entry: `/wow-publish <run-id>` · Mechanical; low tier · Output: clean durable docs, closed tracker, archived run.

## [ORCH]
1. Durable docs: final SPEC version confirmed in `docs/spec/`; extract accepted decisions into `docs/adr/` (immutable, numbered); update `docs/codebase/` front-matter for touched areas; confirm GAPS/TRACEABILITY current.
2. Jira: close accepted epics/stories/tasks; archive per PO convention ("closed and archived for reference"). Apply any queued ops from `jira-queue.md`.
3. Archive `runs/<run-id>/` (move to `runs/archive/` or tag — per wow.config). HANDOFF of the archived run is retired; nothing in `runs/archive/` is load-bearing.
4. GC: list stale quick stubs (FORMATS: empty `result` >7 days) and unresolved debug files → PO confirms deletion/retention. Nothing deleted silently.
5. Regenerate `.claude/settings.local.json` from `scripts/wow/permissions-policy.json` (designed policy; accreted entries dropped). 
6. Run the **P5 sweep** — `scripts/wow/gates.sh sweep --p5 --run <run-id>` — then `node scripts/wow/status.mjs`; commit `[WOW:publish]`. `--p5` is what adds **GATE-7** (unresolved `jira-queue.md`, stale quick stubs, archive state, and the obligation-escrow check — nothing obligation-shaped may live only in the archived run, FORMATS §12) to the sweep: mid-run those are legitimate, at publish they are not.

## [PO]
Confirm GC list. Nothing else.
