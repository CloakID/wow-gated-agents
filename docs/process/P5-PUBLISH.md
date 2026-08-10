# P5 — PUBLISH — DRAFT v0.4
Entry: `/wow-publish <run-id>` · Mechanical; low tier · Output: clean durable docs, closed tracker, archived run.

## [ORCH]
1. Durable docs: final SPEC version confirmed in `docs/spec/`; extract accepted decisions into `docs/adr/` (immutable, numbered); update `docs/codebase/` front-matter for touched areas; confirm GAPS/TRACEABILITY current.
2. Jira: close accepted epics/stories/tasks; archive per PO convention ("closed and archived for reference"). Apply any queued ops from `jira-queue.md`.
3. Archive `runs/<run-id>/` (move to `runs/archive/` or tag — per wow.config). HANDOFF of the archived run is retired; nothing in `runs/archive/` is load-bearing.
4. GC: list stale quick stubs (FORMATS: empty `result` >7 days) and unresolved debug files → PO confirms deletion/retention. Nothing deleted silently.
5. Regenerate `.claude/settings.local.json` from `scripts/wow/permissions-policy.json` (designed policy; accreted entries dropped). 
6. Run `gates.sh` full sweep + `status.mjs`; commit `[WOW:publish]`.

## [PO]
Confirm GC list. Nothing else.
