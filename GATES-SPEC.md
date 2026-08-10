# GATES-SPEC — mechanical enforcement (single home for rules) — DRAFT v0.4

> Implemented as `scripts/wow/gates.sh` at pilot. Hook placement matters: **GATE-1 runs in the `commit-msg` hook** (the message doesn't exist at pre-commit); **GATE-5 runs in `pre-commit`** (staged files). Hooks live in the common git dir and are **inherited by every worktree** — executors get enforcement for free. Full sweep runs at every gate + P5. Patterns/vocabulary/schemas come from `scripts/wow/formats.json` — consumed by **both gates.sh and status.mjs**; neither script contains inline formats. Process docs reference gates by ID and never restate them. Every gate has a negative test in `scripts/wow/tests/`; a gate whose negative test doesn't fail when the gate is disabled is itself a defect (inert-gate class — recurred 3× under GSD).

| ID | Check | Where | On fail |
|---|---|---|---|
| GATE-1 | Commit message contains exactly one lane ref (`[T:]`/`[Q:]`/`[D:]`/`[WOW:publish]`) and the referenced task/lane path exists | **commit-msg hook** | block commit |
| GATE-2 | Phase close: every REQ ID named by the active spec/plan has an updated technical-status row in `docs/REQUIREMENTS.md` | gate sweep | block gate |
| GATE-3 | Completion-class statuses / done-words carry `ev:` citations in the same row/sentence (RUN-REPORT, report files, SPEC ACs, REQUIREMENTS rows, quick NOTE results). **Enforced subset only** — claim-label discipline is convention, not gated | gate sweep | block gate |
| GATE-4 | Every invariant/check added or modified in this run has a recorded non-vacuity proof | gate sweep | block gate |
| GATE-5 | `file:line` citations **in files modified by this commit/run** pass preflight (match/drifted/gone). Sweep-found drift in *unmodified* docs is NOT blocking — it feeds audit-trigger counter AT-4 (P4) | **pre-commit** + sweep | block commit/gate |
| GATE-6 | Main-lane plan in area X requires map freshness per FORMATS §6 (git-only rule) or a P0 completion record in HANDOFF | at `/wow-plan` | block plan |
| GATE-7 | P5 sweep: no unresolved `jira-queue.md`, no un-GC'd stale quick stubs, archive state consistent | at P5 | block publish |
| GATE-8 | **Plan structural lint** (mechanized reviewer checks, runs before G2a review): (a) no ownership overlap between unit path lists, and no unit claims an ORCH-owned file (FORMATS §9); (b) AC↔task coverage matrix present and total (every SPEC AC mapped); (c) every auto task has a verify command. PLAN.md must parse against the plan schema in formats.json | at G2, pre-review | block review |
| GATE-9 | **Gate-closure record**: G1/G2/G4 close requires `signed: <date> ev:jira{KEY-nn}` in the governing artifact (spec header for G1/G4, PLAN header for G2) | gate sweep | gate not closed |
| GATE-10 | **Divergence diff (git↔Jira)** at gate open: statuses/sign-offs compared against the expected mapping (FORMATS §10); each divergence must be classified (git wrong / Jira wrong / real gap) before gate close. Requires MCP; offline → diff deferred to jira-queue and the deferral recorded | gate open | block gate close on unclassified divergences |

**formats.json content spec (single machine home, dual consumers):** `ids` (run/task/unit/DEV/PARK/VF/DEF/CV regexes) · `commit_trailers` · `branch_patterns` · `status_vocab` + forbidden synonyms · `claim_labels` · `evidence` types · `codebase_frontmatter` schema · **`plan_schema`** (units, ownership lists, coverage matrix, tasks w/ verify) · **`report_row_schema`** · **`requirements_row_schema`** · `jira_mapping` (FORMATS §10 table) · `runs_layout`.

**Recovery on any gate failure:** FORMATS §7. **Explicitly not gates (judgment — ORCH/PO):** premise-check quality, unit sizing, autonomy-contract scope, contract-gap review, classification decisions, claim-label quality. A gate that pretends to check judgment is theater.
