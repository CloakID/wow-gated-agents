# ADV-R12 — adversarial review of v0.7.5-draft (fresh context)

> **Disposition (R12b, 2026-10-06):** every CONFIRMED and PLAUSIBLE finding below was remediated in-round, each with its own test and mutation proof (M156–M187): 01 (definitions are heading/list heads in `*-verify.md`), 02 (gated-doc globs for the named run; archived adds nothing), 03 (closure vocabulary only), 04 (`^(?:none\b|\[\])`), 05 (heading slug OR content token; AT-4 counts line form only; headings listed), 06 (no backtick in `report_row`), 07 (producer available at `dispatched_at_wave`), 08 (id-keyed rows are status-shaped), 09 (archive searched; lower-wave reports/evidence delivered; one message per task+path), 10 (fenced `capture:` is a mention; raw-byte compare), 11 (decoration/table/numbered-list forms; message prints the shape), 12 (month/day range + future-date fallback), 13 (`branch: Reset to`, `update-ref`), 14 (formats comments corrected), 15 (closer length ≥ opener), 16 (declared empty set is graded, not vacuous), 17 (`lint-ok` marker dropped; literal `\|` routes through a file — P2), 18 (GATE-7 refuses an AT-2 row without `ev:cmd`; `audit_triggers.runnable_citation_required`). The reviewer's text follows verbatim.

Method: throwaway fixture repos under `/tmp/adv-r12/` (`fx1` = engine copy + `git init`, `inst` = `install.sh` target, `fx1-wt` = linked worktree), v0.7.4 engine swapped in from `git show 492dfc7:` for A/B runs. Every CONFIRMED item below was reproduced with the command shown; the full suite (`run-all.sh`, 540 assertions) passes on HEAD and none of the items below is covered by it.

## Verdict as delivered

**Not sound to ship as-is.** Three of the round's own fixes fail inside their defect class on ordinary inputs the process docs prescribe: (1) the new VF double-definition arm (F-105) refuses every run whose RUN-REPORT `## defects`/walk rows tabulate a verifier finding beside the verify report that defined it — every run with a `FAIL` grade goes red at P5; (2) `gate-3 --run` (now passed by every `sweep --run`) scans `PLAN.md`, `HANDOFF.md`, `orch/*.md` and `evidence/**/*.md`, so a signed plan whose Done-means cell says `PASS` or `deployed` is refused as an unevidenced status — PLAN.md was never a GATE-3 subject, and gate-8 is its gate; (3) the F-94-item-4 "closure columns" exemption turns any table headed `Outcome` into a column GATE-3 does not read at all, so `| T01 | COMPLETED |` with no citation now passes where v0.7.4 refused it — a one-word fail-open escape. Alongside: the documented `requirements: []` sentinel can never match; the F-112 anchor preflight demands a *heading* where FORMATS §3 promises *content* anchors and feeds its false refusals into AT-4; F-87's decoration tolerance lets backticked (mention) AT rows parse in the escrow — the exact phantom-hit class formats.json's own comment forbids; and `dispatched_at_wave` reopens F-58 for consumers of the re-dispatched unit. The remaining fixes held under attack (list at the end). Fix 1–3 and 4–8 before tagging; the LOWs can ride.

## Findings

**ADV-R12-01 — HIGH — CONFIRMED — GATE-7's VF double-definition arm (F-105) fires on the RUN-REPORT row that *reports* the finding, so every run with a FAIL grade is refused at P5.**
`gates.py:2543-2554`: `defn` matches a VF id at the head of a heading, list item or table-row first cell in *every* `named_texts` entry — and `named_texts[0]` is `RUN-REPORT.md`. P3 §"RUN-REPORT structure" requires `defects`/`failed` rows per item, and walk/report rows carry the item id whole in the first cell.
Repro (`fx1`): `reports/U1-verify.md` holds `- VF-U1-01 — …` and `| VF-U1-01 | FAILED | ev:… |`; `RUN-REPORT.md` holds `| VF-U1-01 | FAILED | ev:file{…U1-verify.md} |`.
```
$ bash scripts/wow/gates.sh gate-7 --run 261001-demo-r1
GATE-7: VF-U1-01 is DEFINED in 2 report files (runs/261001-demo-r1/RUN-REPORT.md, runs/261001-demo-r1/reports/U1-verify.md) — one id, two findings; …
rc=1
```
Same shape for an amendment delta verifier (`reports/AM-01-verify.md`) tabulating the closure of `VF-U3-07` — the exact table F-94 item 4 just made legal. Why it matters: a mandatory P5 gate that cannot pass on any run that found something. Fix: scope `defn` to `*-verify.md` files only, and treat a row whose status/closure cell is set (CLOSED/repaired/FAILED…) as a *reference*, not a definition — or define "definition" as the id's first appearance under a heading in the file that allocates its segment (`U<n>-verify.md` for `VF-U<n>-`, `AM-<nn>-verify.md` for `VF-AM<nn>-`).

