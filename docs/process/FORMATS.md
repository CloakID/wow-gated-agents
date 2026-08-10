# FORMATS — naming, labels, evidence, status (human view) — DRAFT v0.4

> **[ALL AUDIENCES]** Semantics and examples live here. Authoritative regexes/vocabulary/schemas live in `scripts/wow/formats.json` (single machine home; **both** gates.sh and status.mjs consume it — plan schema, report rows, REQUIREMENTS rows, runs/ layout, REQ↔run mapping included). If this file and formats.json disagree, formats.json wins and the disagreement is a defect.

## 1. Identifiers & naming

- **Spec:** `docs/spec/SPEC-<feature>-v<N>.md`, feature = kebab, ≤24 chars. Version bumps only at G4.
- **Main-lane run:** `runs/<YYMMDD>-<slug>-r<N>/` — slug = spec feature; `r<N>` = iteration. Example: `runs/260812-user-auth-r1/`.
- **Unit / task:** `U<n>` · `<run-id>.T<nn>` (e.g. `260812-user-auth-r1.T04`).
- **Cross-phase stable IDs (unit-scoped; survive P3→P4→SPEC vN+1):** deviations `DEV-U<n>-<nn>` · parks `PARK-U<n>-<nn>` · verifier findings `VF-U<n>-<nn>` · plan defects `DEF-plan-<nn>` · cannot-validate `CV-<run-id>-<nn>`.
- **Branches:** `wow/<run-id>/base` (run base) · `wow/<run-id>/U<n>` (one per unit) · `wow/<run-id>/int` (integration). Merge rules in P3 — executors never merge/rebase/push shared branches.
- **Quick:** `runs/quick/<YYMMDD>-<slug>/NOTE.md`. **Debug:** `runs/debug/<slug>.md` → `resolved/`.
- **Commit trailer (GATE-1, commit-msg hook):** exactly one of `[T:<task-id>]`, `[Q:runs/quick/<dir>]`, `[D:<debug-slug>]`, `[WOW:publish]`.
- **ADR:** `docs/adr/NNN-<slug>.md`, sequential, immutable once accepted.

## 2. Claim labels — CONVENTION (reviewed at gates, not gated)

- `[FACT|ev:<citation>]` · `[ASSUMPTION|A-<nn>|owner=<PO|run>]` · `[INFERENCE|from=<A-nn/F-nn/task-ids>]`
Apply to load-bearing claims in specs and reports; quality is a review judgment. Do **not** tag defensively — a document where everything is labeled says nothing.

## 3. Evidence citations (`ev:`) — ENFORCED subset (GATE-3)

Format: `ev:<type>{<locator>}`:
- `ev:cmd{<command> => <exit|summary> @<ISO8601>}` · `ev:file{<path>#<anchor>}` (content anchors preferred; `file:line` must pass GATE-5) · `ev:commit{<sha≥7>}` · `ev:jira{<KEY-123>}` · `ev:url{<https://…>}`
**Enforced rule:** any row/claim using a completion-class status token (§4) or *done / verified / deployed / fixed* as a status carries an `ev:` citation in the same row/sentence. Nothing else is citation-gated.

## 4. Status vocabulary (report rows, requirement rows)

`COMPLETED` (ev required) · `FAILED` (ev of failure) · `BLOCKED` (blocker ref; cascade form `BLOCKED(cascade:<source-id>)`) · `PARKED` (park record ref) · `DEFERRED` (successor + discharge) · `OPEN`. No synonyms (gates reject status-like words outside this vocabulary).

## 5. Cannot-validate record

```
CV-<run-id>-<nn>: <claim>
  reason / workaround / successor / discharge
```
(fields as v0.3; discharge = the observable event that closes the record.)

## 6. Codebase-map front-matter (P0 freshness, GATE-6) — git-only

```yaml
---
area: auth
verified_against: <git sha>
paths: ["src/auth/**", "helm/auth/**"]
---
```
**Fresh ⇔ `git log <verified_against>..HEAD -- <paths>` is empty.** No calendar component. Stale map + main-lane work in the area ⇒ P0 required.

## 7. Gate-failure recovery

Fix-forward within the phase (repair artifact, re-run gate), **max 2 attempts** → then PARK + escalate at next gate. Never bypass; gate changes = PO sign-off + updated non-vacuity test.

## 8. HANDOFF.md (per run, ≤80 lines, overwritten, **ORCH-owned**)

Sections: `position` · `active-constraints` (blocking checkboxes) · `parked` (ids + one-liners) · `pointers` (manifest refs only).

## 9. ORCH-owned files (excluded from unit ownership — GATE-8 rejects units claiming them)

`runs/<id>/PLAN.md` · `runs/<id>/RUN-REPORT.md` · `runs/<id>/HANDOFF.md` · `runs/<id>/jira-queue.md`. AGENTs write **only** `runs/<id>/reports/U<n>.md` (executor) and `runs/<id>/reports/U<n>-verify.md` (verifier). ORCH assembles RUN-REPORT from report files.

## 10. Git/Jira ownership & expected mapping (GATE-10 divergence diff)

Git owns **content** (spec text, ACs, plans, code, gaps, traceability, evidence). Jira owns **workflow history** (transitions, sign-offs, discussion). `docs/REQUIREMENTS.md` status = *technical* (evidence-backed); Jira status = *workflow*.

Expected-consistent pairs (out-of-mapping = divergence → classify, never silently merge):

| REQUIREMENTS (technical) | Jira story/task (workflow) |
|---|---|
| OPEN | To Do / In Progress |
| COMPLETED (ev) | In Review / Accepted / Done |
| FAILED / BLOCKED / PARKED | In Progress / Blocked |
| DEFERRED | Deferred / Backlog |

Divergence classification at gate open: **git wrong** (update git, cite) · **Jira wrong** (transition Jira, cite) · **real gap** (actionable item → P4 classification). Sign-off records: Jira transition is authoritative; the governing git artifact mirrors it as `signed: <date> ev:jira{KEY-nn}` (GATE-9).
