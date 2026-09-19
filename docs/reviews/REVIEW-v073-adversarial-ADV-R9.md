# ADV-R9 — Adversarial review of WoW v2 v0.7.3-draft (fresh context)

Target: device commit 87ffe7e (tree 8f9c73d…, byte-identical container mirror), diff 0e371bf..HEAD.
Reviewer: isolated subagent, zero prior context, instructed to attack. Environment check: full suite green, parity PASS, self-sweep green. All repros in scratch fixtures; engine repo untouched.

## Findings (11 CONFIRMED, 1 PLAUSIBLE)

### ADV-R9-01 — high — CONFIRMED — escrow discharge is forgeable from a fenced "example" block
`_cv_discharged_in_run` (gates.py:1764) regex-searches the raw per-run aggregate for `CV-<id>: … discharged: … ev:…` with no fence or backtick masking; "evidence" is only the generic `ev:[a-z]+{` opener. A run report recording a real open CV in a table row plus a fenced "example of the record format" containing a fabricated `ev:jira{WOW-1}` discharges the CV — no GAPS.md row demanded; gate-3 passes too (fences skipped there). Removing the fence → gate-7 rc=1. Discharge matching reads the same unmasked text where "seeing more" is fail-unsafe.
Fix: strip fenced blocks and inline code before discharge matching (keep raw text for CV discovery only).

### ADV-R9-02 — high — CONFIRMED — F-75 status counting undercounts; flips AT-3 to false green
status.mjs:231 `line.split('|').slice(1, -1)` (a) drops the last cell of a row without a trailing pipe (legal GFM), and (b) ignores escaped `\|`, which Python `_cells` (gates.py:607, F-18) honors — direct py/js dialect drift in the one place F-75 was meant to align with gate-3's convention.
Repro: two BLOCKED rows, second without trailing pipe → `statuses.BLOCKED: 1`, `AT-3 value 1, hit: False` (a real HIT reported green). A `\|` in a cell misaligns the Status column → COMPLETED counted 0.
Fix: port `_cells` semantics — split on `(?<!\\)\|`; don't slice the final field when the line lacks a trailing pipe.

### ADV-R9-03 — high — CONFIRMED — F-68 resolver scans fenced code: pasting the gate's own refusal blocks the commit
`_dangling_commit_citations` (gates.py:406) masks inline spans but has no ``` fence tracking (unlike gate-3's main loop below it). The F-43 paste-output rule tells operators to quote gate output verbatim; the F-68 refusal itself contains literal `ev:commit{<sha>}`. Quoting it (or the offending table row) in a fence in any runs/ file makes gate-5 pre-commit and gate-3 blocking-fail forever. Same class the authors hit with runs/.gate-log — excluded the log, not fenced quotes. Bonus fragility: a fence with no backticks/blank lines/pipes is accidentally masked by the inline-span regex, so behavior flips on quote content; the F-72 change (gates.py:597) newly unmasks fences containing table rows, enlarging the false-red surface.
Repro: fenced `| …T99 | COMPLETED | ev:commit{beef0421} |` → gate-3 rc=1, gate-5 --staged rc=1; same quote without pipes/blank line → rc=0.
Fix: track fences in `_dangling_commit_citations` exactly as gate-3's line loop does.

### ADV-R9-04 — medium — CONFIRMED — F-69/F-51 cross-file discharge is order-dependent (false red)
`re.search` in `_cv_discharged_in_run` returns the FIRST `CV-<id>:` block in the aggregate (RUN-REPORT first, then sorted verify reports). Allocation in RUN-REPORT + discharge in `reports/U1-verify.md` → registry row demanded despite the code comment citing F-51. Shipped test covers only the opposite order. Same escrow message also emitted twice (once per finditer occurrence).
Fix: iterate all `CV-<id>:` blocks; discharged if ANY carries an evidenced `discharged:`; dedupe messages.

### ADV-R9-05 — medium — CONFIRMED — F-70 gate-8 fix skips ALL plan preamble, not just header fields (false-green regression)
gates.py:2047 skips every line before the first `^##` from the F-28 normative scan. A normative prose paragraph in the preamble ("Executors must never write outside their owns list…") now reaches no executor and gate-8 says nothing — the exact F-28 defect class, reintroduced for the preamble. Under 0e371bf the same plan fails rc=1. Shipped test covers only a `field: value` header line.
Fix: skip only schema-shaped `^[a-z-]+:` header lines (or lines up to the first blank), not arbitrary prose.

