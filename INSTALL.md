# INSTALL — packaging, entry reliability, migration — DRAFT v0.5.6

## Prerequisites

Checked by `install.sh` before it writes anything; a missing required tool aborts the install rather than leaving a half-enforcing repo.

| Tool | Version | Used by | Missing ⇒ |
|---|---|---|---|
| **bash** | 3.2+ | `install.sh`, `gates.sh`, `scripts/wow/tests/*` | install aborts (macOS's 3.2 is enough — nothing uses bash-4 syntax) |
| **git** | 2.5+ | hooks, `git worktree`, `rev-parse --git-common-dir`, GATE-2/5/6's modified-file and freshness rules | install aborts; below 2.5 you lose worktree hook inheritance |
| **python3** | 3.6+ | `gates.py` (the engine behind `gates.sh`), and the in-place CLAUDE.md section rewrite | install aborts — **no gates at all** |
| **node** | 18+ | `status.mjs` | *optional.* Derived status is unavailable; enforcement is unaffected, and `install.sh` only prints a note |

Nothing else is assumed — no npm, no package manager, no CI service. Where a hash is needed the test suite uses whichever of `sha256sum`, `shasum` or `python3` the machine has, so the package runs unchanged on macOS and Linux.

## Canonical home & install path

Canonical package: this repository. Per-repo install = `./install.sh <target-repo>`:
1. Writes/updates the **WoW section** of the target's `CLAUDE.md` (between `<!-- wow-v2:start/end -->` markers; rest of CLAUDE.md untouched). The section is passed to the rewrite as a file, never as a regex replacement string — a backslash in the router text used to abort the rewrite (or duplicate the marker block) while the installer reported success.
2. Copies `docs/process/` (playbooks) and `scripts/wow/`: `gates.sh`, **`gates.py`** (the engine gates.sh delegates to), `formats.json`, `status.mjs`, `tests/`, `permissions-policy.json`, and **`GATES-SPEC.md`** (so the repo's CLAUDE.md router can cite a path that exists locally). `wow.config.json` is created once from a template and never overwritten — it holds repo-local truth.
3. Writes `.claude/commands/wow-*.md` stubs (below) and installs git hooks: **commit-msg** (GATE-1 — message validation cannot run in pre-commit) and **pre-commit** (GATE-5 + GATE-11 on staged files).
4. Before writing anything, install.sh consults the package's own `docs/GAPS.md`: an open `blocks-install` row whose `scope:` matches the target refuses the install, citing the row (**OBL-PKG-11** until implemented — check by hand). Idempotent; re-run to upgrade. Version stamp in `wow.config.json`; `install.sh --check` diffs installed vs canonical.
No npm, no third-party installer, no vendored engine — plain files owned in our repos.

**Where the hooks go.** To the directory git actually reads: `core.hooksPath` when the repo sets one (husky, lefthook and the `pre-commit` framework all do), otherwise the **common git dir**, so **every worktree inherits them** — executor enforcement is free. Writing to `.git/hooks` unconditionally is how a repo can end up with zero enforcement while every self-check reports a healthy install, so both `--check` and `status.mjs` report the resolved directory and how it was chosen.

**Existing hooks are preserved, not clobbered.** A target that already has its own `commit-msg`/`pre-commit` keeps it: the file is moved to `<hook>.pre-wow` and the WoW hook runs it first, failing the commit if it fails. Adopting a process framework should not silently delete a project's lint hook.

**What `--check` verifies.** Engine files and playbooks byte-for-byte; command stubs; the CLAUDE.md section between its markers; files present in the target but no longer in the package (`EXTRA` — a plain install prunes them, so "installed == canonical" stays true across upgrades); and the hooks *by body*, not by the presence of the string `gates.sh`. A hook rewritten to `exit 0` with a comment mentioning gates.sh is drift, and the strongest enforcement layer is exactly the one that must not be silently removable.

## Install modes — declared intent, derived verification (added v0.5.6, PO design question)

`install.sh --mode fresh|upgrade|migrate` **[DESIGNED-NOT-IMPLEMENTED — OBL-PKG-12; run the checks by hand until it lands]**. The mode is the operator's declared intent; the installer derives the target's actual intake state and **refuses on mismatch** — a declared mode is never trusted over evidence (derive-don't-declare, the p0-record pattern):

- `fresh`: no prior wow.config version stamp, no `.planning/`, no pre-existing durable homes expected. Refused if `.planning/` exists (that's a migration) or a version stamp exists (that's an upgrade).
- `upgrade`: prior stamp required. **Drift-refusal guard:** any installed file that differs from BOTH current canonical and the version previously installed is a local modification — the installer lists the diffs and refuses without explicit per-file acknowledgment. This is the general form of the G-11 protection: it guards every future local fix, not one known case.
- `migrate`: `.planning/` present; runs the Migration checklist below (vacuity artifact, legacy-invariant list, permissions merge) as gated steps, not prose.

Orthogonal to modes, always: the package-registry consult (open `blocks-install` rows, OBL-PKG-11) — that guards against a defective *source*; modes and drift-refusal guard the *target*.

## Command stubs (deterministic phase entry)

Each `.claude/commands/wow-<phase>.md` is 3 lines: *"Read `docs/process/P<n>-<PHASE>.md` in full and follow it for $ARGUMENTS. Load only the files its Load line names. Do not proceed from memory."* Single home for playbooks stays `docs/process/`; commands are pointers. Same for `/wow-quick`, `/wow-debug` → LANES.md, `/wow-status` → runs status.mjs and reports.

## Reliability model (how we guarantee the process triggers)

Three layers, weakest-to-strongest:
1. **Deterministic entry** — phases/lanes are entered via `/wow-*` commands; the command text is the load instruction, so playbook loading is not model-remembered. CLAUDE.md's resident router covers the case where a session starts drifting into changes without a command: its rule is short, single, and checkable ("no active lane → stop and route").
2. **Orchestrator-independent backstop** — git hooks: a laneless commit *cannot land* (GATE-1, commit-msg), stale citations in staged content cannot land (GATE-5, pre-commit), and in a migrated repo nothing touches the frozen `.planning/` (GATE-11, pre-commit). Whatever the model forgets, the repo rejects — in every worktree. This is the layer GSD lacked ("prose rules depend on the orchestrator catching itself"). `formats.json` is the shared schema home for gates.sh **and** status.mjs, so enforcement and status derivation can never disagree about a format.

   The hooks fail *open* if `scripts/wow/gates.sh` is absent — a branch predating the install must still be checkoutable — but they say so loudly on stderr rather than passing in silence, and `install.sh --check` and `status.mjs` both report the true hook state.

   **Wiring is tested, not assumed.** `scripts/wow/tests/test-gate-*.sh` prove each gate's *logic* by calling `gates.sh` directly. `scripts/wow/tests/test-install.sh` proves the *wiring*: it installs into a throwaway repo — including one configured with `core.hooksPath` and one with a pre-existing hook — and drives real `git commit`s through the real hooks. Every gate can have a passing negative test while nothing calls it; that is the same inert-gate defect one level up.
3. **Optional hardening (off by default,** per PO "hooks only if absolutely needed"): PreToolUse hook blocking Edit/Write when no active lane context exists (marker file `runs/.active`). Enable per repo only if pilot shows layer 1–2 leakage. SessionStart hook injecting the router line is a cheaper alternative if drift is the observed failure.

Failure telemetry: gates.sh logs rejections to `runs/.gate-log` — pilot reviews it to decide whether layer 3 is needed. That's the evidence-based version of "assurance all elements are triggered when needed."

**Running the gates by hand** (the playbooks name these; hooks call the first three for you):

```sh
scripts/wow/gates.sh list                        # every gate, where it runs, what it blocks
scripts/wow/gates.sh gate-1 <msgfile>            # commit-msg hook
scripts/wow/gates.sh gate-5  --staged            # pre-commit hook
scripts/wow/gates.sh gate-11 --staged            # pre-commit hook (inert unless migrated)
scripts/wow/gates.sh gate-6  --run <id>          # /wow-plan: plan-declared areas: + deps:
scripts/wow/gates.sh gate-8  --run <id>          # G2, before review
scripts/wow/gates.sh gate-9  --gate G2 --run <id>  # gate close: the record is REQUIRED
scripts/wow/gates.sh gate-10 --run <id> --gate G2  # gate open: divergence diff
scripts/wow/gates.sh sweep --run <id>            # every gate sweep
scripts/wow/gates.sh sweep --p5 --run <id>       # P5: the sweep plus GATE-7
```

## Coexistence with GSD (per-repo adoption, no forced migration)

Everything install.sh writes is **repo-scoped** (CLAUDE.md markers, docs/process/, scripts/wow/, commands, hooks). Repos not yet migrated keep GSD untouched — the frameworks never interact across repo boundaries; each repo migrates at its own deliberate moment. The one cross-contamination path is the **reverse** direction: GSD's engine is installed at operator level (`~/.claude/`), so `/gsd:*` commands remain invocable inside WoW repos. Closures: (a) the migrated repo's CLAUDE.md router deprecates GSD entry points for that repo; (b) **GATE-11** rejects any commit touching the frozen `.planning/` in repos flagged `migrated_from_gsd`; (c) keep user-level `~/.claude/CLAUDE.md` framework-neutral ("follow the repo's CLAUDE.md way-of-working") so the repo decides, not the operator config.

## Migration (per repo, at pilot start)

> Cite these steps by their bold names, not their numbers — the list renumbers as it grows (pilot N4).

1. Freeze `.planning/` read-only (git — no deletions; it is history).
2. Lift durables into `docs/`: REQUIREMENTS (active REQ rows only, restated statuses reconciled once), GAPS + surface index, TRACEABILITY, codebase map (from `.planning/codebase/`), specs-in-flight → `docs/spec/`.
3. Derive nothing from STATE.md except by human review; its counters are untrusted (documented parse-miss corruption).
4. **Re-home or retire legacy invariants BEFORE enabling GATE-11** (added v0.5.4, pilot #2): any pre-existing assertion that reads `.planning/` as its subject goes permanently green against frozen history the moment the freeze flips — the inert-gate class. Each such check is either re-pointed at the lifted homes (`docs/REQUIREMENTS.md`, `runs/`) or retired with a recorded reason. The freeze is not flipped until this list is empty.
5. First WoW run starts at `/wow-ground` for the target area. `settings.local.json` regeneration at first P5 is a **reviewed merge, not a wipe** (added v0.5.4): generate from `permissions-policy.json`, then diff against the accreted file and carry forward entries the migration window actually uses (verify commands above all); dropped entries are listed for PO confirmation. A wipe on day one strips the run of its own verify permissions.
6. **Brownfield vacuity warning** (added v0.5.4): gates whose durable homes don't exist yet (no REQUIREMENTS rows, no codebase map, no runs/) pass vacuously until reconciliation builds those homes — reconciliation is the precondition for non-vacuous gates, not cleanup. The check is a **written artifact, not a thought** (v0.5.5, pilot residual on #4): the install step produces `docs/install-vacuity.md` — one table, gate by gate, subject home exists / does not — committed with the install. Filled by hand until OBL-PKG-09 automates it; a green sweep in a repo with empty homes certifies nothing, and now says so on disk.
7. Jira: create the pilot epic at first G1 — no retro-import of GSD history (archived `.planning/` remains the reference).

## Reversibility (added v0.5.4)

Rollback recipe, tested before you rely on the install: (1) remove the WoW section between the CLAUDE.md markers; (2) remove the two installed hooks (commit-msg, pre-commit) from the resolved hooks directory — restore any pre-existing hook bodies `install.sh` chained; (3) delete `.claude/commands/wow-*.md`, `docs/process/`, `scripts/wow/`; (4) `runs/` and the durable `docs/` homes are yours, not the package's — they stay. `install.sh --uninstall` automating this is OBL-PKG-10.

## Audience-label loading rule

Manifests are audience-filtered: AGENT contexts receive only `[AGENT]` sections (P3 defines the manifests). ORCH loads full playbooks. `[PO]` sections are checklists surfaced at gates — the PO is never expected to read the package.