**ADV-R12-02 — HIGH — CONFIRMED — `gate-3 --run <id>` scans PLAN.md, HANDOFF.md, orch/*.md and evidence/**/*.md; the sweep now passes `--run`, so a signed plan's Done-means `PASS`/`deployed` cell is refused at every P3/P4/P5 sweep.**
`gates.py:973-977` adds every `.md` under the run dir; `sweep()` at `gates.py:3983` now adds `--run` for gate-3. The plan's task table has no Status header, so every cell is checked (`status_vocab.$status_columns_comment` itself notes "'OK' and 'PASS' in a Done-means … column read as forbidden synonyms").
```
$ printf '…| 261001-demo-r1.T01 | run tests | `pytest tests/test_a.py` | PASS | fails on bad input |\n| 261001-demo-r1.T02 | ship | `make deploy` | deployed | fails when down |…' > runs/261001-demo-r1/PLAN.md
$ bash scripts/wow/gates.sh gate-3 --run 261001-demo-r1
GATE-3: runs/261001-demo-r1/PLAN.md:16 'PASS' is not in the status vocabulary (…) — a verdict belongs under a Grade/Verdict header … (F-20)
GATE-3: runs/261001-demo-r1/PLAN.md:17 done-word 'deployed' used as a status without an ev: citation
```
Also refused: a Done-means `ok`, a `## Load` table in the plan (`| VF-U2-07 | fixed |`), and `evidence/U1/pasted.md` containing `Status: COMPLETED` (a capture). At `sweep --p5 --run <id>` after archiving, the archived plan is graded under today's vocabulary too (F-65's exemption lost). The F-94 test fixture has no PLAN.md, which is why 540 assertions did not see it. Fix: `run_docs` = the run's `RUN-REPORT.md`, `reports/*.md`, `FINDINGS.md`, `findings/*.md`, `walk-G4.md` (the gated-doc globs, applied to the named run even when archived) — not `os.walk` of everything.

