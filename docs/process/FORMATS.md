# FORMATS — naming, labels, evidence, status (human view) — DRAFT v0.5.6

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
**Enforced rule (GATE-3):** any row/claim using an evidence-required status token (§4: `COMPLETED`, `FAILED`) or *done / verified / deployed / fixed* as a status carries an `ev:` citation in the same row/sentence — and the citation must match its own type's shape above. `ev:cmd{it worked}` is not a citation; `ev:cmd{pytest -q => 0 @2026-08-14}` is. Reference-class statuses (`BLOCKED`/`PARKED`/`DEFERRED`) carry their §4 reference in the same row: an `ev:` citation or a stable id (`PARK-U2-01`, `DEV-U1-03`, `VF-…`, `DEF-plan-…`, `CV-…`); the row's own subject id does not count as a reference to anything. Nothing else is citation-gated.

## 4. Status vocabulary (report rows, requirement rows)

`COMPLETED` (ev required) · `FAILED` (ev of failure) · `BLOCKED` (blocker ref; cascade form `BLOCKED(cascade:<source-id>)`) · `PARKED` (park record ref) · `DEFERRED` (successor + discharge) · `OPEN`. No synonyms (gates reject status-like words outside this vocabulary).

Where a scanned table has a header row naming a **Status / State / Result** column, only that column is status-checked; a table with no header is checked in full. Otherwise an ordinary `OK` in a *Done-means* or *Verify* cell reads as a forbidden synonym, and a gate that cries wolf is a gate someone disables.

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

**Plan linkage:** unit plans declare an `areas:` list naming the codebase areas the unit touches — that is GATE-6(a)'s input. Without it the gate depends on the operator remembering `--area`, and a gate that only runs when someone remembers a flag is not a gate.

**No map yet?** The ORCH records the P0 outcome in the run's HANDOFF as `p0-record: <area> = fresh | not-required | updated`, and GATE-6 honours it. It is a format like any other — the machine home is `codebase_frontmatter.p0_record` in formats.json.

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

The diff lives in `runs/<run-id>/divergence-<gate>.md` as a table with **Item | Git | Jira | Classification** columns; GATE-10 reads the verdict from the Classification column, not from anywhere in the row. An empty diff is written as *"No divergences"* **plus an `ev:` citation of the query that produced it** — an unevidenced empty diff is an assertion, not a check. If the tracker was unreachable, say so in the record and leave an open `- [ ] gate-10 …` item in `jira-queue.md`; a deferral recorded nowhere is not a deferral.

## 11. External-dependency maps (`docs/deps/<name>.md`) — added v0.4.1, from pilot feedback PF-01

Facts about third-party surfaces (external APIs, SaaS platforms, vendor services) live in `docs/deps/<name>.md` — **not** `docs/codebase/`, because git-based freshness (§6) is meaningless for surfaces you don't version. Front-matter:

```yaml
---
dependency: payments-api
kind: external-api   # external-api | saas | vendor-lib | service
verified: 2026-08-13
probe: curl -s https://api.vendor.example/v2/openapi.json | sha256sum
verified_against_hash: <sha256 of probe output at verification time>
max_age_days: 30     # fallback when no probe surface exists
---
```

**Freshness rule:** fresh ⇔ the probe's current output hash equals `verified_against_hash`. If no probe surface is definable, fresh ⇔ `verified` within `max_age_days` — the calendar fallback is legitimate here precisely because git is unavailable (unlike §6, where it was dropped for the better git rule). A changed hash does not mean the map's claims are wrong; it means *the vendor surface moved since verification — re-verify* — the exact external analogue of commits touching mapped paths.

Good probe surfaces, in preference order: published OpenAPI/schema document · version/changelog endpoint · docs-page content hash. Pick the narrowest surface that would change when your capability claims could be invalidated.

**Plan linkage:** unit plans declare a `deps:` list naming the external dependencies they rely on; GATE-6 covers both map kinds (codebase areas via §6's `areas:`, declared deps via this section's `deps:`).

## 12. Obligations — "X must happen before Y" (added v0.5.2, pilot feedback PF-03/F-6)

The framework has single homes for facts, decisions and routes; obligations get one too — and it is **not a new artifact**: `docs/GAPS.md` is the obligation registry. An obligation is a gap record whose discharge is future work (an owed audit, a mandated follow-up, a precondition for the next feature). It survives run archival because GAPS.md is durable — nothing that must outlive a run may live only in `runs/` (GATE-7 escrow check).

Record fields (schema in formats.json `gap_row`): id · taxonomy tag · **owner** (who discharges) · **effect** — closed controlled vocabulary: `advisory` | `blocks-new-feature-work` (consumer: GATE-12 refuses new-feature `/wow-spec`) | `blocks-install` (consumer: install.sh — **[DESIGNED-NOT-IMPLEMENTED — OBL-PKG-11]** — reads the PACKAGE's own registry before writing and refuses install/upgrade into any target matched by an open row's `scope:`; rows carry `scope:` = repo name list or `*`, default `*` — added v0.5.5/v0.5.6, pilot N3+D1). An unrecognized effect value is a **validation failure, loudly** — never a silent downgrade to non-blocking · successor · discharge condition · `ev:` on creation and on discharge.

`effect: blocks-new-feature-work` is machine-consequential: GATE-12 refuses `/wow-spec` for a **new feature** while one is open. Exempt (they are how obligations get discharged): audit specs, fix iterations (`r>1`), and probes, when they reference the blocking obligation's id. Keep `effect` separate from `owner` — who discharges and what it blocks are different facts; conflating them in one field re-creates the drift class this framework exists to kill.

**Derivation, not narrative:** status.mjs reads GAPS.md (and REQUIREMENTS) — it answers *what does the current state require next*, not only *what is the state*. Audit-trigger counters derive from durable homes, never from archived RUN-REPORTs. Between-run continuity comes from derivation over durable records — HANDOFF stays per-run and retired at P5; no persistent narrative state returns through this door.