### ADV-R9-06 — medium — CONFIRMED — gate-7 with an explicit `--run` passes vacuously; verify-report CVs escape escrow when RUN-REPORT is absent
The escrow walk enters only run dirs containing RUN-REPORT.md. A run that died after verify (CVs in `reports/U1-verify.md`, no RUN-REPORT — F-69's own scenario) or a typo'd `--run` id walks 0 runs and exits 0 even at `--p5`, with only the advisory VACUOUS note. Contradicts the engine's own rule ("a gate invoked with no scope is not a pass") and makes the F-70 vacuity mechanism toothless precisely at publish.
Fix: when `run_id` was explicitly passed (or at `--p5`) and `runs_walked == 0` while the run dir exists, fail; consider walking dirs that have verify reports even without RUN-REPORT.

### ADV-R9-07 — medium — CONFIRMED — audit-trigger section regex drift: escrow reads `##` only, status.mjs reads `#+`
gate-7 locates the AT section via `handoff_section_heading` (`^##\s*{name}`, gates.py:1695); status.mjs:348 uses an inlined `^#+\s*…` (itself violating the nothing-inlined contract). `### audit triggers` → status.mjs derives AT-2=9 hit:true while gate-7's escrow third class is silent — one recorded value, two consumers, opposite answers, in the very round (F-74) that re-aligned the ROW pattern.
Fix: one `#+`-level section regex in formats.json, used by both.

### ADV-R9-08 — medium — CONFIRMED — F-72 boundary un-masks legitimate wrapped code spans (mention becomes claim)
The F-72 bail-out (gates.py:597) triggers on any span interior containing `\n\s*\|` — but a wrapped shell pipeline in backticks puts `|` at line start naturally. The span is then scanned, violating "backticked citations are mentions and are not scanned at all".
Repro: `` `ev:cmd{x\n| y}` `` in prose → gate-3 rc=1 "malformed citation 'ev:cmd{x'".
Fix: require the crossing line to look like a table row (≥2 unescaped pipes), not merely begin with `|`.

### ADV-R9-09 — medium — CONFIRMED — gate-11 freeze bypassed by an UNCOMMITTED `legacy_freeze_exclude`
gates.py:496 reads `legacy_freeze_exclude` from the worktree wow.config.json at pre-commit. Edit config (don't stage) → `git rm -r .planning/` → commit → revert config: the erasure gate-11's own comment names lands with zero trace. Class pre-exists (`migrated_from_gsd` flip), but F-60 adds a far more deniable knob with no guard.
Repro: deletion blocked rc=1; worktree-only `"legacy_freeze_exclude": [".planning/*"]` → same staged deletion rc=0.
Fix: read config from HEAD/index for gate-11, or refuse when wow.config.json is dirty, or echo the active exclude list into the PASS output.

### ADV-R9-10 — low — CONFIRMED — F-76 G4 resolver refuses legacy layouts; promised hint missing on that path
With `SPEC-x-v2.md` present as ordinary `status: draft` (only `blocked-draft` is exempt), gate-9 --gate G4 resolves v2 and refuses even when a valid `signed: G4` record exists in v1 — the layout the pre-0.7.3 resolver produced for every closed run. The refusal on this path has NO F-76 `--spec` hint (hint fires only on the token-mismatch branch, gates.py:2299; shipped ADV-5 test happens to route through that branch).
Fix: attach the hint to the no-record refusal too; consider skipping unsigned drafts, not only blocked-drafts.

### ADV-R9-11 — low — CONFIRMED — credential idiom fires on `${PWD:-…}`
`PW` substring-matches inside `PWD` (formats.json:832). `` `echo "ran in ${PWD:-unknown}" && pytest a` `` → gate-13 rc=1 claiming credential disclosure. `lint-ok` is an escape but the message is wrong.
Fix: `PW(?![A-Za-z])`-style boundaries.

### ADV-R9-12 — low — PLAUSIBLE — F-74 diagnostic miscounts and understates the parse rule
`atRowsSeen` counts header rows and indented rows; the column-0-anchored `^\|` pattern is not what the message describes. An indented but otherwise perfect table yields "N seen, 0 parsed" with a misleading explanation.
Fix: allow `^\s{0,3}\|` (CommonMark-legal) in `report_row`, or state the anchor in the message.

## Checked and NOT found defective
Dialect portability of all v0.7.3 regexes (compiled and behavior-probed in both engines, identical); `{run_core}`/`{task_tail}` expansion parity (byte-identical); `$`-key handling in every consumer (no crash, no misread); `<sha>^{commit}` on short/blob/ambiguous shas fails closed; `check-id --base` refusals; F-65 archive exclusion honored by both blocking arms; CRLF/empty-repo/no-runs inputs don't crash.

## Verdict
Not safe to publish as-is. The release's headline mechanisms each carry a verified hole in their own terms: the escrow can be discharged by a fenced forgery (01) and skipped outright at publish (06), the new AT-3 deriver reports a triggered audit as green on legal markdown (02), and the ev:commit arm mechanically blocks the workflow another rule mandates (03), plus two further false-green regressions (05, 09). None of the fixes is architectural. 01/02/03/05/06 should land, with negative tests in the repo's own style, before v0.7.3 ships.