**ADV-R12-03 — HIGH — CONFIRMED — a column headed `Outcome` (closure_columns) is excluded from *every* status check, not just the CLOSED synonym; `COMPLETED` with no evidence passes under it.**
`gates.py:1141-1143`: `checked` drops the closure column entirely; F-94 item 4 asked only to "admit CLOSED in a column headed Closure/Outcome/Fix outcome". "Outcome" is the most natural header for a unit report's task table.
```
$ cat runs/261001-demo-r1/reports/U1.md
| Task | Outcome | notes |
|---|---|---|
| 261001-demo-r1.T01 | Done | all good |
| 261001-demo-r1.T02 | COMPLETED | no evidence here |
| 261001-demo-r1.T03 | Success | |
$ gate-3 --paths runs/261001-demo-r1/reports/U1.md      # v0.7.5
GATE-3 PASS
# v0.7.4 engine on the same file:
GATE-3: …:7 done-word 'Done' used as a status without an ev: citation
GATE-3: …:8 status COMPLETED without an ev: citation
GATE-3: …:9 'Success' is not in the status vocabulary (…)
```
(The F-14-addendum "declared status section" refusal still fires inside RUN-REPORT's declared sections, so the escape is every other table: unit reports, verify reports, specs, GAPS.) Fix: keep the closure column in `checked` and exempt only the closure vocabulary (`CLOSED`, `repaired`, …) in that column — never the evidence-required statuses or done-words; drop `Outcome` from the list or make the list a vocabulary, not a column.

**ADV-R12-04 — MEDIUM — CONFIRMED — `requirements: []` is documented as the empty-set sentinel in four places and never matches: `\[\]\b` needs a word boundary after `]`.**
`formats.json:523` `"empty_declaration": "^(?:none|\\[\\])\\b"`; documented as "(or `[]`)" in formats.json, GATES-SPEC GATE-2 row, CHANGELOG, P1.
```
$ python3 -c "import re;p=r'^(?:none|\[\])\b';print([bool(re.match(p,v,re.I)) for v in ['none','[]','[] — audit']])"
[True, False, False]
$ bash scripts/wow/gates.sh gate-2 --run 261001-demo-r1       # spec header: requirements: [] — an audit delivers findings
GATE-2: docs/spec/SPEC-demo-v1.md declares `requirements: [] — an audit delivers findings` — no id matches ^REQ-[0-9]{3}$ and the value is not the empty-set sentinel …
rc=1
```
Fix: `^(?:none\b|\[\])`.

**ADV-R12-05 — MEDIUM — CONFIRMED — the F-112 anchored preflight requires the anchor to be a *heading*; FORMATS §3 promises *content* anchors, so row-id anchors (`#AC-2`, `#OBL-X-01`, `#GATE-3`) are refused at pre-commit — and each false refusal in an unmodified doc counts toward AT-4.**
`gates.py:597-604` (`heads` = `^#{1,6}` lines only; "lenient" only when the target has no headings at all). The pilots' own citations use this shape (`ev:file{scripts/wow/GATES-SPEC.md#GATE-3}` in prodsim/F-113, where GATE-3 is a table row).
```
$ cat docs/GAPS.md   # rows cite ev:file{docs/spec/SPEC-demo-v1.md#AC-2} and ev:file{docs/GAPS.md#OBL-X-01}
$ bash scripts/wow/gates.sh gate-5 --paths docs/GAPS.md
GATE-5: docs/GAPS.md:7 cites ev:file{docs/spec/SPEC-demo-v1.md#AC-2} — the target exists (…) but has no heading anchored 'ac-2' (prodsim/F-112)
GATE-5: docs/GAPS.md:8 cites ev:file{docs/GAPS.md#OBL-X-01} — the target exists (…) but has no heading anchored 'obl-x-01' (prodsim/F-112)
$ node scripts/wow/status.mjs | grep AT-4
  AT-4 stale_file_line_refs_unmodified_docs: 3 (>=3)  HIT          # 2 anchors + 1 GONE; metric is "stale file:line refs"
```
Why it matters: blocks the commit of any touched durable doc carrying a row-id anchor on upgrade, and manufactures an AT-4 hit (escrow then demands a GAPS row). Fix: accept an anchor that matches a heading slug **or** appears as a bare token/first table cell in the target (`(?<![\w-])<anchor>(?![\w-])`), and count only `DRIFTED` line citations in the AT-4 figure (`gates.py:636`).

**ADV-R12-06 — MEDIUM — CONFIRMED — F-87's decoration tolerance admits backticks before the AT id and the integer, so a mention row parses as a recorded trigger value: phantom hits in the escrow, and the two consumers disagree.**
`formats.json:720` `report_row` now starts `\|[\s*\`_]*(AT-…)`; `$report_row_comment` three lines down says "threshold-documentation rows must NOT parse … a false parse in the escrow is a phantom trigger hit (ADV-6)". v0.7.4's `\|\s*(AT-` blocked the backtick.
```
## audit triggers
| trigger | threshold |
|---|---|
| `AT-5` | `1` fires the audit |
| `AT-3` | `2` blockers |

| trigger | value |
|---|---|
| AT-5 | 0 |
$ gate-7 --run 261001-demo-r1
GATE-7: …RUN-REPORT.md records AT-5 = 1 (>= over threshold 1) — a trigger hit is an owed audit …
GATE-7: …RUN-REPORT.md records AT-3 = 2 (> over threshold 1) …
$ node status.mjs --run 261001-demo-r1 | grep AT-5
  AT-5 ac_passed_for_wrong_reason: 0 (>=1)        # status.mjs keeps the LAST row, gate-7 fires on every row
```
Fix: tolerate `*` and `_` only (`[\s*_]*`), keep the backtick out (PF-a: backticked = mention); make both consumers take the same row (first or last) or refuse two rows for one id.

**ADV-R12-07 — MEDIUM — CONFIRMED — `dispatched_at_wave` reopens F-58 on the output side: a unit re-dispatched at wave 2 keeps `wave: 1` for its outputs, so a wave-2 consumer of its new output passes the strictly-lower-wave rule.**
`gates.py:2937-2943` (`_consumes_at`) and `:2971` compare the *producer's* `_wave(v)` (unchanged) against the consumer; the producer's new task runs at the re-dispatch boundary.
```
U2: wave: 1, dispatched_at_wave: 2, owns src/b.py, T02 "write src/b.py (added by AM-01 at wave 2)"
U3: wave: 2, inputs: src/b.py
$ gate-8 --run 261001-demo-r1
GATE-8 PASS
```
That is the same-wave-producer case F-58 was written for. Fix: a producer's availability wave for the F-58 rule is `max(wave, dispatched_at_wave)` unless the input is listed under an explicit `outputs_at_wave:`/per-task marker; at minimum refuse when a consumer's wave ≤ the producer's `dispatched_at_wave`.

**ADV-R12-08 — MEDIUM — CONFIRMED — the F-102 narrowing admits every Title-case forbidden synonym on a row keyed by an AC, unit or finding id (not only `live`).**
`gates.py:1153-1155,1219-1220`: in a table with no status header the synonym rule now binds only to an uppercase token or a row carrying a *task/requirement* id; AC-, U-, VF-, PARK- keyed rows are not "status-shaped".
```
| item | verdict-ish |
|---|---|
| AC-3 | Passed |
| U2 | Shipped |
$ gate-3 --paths … (v0.7.5)  → only the task-id row is refused; v0.7.4 refused all three.
```
F-102's non-vacuity ("a task row with status LIVE is still refused") passes while `| AC-3 | Passed |` — the F-20 claim the rule exists for — now slips. Fix: extend "status-shaped" to rows whose first cell matches any `ids.*` / `reference_id_patterns` shape, or keep the Title-case check and exempt only the contracted reading words via a plan-declared vocabulary.

**ADV-R12-09 — LOW — CONFIRMED — F-97's reads lint: (a) an id from the *prior* run (which F-104, same round, tells P2 to load) is refused unless re-mentioned outside the row; (b) a lower-wave unit's `reports/`/`evidence/` files are not deliverable to a later wave unless that unit lists them in `owns:`; (c) each path is reported once per cell it appears in.**
`gates.py:3036-3056`. Repro (`fx1`): `T04 | discharge CV-260920-prior-r1-U2-03 (see runs/archive/260920-prior-r1/reports/U2-verify.md)` → "names CV-260920-prior-r1-U2-03 and nothing in the plan or the run tree allocates it"; `U2 (wave 2) T07 … runs/261001-demo-r1/evidence/U1/t01.log` → "exists nowhere the wave order can deliver" twice (Action + Verify). Workable (`lint-ok:`, or own the file in U1), but the lint's search text should include `runs/archive/**` reports for `cannot_validate`/`park` ids, the unit-own `reports|evidence/U<n>` exemption should apply to every lower-wave unit, and messages should be de-duplicated per (task, path).

**ADV-R12-10 — LOW — CONFIRMED — the `capture:` binder (F-96) reads raw lines, so a `capture: <path>` shown inside a fence (a template, a pasted NOTE) is graded as a claim; and the compare is line-normalised, not byte-for-byte (CRLF capture == LF paste).**
`gates.py:1026-1066` (no fence tracking; `read()` opens with universal newlines).
```
```text
capture: <path-to-capture>
```
$ gate-3 --paths runs/…/reports/U1.md
GATE-3: …:27 `capture: <path-to-capture>` names no file …
```
Fix: skip `capture:` lines inside fences/inline code (use `_strip_fenced_blocks` positions) and compare bytes (`open(...,'rb')`).

**ADV-R12-11 — LOW — CONFIRMED — `ids.amendment_record` admits no cell decoration and no table form, so `**AM-02** — 2026-09-22 — PO` or `| AM-02 | 2026-09-22 | PO |` is invisible and GATE-9 reports "count did not grow" on a recorded amendment.**
`formats.json:34`. Measured: `**AM-02** — 2026-09-22 — PO` → False; `1. AM-02 — …` → False; `AM-02 — 2026-09-22T10:00 — PO` → False. The F-105 VF definition regex in the same round tolerates `\**`; this one does not, and the refusal message does not name the required line shape. Fix: `(?:[-*]\s+|\d+\.\s+|#{1,6}\s+|\|\s*)?[*_\`]*(AM-[0-9]{2})[*_\`]*\s+[—–-]`, and print the shape in the message.

**ADV-R12-12 — LOW — CONFIRMED — stub age from an invalid directory date is a *negative* age (never stale) instead of the documented mtime fallback, in both engines.**
`gates.py:2110-2125` (`time.mktime` normalises month 99), `status.mjs:361` (`new Date(2099, 98, 99)` likewise).
```
999999 age days: -29462.1     261301 age days: -86.1     js -86
```
Fix: validate month/day ranges before computing; fall back to mtime otherwise.

**ADV-R12-13 — LOW — CONFIRMED — `gates.sh history` misses `git branch -f` / `update-ref` rewrites (reflog subject `branch: Reset to …`).**
`gates.py:4082`, `formats.json branch_patterns.history_rewrite_entry`. Repro: `git branch -f wow/<run>/U2 master` → reflog `branch: Reset to master` → `HISTORY PASS`. Fix: add `|branch: Reset to|update-ref` to the pattern.

**ADV-R12-14 — LOW — CONFIRMED — formats.json claims "Both engines read this key" for `amendment_record` and `cannot_validate_short_token`; status.mjs reads neither.**
`formats.json:35,38`; `grep -n "amendment_record\|cannot_validate_short" status.mjs` → nothing. The F-55 rule ("an inert-and-wrong declaration is worse than an absent one") applies to the comment. Fix: drop the claim or wire the keys.

**ADV-R12-15 — LOW — CONFIRMED — GATE-3's fence tracker closes a 4-backtick fence on a 3-backtick line (CommonMark: closer ≥ opener length), so a raw citation inside a ````-fenced example that shows a ``` fence is graded.**
`gates.py:1069-1071` (compares only the fence character). Repro case `r` in `/tmp/adv-r12/fx1/mk113.py`: `rc 1 malformed citation` where CommonMark says the text is fenced. Fix: track fence length too.

**ADV-R12-16 — LOW — CONFIRMED — `gate-2` labels an explicitly declared empty set "VACUOUS", and the sweep summary counts it as "green over an empty set".**
`gates.py:1479-1480` emits `_subject_note("GATE-2", 0)` after accepting `requirements: none`. An audit run with a declared empty set is graded, not vacuous; the summary line now mis-describes every audit publish. Fix: a distinct note ("subject: 0 requirement row(s) — declared empty set, platform/F-100") that the sweep does not count as vacuous.

**ADV-R12-17 — LOW — PLAUSIBLE — `verify-cmd` prints a `lint-ok:`-suffixed cell verbatim (backticks kept, marker trailing), and `\|` → `|` destroys a BRE alternation (`grep 'foo\|bar'`) that the cell cannot express otherwise.**
`gates.py:4128-4133`. Measured: `` `test -f docs/adr/0007-thing.md` lint-ok: created by T08 `` printed as-is. F-18's convention leaves no spelling for a literal `\|`; the "RUNNABLE form" P3 now points at inherits the ambiguity. Fix: strip the accept marker and the wrapping span before printing; document that a literal `\|` routes through a script file.

**ADV-R12-18 — LOW — PLAUSIBLE — prodsim/F-91's "require the AT-2 row's citation to be a runnable command" landed as prose only.**
P4 step 5 and `audit_triggers.AT-2.$definition` state it; no gate reads the AT-2 row's `ev` cell (`report_row` captures id and integer only; gate-3 demands evidence only beside a status word). Fix: in the escrow, require an `ev:cmd{…}` on the AT-2 row (and AT-1's), same pass that already parses the row.

