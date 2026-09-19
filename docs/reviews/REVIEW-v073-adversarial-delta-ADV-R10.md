# ADV-R10 — Adversarial delta review of the R9 remediation (fresh context)

Target: the R9 remediation commit (container b73bebc on top of the 87ffe7e mirror). Reviewer: isolated subagent, zero prior context, instructed to attack the fixes for regressions, half-closed holes and dialect drift; every CONFIRMED item reproduced in throwaway fixtures and regression claims counter-checked against the pre-fix engine.

## Verdict as delivered
Not sound to ship as-is: three fixes failed inside their own defect class. **All five required corrections and all named lows were then implemented in round R9b** (see disposition per finding below); the R9b corrections carry their own tests and mutation proofs.

## Findings and disposition

### ADV-R10-01 — HIGH — CONFIRMED — escrow forgery re-runs via `~~~` fences and indented code blocks
`_strip_fences` toggled only on ```. A forged discharge in a `~~~` fence or a 4-space indented code block still read as claim text.
**Fixed (R9b):** `_strip_fenced_blocks` handles both fence spellings (opener token closes only its own kind) and `_blank_indented_code` blanks CommonMark indented code blocks (a block starts at an indented line after a blank, so 2-space CV continuation lines and lazy 4-space continuations stay claims). Tests: both channels rejected; mutations on both helpers caught.

### ADV-R10-02 — HIGH — CONFIRMED — gate-11 index-read defeated by commit-then-amend
Stage exclusion + erasure, commit, `git restore --source=HEAD~1` + `--amend` → erasure in HEAD, zero committed trace of the exclude.
**Fixed (R9b):** `legacy_freeze_exclude` binds only from the COMMITTED config (HEAD) — an exclusion must land as its own reviewable commit first, raising the bypass bar to overt history rewriting; the refusal names this remedy when a staged-but-uncommitted exclude would have matched; the freeze flag stays sticky the fail-safe way (HEAD, index or worktree arms it). Tests updated + new; mutation caught.

### ADV-R10-03 — HIGH — CONFIRMED — the shared section regex REGRESSED the escrow: fenced `# comment` inside the AT section hid a recorded hit
The new `(?=^#|…)` terminator stopped at any `#` line — including a shell comment inside a fence — at BOTH consumers, so the value silently disappeared everywhere (old engine caught it).
**Fixed (R9b):** both consumers locate the section on fence-STRIPPED text (`_strip_fenced_blocks` / `stripFencedBlocks`). Tests both sides; mutations both sides caught.

### ADV-R10-04 — MEDIUM — CONFIRMED — fence state carried across FILE boundaries
One unclosed ``` in RUN-REPORT marked every verify report as fenced — hiding the exact cross-file discharge ADV-R9-04 exists for.
**Fixed (R9b):** claim text built per file (fence state resets at each file boundary). Test + mutation caught.

### ADV-R10-05 — MEDIUM — CONFIRMED — gate-8 preamble exemption keyed on shape, not schema
`constraint: executors must never…` hid a rule under any `word:` costume.
**Fixed (R9b):** exemption is by NAME — `plan_schema.preamble_fields` (spec, story-continuity, run, date, author, status, run-base, tier); an unlisted key carrying normative language fails, and the message names the preamble_fields remedy for genuinely descriptive fields. Test + mutation caught.

### ADV-R10-06 — LOW — CONFIRMED — credential bounding fixed one token of the family
`${TOKENIZER_MODEL:-…}`, `${CREDIT_LIMIT:-…}`, `${PASSENGER_COUNT:-…}` still flagged.
**Fixed (R9b):** every token letter-bounded both sides: `PASS(WORD|WD)?`, `SECRETS?`, `TOKENS?`, `CREDS?(ENTIALS?)?`, each with the trailing guard; probed identical in both regex dialects. Test + mutation caught.

### ADV-R10-07 — LOW — CONFIRMED — ev:commit resolver half-closed in both directions
(a) `~~~`/indented quotes still blocked. **Fixed (R9b):** resolver reads through the same fence/indent claim discipline; test added.
(b) One unclosed ``` before a real dangling sha → false green. **Accepted residual, now documented in the resolver's comment:** structural to toggle-tracking; the falsifier for citation truth is the verifier's re-run (F-43), not this arm.

### ADV-R10-08 — LOW — CONFIRMED — backticked `discharged: … ev:` now refused (behavior change vs pre-R9)
Consistent with mention-vs-claim but undocumented.
**Fixed (R9b):** the unevidenced-closure message now states that a backticked or fenced ev: is a mention (PF-a).

### ADV-R10-09 — LOW — CONFIRMED — `--run <archived-run>` refused with a false "names no directory"
**Fixed (R9b):** an archived run is refused as ARCHIVED, naming `runs/archive/<id>` and F-36's exemption. Test added.

### ADV-R10-10 — LOW — CONFIRMED — CRLF conversion read as "local edits" by the install stamp guard
**Fixed (R9b):** section reading and stamping normalize `\r`. Test + mutation caught.

### ADV-R10-11 — INFO — CONFIRMED — DEV-R9-11 note fired on a fresh `git init -b main` repo (unborn HEAD)
**Fixed (R9b):** the warning also accepts `git symbolic-ref --short HEAD` = main.

### ADV-R10-12 — LOW — PLAUSIBLE — `_cells` port stopped at two of four status.mjs sites
**Fixed (R9b):** `requirements()` and `specs()` row parsing routed through `cellsOf`.

## Clean under attack (verified by the reviewer)
ADV-R9-02 core, -04 core, -06, -08, -10, -12 and the DEV items; dialect parity of all new regexes in both engines; JS `fill` with `{name}` next to `{1,6}`; sed `$i\` insertion; stamp parity between --check and plain install.
