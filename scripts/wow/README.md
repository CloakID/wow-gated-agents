# scripts/wow — the enforcement engine

Implements GATES-SPEC.md. Written during pilot #1 (`frisbii-subscriptions`); this branch
contributes it back.

| File | Role |
|---|---|
| `formats.json` | **The single machine home.** Ids, commit trailers, branch patterns, status vocabulary, evidence types, codebase and dependency front-matter, plan/report/requirements schemas, Jira mapping, runs layout, audit-trigger thresholds. Consumed by *both* `gates.sh` and `status.mjs` |
| `gates.sh` | Entry point. Everything — hooks, playbooks, operators — calls this and only this |
| `gates.py` | The engine `gates.sh` delegates to |
| `status.mjs` | Derived status. No persistent narrative state; reads the same `formats.json` |
| `tests/` | One negative test per gate |
| `permissions-policy.json` | `.claude/settings.local.json` is regenerated from this at P5 |
| `GATES-SPEC.md` | Copied in by `install.sh`; the repo's CLAUDE.md router cites this path |

## Why gates.sh delegates to gates.py

GATES-SPEC names `gates.sh`, and that is still the only thing anything calls. But GATE-8 compares
glob-expanded ownership sets, and every gate reads schemas out of JSON — bash does neither
honestly. The wrapper keeps the specified single entry point; the engine is where the work is.
Raised for review: if the package would rather have a pure-bash implementation, that is a
different set of trade-offs and worth an issue.

## What is deliberately *not* fully mechanical

Two gates report the limits of what a shell can know, rather than pretending:

- **GATE-10** cannot reach the Atlassian MCP from a git hook. It checks that the ORCH produced a
  divergence record for the gate and that every row carries a classification. Producing the diff
  is an MCP action; verifying it is complete is mechanical.
- **GATE-6's dependency half** runs a probe command read from `docs/deps/<name>.md`. That is the
  same trust level as a git hook or a Makefile target. `--no-probe` degrades to the
  `max_age_days` fallback rather than silently passing.

Everything else either fails for a stated reason or passes.

## No inline formats

If a literal regex, status word or schema appears in `gates.py` or `status.mjs`, that is a defect
— it belongs in `formats.json`, or the two consumers can drift apart on what a format means.

## Running

```sh
gates.sh list                          # every gate, where it runs, what it blocks
gates.sh gate-1 <msgfile>              # commit-msg hook
gates.sh gate-5  --staged              # pre-commit hook
gates.sh gate-11 --staged              # pre-commit hook, inert unless migrated_from_gsd
gates.sh gate-6 --run <id>             # /wow-plan: codebase areas + declared deps
gates.sh gate-8 --run <id>             # G2, before review
gates.sh gate-10 --run <id> --gate G2  # gate open
gates.sh sweep --run <id>              # every gate + P5

bash tests/run-all.sh                  # the negative tests
node status.mjs [--json] [--run <id>]  # derived status
```