## Attacked and held

- **F-89/F-102 shorthand walk**: `CV-2610…`, `CV-2610...`, `CV-261001-demo-r1-U<n>-01`, a 150-char cut `CV-2610`, a placeholder-suffixed id — none reads as `CV-26`; `CV-07` standing for an evidenced in-run discharge is satisfied, an unevidenced one stays demanded with the F-102 message, an unallocated `CV-09` is demanded once (two mentions → one verdict), and verdicts name the verify file. v0.7.4 on the same fixture produced 5× `CV-26` attributed to RUN-REPORT.
- **evidence.any/kind with quoted braces**: `grep -c 'ev:file{' PLAN.md` and the `"…"` form parse as one cmd citation; `'}'`, `"it's"`, `awk '{print $1}'`, two such citations on one line, an unterminated quote all behave; no super-linear time at 5 000-char adversarial bodies (`'a`×n, `a{`×n, `'{`×n, `x'`×n all ≤1 ms).
- **F-113 reproduction set** a–o: d, e, f, l, n now PASS/refuse as the finding specifies; g, m, q still refused; o (tilde fence) passes.
- **F-98 walk**: `DEF-plan-01 … DEF-plan-05 | COMPLETED` enrols nothing; a FAILED range enrols every member; a DEF-plan only in a COMPLETED row's evidence cell is not enrolled; `resolved-in-run` without `ev:` is refused, with a bare `ev:commit{…}` accepted, with a backticked one refused; `Resolved-in-run — note` (case/suffix) still bound.
- **F-100 `none` path**: `requirements: none — …` with a REQ mentioned in the body → 0 ids, no text-scan fallback, `--close` still demands the walk over the FAILED/PARKED rows.
- **F-107 GATE-13**: signed+committed → nothing linted; uncommitted signature → linted; a row added after signing with `set -e; !` is refused while the frozen row is not; reorder/rename by id behaves (re-sign in the same commit as an inert row freezes it — by construction, noted, not filed).
- **F-86**: `git merge-base … || exit 1` refused; `…; rc=$?` and `rev-parse --verify` accepted.
- **F-94 modified_in_run**: a `git mv` out of `docs/spec/` reports both ends (committed and staged); `helm/ü-values.yaml` prints as itself.
- **F-97 (prodsim) gate log**: a rejection inside a linked worktree lands in `<main>/.git/wow/gate-log` with the worktree path and `wow/<run>/U1` branch per line; nothing writes `runs/.gate-log` any more (the one I found was v0.7.4's, from my A/B swap).
- **F-92 install digests**: 31 digests written at install, not rewritten by `--check`; an appended comment in `gates.py` is reported advisory, `package_integrity_check: "block"` turns it into `rc=1`; clean tree → `rc=0`.
- **F-82 wiring probe** on the installed target with a planted red gate: all six sweep gates read wired.
- **F-94 flag refusal**: `--quiet` is stripped before dispatch (hooks keep working); every `gates.sh gate-N --flag` spelling in docs/, GATES-SPEC, README, INSTALL is in `GATE_FLAGS`; `gate-10 --bogus` refused.
- **F-108 / --boundary**: an `orch/` input is accepted at G2 with no producer; `--boundary 2` refuses when the file is absent on `wow/<run>/int` (and when the branch is absent); `--boundary 1` checks nothing for a wave-2 consumer; a unit claiming `orch/*` or `reports/AM-01-verify.md` in `owns:` stays refused.
- **F-104 (prodsim) field**: `dispatched_at_wave:` ≤ `wave:` refused; a wave-1 input consumed at wave 2 accepted.
- **F-87/F-88/F-99 status.mjs**: `## audit triggers — recorded at P4` with `**AT-1**`, `**0 — NOT HIT**` parses; AT-3 derives 1 from the real BLOCKED row and ignores "0 — no BLOCKED rows"; an archived run named with `--run` reads AT-1/2/3/5 back and says so; `reviews: 1` is printed.
- **F-83/F-84/F-85 subject notes**: parity's labelled⇔call-site arm holds; GATE-4 prints `inventory: n/n` beside `subject: 0 run invariant(s)`; GATE-9's unscoped form states its subject.
- **F-96 formatter case**: `*two*` → `_two_` in the paste is refused at the right line; byte-identical paste with trailing spaces passes.
- **F-114**: a `260101-*` stub with fresh mtime is listed stale by gate-7 and status.mjs alike.
- **F-99 history**: amend + soft-reset on a unit branch in a worktree → 2 entries refused; branches absent → explicit VACUOUS line.
- **F-110**: an attest in a `Decision` column without `Q "…" A "…"` is refused; plain attests elsewhere unaffected. **F-91**: one header message per table.
- **F-112 bare form**: a GAPS citation into a run that was archived resolves through the rewrite; a target absent at both paths is GONE; `<placeholders>`, `formats.json#ids` (no headings) and `src/a.py#L1` pass.
