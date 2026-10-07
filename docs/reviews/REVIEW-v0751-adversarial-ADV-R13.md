# ADV-R13 — adversarial review of v0.7.5.1-draft (fresh context)

> **Disposition (R13b, 2026-10-07):** every finding below was remediated in-round, each with its own test and mutation proof (M208–M233), except where noted: 01 (fidelity arms: body-defined ids ⊆ `ids:` ⊆ body ids; FAIL / PASS-with-carry-forwards grade and FAILED/BLOCKED/PARKED status cells named in `verdict:` — M208/M209/M210), 02 (`handback.max_chars` 2,000 bytes — M211), 03 (obsoleted by the DEV-R13-01 end rule: an indented block needs a blank line before it and a blank line not followed by a field/list line ENDS the section, so the paste is body; the test keeps the shape as an accept control), 04 (values read: empty refused, `ids:`/`parked:` are `none` or family ids, id-shaped strays refused — M212/M213/M214), 05 (`clears:` located inside `## resume` on fence-stripped text, last wins, resume text skips it — M228/M229), 06 (bullet/bold/case-tolerant `handoff_clears_field`; GATE-7 `--p5` refuses a RUN-REPORT recording fewer trigger rows than the registry declares — M224), 07 (delegate home `runs/<id>/orch/<role>-<n>.md` in `handback.files`, ORCH-owned per §9, `[AGENT] — delegate` section in P3 — M220), 08 (parity: `always` vs `p5_only` by the `where` cell, lists disjoint — M225/M226/M227; GATE-15 grades the archived named run at `--p5` — M221), 09 (text: AT-6 is a self-reported symptom counter — `derived_by: orch`, `self_reported: true`, GATES-SPEC "explicitly not gates" and FORMATS §14 reworded; the hand-back byte total as a tree-derivable subject is noted for v0.7.6), 10 (P4 Load line, INSTALL remedy, P3 step 1 exception, P4/P5 delegate pointers), 11 (status.mjs counts by GATE-15's predicate incl. delegates; resume name from `runs_layout.handoff_resume_section` — M230/M231/M232), 12 (position counts non-blank lines, front matter excluded; setext heading ends the section — M218), 13 (`_blank_html_comments` before locating — M217). CHANGELOG itemisation corrected (7 install assertions).

Method: throwaway fixture repos under `/tmp/adv-r13/` (`fx1` = engine copy + `git init` carrying a realistic run `261007-demo-r1` — signed-shape PLAN, `reports/U1.md` + `reports/U1-verify.md` with conforming hand-backs, RUN-REPORT with an `## audit triggers` table, HANDOFF with `## resume` / `clears: 1`; `inst` = `install.sh` target from HEAD; `inst2` = v0.7.5 install (`git archive cf0471d`) with an active run, then upgraded to HEAD; `clone` = a real clone with history for the stamp check; `mut1` = fx1 with gate-15 moved to `sweep.p5_only`). Every CONFIRMED item was reproduced with the command shown. The suite (`run-all.sh`) is green on HEAD in a copy at 606 assertions (579 on cf0471d — the CHANGELOG itemisation 16+6+4 = 26 is one short; test-install.sh's `sweep_membership` loop gains the seventh). None of the items below is covered by it. The baseline run fixture passes `sweep --run` 7/7 and `sweep --p5 --run` after archival, so nothing below is a fixture artefact.

## Verdict as delivered

**Not sound to ship as-is — but close, and the defects are in the gate's semantics, not its wiring.** The trait is honestly described (FORMATS §14 says in so many words that it is a convention with a gated edge), the installer carries it, the upgrade path goes red exactly as INSTALL's table says, parity and the P5 sweep hold on an installed consumer, and GATE-15 refuses every shape its test names. What fails is the claim the trait rests on: that the ORCH can *route on the hand-back*. (1) Nothing ties a hand-back to the gated rows beneath it — a verify report whose body grades `FAIL` with two `VF-` findings and whose hand-back says `verdict: PASS` / `ids: none` passes the whole sweep, so the one input the ORCH is now told to read is the one input no gate checks; (2) the "bound" is twenty *lines* — a 100 KB hand-back passes — and an indented (4-space) paste, the shape the package's own B1 fix already treats as a paste elsewhere, is not a fence to GATE-15; (3) the four fields are presence-checked only: `verdict:` with nothing after it passes while the gate's own message and FORMATS §4 say "write `none` when empty". On the AT-6 side, status.mjs reads `clears:` from anywhere in HANDOFF — a fenced `## resume` template with `clears: 7` beats the real `clears: 1`, and a `clears:` under `## position` yields "NO ## resume section" and "AT-6 = 5 read from ## resume" on adjacent lines — while the bullet and bold spellings every other HANDOFF section uses read UNRECORDED, and UNRECORDED is non-blocking at P5. Doc-side, §14 names eight new delegates (mapper, premise attacker, preflighter, triager, reconciler, assembler, walk preparer, publisher) whose reports have no sanctioned path, no `[AGENT]` section and therefore no gated hand-back — GATE-15 covers only the two agent kinds that already had bounded reports — and their manifests must be cut from `[ORCH]`-tagged steps, which the resident router's Roles line forbids. Fix ADV-R13-01..04 and 07..08 before tagging; the rest can ride or be folded into v0.7.6.

## Findings

**ADV-R13-01 — HIGH — CONFIRMED — a hand-back may contradict the gated rows below it; the ORCH is told to route on the one section no gate reads against anything.**
`gates.py:2254-2258` checks each required field for *presence* and nothing else; no arm compares `verdict:` with the Grade/Verdict column or `ids:` with the `VF-`/`CV-` ids the body defines. FORMATS §4 (line 48) makes the body the claim and the hand-back "a summary of cited rows below, not a claim"; P3 step 3 (line 18) then says the ORCH "routes on the verifier report's hand-back (`verdict:` and `ids:`) … the ORCH does not [read the findings]".
Repro (`fx1`): `reports/U1-verify.md` hand-back `- verdict: PASS` / `- ids: none`; body `| U1 | FAIL | VF-U1-01 |` under a `Grade` header plus `- VF-U1-01 — …` and `- VF-U1-02 — …` findings.
```
$ bash scripts/wow/gates.sh sweep --run 261007-demo-r1
PASS parity … PASS gate-3 … PASS gate-15
sweep: 7/7 passed (1 vacuous — green over an empty set)
```
Why it matters: under #8 the ORCH never sees the FAIL row; no fix wave is dispatched; the first reader of the body is the RUN-REPORT assembler at step 8, after the wave closed. Both halves are mechanical: (a) every id matching `ids.verifier_finding`/`ids.cannot_validate` defined in the body (the F-105 `defn` shape, `gates.py:2705`) must appear in `ids:`; (b) a `Grade`/`Verdict` cell of `FAIL` requires `FAIL` in `verdict:` (and `PASS-with-carry-forwards` its CV id). Both belong in GATE-15, which already has the file open.

**ADV-R13-02 — HIGH — CONFIRMED — the "bound" is twenty non-blank *lines*; a 100 KB hand-back passes, and the ORCH's context is what the trait exists to protect.**
`gates.py:2244-2247` (`content = [ln for ln in body if ln.strip()]`, compared to `max_lines`); no byte or token bound anywhere in `handback` (formats.json:679-695).
```
$ python3 - <<'EOF'   # 4 fields + 16 lines, each 5 000 chars
…
EOF
bytes: 100704
$ bash scripts/wow/gates.sh gate-15 --paths runs/261007-demo-r1/reports/X.md
     subject: 1 agent report(s)
GATE-15 PASS
```
Why it matters: a verifier that cannot fit its findings into twenty lines will — rationally — write twenty long ones, and the gate that exists to keep bodies out of the router's context certifies the body as a hand-back. `max_chars` (or `max_line_chars`) beside `max_lines` in the schema is the whole fix; the same holds for the `## resume` section nobody bounds.

**ADV-R13-03 — MEDIUM — CONFIRMED — an indented (4-space) code block is a paste GATE-15 does not see; `_FENCE_OPEN` is the only paste shape it refuses.**
`gates.py:2249` uses `_FENCE_OPEN` (` ``` ` / `~~~` within 3 spaces); the v0.7.5 B1 fix gave status.mjs `blankIndentedCode` and the escrow learned indented code (ADV-R10-01/03) precisely because an indented block is a paste.
```
$ printf '## hand-back\nverdict: FAIL\nids: VF-U1-01\npointers: x\nparked: none\n\n    $ pytest\n    1 failed\n    Traceback ...\n' > runs/261007-demo-r1/reports/X.md
$ bash scripts/wow/gates.sh gate-15 --paths runs/261007-demo-r1/reports/X.md
GATE-15 PASS
$ printf '…parked: none\n    ```\n    $ pytest\n    ```\n' > …/X.md     # a fence indented 4 spaces is an indented block, not a fence
GATE-15 PASS
```
(`~~~` and four-backtick fences ARE refused — those held.) Fix: refuse any line matching the package's own indented-code rule inside the section, or run the section through `_strip_fenced_blocks` + the indented-code blanker and refuse if anything was blanked.

**ADV-R13-04 — MEDIUM — CONFIRMED — the four fields are presence-checked only: empty, garbage and non-id values pass, while FORMATS §4, the GATE-15 row and the gate's own refusal text say "write `none` when empty".**
`gates.py:2254-2258`: `field_pattern` ends at the colon (`^\s*(?:[-*]\s+)?\**{name}\**\s*:`, formats.json:691); nothing reads the value. The refusal text itself says "(write `verdict: none` when there is nothing)".
```
$ printf '## hand-back\nverdict:\nids:\npointers:\nparked:\n' > …/X.md ; gates.sh gate-15 --paths …/X.md
GATE-15 PASS
$ printf '## hand-back\nverdict: ???\nids: see below\npointers: everywhere\nparked: tbd\n' > …/X.md ; gates.sh gate-15 --paths …/X.md
GATE-15 PASS
```
Why it matters: non-negotiable #6 — a rule stated in three places and gated in none. Minimum: a field's value is `none` or non-empty; `ids:`/`parked:` values are `none` or a list of tokens matching `ids_expanded.*`.

**ADV-R13-05 — MEDIUM — CONFIRMED — AT-6 and the `resume:` line are read from the WHOLE HANDOFF, raw: a `clears:` outside `## resume` counts, and a fenced template of the section beats the real one.**
`status.mjs:337-338` (`handoff.match(...)` on raw text) and `status.mjs:525-531` (`h.match(clearsRe)` on raw text, no section scoping) — while every other HANDOFF/RUN-REPORT reader in the same file strips fences (`stripFencedBlocks`, line 288/457) after ADV-R10-03 and F-75. The derivation note then claims "read from HANDOFF ## resume".
```
$ printf '# HANDOFF\n\n## position\nwave 1\nclears: 5\n\n## pointers\n- x\n' > runs/261007-demo-r1/HANDOFF.md
$ node scripts/wow/status.mjs | grep -A1 'resume:\|AT-6'
    resume: NO ## resume section in HANDOFF — a fresh ORCH has nowhere to restart from (FORMATS §8, v0.7.5.1)
  AT-6 orch_context_clears_this_run: 5 (>2)  HIT
       read from HANDOFF ## resume `clears:` (the ORCH records every context clear there)
$ printf '# HANDOFF\n\n## position\nwave 1\n\n```\n## resume\nclears: 7\n```\n\n## resume\nwave 1\nclears: 1\n' > …/HANDOFF.md
$ node scripts/wow/status.mjs --json --run 261007-demo-r1 | …   →  AT-6 value=7 hit=True | run.clears=7 resume='clears: 7'
$ … template with `clears: <n>` in the fence and `clears: 0` below → resume='<wave> — <next step>'
```
Why it matters: the resume line is what a fresh ORCH is told to restart from, and it is handed the template; AT-6 is "the trait's own subject" and a HIT demands a GAPS obligation at P5. Fix: locate the `## resume` section on fence-stripped text (the `handoff_section_heading` template already exists) and match `handoff_clears_field` inside it only; take the LAST match (HANDOFF is overwritten, and an appended resume is the likely shape — today the first wins: `clears: 0` then `clears: 4` reads 0).

**ADV-R13-06 — MEDIUM — CONFIRMED — `- clears: 3`, `**clears:** 3` and `Clears: 3` read UNRECORDED; UNRECORDED is non-blocking at P5, so the bullet form every other HANDOFF section uses silently disarms the trigger.**
`formats.json:644` `handoff_clears_field = ^clears:\s*([0-9]+)\b` — no list-marker, bold or case tolerance, while the sibling `handback.field_pattern` (line 691) and the AT rows (F-87) tolerate exactly these. FORMATS §8 describes `parked`/`pointers` as "ids + one-liners" bullet sections.
```
$ printf '# HANDOFF\n\n## resume\nwave 1\n- clears: 3\n' > …/HANDOFF.md ; node status.mjs --json --run … → AT-6 value=None hit=None
$ printf '…\n**clears:** 3\n' → None None ;  printf '…\nClears: 3\n' → None None
$ # and at P5 an unrecorded AT-6 blocks nothing:
$ grep -v AT-6 RUN-REPORT.md > RUN-REPORT.md ; bash scripts/wow/gates.sh gate-7 --p5 --run 261007-demo-r1
GATE-7 PASS
$ # …nor does a RUN-REPORT with NO audit-triggers section at all (pre-existing for AT-1..5)
GATE-7 PASS
```
Why it matters: the release says "UNRECORDED, never 0" as if unrecorded were the safe direction; at publish it is the green one. Fix: reuse the hand-back field shape for `clears:`; and (the class fix, also covering AT-1..AT-5) `gate-7 --p5` should refuse a RUN-REPORT whose `## audit triggers` table lacks a row for any `derived_by: status|orch` trigger.

**ADV-R13-07 — MEDIUM — CONFIRMED — the eight delegates §14 introduces have no report path, no `[AGENT]` section and no gated hand-back; GATE-15 gates only the two agent kinds that already had bounded reports, and the delegates' manifests must be cut from `[ORCH]`-tagged steps the router says never to load into an AGENT.**
Evidence: `plan_schema.agent_writable_paths` = `runs/*/reports/U*.md`, `U*-verify.md` (+ `delta_verifier_paths`); FORMATS §9 (line 89) "AGENTs write **only** …"; `handback.files` = `runs/*/reports/*.md`; the only `[AGENT]` sections in `docs/process/` are P3's executor and verifier (`grep -n '^## \[AGENT\]' docs/process/*.md`); the triager/reconciler/assembler/walk-preparer/publisher/mapper/premise-attacker/preflighter each occur once or twice, all inside `[ORCH]` steps; CLAUDE-WOW-SECTION.md:9 "never load `[ORCH]`/`[PO]` duties into an AGENT context"; README.md:17 "Every section is audience-tagged … so subagents are never shown duties they can't perform".
```
$ grep -rn -o "triager\|reconciler\|assembler\|walk preparer\|publisher\|mapper\|premise attacker\|preflighter" docs/process/*.md | wc -l
17        # every hit is in FORMATS §14's table or an [ORCH] step; zero [AGENT] sections, zero file paths
```
Why it matters: the steps that actually consume context (sweep triage of a 43-line failure list, the reconciliation walk over every report, RUN-REPORT assembly) are the ones delegated, and their hand-backs live nowhere GATE-15 looks — a triager that hands back in its final message is unbounded by construction, and §14's own spec for it ("one-line remedy each" over a 43-failure sweep) cannot fit the 20-line bound anyway. Either give delegates a home (`runs/<id>/reports/<role>-<n>.md`, added to `handback.files` and to §9's list) with an `[AGENT] — delegate` section carrying the closed-manifest rule, or state in §14 that delegate hand-backs are ungated and why.

**ADV-R13-08 — MEDIUM — CONFIRMED — the parity sweep-membership arm checks the union of the lists; moving GATE-15 to `p5_only` passes parity, and at P5 the gate is vacuous on the run being published, so the M203 class ("a gate nothing calls") survives in a form the arm was built to catch.**
`gates.py:3987-3996`: `in_lists = always ∪ p5_only`; `where` is tested for the substring "sweep", not for which sweep. `gates.py:2215-2218`: `--run <archived>` returns PASS "graded at its own publish; nothing to check" — and P5 step 6 runs the sweep AFTER step 3 archives, so "its own publish" is the one sweep that never grades it.
```
$ # fx1: move gate-15 from sweep.always to sweep.p5_only (where still says "sweep + verifier self-check")
$ bash scripts/wow/gates.sh parity
PARITY PASS
$ # fx1, run archived as at P5 step 3, then the step-6 sweep:
$ bash scripts/wow/gates.sh sweep --p5 --run 261007-demo-r1 | grep -A2 gate-15
PASS gate-15
     --run 261007-demo-r1 is ARCHIVED — graded at its own publish (platform/F-65); nothing to check
     subject: 0 agent report(s) — VACUOUS …
$ # the same holds for a gate in BOTH lists: parity PASS, the P5 sweep runs it twice (9 gates in "8/9 passed")
```
The suite does go red under this mutation — but by accident: test-gate-parity's own fixture removes gate-15 from `always` and asserts a refusal that no longer comes, i.e. "FAIL not rejected" on its negative, not an assertion that gate-15 runs in every sweep. Fix: `where` containing "sweep" without "P5" ⇒ must be in `always`; "P5 sweep" ⇒ `p5_only`; the two lists disjoint. And GATE-15's archived branch should grade the named run at `--p5` the way gate-7 does (`gates.py:2446-2469`), since that is the publish it defers to.

**ADV-R13-09 — MEDIUM — CONFIRMED — AT-6 measures run length, is self-reported by the party it measures, and is optional at publish — yet GATES-SPEC and §14 present it as the trait's observable.**
`formats.json:740-747` (`metric: orch_context_clears_this_run`, `derived_by: status`, `source: … handoff_clears_field`), FORMATS §8 ("incremented by the ORCH that resumes"), GATES-SPEC:60 ("AT-6 counts the consequence"). The number is written by the ORCH whose behaviour it grades, after the clear that is the failure mode for remembering to write it; an ORCH that reads every body in a short run scores 0, a fully delegating ORCH in a 12-wave run can exceed 2; and (ADV-R13-06) the row can be absent at P5 with every gate green. The docs say the trait is unobservable from the tree (§14, GATES-SPEC "explicitly not gates") and in the same breath call AT-6 "the trait's own subject (a mechanism states its subject)". Fix the text: AT-6 is a *symptom counter* for run length; the trait has no subject the tree can see. Or give it one that is not self-reported — e.g. the hand-back byte total per run (ADV-R13-02's bound, summed) is derivable by status.mjs from the tree.

**ADV-R13-10 — LOW — CONFIRMED — the P4 Load line still loads the whole RUN-REPORT into the ORCH, and §14's "never reads" list omits it; INSTALL's remedy says "the ORCH does not write an agent's report" while P3 step 6 has the ORCH's reconciler closing rows in agent reports.**
`docs/process/P4-REPORT.md:3` "Load: RUN-REPORT, SPEC, …" (unchanged this round) vs P3 step 8 (line 23) "the ORCH … reads only its row counts and the assembler's hand-back" and P4 step 2 (line 7) "it reads no report body itself" — the RUN-REPORT is the assembly of every body and has no `## hand-back` (it is not under `reports/`, correctly). `INSTALL.md:121` "the ORCH does not write an agent's report" vs `P3-RUN.md:21` "closes any whose named blocker is discharged, preserving the original grade in a dated reconciliation note" (in `reports/U<n>.md`). P3 step 1 (line 16) still ends "**Nothing else.**" after step 3 (line 18) adds the verifier report's path to a fix-wave executor's manifest. §14's P4 row delegates "AT derivation (step 5)" and P5's header delegates steps 3/4/6, but P4 step 5 and P5 steps 3/4/6 themselves were not touched and still read as ORCH-performed.

**ADV-R13-11 — LOW — CONFIRMED — status.mjs's `hand-backs: n/m … open with ## hand-back` counts the heading anywhere in the file, fenced or not; it says 2/2 on a report GATE-15 refuses six ways.**
`status.mjs:339` (`hp.test(read(...))` on raw text, no position/bound/field check; `.md` files in `reports/` only, while GATE-15's glob also descends into `reports/sub/`).
```
$ # U1.md: no hand-back at top; a fenced "## hand-back (template)" at line 9
$ node scripts/wow/status.mjs | grep hand-backs
    hand-backs: 2/2 agent report(s) open with ## hand-back (GATE-15)
$ bash scripts/wow/gates.sh gate-15 --run 261007-demo-r1 | head -2
GATE-15: …/U1.md:9 `## hand-back` is not at the top …
GATE-15: …/U1.md hand-back carries a fenced block …
```
Also: `status.mjs:337` inlines the vocabulary word `'resume'` instead of reading `runs_layout.handoff_sections`, and AT-6's reader ignores the `source` key it declares — formats.json's own no-inline rule. Fix: share one predicate (position + bound + fields) or rename the line to what it measures.

**ADV-R13-12 — LOW — CONFIRMED — "within the first 3 lines" counts blank lines and front matter; a title + two blanks, or a 3-line YAML block, is refused "not at the top", and a setext heading does not end the section.**
`gates.py:2237` (`start >= 3` over raw lines), `gates.py:2241` (section ends only at an ATX `#` heading).
```
$ printf '# U1 report\n\n\n## hand-back\n…' → GATE-15: X.md:4 `## hand-back` is not at the top
$ printf -- '---\nunit: U1\n---\n## hand-back\n…' → GATE-15: X.md:4 `## hand-back` is not at the top
$ printf '…parked: none\n\nFindings\n--------\n' + 25 bullets → GATE-15: hand-back is 31 non-blank line(s), over the 20-line bound
```
Why it matters: formatter-inserted blanks and the package's own front-matter idiom (`codebase_frontmatter`) produce the refusal; the fix is to count non-blank, non-front-matter lines before the heading, as the bound itself already counts non-blank lines.

**ADV-R13-13 — LOW — CONFIRMED — a `## hand-back` inside a multi-line HTML comment satisfies the gate and renders as nothing.**
`gates.py:2230` matches the heading on raw lines; `<!-- … -->` is not stripped.
```
$ printf '<!--\n## hand-back\nverdict: x\nids: none\npointers: x\nparked: none\n-->\n# real report\nbody\n' > …/X.md ; gates.sh gate-15 --paths …/X.md
GATE-15 PASS
```
Contrived as an attack, but it is the same class as the fenced `#` heading ADV-R10-03 fixed in every other section locator: locate on stripped text.

## Not findings (tried, held)

- `~~~` fences, four-backtick fences, a fence whose opener sits above the heading, a `## hand-back` only inside a fence at the top, `### hand-back`, `## Hand-back`, a table-shaped hand-back, fields under a `###` sub-heading, `verdicts:` — all refused as intended; `##hand-back`, trailing spaces, CRLF, bold field names, bullet field names, a second `## hand-back` later (first wins) — accepted as intended.
- GATE-3 does not refuse legitimately written hand-backs: `verdict: FAIL`, `verdict: PASS`, `- verdict: COMPLETED`, `verdict: all tasks DONE`, `**verdict**: FAIL — see findings` all pass `gate-3 --paths`; done-words and verdict words in `verdict:` are prose, not rows. (Only a literal `result: FAILED` inside the line trips `status_prefix`, as it always did.)
- GATE-7 at `--p5` with full `CV-` ids and `PARK-` ids repeated in `ids:`/`parked:` passes (escrow satisfied by the body's discharged record); the F-105 double-definition arm does not fire on a hand-back's `ids:` list (same file as the definition). A recorded `AT-6 = 3` without a GAPS row IS refused at P5 (`names BOTH AT-6 and the run`), and an archived run's AT-6 is read back with bold cells and a prose suffix (`| **AT-6** | **4** |`, `| AT-6 orch context clears | 4 — HIT |`).
- Scope: RUN-REPORT.md is correctly NOT required to carry a hand-back; `reports/AM-01-verify.md` IS required (refused without one); non-`.md` files in `reports/` are ignored by both engines; a run with no `reports/` dir is `subject: 0 — VACUOUS`, PASS; status.mjs `--json` does not throw on either; an archived run's reports are excluded unscoped (`citation_scan_exclude`); a missing run is refused; `--run` scopes away another active run's bad report.
- Parity on an installed consumer (`inst`, `install.sh` from HEAD) passes; `sweep` on it is 7/7 (4 vacuous); `gates.sh list` shows GATE-15 in both sweep lines; `formats-expand` produces no drift; a `where` missing on a listed gate is refused ("`where: `").
- Upgrade (`inst2`, v0.7.5 install with an active run → HEAD): `--check` reports drift, the CLAUDE.md section is replaced and carries #8 (and the fresh install's does too, 37 lines), FORMATS §14 and the GATE-15 row land in the consumer, the next `sweep --run` goes red with exactly the INSTALL-table message, and `status.mjs` prints the `resume: NO ## resume section` and `AT-6 … unrecorded is not zero` lines as the table says.
- Stamps: every modified doc's header reads `DRAFT v0.7.5.1`; `formats.json` version = CHANGELOG top entry; parity in a real clone (with history) passes; LANES.md untouched and unstamped, correctly; `gates.py`'s four-component version regex works (`title_re`). The resident router is 39 lines by `wc -l` (the ≤60 budget is a line budget, so the 700-character line 32 is "one line" — the same measure ADV-R13-02 objects to, noted, not filed). README's "fifteen" and test-gate-4's `15/15` inventory are updated.
- `clears: 03` reads 3, `clears: -1` and `clears: three` read UNRECORDED, `clears:3` reads 3, a blockquoted `> clears: 3` is skipped (first non-quoted match wins), a 20-digit value parses to 1e20 and HITs — none of these is wrong on its own.
- Test suite: 606 assertions green on HEAD in a copy; 579 on cf0471d; the itemisation in the CHANGELOG is one short (install gains 7, not 6: the `sweep_membership` loop) — a nit, not filed.
