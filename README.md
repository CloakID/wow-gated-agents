# WoW v2 — a gated, evidence-first way of working for AI coding agents

**Status: DRAFT — current version is the top entry of [CHANGELOG.md](CHANGELOG.md) (the package's single version authority); engine debts are registered in [docs/GAPS.md](docs/GAPS.md). Two pilots running, actively seeking feedback.**

WoW v2 is a spec→plan→run→report process for building software with AI coding agents (designed against Claude Code, portable in principle to any agent runner). It grew out of six months of running [GSD (get-shit-done)](https://github.com/gsd-build/get-shit-done) across two production repos, auditing what actually failed, and rebuilding around two findings that kept repeating:

1. **Prose rules fail; mechanical gates work.** Nearly every logged process lapse was a rule the model was supposed to remember. Rules that mattered only started holding when they became runnable checks the orchestrator couldn't skip.
2. **Every documentation drift was a copy-sync failure.** Facts duplicated across files (status in four places, decisions in six) diverged, always. The fix is structural: single home per fact, derived views, no persistent narrative state.

Full story with evidence: [DESIGN-RATIONALE.md](DESIGN-RATIONALE.md).

## What's in the box

- **[CLAUDE-WOW-SECTION.md](CLAUDE-WOW-SECTION.md)** — the ~60-line resident router (lanes, non-negotiables, paths) that goes in your agent memory file. Everything else loads on phase entry.
- **[docs/process/](docs/process/)** — phase playbooks **P0 GROUND → P1 SPEC → P2 PLAN → P3 RUN → P4 REPORT & RECONCILE → P5 PUBLISH**, plus [LANES.md](docs/process/LANES.md) (quick/debug lanes and precedence) and [FORMATS.md](docs/process/FORMATS.md) (IDs, evidence citations, status vocabulary, git/tracker ownership split). Every section is audience-tagged `[PO]` / `[ORCH]` / `[AGENT]` so subagents are never shown duties they can't perform.
- **[GATES-SPEC.md](GATES-SPEC.md)** — the eleven mechanical gates (commit-msg + pre-commit hooks + gate sweeps), each required to ship with a **non-vacuity proof**: the negative test that shows the gate can actually fail.
- **[scripts/wow/](scripts/wow/)** — the reference implementation: `gates.sh` (+ its engine `gates.py`), `formats.json` (the single machine home for every pattern, path and vocabulary), `status.mjs` (derived status), and `tests/` — one negative test per gate plus `test-install.sh`, which drives real commits through the real hooks to prove the gates are *wired*, not merely correct.
- **[install.sh](install.sh)** — per-repo installer. Idempotent, writes only repo-scoped files, preserves an existing hook by chaining to it, and `--check` reports drift against the canonical package.
- **[INSTALL.md](INSTALL.md)** — packaging, the three-layer entry-reliability model, and a migration path from GSD's `.planning/`.
- **[FIELD-MECHANISMS.md](FIELD-MECHANISMS.md)** — deployment-specific mechanisms (invariant suites, gap registration, coevolution stamps…) described by aim + dependencies; implementations are per-project.

## What's new in v0.5.0

v0.4 was the design. **v0.5.0 adds the reference implementation** — and, more to the point, evidence that it is *connected*.

- **The engine ships.** `install.sh` + `scripts/wow/` (`gates.sh` → `gates.py`, `formats.json`, `status.mjs`, `tests/`). One command installs it into any git repo; `--check` reports drift against the canonical package; re-running upgrades in place.
- **Wiring is now tested, not assumed.** Every gate had a passing negative test while GATE-7 sat in no sweep list, GATE-6's codebase half had no caller, and hooks were written to `.git/hooks` in repos whose `core.hooksPath` meant git never read them — with the installer and the status tool both reporting a healthy install. All of those are fixed, and the new `tests/test-install.sh` installs into throwaway repos and drives real commits through real hooks so the class cannot come back. **104 assertions**, and disabling any gate still fails its own test.
- **Gates that could pass for the wrong reason no longer do.** A lane ref must name a real task *row*, not a task id mentioned in prose; GATE-2 wants the requirement row *updated in this run*, not merely present; GATE-5 judges the staged content rather than the worktree; GATE-8 fails a spec whose ACs it cannot parse instead of calling zero-of-zero total; GATE-9 makes the sign-off record *required* when a gate is actually closing; GATE-10 reads the verdict from the Classification column and wants an empty diff evidenced; GATE-11 blocks deletions of frozen history, not just edits.
- **`formats.json` is genuinely the single machine home.** The scan-target list, the `p0-record` vocabulary, the invariant/non-vacuity markers, the divergence-record columns and the install manifest all used to live inside the engines, where nobody reading the docs could find them. `gates.py`, `status.mjs` **and** `install.sh` are all consumers of it now, so no two of them can disagree about what a format is.
- **Prerequisites are stated and checked** (bash 3.2+, git 2.5+, python3; node optional, for status only). `install.sh` aborts on a missing one instead of installing a half-enforcing repo, an existing `pre-commit`/`commit-msg` hook is preserved and chained rather than overwritten, and the package no longer assumes macOS.

Upgrading a repo installed from v0.4: `./install.sh /path/to/repo`, then `bash scripts/wow/tests/run-all.sh`.

## Core ideas, in one paragraph each

**Bounded autonomy, not perfect plans.** Executors get an explicit autonomy contract: in-contract deviations are decided and logged (`DEV-U2-03`); anything cross-unit, acceptance-criteria-touching, or irreversible is parked with a blocker note and the run continues. No mid-run questions, no silent improvisation.

**Verification is independent and re-validated.** A verifier agent with a fresh context — never shown the implementer's reasoning — re-runs every check itself. Fixes are re-validated (in our field data, 2 of 10 review fixes were themselves wrong). Acceptance criteria are executable, and harness-touching ones carry a written **premise check**: *can this pass for the wrong reason?* (Our worst field failure was a milestone that passed every gate while delivering zero real value.)

**Parallelism is a merge problem.** Units own disjoint path sets (machine-checked), interfaces freeze at plan sign-off, executors commit only to their unit branch, and only the orchestrator merges — sequentially, in wave order, with a defined conflict policy and a serial integration wave last.

**Git owns content; the tracker owns workflow.** Requirement *technical* status (evidence-backed) lives in git; *workflow* status lives in the tracker (Jira in our deployment). Divergence between them is never silently merged — gates open with a diff, and every out-of-mapping pair is classified: git wrong, tracker wrong, or a real gap.

## Prerequisites

The package is plain files — no npm, no vendored engine, no third-party installer. It needs:

| | Version | Needed for | Without it |
|---|---|---|---|
| **bash** | 3.2+ | `install.sh`, `gates.sh`, the negative tests | nothing runs (macOS ships 3.2; nothing here needs bash 4) |
| **git** | 2.5+ | hooks, `git worktree`, `--git-common-dir`, every freshness and modified-file rule | nothing runs |
| **python3** | 3.6+ | `gates.py` — the engine `gates.sh` delegates to; also the in-place CLAUDE.md section edit | **no gates**; `install.sh` refuses to run |
| **node** | 18+ | `status.mjs` only | *optional* — you lose derived status, not enforcement |

`install.sh` checks these before writing anything and aborts with a named prerequisite rather than installing a half-working framework. Nothing else is assumed: no package manager, no CI service, no OS-specific tools (the suite hashes with whichever of `sha256sum`/`shasum`/`python3` exists).

## Adopting it

Read INSTALL.md. Short version:

```sh
git clone <this repo> && cd wow-v2
./install.sh /path/to/your-repo          # idempotent; re-run to upgrade
cd /path/to/your-repo
bash scripts/wow/tests/run-all.sh        # negative test per gate + the wiring test
node scripts/wow/status.mjs              # derived status (optional; needs node)
```

Then set the tracker project key in `scripts/wow/wow.config.json` and enter work through the `/wow-*` commands. `./install.sh --check /path/to/your-repo` reports drift between what is installed and the canonical package — including a hook someone has quietly neutered.

## Feedback

This is a design under review — see [CONTRIBUTING.md](CONTRIBUTING.md) for the specific questions we most want challenged. Issues and discussions welcome.

MIT licensed.
