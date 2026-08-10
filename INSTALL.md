# INSTALL — packaging, entry reliability, migration — DRAFT v0.4

## Canonical home & install path

Canonical package: this repository. Per-repo install = `./install.sh <target-repo>`:
1. Writes/updates the **WoW section** of the target's `CLAUDE.md` (between `<!-- wow-v2:start/end -->` markers; rest of CLAUDE.md untouched).
2. Copies `docs/process/` (playbooks), `scripts/wow/` (gates.sh, status.mjs, formats.json + tests, permissions-policy.json template, wow.config.json template).
3. Writes `.claude/commands/wow-*.md` stubs (below) and installs git hooks: **commit-msg** (GATE-1 — message validation cannot run in pre-commit) and **pre-commit** (GATE-5 on staged files). Hooks sit in the common git dir, so **every worktree inherits them** — executor enforcement is free.
4. Idempotent; re-run to upgrade. Version stamp in `wow.config.json`; `install.sh --check` diffs installed vs canonical.
No npm, no third-party installer, no vendored engine — plain files owned in our repos.

## Command stubs (deterministic phase entry)

Each `.claude/commands/wow-<phase>.md` is 3 lines: *"Read `docs/process/P<n>-<PHASE>.md` in full and follow it for $ARGUMENTS. Load only the files its Load line names. Do not proceed from memory."* Single home for playbooks stays `docs/process/`; commands are pointers. Same for `/wow-quick`, `/wow-debug` → LANES.md, `/wow-status` → runs status.mjs and reports.

## Reliability model (how we guarantee the process triggers)

Three layers, weakest-to-strongest:
1. **Deterministic entry** — phases/lanes are entered via `/wow-*` commands; the command text is the load instruction, so playbook loading is not model-remembered. CLAUDE.md's resident router covers the case where a session starts drifting into changes without a command: its rule is short, single, and checkable ("no active lane → stop and route").
2. **Orchestrator-independent backstop** — git hooks: a laneless commit *cannot land* (GATE-1, commit-msg), stale citations in modified files cannot land (GATE-5, pre-commit). Whatever the model forgets, the repo rejects — in every worktree. This is the layer GSD lacked ("prose rules depend on the orchestrator catching itself"). `formats.json` is the shared schema home for gates.sh **and** status.mjs, so enforcement and status derivation can never disagree about a format.
3. **Optional hardening (off by default,** per PO "hooks only if absolutely needed"): PreToolUse hook blocking Edit/Write when no active lane context exists (marker file `runs/.active`). Enable per repo only if pilot shows layer 1–2 leakage. SessionStart hook injecting the router line is a cheaper alternative if drift is the observed failure.

Failure telemetry: gates.sh logs rejections to `runs/.gate-log` — pilot reviews it to decide whether layer 3 is needed. That's the evidence-based version of "assurance all elements are triggered when needed."

## Migration (per repo, at pilot start)

1. Freeze `.planning/` read-only (git — no deletions; it is history).
2. Lift durables into `docs/`: REQUIREMENTS (active REQ rows only, restated statuses reconciled once), GAPS + surface index, TRACEABILITY, codebase map (from `.planning/codebase/`), specs-in-flight → `docs/spec/`.
3. Derive nothing from STATE.md except by human review; its counters are untrusted (documented parse-miss corruption).
4. First WoW run starts at `/wow-ground` for the target area; `settings.local.json` regenerated from policy template at first P5.
5. Jira: create the pilot epic at first G1 — no retro-import of GSD history (archived `.planning/` remains the reference).

## Audience-label loading rule

Manifests are audience-filtered: AGENT contexts receive only `[AGENT]` sections (P3 defines the manifests). ORCH loads full playbooks. `[PO]` sections are checklists surfaced at gates — the PO is never expected to read the package.
