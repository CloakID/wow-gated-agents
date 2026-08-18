# WoW v2 — CLAUDE.md section (thin router) — DRAFT v0.5.0

> Drop this section into your repo's CLAUDE.md (or equivalent agent memory file). Target ≤60 lines resident; everything else loads on phase entry.

---

## Way of Working (WoW v2)

**Roles.** `PO` = product owner (human). `ORCH` = this orchestrating session. `AGENT` = spawned subagents (executors, verifiers, reviewers). Process docs tag every section with its audience; never load `[ORCH]`/`[PO]` duties into an AGENT context.

### Lane router (decide before any change)

- Read-only work (questions, analysis, drafting outside the repo): no lane.
- Defect or anomaly found → **debug lane**: `/wow-debug`. Exit only via PO classification (never straight to a fix).
- Change with known scope AND ≤2 files AND no interface/schema change AND reversible AND no new dependency AND no prod config → **quick lane**: `/wow-quick`.
- Everything else → **main lane**, entered at the phase the work is in: `/wow-spec`, `/wow-plan`, `/wow-run`, `/wow-report`, `/wow-publish`. New work starts at `/wow-spec` (or `/wow-ground` if the codebase map for the area is stale — machine-checked, see P0).
- Every commit must carry a lane reference (`[T:…]`, `[Q:…]`, `[D:…]`) — GATE-1 (commit-msg hook) blocks laneless commits. If you find yourself editing files with no active lane, stop and route.

Each `/wow-*` command loads its playbook from `docs/process/`. Do not execute a phase from memory.

### Non-negotiables (full definitions in docs/process/ and scripts/wow/GATES-SPEC.md — reference, do not restate)

1. **Single home per fact — with the git/Jira split.** Git owns **content**: spec text, ACs, plans, code, gaps (`docs/GAPS.md`), traceability, codebase map, evidence. Jira owns **workflow history**: status transitions, sign-offs, discussion. `docs/REQUIREMENTS.md` holds *technical* status (evidence-backed); Jira holds *workflow* status. Divergence between the two is never silently merged — gates open with a divergence diff (GATE-10) and every difference is classified as an actionable gap.
2. **No persistent narrative state.** Status is derived (`scripts/wow/status.mjs`); continuity is `runs/<id>/HANDOFF.md` (≤80 lines, overwritten, ORCH-owned); history is git.
3. **Evidence discipline.** Completion-class statuses and done-words carry `ev:` citations — checked by GATE-3 at every sweep (gate close and P5), not at commit time; a bad citation lands in a commit and is caught at the next gate. Convention (reviewed, not gated): FACT/ASSUMPTION/INFERENCE labels on load-bearing claims per `docs/process/FORMATS.md`.
4. **Park, don't ask.** During runs: in-contract deviations are decided and logged (`DEV-U<n>-<nn>`); cross-unit, AC-touching, or irreversible actions are parked (`PARK-U<n>-<nn>`). No mid-run questions, no silent improvisation. Cascades are computed by the ORCH at wave boundaries, never by executors.
5. **PO gates leave a record.** G1/G2/G4 close = Jira transition + mirrored `signed: <date> ev:jira{…}` line in the governing artifact (GATE-9). Gate failures: fix-forward ≤2 attempts, then park (FORMATS §7). Gates are never bypassed or weakened mid-run.
6. **A rule that matters is a gate, not a sentence.** Mechanical rules live once in `scripts/wow/GATES-SPEC.md` + `formats.json` (consumed by gates.sh **and** status.mjs); each gate ships with its non-vacuity proof, and the gate set ships with a wiring test that commits through the real hooks.
7. **INVESTIGATE-THEN-ASK.** Findings are investigated (facts + impact captured), classified by the PO, then scoped — in that order.

### Paths

`docs/spec/SPEC-<feature>-vN.md` · `docs/process/` (P0–P5, LANES, FORMATS) · `runs/<YYMMDD>-<slug>-r<N>/` (main; `reports/` per agent) · `runs/quick/`, `runs/debug/` · `scripts/wow/` (gates.sh + gates.py, status.mjs, formats.json, wow.config.json, permissions-policy.json, tests/) · branches `wow/<run-id>/{base,U<n>,int}` (merge rules: P3).

### Jira

Atlassian MCP only; project key in `wow.config.json`. Mapping: spec→epic, unit→story, task→task, defect→bug. Gates open with the divergence diff; acceptance closes and archives items. MCP down → queue ops in `runs/<id>/jira-queue.md`, apply at next gate. Never raw REST, never silent skip.
