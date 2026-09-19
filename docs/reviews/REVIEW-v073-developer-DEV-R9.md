# DEV-R9 — Developer-persona review of WoW v2 v0.7.3-draft (fresh context)

Target: device commit 87ffe7e (diff 0e371bf..HEAD). Reviewer: isolated subagent playing a senior developer with zero prior exposure, doing (a) fresh adoption, (b) v0.7.2→v0.7.3 upgrade with pre-existing state, (c) docs read, (d) 10 forced gate failures graded. Experience audit only; gate-logic correctness covered by ADV-R9.

## Findings

**DEV-R9-01 · blocker — plain upgrade silently deletes repo-local CLAUDE.md content; `--check` warns, then tells you to run the thing that deletes it.**
An upgrader who recorded a PO decision inside the wow-v2 markers loses it on plain `install.sh <repo>` with only "wrote CLAUDE.md wow-v2 section (replaced)". The F-66 loss warning lives only in optional `--check` — whose own last line is "DRIFT FOUND — re-run install.sh to upgrade". A hurried dev follows the last line.
Fix: on plain install, when the outgoing section differs from BOTH old and new package sections (contains local lines), print the "will be lost" diff and require a force flag, or auto-save displaced lines below the closing marker.

**DEV-R9-02 · major — greenfield adoption dead-ends at the first `/wow-spec`; no doc owns the bootstrap.**
Followed INSTALL.md's next steps (all green), entered `/wow-spec` → GATE-12: "no docs/GAPS.md — … create the registry (an empty table is a valid registry), and that is not a pass". Nothing names an adoption step "create docs/GAPS.md / docs/REQUIREMENTS.md with these headers"; the 7-column gap_row schema must be reverse-engineered from FORMATS §12 (not installed).
Fix: install.sh seeds an empty-but-valid docs/GAPS.md (header row only) like it seeds wow.config.json, or the GATE-12 message prints the header row to paste.

**DEV-R9-03 · major — nobody names the lane for committing the install; the discovered answer is the universal bypass.**
First commit after install → GATE-1 laneless refusal. No doc says which trailer covers "I just installed WoW". LANES.md says `[WOW:publish]` "resolves to nothing by design" — the newcomer tries it, it works, and also lands real code in the same commit. Lesson learned in ten minutes: "[WOW:publish] makes GATE-1 go away."
Fix: one sentence in INSTALL.md + install epilogue naming the trailer; consider scoping what the trailer may touch.

**DEV-R9-04 · major — two version authorities disagree after every upgrade, and the sweep names the stale one as truth.**
After upgrade, wow.config.json still says `"wow_version": "0.7.2-draft"` while status.mjs says "engine v0.7.3-draft installed". Every consumer sweep prints "consumer version truth is wow.config.json's installed stamp" — pointing at the stamp that is now wrong, and nothing checks or updates it.
Fix: install.sh rewrites the `wow_version` key on upgrade; parity compares the two.

**DEV-R9-05 · major — GATE-13 mis-blames the wrong cell on an unescaped shell pipe in Verify (the class F-18 claims closed).**
Verify of `` `echo $API_TOKEN | wc -c` `` → GATE-13 "Non-vacuity cell cites nothing runnable: 'it works'" — blaming a healthy cell because the pipe shifted columns. GATE-8 on the same plan diagnoses the pipe perfectly; only one of the two G2 gates has the cell-count guard.
Fix: route GATE-13's row parse through the same `_table_scan` cell-count refusal.

**DEV-R9-06 · major — "stale citations cannot land" oversells: GATE-5 only sees `ev:file{path:N}`.**
Staged `see docs/REQUIREMENTS.md:99` (nonexistent line) → PASS. `ev:file{src/a.py#L99}` → PASS. Only `ev:file{path:line}` bodies are preflighted.
Fix: GATES-SPEC/INSTALL say so verbatim, or the scan widens.

**DEV-R9-07 · major — observed GATE-9/G4 behavior contradicts the new v0.7.3 spec text, and the doc's two clauses contradict each other.**
GATES-SPEC GATE-9 row says both "legacy tokenless records stay valid" and "legacy tokenless record must not close G4 (ADV-5)". Observed: v1-only legacy tokenless record → G4 PASS. Reader cannot tell which rule wins.
Fix: state the precedence in the GATE-9 row.

