# scripts/wow — the enforcement engine

Implements GATES-SPEC.md. Written during pilot #1; this branch contributes it back.

## Prerequisites

| | Version | Needed for | Missing ⇒ |
|---|---|---|---|
| bash | 3.2+ | `gates.sh`, `tests/*` | nothing runs |
| git | 2.5+ | hooks, worktrees, every freshness and modified-file rule | nothing runs |
| python3 | 3.6+ | `gates.py`, the engine behind `gates.sh` | **no gates** |
| node | 18+ | `status.mjs` | optional — no derived status; enforcement unaffected |

No npm, no package manager, no OS-specific tools: the suite hashes with whichever of
`sha256sum`, `shasum` or `python3` exists, so it runs unchanged on macOS and Linux.

| File | Role |
|---|---|
| `formats.json` | **The single machine home.** Ids, paths, commit trailers, branch patterns, status vocabulary, evidence types, scan targets, codebase and dependency front-matter, plan/report/requirements schemas, Jira mapping, non-vacuity markers, legacy freeze, runs layout, audit triggers, install manifest, sweep composition. Consumed by *both* `gates.sh` and `status.mjs` |
| `gates.sh` | Entry point. Everything — hooks, playbooks, operators — calls this and only this |
| `gates.py` | The engine `gates.sh` delegates to |
| `status.mjs` | Derived status. No persistent narrative state; reads the same `formats.json` |
| `tests/` | One negative test per gate, plus `test-install.sh` — the wiring test |
| `permissions-policy.json` | `.claude/settings.local.json` is regenerated from this at P5 |
| `GATES-SPEC.md` | Copied in by `install.sh`; the repo's CLAUDE.md router cites this path |

## Why gates.sh delegates to gates.py

GATES-SPEC names `gates.sh`, and that is still the only thing anything calls. But GATE-8 compares
glob-expanded ownership sets, and every gate reads schemas out of JSON — bash does neither
honestly. The wrapper keeps the specified single entry point; the engine is where the work is.
Raised for review: if the package would rather have a pure-bash implementation, that is a
different set of trade-offs and worth an issue.

## Two kinds of test, because there are two kinds of failure

- **`test-gate-<n>.sh` — logic.** Each builds a fixture that must be rejected and asserts the
  *cause* matches, so a gate that rejects for an unrelated reason has not been proved. Disable any
  gate and its test fails; that is the non-vacuity proof GATE-4 requires.
- **`test-install.sh` — wiring.** Installs into throwaway repos and drives real `git commit`s
  through the real hooks, including a repo that sets `core.hooksPath` and one that already has its
  own hook. Every gate can have a perfect negative test while nothing calls it — that is the same
  inert-gate defect one level up, and it is how GATE-7 sat in no sweep list, GATE-6's area half had
  no caller, and hooks landed where git never looks while `--check` said "no drift".

## What is deliberately *not* fully mechanical

Two gates report the limits of what a shell can know, rather than pretending:

- **GATE-10** cannot reach the Atlassian MCP from a git hook. It checks that the ORCH produced a
  divergence record for the gate, that every row carries a classification *in the Classification
  column*, that an empty diff is evidenced rather than asserted, and that an offline gate open
  leaves an open `jira-queue.md` item. Producing the diff is an MCP action; verifying it is
  complete is mechanical.
- **GATE-6's dependency half** runs a probe command read from `docs/deps/<name>.md`. That is the
  same trust level as a git hook or a Makefile target. `--no-probe` degrades to the
  `max_age_days` fallback rather than silently passing.

Everything else either fails for a stated reason or passes.

## No inline formats

If a literal regex, path, status word or section name appears in `gates.py` or `status.mjs`, that
is a defect — it belongs in `formats.json`, or the two consumers can drift apart on what a format
means. This is not aspirational: the scan-target list, the `p0-record` vocabulary, the
invariant/non-vacuity markers and the divergence-record column names all used to live in the
engine, where nobody reading the docs could find them.

## Running

```sh
gates.sh list                          # every gate, where it runs, what it blocks
gates.sh gate-1 <msgfile>              # commit-msg hook
gates.sh gate-5  --staged              # pre-commit hook (judges the INDEX, not the worktree)
gates.sh gate-11 --staged              # pre-commit hook, inert unless migrated_from_gsd
gates.sh gate-6 --run <id>             # /wow-plan: plan-declared areas: + deps:
gates.sh gate-6 --area <a> [--no-probe]  # P0: one area, or deps without running probes
gates.sh gate-8 --run <id>             # G2, before review
gates.sh gate-9 --gate G2 --run <id>   # gate close: the record is REQUIRED
gates.sh gate-10 --run <id> --gate G2  # gate open
gates.sh sweep --run <id>              # the sweep every gate runs
gates.sh sweep --p5 --run <id>         # P5: the sweep plus GATE-7

bash tests/run-all.sh                  # negative test per gate + the wiring test
node status.mjs [--json] [--run <id>]  # derived status
```
