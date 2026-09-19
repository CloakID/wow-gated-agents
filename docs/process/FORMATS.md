# FORMATS — naming, labels, evidence, status (human view) — DRAFT v0.7.3

> **[ALL AUDIENCES]** Semantics and examples live here. Authoritative regexes/vocabulary/schemas live in `scripts/wow/formats.json` (single machine home; **both** gates.sh and status.mjs consume it — plan schema, report rows, REQUIREMENTS rows, runs/ layout, REQ↔run mapping included). If this file and formats.json disagree, formats.json wins and the disagreement is a defect.

## 1. Identifiers & naming

- **Spec:** `docs/spec/SPEC-<feature>-v<N>.md`, feature = kebab, ≤24 chars. Version bumps only at G4.
- **Main-lane run:** `runs/<YYMMDD>-<slug>-r<N>/` — slug = spec feature (audit/fix/probe runs may carry a longer descriptive slug); `r<N>` = iteration. Example: `runs/260812-user-auth-r1/`. Slug cap: **48 chars** (v0.7.1, F-46 — the old cap of 24 was hit by a real brownfield slug and surfaced as "trailer missing" five gates later). The run id has ONE definition — named anatomy parts (`ids.run_date`/`run_slug`/`run_iter`) composed into `ids.run_core` in formats.json — and every derived shape (task ids, CV ids, branch names, commit trailers) is expanded from it at load by both engines; the cap lives only in `run_slug`'s quantifier, and even the diagnostics derive it by probing rather than restating it (engine round 6, audit A1). **Check the id at run open:** `scripts/wow/gates.sh check-id <run-id>` refuses an inexpressible id before any artifact is signed against it.
- **Unit / task:** `U<n>` · `<run-id>.T<nn>` with an **optional letter suffix** `T<nn>[a-z]` for a task split mid-run (v0.7.1, F-39: `T07a` is a legal task id, resolvable by a `[T:]` trailer — before this, a split task was real work with an uncommittable id). Example: `260812-user-auth-r1.T04`.
- **Cross-phase stable IDs (unit-scoped; survive P3→P4→SPEC vN+1):** deviations `DEV-U<n>-<nn>` — **or `DEV-ORCH-<nn>`** (v0.7.3, prodsim/F-66: the ORCH is not a unit and owns decisions no unit can deviate from — branch model, cascade rule, wave boundaries; a playbook deviation had no expressible id and was guaranteed to end as prose no gate reads. ORCH-allocated, single-threaded per run so the F-17 allocator argument holds trivially; carries what/why/impact plus what coverage it gives up, and the PO classifies it at the NEXT gate — mirroring §7's ORCH-authored clause, not reintroducing a human mid-phase) · parks `PARK-U<n>-<nn>` · verifier findings `VF-U<n>-<nn>` · plan defects `DEF-plan-<nn>` · cannot-validate `CV-<run-id>-U<n>-<nn>` (v0.6.3, F-17: the unit segment IS the allocator — unit membership partitions the number space, so parallel verifiers in fresh contexts cannot collide; the legacy run-scoped form without `U<n>` stays valid for existing records) · plan amendments `AM-<nn>` (v0.6.3, F-29: date, decider, what changed, whether it widens scope — a signed artifact modified after signing carries at least one, checked by GATE-9).
- **Branches:** `wow/<run-id>/base` (run base) · `wow/<run-id>/U<n>` (one per unit) · `wow/<run-id>/int` (integration). Merge rules in P3 — executors never merge/rebase/push shared branches.
- **Quick:** `runs/quick/<YYMMDD>-<slug>/NOTE.md`. **Debug:** `runs/debug/<slug>.md` → `resolved/`.
- **Commit trailer (GATE-1, commit-msg hook):** exactly one of `[T:<task-id>]` (task work), `[T:<run-id>]` (bare form, v0.6.3 F-08/F-10: a run's PHASE artifacts — the P1 spec and HANDOFF, P4's reconciled spec/divergence/RUN-REPORT — so the artifact a PO signs is in git at the moment of signing), `[Q:runs/quick/<dir>]`, `[D:<debug-slug>]`, `[WOW:publish]`, `[WOW:migrate]` (migration window only) — full semantics in LANES.md. Trailers in backticks or fenced/indented blocks are **mentions and do not count** (F-07) — a commit may discuss lanes.
- **Requirement ids (GATE-2, status.mjs):** default `REQ-nnn` (`ids.requirement`). A brownfield repo whose requirement identities are another stable shape sets `requirement_id` in `wow.config.json` (repo-local truth, never overwritten by install) — added v0.6.1, pilot #2 PF-d, so adoption never forces renumbering and never buys a permanently-vacuous GATE-2. Rows the effective pattern cannot read fail loudly.
- **ADR:** `docs/adr/NNN-<slug>.md`, sequential, immutable once accepted.

## 2. Claim labels — CONVENTION (reviewed at gates, not gated)

- `[FACT|ev:<citation>]` · `[ASSUMPTION|A-<nn>|owner=<PO|run>]` · `[INFERENCE|from=<A-nn/F-nn/task-ids>]`
Apply to load-bearing claims in specs and reports; quality is a review judgment. Do **not** tag defensively — a document where everything is labeled says nothing.

## 3. Evidence citations (`ev:`) — ENFORCED subset (GATE-3)

Format: `ev:<type>{<locator>}`:
- `ev:cmd{<command> => <exit|summary> @<ISO8601>}` · `ev:file{<path>#<anchor>}` (content anchors preferred; `file:line` must pass GATE-5) · `ev:commit{<sha≥7>}` · `ev:jira{<KEY-123>}` · `ev:url{<https://…>}` · `ev:attest{<who>: <claim> @<ISO8601>}` (v0.6.3, F-27: evidence for a task placed with a human IS a person's decision — 'the operator read one row and declined the next statement' has no command to cite, and dressing it as ev:cmd records a human decision in a shell command's grammar). **Reference ids in report rows are written bare** (v0.6.4, F-32): backticked ids are mentions (v0.6.1) and satisfy no reference rule — the markdown habit of quoting ids costs a debugging cycle exactly when a row needs its reference to count. **Captured evidence is scrubbed before commit** (v0.6.4, PII): a capture holding third-party personal data is trimmed at capture time with the trim RECORDED (a declared trim is honest; a silent one is the defect the capture-whole rule forbids) — GATE-14 refuses the commit otherwise. **An `ev:` token whose kind is outside this set is a GATE-3 failure** — previously a malformed known kind failed loudly while an invented kind was silently not-a-citation, and the invented kind is the author who believes they are complying.
**Enforced rule (GATE-3):** any row/claim using an evidence-required status token (§4: `COMPLETED`, `FAILED`) or *done / verified / deployed / fixed* as a status carries an `ev:` citation in the same row/sentence — and the citation must match its own type's shape above. `ev:cmd{it worked}` is not a citation; `ev:cmd{pytest -q => 0 @2026-08-14}` is. Reference-class statuses (`BLOCKED`/`PARKED`/`DEFERRED`) carry their §4 reference in the same row: an `ev:` citation or a stable id (`PARK-U2-01`, `DEV-U1-03`, `VF-…`, `DEF-plan-…`, `CV-…`); the row's own subject id does not count as a reference to anything. Nothing else is citation-gated.

**What GATE-3 proves — and what it cannot** (v0.7.1, F-43): the gate proves a citation's **form**, never its truth — a fabricated `ev:cmd{pytest -q => 0 @…}` is well-formed by construction, and a well-formed lie passes every format check ever written. Truth enters through exactly one door: **the verifier re-runs the cited command** and compares. So executors **paste actual command output** into their report (fenced, as a mention) next to the `ev:cmd` claim — a paste costs nothing when the run was real, raises the effort of fabrication, and — decisively — gives the verifier a concrete artifact to DIFF against its own re-run (audit A3: a paste is not fabrication-proof; a capable executor can invent plausible output, which is exactly why the re-run stays the only truth check); a report whose citations have no pasted output is the verifier's cue to re-run everything, not a format violation. The engine half (sampled re-execution / output digests) is registered as OBL-PKG-19 — until it lands, this is a review rule, and the P3 verifier brief says so. **The one exception is `ev:commit`** (v0.7.3, prodsim/F-68, discharging OBL-PKG-23): its truth is one command — so GATE-3 RESOLVES every cited sha, blocking in the run tree (where the write-the-citation-before-the-commit habit bites; four well-formed false citations shipped in one pilot run), advisory in durable docs (dangling shas there are legitimate history: branch GC, shallow clones, rewrites). The remedy is always the same and the message says it: commit first, then cite.

The body admits **one level of balanced braces** (v0.6.2, frisbii braces finding) — awk action blocks, jq object construction and regex quantifiers are citable. Deeper nesting cannot be expressed, and GATE-3 says exactly that rather than calling the citation malformed. Anything in inline code (backticks) is a **mention, not a claim** (v0.6.1): never flagged, never satisfying — so prose *about* this format is safe to write.

## 4. Status vocabulary (report rows, requirement rows)

`COMPLETED` (ev required) · `FAILED` (ev of failure) · `BLOCKED` (blocker ref; cascade form `BLOCKED(cascade:<source-id>)`) · `PARKED` (park record ref) · `DEFERRED` (successor + discharge) · `OPEN`. No synonyms (gates reject status-like words outside this vocabulary).

Where a scanned table has a header row naming a **Status / State / Result** column, only that column is status-checked; a table with no header is checked in full. Otherwise an ordinary `OK` in a *Done-means* or *Verify* cell reads as a forbidden synonym, and a gate that cries wolf is a gate someone disables.

**A status-shaped cell that is not gradeable fails** (v0.6.3, F-14): a cell beginning with an UPPERCASE status token followed by anything other than evidence or a reference id — `COMPLETED — verdict NO on both instances` — used to equal no vocabulary member and fall through every branch in silence, on the most consequential completion claim of a run. Sanctioned shapes: a bare status; status + `ev:` citation; status + reference id; the cascade form.

**A findings index points, it does not claim** (v0.6.3, F-31): a summary table re-asserting dispositions is a second home for facts the sections already cite (and `CLOSED` is not in any vocabulary). The sanctioned index is navigational — each finding links the section that answers it, and the disposition lives where the evidence does.

**Verdicts are not statuses** (v0.6.2, F-10). A status describes the work; a verdict is an independent judgement *about* it, and a task can be `COMPLETED` by its executor and `FAIL` its verifier — that pair is the most important signal a run produces. A **Grade / Verdict** column is checked against its own vocabulary: `PASS` · `PASS-with-carry-forwards` (CV id in the same row) · `FAIL` (VF id in the same row). Verdict words outside a Grade/Verdict column remain forbidden synonyms.

## 5. Cannot-validate record

```
CV-<run-id>-U<n>-<nn>: <claim>
  reason / workaround / successor / discharge
```
(fields as v0.3; discharge = the observable event that closes the record. **A record closed inside its own run adds `discharged: <date> ev:<citation>`** — v0.7.2, F-51: a CV is obligation-shaped only WHILE its discharge is future; eight of eighteen records in one pilot run were closed before publish and the escrow demanded registry rows for all eighteen, filling the registry of open obligations with records that owe nothing. GATE-7 exempts an evidenced in-run closure; a `discharged:` line WITHOUT evidence stays demanded — an unevidenced closure is an assertion.) **Allocation (v0.6.3, F-17):** the verifier allocates the number inside its own unit segment — three parallel verifiers correctly following the old run-scoped shape all allocated `-01`, and a CV record is exactly the id that outlives the run. Legacy run-scoped ids in existing records stay valid. **Short form (v0.7.0, OBL-PKG-13):** inside its own run's artifacts the shorthand `CV-<nn>` is legal and resolves to the run's full id; every durable home carries the **full form** — it is the id that outlives the run. The escrow resolves shorthands and demands the full row (real reports write `CV-01`, and the long regex alone made the escrow vacuous for exactly the records it exists to catch).

## 6. Codebase-map front-matter (P0 freshness, GATE-6) — git-only

```yaml
---
area: auth
verified_against: <git sha>
paths: ["src/auth/**", "helm/auth/**"]
---
```
**Fresh ⇔ `git diff --quiet <verified_against> HEAD -- <paths>` — the CONTENT under the mapped paths is unchanged** (v0.7.1, F-45; previously "commits touching the paths" — a merge ripple, a revert pair, or a formatting-only commit chain flagged maps stale whose subject matter had not moved, and a gate that cries stale gets its P0 skipped). Commits that touch the paths but leave the tree identical are reported as informational, not stale — INFERENCE, from GATE-3's cry-wolf clause rather than measured pilot behavior: routine false staleness is expected to train readers to skip P0. No calendar component. Stale map + main-lane work in the area ⇒ P0 required.

**Plan linkage:** unit plans declare an `areas:` list naming the codebase areas the unit touches — that is GATE-6(a)'s input. Without it the gate depends on the operator remembering `--area`, and a gate that only runs when someone remembers a flag is not a gate.

**No map yet?** The ORCH records the P0 outcome in the run's HANDOFF as `p0-record: <area> = fresh | not-required | updated`, and GATE-6 honours it. It is a format like any other — the machine home is `codebase_frontmatter.p0_record` in formats.json.

## 7. Gate-failure recovery

Fix-forward within the phase (repair artifact, re-run gate), **max 2 attempts** → then PARK + escalate at next gate. Never bypass; gate changes = PO sign-off + updated non-vacuity test.

**What the counter counts (v0.6.3, F-21):** the bound is per **failure of a fix**, not per check — attempt 1 is the fix, attempt 2 is the corrected fix; a verifier finding that the check as SIGNED already missed (a newly-surfaced pre-existing limit, reachable by neither the amendment nor its correction) is a **carry-forward** (CV record + registry row), not a spent attempt. When the fix's author is the ORCH, the **PO classifies** which of the two a finding is — an unspecified counter is decided by the party with the most at stake in the answer, and the ORCH grading its own amendment is that party.

## 8. HANDOFF.md (per run, ≤80 lines, overwritten, **ORCH-owned**)

Sections: `position` · `active-constraints` (blocking checkboxes) · `parked` (ids + one-liners) · `pointers` (manifest refs only).

The 80-line limit counts as `wc -l` does (v0.6.2 — the previous counter included the trailing newline, so no conforming file could ever reach 80). The limit is **advisory** (PO decision 2026-08-24): status.mjs reports the overage; no gate blocks on it — a long handoff must not block publishing at the moment continuity matters most.

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

**Shared-project scope** (v0.7.1, F-42): a repo whose Jira project hosts more than this repo's work sets `jira.scope` in `wow.config.json` — a JQL fragment (e.g. `component = platform` or `labels = cloakid-platform`) the ORCH ANDs into every query the mapping runs. **Convention, ORCH-consumed, not gated** (audit A2): no engine code reads this key — the gates check the divergence *record*, and the queries behind it are the ORCH's to run; a scope the ORCH ignores is a review finding, not a gate failure. Without it, GATE-10 diffs against every ticket in a shared project and drowns real divergences in other teams' noise; with it, the scope is a declared, versioned fact rather than a habit of whoever runs the gate.

Divergence classification at gate open: **git wrong** (update git, cite) · **Jira wrong** (transition Jira, cite) · **real gap** (actionable item → P4 classification). Sign-off records: Jira transition is authoritative; the governing git artifact mirrors it as `signed: <date> ev:jira{KEY-nn}` (GATE-9).

The diff lives in `runs/<run-id>/divergence-<gate>.md` as a table with **Item | Git | Jira | Classification** columns; GATE-10 reads the verdict from the Classification column, not from anywhere in the row. An empty diff is written as *"No divergences"* **plus an `ev:` citation of the query that produced it** — an unevidenced empty diff is an assertion, not a check. If the tracker was unreachable, say so in the record and leave an open `- [ ] gate-10 …` item in `jira-queue.md`; a deferral recorded nowhere is not a deferral.

## 11. External-dependency maps (`docs/deps/<name>.md`) — added v0.4.1, from pilot feedback PF-01

Facts about third-party surfaces (external APIs, SaaS platforms, vendor services) live in `docs/deps/<name>.md` — **not** `docs/codebase/`, because git-based freshness (§6) is meaningless for surfaces you don't version. The `probe:` line is executed as shell, so what it may **be** is part of the schema (v0.6.2, frisbii S-2): its first word must match `probe_allowed` in formats.json (default: a repo-local script — the request wrapper), overridable via `probe_command_pattern` in `wow.config.json`. Checked **before** execution; a disallowed probe fails loudly and is never run — and never falls through to the calendar branch. Front-matter:

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

The framework has single homes for facts, decisions and routes; obligations get one too — and it is **not a new artifact**: `docs/GAPS.md` is the obligation registry. **The registry file holds exactly ONE table** (stated v0.6.1, pilot #2 PF-c): row discovery matches any id-shaped first cell anywhere in the file — deliberate per FR-1, so an unreadable row fails loudly instead of parsing as empty — which means a second table whose first cells are id-shaped will be read as malformed gap rows. Put non-obligation tables in a sibling document; an id wrapped in backticks is a mention and is not row-matched. An obligation is a gap record whose discharge is future work (an owed audit, a mandated follow-up, a precondition for the next feature). It survives run archival because GAPS.md is durable — nothing that must outlive a run may live only in `runs/` (GATE-7 escrow check).

Record fields (schema in formats.json `gap_row`): id · taxonomy tag · **owner** (who discharges) · **effect** — closed controlled vocabulary: `advisory` | `blocks-new-feature-work` (consumer: GATE-12 refuses new-feature `/wow-spec`) | `blocks-install` (consumer: install.sh — reads the PACKAGE's own registry before writing and refuses install/upgrade into any target matched by an open row's `scope:`; rows carry `scope:` = repo name list or `*`, default `*` — added v0.5.5/v0.5.6, pilot N3+D1). An unrecognized effect value is a **validation failure, loudly** — never a silent downgrade to non-blocking. **Effect transitions are witnessed** (PO decision 2026-08-18, review PR-5): any change to an open row's `effect` carries an in-row note `effect: <old>→<new> <date>` plus fresh `ev:` — the sweep's transition check (engine round 3, OBL-PKG-16) fails an unwitnessed change, and GAPS.md is a scan target. **Code identifiers in registry cells go in inline backticks** (v0.7.3, prodsim/F-71: a repo's own formatter parsed bare snake_case as emphasis and silently rewrote `successor`/`discharge` identifiers into unexecutable `*`-spans — the fields that tell a future agent how to close the gap; inline code round-trips byte-for-byte). **A fully-backticked FIRST cell is not a row** — `gap_row.row_start` cannot match a leading backtick, so backticking the id cell silently removes the row from the registry; backtick identifiers, never the id cell. Escape any literal `|` inside any cell as `\|` (v0.6.4, F-18: `_cells` honors the escape everywhere now, retiring the old trailing-cell-only caveat — a field that carries a shell command must not be delimited by a character shells use) · successor · discharge condition · `ev:` on creation and on discharge.

`effect: blocks-new-feature-work` is machine-consequential: GATE-12 refuses `/wow-spec` for a **new feature** while one is open. Exempt (they are how obligations get discharged): audit specs, fix iterations (`r>1`), and probes, when they reference the blocking obligation's id — **and remediation specs** (v0.7.2, F-53), which discharge NO blocker and are admitted when their `--ref` resolves to a **recorded defect** (a PARK/VF/DEF-plan/CV id or registry row, found as a claim in `runs/` or the registry): repairing the regression the previous run shipped is the normal shape of post-run work, and keying every exemption to blocking rows left it only the overrule route. New capability under a remediation flag is a G1 review refusal, not a mechanical one. Keep `effect` separate from `owner` — who discharges and what it blocks are different facts; conflating them in one field re-creates the drift class this framework exists to kill.

**Derivation, not narrative:** status.mjs reads GAPS.md (and REQUIREMENTS) — it answers *what does the current state require next*, not only *what is the state*. Audit-trigger counters derive from durable homes, never from archived RUN-REPORTs. Between-run continuity comes from derivation over durable records — HANDOFF stays per-run and retired at P5; no persistent narrative state returns through this door.

## 13. Pilot feedback log (`docs/pilot-feedback.md`) — added v0.6.0, PO decision 2026-08-18

Feedback ids are load-bearing (the CHANGELOG cites them); this is their definition. One table:

| id | source | state | upstream-ref |
|---|---|---|---|

`F-nn` = repo-local finding ids; `PF-nn` is reserved for package-side records. **A finding id cited OUTSIDE its allocating repo is written qualified** — `platform/F-58`, `prodsim/F-60` — and the installed package files count as a crossing, because they land inside every consumer (v0.7.3, prodsim/F-67: a new pilot measured the package's bare citations, started 'above the maximum', mis-measured on the first try, and its very first id collided with a load-bearing one — arithmetic across repos is a race; qualification is collision-proof at the point the crossing happens. The four previously-colliding citations are requalified; older bare history is grandfathered). **The log is per-branch until merged** (prodsim/F-73): append-only survives no branch split, and gate-7 reconciles whatever branch it runs on — reconcile the log at merge like any other durable home. `state` ∈ open |
adopted | declined | superseded. `upstream-ref` = the issue/commit/CHANGELOG entry that answered
it. Append-only; the file lives in any consuming repo that files feedback. **A logged finding owes its write-up before the next publish** (v0.6.4, F-37): a log row is cheap at the moment of the finding and a write-up is not, so the two drift — twice now, with the first occurrence predicting the second. gate-7 `--p5` reconciles the log against the upstream write-ups directory, only where a log exists.

**Audit findings:** an audit run's verdict table is `runs/<id>/FINDINGS.md` — a named run
artifact (see runs_layout), archived with its run. **GLOSSARY:** `docs/GLOSSARY.md` is an
optional durable home for term definitions; no schema, no gate.
