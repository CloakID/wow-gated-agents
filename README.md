# WoW v2 — a gated, evidence-first way of working for AI coding agents

**Status: DRAFT v0.4 — pre-pilot, actively seeking feedback.**

WoW v2 is a spec→plan→run→report process for building software with AI coding agents (designed against Claude Code, portable in principle to any agent runner). It grew out of six months of running [GSD (get-shit-done)](https://github.com/gsd-build/get-shit-done) across two production repos, auditing what actually failed, and rebuilding around two findings that kept repeating:

1. **Prose rules fail; mechanical gates work.** Nearly every logged process lapse was a rule the model was supposed to remember. Rules that mattered only started holding when they became runnable checks the orchestrator couldn't skip.
2. **Every documentation drift was a copy-sync failure.** Facts duplicated across files (status in four places, decisions in six) diverged, always. The fix is structural: single home per fact, derived views, no persistent narrative state.

Full story with evidence: [DESIGN-RATIONALE.md](DESIGN-RATIONALE.md).

## What's in the box

- **[CLAUDE-WOW-SECTION.md](CLAUDE-WOW-SECTION.md)** — the ~60-line resident router (lanes, non-negotiables, paths) that goes in your agent memory file. Everything else loads on phase entry.
- **[docs/process/](docs/process/)** — phase playbooks **P0 GROUND → P1 SPEC → P2 PLAN → P3 RUN → P4 REPORT & RECONCILE → P5 PUBLISH**, plus [LANES.md](docs/process/LANES.md) (quick/debug lanes and precedence) and [FORMATS.md](docs/process/FORMATS.md) (IDs, evidence citations, status vocabulary, git/tracker ownership split). Every section is audience-tagged `[PO]` / `[ORCH]` / `[AGENT]` so subagents are never shown duties they can't perform.
- **[GATES-SPEC.md](GATES-SPEC.md)** — the ten mechanical gates (commit-msg + pre-commit hooks + gate sweeps), each required to ship with a **non-vacuity proof**: the negative test that shows the gate can actually fail.
- **[INSTALL.md](INSTALL.md)** — packaging, the three-layer entry-reliability model, and a migration path from GSD's `.planning/`.
- **[FIELD-MECHANISMS.md](FIELD-MECHANISMS.md)** — deployment-specific mechanisms (invariant suites, gap registration, coevolution stamps…) described by aim + dependencies; implementations are per-project.

## Core ideas, in one paragraph each

**Bounded autonomy, not perfect plans.** Executors get an explicit autonomy contract: in-contract deviations are decided and logged (`DEV-U2-03`); anything cross-unit, acceptance-criteria-touching, or irreversible is parked with a blocker note and the run continues. No mid-run questions, no silent improvisation.

**Verification is independent and re-validated.** A verifier agent with a fresh context — never shown the implementer's reasoning — re-runs every check itself. Fixes are re-validated (in our field data, 2 of 10 review fixes were themselves wrong). Acceptance criteria are executable, and harness-touching ones carry a written **premise check**: *can this pass for the wrong reason?* (Our worst field failure was a milestone that passed every gate while delivering zero real value.)

**Parallelism is a merge problem.** Units own disjoint path sets (machine-checked), interfaces freeze at plan sign-off, executors commit only to their unit branch, and only the orchestrator merges — sequentially, in wave order, with a defined conflict policy and a serial integration wave last.

**Git owns content; the tracker owns workflow.** Requirement *technical* status (evidence-backed) lives in git; *workflow* status lives in the tracker (Jira in our deployment). Divergence between them is never silently merged — gates open with a diff, and every out-of-mapping pair is classified: git wrong, tracker wrong, or a real gap.

## Adopting it

Read INSTALL.md. Short version: copy the router section into your CLAUDE.md, copy `docs/process/`, implement `gates.sh`/`formats.json`/`status.mjs` per GATES-SPEC (reference implementation coming after our pilot), install the two git hooks, and enter work through the `/wow-*` commands.

## Feedback

This is a design under review — see [CONTRIBUTING.md](CONTRIBUTING.md) for the specific questions we most want challenged. Issues and discussions welcome.

MIT licensed.
