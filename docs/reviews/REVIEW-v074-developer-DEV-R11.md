# DEV-R11 — Developer-persona review of WoW v2 v0.7.4-draft (fresh context)

Target: the v0.7.3 → v0.7.4-draft upgrade, walked on a fixture pilot repo (a signed run with BLOCKED and DEFERRED rows, GAPS rows citing files, a debug record, prettier-touched CLAUDE.md — green under v0.7.3), then P5 followed literally. Reviewer: isolated subagent playing a senior developer with zero prior exposure; experience audit only. Prettier 3.8.1 was on the box, so the formatter case was run for real.

## Verdict as delivered
Not as-is: two day-one blockers and seven doc/tool contradictions. **Findings 01–20 and the nits 22/24/26 were remediated in round R11b; 21, 23, 25 are folded into the v0.7.5 reduction round (OBL-PKG-25/26).**

## Findings and disposition

- **DEV-R11-01 · blocker — a real prettier pass still tripped the section guard** (blank lines around the markers); the upgrade exited 1 half-applied. **Fixed:** the stamp hashes the normalized section (emphasis markers, trailing whitespace and blank lines are formatting), the section is written prettier-conformant (verified: prettier is a no-op on it), `--check` compares normalized.
- **DEV-R11-02 · blocker — every fresh clone and CI checkout failed every sweep** (hooks are per-clone and untracked) with a remedy that did not apply. **Fixed:** `scripts/wow/gates.sh hooks --install` self-heals in the repo (hook body's one home: `install.hook_template`, rendered identically by install.sh, byte-checked by `--check`); `enforcement_layer_check: "advisory"` for checkouts that never commit; the refusal names both.
- **DEV-R11-03 · major — "chains, never destroys" destroyed on the second clobber.** **Fixed:** install.sh and `hooks --install` rotate the older chained copy to `.pre-wow.<n>` and chain the new foreign hook; the message says the rotated copy does not run.
- **DEV-R11-04 · major — P4 step 1 refused before step 2 could write the walk.** **Fixed:** walk check at `gate-2 --close` (step 4); P4 says so.
- **DEV-R11-05 · major — the decision surface counted itself as open and had no lane.** **Fixed:** `runs/debug/classification-request.md`, excluded from the open set, commits under `[D:classification-request]`.
- **DEV-R11-06 · major — bare `[T:<run-id>]` refused after archival with a harmful remedy.** **Fixed:** resolves the archive dir; the remedy no longer says "create the dir".
- **DEV-R11-07 · major — GATE-10 said "not a divergence" and "unclassified" about the same row.** **Fixed:** an expected-consistent row with an empty classification is not a divergence; a non-vocabulary word in the column stays a defect.
- **DEV-R11-08 · major — GATE-9's numbers were mislabeled and FORMATS stated the old rule.** **Fixed:** "(N before this change, N after)", names the `AM-<nn>` to add; FORMATS §1 carries the per-modification rule and an AM block example.
- **DEV-R11-09 · major — cited stale stubs were listed for deletion, then the deletion refused.** **Fixed:** gate-7 and status.mjs retain cited stubs and name the citing registry line.
- **DEV-R11-10 · major — named exports rendered an empty section silently.** **Fixed:** named exports accepted; anything else is a reported error; the contract is in GATES-SPEC §Config keys.
- **DEV-R11-11 · major — P4 keyed on a `kind:` header no doc defined.** **Fixed:** `jira_mapping.kind_header` in formats, P1 records it, lists aligned (`remediation` included).
- **DEV-R11-12 · major — the walk artifact had no format; matching was by substring.** **Fixed:** FORMATS §1/§4 walk row, first cell = item id, whole-matched; `walk: N/N` on PASS.
- **DEV-R11-13 · minor — INSTALL's Upgrading section prepared you for none of what went red.** **Fixed:** a "what goes red on an existing repo, and the one-line remedy" table.
- **DEV-R11-14 · minor — GATE-8's remedy pointed at a file the next upgrade overwrites.** **Fixed:** full path; "file upstream".
- **DEV-R11-15 · minor — `ids_expanded.requirement` ignored `requirement_id`.** **Fixed:** documented as the one override.
- **DEV-R11-16 · minor — the shell guard could not fire on bash 3.2.** **Fixed:** checks 3.2, not 3.
- **DEV-R11-17 · minor — empty manifest arrays under `set -u` on bash < 4.4.** **Fixed:** `${arr[@]+"${arr[@]}"}`.
- **DEV-R11-18 · minor — F-80 reported twice in two vocabularies.** **Fixed by ADV-R11-01:** one resolver, one verdict; the message defines "archive rewrite".
- **DEV-R11-19 · minor — `run_staged_scope_extra` did not expand `{run_id}`.** **Fixed.**
- **DEV-R11-20 · minor — status contradicted itself on FOREIGN.** **Fixed:** `missing: hook:pre-commit (FOREIGN)`.
- DEV-R11-21 (finding-id salt) → OBL-PKG-26; DEV-R11-22 (stub "Load line") **fixed**; DEV-R11-23 ("no runs yet" after archiving) **fixed** ("no ACTIVE run"); DEV-R11-24 (usage lists every command) **fixed**; DEV-R11-25 (3+-read sentences, undefined jargon) → OBL-PKG-25; DEV-R11-26 (`$removed` key paths) **fixed**.

## Three best things (calibration)
- `sweep --p5 --run` after archival finally does what the phase says, and every refusal around it states the rule and the alternative.
- GATE-1's staged-scope refusal names the file, the rule, the correct trailer form and the config key in one line.
- `install.sh --check` shows the actual diff of the router section before writing; the F-87 registry message names the row, the likely cause and the exact escape.
