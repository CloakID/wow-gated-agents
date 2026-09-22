# ADV-R11 — Adversarial review of WoW v2 v0.7.4-draft (fresh context)

Target: the v0.7.4-draft defect-fix round (23 pilot findings, container commit on top of the published v0.7.3 tree). Reviewer: isolated subagent, zero prior context, instructed to attack every claimed fix in its own terms; every CONFIRMED item reproduced in throwaway fixtures, regressions counter-checked against the v0.7.3 engine.

## Verdict as delivered
Unsound to ship as-is: three fixes failed inside their own defect class. **All twelve findings were remediated in round R11b** (disposition per finding below), each with its own test and mutation proof.

## Findings and disposition

**ADV-R11-01 — HIGH — CONFIRMED — P5 step 6 still failed after step 3: gate-5 rejected the citation gate-7 accepted.** `_target_exists` had no archive rewrite while gate-7's F-80 arm did; one sweep, two verdicts about one GAPS row, and the pre-commit hook then refused every later commit touching GAPS.md. **Fixed:** one shared `_resolve_target`/`_archive_rewrites` used by gate-5's preflight and gate-7's citation check.

**ADV-R11-02 — HIGH — CONFIRMED — F-72 refused every ORCH merge commit.** A merge's staged set is the merged product; P3's `merge --no-ff U<n>` and P5 step 0 all commit under the bare form. **Fixed:** `MERGE_HEAD` present ⇒ no scope check; LANES/P3 name the merge trailer.

**ADV-R11-03 — HIGH — CONFIRMED — F-87b opened an obligation escape v0.7.3 did not have.** DEFERRED discovery on fence-stripped text made a fenced status table invisible to both gate-3 and the escrow. **Fixed:** discovery back on raw text with an id-SHAPE filter (a `32:` grep prefix is not an item; a fenced `REQ-…` row is).

**ADV-R11-04 — MEDIUM — CONFIRMED — P4 step 1 ran the G4 check that step 2's artifact satisfies** (F-77's ordering class one phase earlier). **Fixed:** the walk check moved to `gate-2 --close` (P4 step 4); gate-10 at G4 is the open check again.

**ADV-R11-05 — MEDIUM — CONFIRMED — gate-3's main loop still masked with fences intact.** **Fixed:** fences stripped before the doc-wide mask; original lines still drive fence tracking and cells.

**ADV-R11-06 — MEDIUM — CONFIRMED — the F-79 continuation swallowed unindented prose after a field.** **Fixed:** continuation is indented-only; an unindented line ends the field.

**ADV-R11-07 — MEDIUM — CONFIRMED — the gate-11 read-failure refusal blocked the repair commit and fired when the freeze was not armed.** **Fixed:** the index copy must always be readable; the HEAD copy only while the freeze is armed.

**ADV-R11-08 — MEDIUM — CONFIRMED — F-80 called the modeled `runs/debug/` → `resolved/` move a deletion.** **Fixed:** the shared resolver knows that rewrite too.

**ADV-R11-09 — MEDIUM — CONFIRMED — walk ids matched by substring (`U1` in `U10`).** **Fixed:** whole-match on the walk row's first cell.

**ADV-R11-10 — MEDIUM — CONFIRMED — `status --json` hooks changed type from boolean to string (all truthy).** **Fixed:** `hooks` stays boolean; `hookState` carries ABSENT/FOREIGN/installed.

**ADV-R11-11 — LOW — CONFIRMED — the decision surface counted as an open debug record.** **Fixed:** excluded by name; renamed to `classification-request.md` so `[D:classification-request]` resolves.

**ADV-R11-12 — LOW — CONFIRMED — an extension that never settles hung status; stdout corrupted `--json`.** **Fixed:** 5s timeout via `Promise.race`; stdout captured during load.

## Attacked and held
The temp-file pattern for bash 3.2 (PYTMP reuse, trap, error paths); `_cfg_at` on unborn HEAD, staged-new config, symlinked paths, corrupt index; the hook-layer check across worktrees, relative `core.hooksPath`, chained `.pre-wow`, the package repo, fixtures; the section normalizer's substance/formatting boundary; GATE-9 per-modification across amend+edit, amend-only, signing-commit-is-latest, staged-only dirt; fnmatch `*` crossing `/`; `formats-expand` idempotence and both engines' expansion equality; escrow per-file claim text, cross-file dedupe, order independence; the archived-run grading itself.