**DEV-R9-08 · major — the configurable surface is invisible in the config the consumer actually has.**
Seeded wow.config.json shows 7 keys; six documented keys (requirement_id, probe_command_pattern, main_branch, jira.scope, legacy_freeze_exclude, run_base) appear nowhere in it, canonically documented only in an INSTALL.md list item that is not installed. The seeded default `"task": "Task"` is the exact value INSTALL.md v0.7.3 warns against (prodsim/F-61).
Fix: seed the template with all keys (commented/defaulted); flip or annotate the mapping default; put the hierarchy rule in an installed doc.

**DEV-R9-09 · minor — first-contact status.mjs mixes real signal with fabricated context.**
On an empty repo: the F-74 "0 row(s) seen, 0 parsed" diagnostic implies a parse failure when there is no run at all; "Requirements — 0 row(s): " dangling colon; cryptic "newer? run install.sh --check from a clone of the package repo".
Fix: gate the F-74 diagnostic on a run existing ("no runs yet — derived at first P4").

**DEV-R9-10 · minor — vacuity vocabulary inconsistent; the sweep summary still says the sentence the release mocks.**
gate-3 says VACUOUS, gate-2 says "nothing to check" (same condition, no marker), gate-4/gate-9 print nothing, and the summary line is `sweep: 6/6 passed` — the exact "'6/6 passed' over an empty set" string the CHANGELOG ridicules, unmarked at the level a human reads. README overclaims "every gate PASS carries its subject count".
Fix: propagate VACUOUS to the summary (`6/6 passed (1 vacuous)`); align gate-2's wording; scope the README claim.

**DEV-R9-11 · minor — `run_base` default chain breaks on non-`main` repos; refusal doesn't name the config remedy.**
On a master-default repo, `check-id --base main` correctly refuses but cites prodsim/F-65 instead of "set main_branch/run_base in wow.config.json"; install never notices main doesn't resolve.
Fix: append the config remedy; warn at install.

**DEV-R9-12 · minor — installed surfaces are salted with other repos' finding ids the consumer can never resolve.**
The resident router (≤60-line budget, in the consumer's CLAUDE.md) and gate messages cite prodsim/F-68, platform/F-69, ADV-5 — dead references and token load in an agent-memory file (messages do carry remedies, hence minor).
Fix: keep finding ids in GATES-SPEC/CHANGELOG; strip from router and message text or make them trailing `[ref: …]`.

**DEV-R9-13 · minor — doc density at self-parody levels; the docs know it.**
GATE-7 row 3,943 chars in one table cell; FORMATS' DEV-ORCH entry a ~700-char parenthetical; P3 step order `3, 3b, 4a-pre, 4a, 4, 5`; ~180KB doc set. OBL-PKG-25 defers to v0.7.4 — fine — but renumber P3's steps now.

**DEV-R9-14 · minor — README stale/incorrect claims.**
"the twelve mechanical gates" (there are 14); the new GATE-13 credential lint filed under "Correct repos stop being refused" (it is a new refusal); unqualified "credential-disclosure lint" though only default-expansion forms are caught (`$API_TOKEN` bare passes).

**DEV-R9-15 · minor — `install-vacuity.md` limbo.**
INSTALL migration step 6 still mandates the hand-written artifact (OBL-PKG-09 pending) in a doc the consumer doesn't receive, scoped to GSD migration though the rationale applies to greenfield, and v0.7.3's live VACUOUS markers now do that job without the doc saying whether the artifact is superseded.

**DEV-R9-16 · nit — `runs/.gate-log` polluted before first use and silently committed.**
INSTALL's own next-step (run-all.sh) writes 2 fake GATE-1 rejections into the fresh repo's gate log; untracked, not gitignored, rides the first `git add -A`. No doc says whether to commit it.

## Message quality (10 forced failures)
8 of 10 graded A-range (GATE-1 slug diagnosis A+: names token, part, measured length, derived cap). Failures: GATE-13 pipe-shifted blame (F — wrong rule, wrong cell, misleading remedy); the F-74 zero-runs diagnostic and the version-authority line are the other two worst messages (see DEV-R9-05/09/04).

## Three best things (calibration)
- Gate failure messages are, GATE-13's parse bug aside, the best the reviewer has seen in a process tool.
- The upgrade kept a green repo green, and the F-74 fix is visible on identical artifacts with zero edits.
- install.sh is genuinely careful: idempotent, chains pre-existing hooks, refuses incomplete packages, and --check's "< = yours, > = package" diff is exactly right.

## Verdict
Not as-is. Engine and error messages are team-ready; the adoption and upgrade paths are not. With DEV-R9-01, -02, -04 and the GATE-13 cell-count guard (-05) landed, roll-out without a wrapper. Doc set needs the promised v0.7.4 reduction before anyone but the framework champion reads it.
