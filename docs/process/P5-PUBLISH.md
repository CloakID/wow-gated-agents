# P5 — PUBLISH — DRAFT v0.6.2
Entry: `/wow-publish <run-id>` · Mechanical; low tier · Output: clean durable docs, closed tracker, archived run.

## [ORCH]
0. **Merge to `main` — this step owns it** (v0.6.2, F-11: previously the merge belonged to no phase; a run could pass G4, archive itself, and never be on `main`). Merge `main` into the run branch, resolve, then open the PR or fast-forward per `merge_to_main` in wow.config.json. Before step 3 because archiving a run that never reached `main` is worse; before step 5 because step 5 is destructive (below).
1. Durable docs: final SPEC version confirmed in `docs/spec/`; extract accepted decisions into `docs/adr/` (immutable, numbered); update `docs/codebase/` front-matter for touched areas; confirm GAPS/TRACEABILITY current.
2. Jira: close accepted epics/stories/tasks; archive per PO convention ("closed and archived for reference"). Apply any queued ops from `jira-queue.md`.
3. Archive `runs/<run-id>/` (move to `runs/archive/` or tag — per wow.config). HANDOFF of the archived run is retired; nothing in `runs/archive/` is load-bearing.
4. GC: list stale quick stubs (FORMATS: empty `result` >7 days) and unresolved debug files → PO confirms deletion/retention. Nothing deleted silently.
5. Regenerate `.claude/settings.local.json` from `scripts/wow/permissions-policy.json` (designed policy; accreted entries dropped). **Destructive by design, so it refuses on a branch behind `main`** (v0.6.2, F-11 — GATE-7 at `--p5` enforces this): it regenerates from the tree it runs in, and a grant that landed on `main` through another lane would be silently dropped. Step 0 is what makes this step safe.
6. Run the **P5 sweep** — `scripts/wow/gates.sh sweep --p5 --run <run-id>` — then `node scripts/wow/status.mjs`; commit `[WOW:publish]`. `--p5` is what adds **GATE-7** (unresolved `jira-queue.md`, stale quick stubs, archive state, phantom empty run dirs, the behind-main refusal, and the obligation-escrow check — nothing obligation-shaped may live only in the archived run, FORMATS §12) to the sweep: mid-run those are legitimate, at publish they are not.

## [PO]
Confirm GC list. Nothing else.
