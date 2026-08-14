# INSTALL — packaging, entry reliability, migration — DRAFT v0.5.0

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
4. Idempotent; re-run to upgrade. Version stamp in `wow.config.json`; `install.sh --check` diffs installed vs canonical.
No npm, no third-party installer, no vendored engine — plain files owned in our repos.

**Where the hooks go.** To the directory git actually reads: `core.hooksPath` when the repo sets one (husky, lefthook and the `pre-commit` framework all do), otherwise the **common git dir**, so **every worktree inherits them** — executor enforcement is free. Writing to `.git/hooks` unconditionally is how a repo can end up with zero enforcement while every self-check reports a healthy install, so both `--check` and `status.mjs` report the resolved directory and how it was chosen.

**Existing hooks are preserved, not clobbered.** A target that already has its own `commit-msg`/`pre-commit` keeps it: the file is moved to `<hook>.pre-wow` and the WoW hook runs it first, failing the commit if it fails. Adopting a process framework should not silently delete a project's lint hook.

**What `--check` verifies.** Engine files and playbooks byte-for-byte; command stubs; the CLAUDE.md section between its markers; files present in the target but no longer in the package (`EXTRA` — a plain install prunes them, so "installed == canonical" stays true across upgrades); and the hooks *by body*, not by the presence of the string `gates.sh`. A hook rewritten to `exit 0` with a comment mentioning gates.sh is drift, and the strongest enforcement layer is exactly the one that must not be silently removable.

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

1. Freeze `.planning/` read-only (git — no deletions; it is history).
2. Lift durables into `docs/`: REQUIREMENTS (active REQ rows only, restated statuses reconciled once), GAPS + surface index, TRACEABILITY, codebase map (from `.planning/codebase/`), specs-in-flight → `docs/spec/`.
3. Derive nothing from STATE.md except by human review; its counters are untrusted (documented parse-miss corruption).
4. First WoW run starts at `/wow-ground` for the target area; `settings.local.json` regenerated from policy template at first P5.
5. Jira: create the pilot epic at first G1 — no retro-import of GSD history (archived `.planning/` remains the reference).

## Audience-label loading rule

Manifests are audience-filtered: AGENT contexts receive only `[AGENT]` sections (P3 defines the manifests). ORCH loads full playbooks. `[PO]` sections are checklists surfaced at gates — the PO is never expected to read the package.
