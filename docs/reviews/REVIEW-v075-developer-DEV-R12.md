# DEV-R12 — developer-persona upgrade audit, v0.7.4-draft → v0.7.5-draft (fresh context)

> **Disposition (R12b, 2026-10-06):** blockers 01–04 and majors 05–13 remediated in-round with tests and mutation proofs; minors 14–23 remediated (14 installer note + INSTALL text + staged_scope; 15/16/17/19/20/21/22/23a–g as text or engine changes — 23c archived plan resolution, 23d "unchanged", 23g `int` absent message). DEV-R12-11's surface is `walk-G4.md`'s `## ORCH classification` table (FORMATS §4, P3 §4, P4). DEV-R12-12: AT-2's citable sources are committed artifacts only (the gate log is out) and P4 carries a workable command; a packaged `at2` command is not shipped — the count is consumer-shaped by definition. The reviewer's text follows verbatim.

Persona: maintainer of a consuming repo on v0.7.4 (installed from `492dfc7`), zero prior exposure to the package, reading CHANGELOG top entry → README "What's new" → INSTALL "Upgrading" → GATES-SPEC → docs/process/*.md → formats.json comments, and doing what they say.

Fixture: `/tmp/dev-r12/repo` (git, `main`), built and committed GREEN under v0.7.4 through the real hooks: `docs/REQUIREMENTS.md` (REQ-001..003), a signed feature spec with ACs (`SPEC-order-export-v1.md`, reconciled to v2 at G4), an audit spec with `requirements: none — …` (`SPEC-trigger-audit-v1.md`), an active run `260915-order-export-r1` (signed PLAN with AM-01, 3 units/waves with `owns:`/`inputs:`/`governs:`/`areas:`, task cells with pipes, grep, git, jq; U1 verify report with a FAIL + `VF-U1-01`, a CV discharged in-run and mentioned as `CV-01`, a `PASS-with-carry-forwards`; RUN-REPORT with `## audit triggers — recorded at P4` in bold cells; walk-G4; divergence-G1/G2/G4; a prettier-shaped paste), an archived audit run under `runs/archive/260901-trigger-audit-r1/` cited from `docs/GAPS.md` in bare and `#anchor` forms, a quick stub dated 2026-06-01 with an empty `result`, a codebase map. Branches `wow/<id>/{base,int,U1..U3}`, `--no-ff` merges, bare and task trailers.

**Baseline under v0.7.4 (on `int`):** `sweep --run` 6/6 PASS; `gate-2 --close` PASS (`walk: 3/3`); `gate-7 --run` RED on `uses shorthand CV-01 but docs/GAPS.md has no full-form row` (the F-89/F-102 class — the CV was discharged in-run with `ev:jira`); `status.mjs` showed AT-1/AT-2 "not derived — run has no RUN-REPORT audit triggers section yet" (the F-87 heading-suffix class); `tests/run-all.sh` reported all six sweep gates "in no sweep" (the F-82 class) with a green sweep. All three are things this release claims to fix.

**Upgrade:** `install.sh --check` (rc=1, DRIFT listed) → `install.sh` (rc=0, re-stamped, wrote `package-digests.json`) → `--check` "no drift" → committed per the installer's own instruction.

## Verdict as delivered

**Not as-is.** The three headline fixes work on the fixture exactly as advertised — the suite passes inside the consumer, status.mjs reads the suffixed/bold table with zero edits, and the shorthand `CV-01` with an evidenced in-run discharge goes from red to green with zero edits. But four things on the documented happy path go red with no usable remedy: (1) `sweep --run` now refuses every GATE-10 divergence record (`To Do`, `Done`, `COMPLETED` in the Git/Jira columns FORMATS §10 prescribes) at every gate and, at `--p5`, re-grades the archived run under today's vocabulary; (2) the pre-commit hook refuses to commit a NEW plan whose Non-vacuity cells cite the run-time evidence files GATE-13 asks for, with a message about archived runs; (3) GATE-7 refuses publish of any run whose RUN-REPORT `## defects` table names its own VF in the first cell — the shape P3 mandates — and the INSTALL remedy (`VF-AM<nn>-<nn>`) does not apply; (4) a `capture: <repo-relative path>` line, the form P3 prescribes, goes red at P5 step 6 once the run is archived, and the only remedy is editing the archive. Beneath those, the `requirements: none — <why>` sentinel enrols any id its `<why>` mentions, `gate-2 --close` at `--p5` passes vacuously ("0 items, no walk owed") on a run that has a walk, and the F-99 permission change never reaches an upgraded consumer at all. Fix DEV-R12-01..04 and 05/06 before pilots see this; the rest can ride with a corrected "what goes red" table.

## Findings

**DEV-R12-01 · blocker — `sweep --run` / `gate-3 --run` refuse the GATE-10 divergence records every phase writes, and re-grade the archived run at `--p5`.**
Did: `bash scripts/wow/gates.sh sweep --run 260915-order-export-r1` (green on v0.7.4 minutes earlier).
Saw: `FAIL gate-3 / runs/260915-order-export-r1/divergence-G2.md:4 'To Do' is not in the status vocabulary (BLOCKED, COMPLETED, …) / divergence-G4.md:4 status COMPLETED without an ev: citation / divergence-G4.md:4 done-word 'Done' used as a status without an ev: citation`. After P5 step 3: `sweep --p5 --run` repeats it on `runs/archive/260915-order-export-r1/divergence-G2.md` — F-65's "graded under the vocabulary of its time" is gone for the named run.
Expected: `Item | Git | Jira | Classification` rows holding Jira workflow words are the FORMATS §10 format; GATE-3 was never their gate. Not in INSTALL's "what goes red" table; the message's implied remedy (rewrite the Jira column) contradicts §10.
Fix: `gate-3 --run` scans the gated-doc globs applied to the named run (`RUN-REPORT.md`, `reports/*.md`, `FINDINGS.md`, `findings/*.md`, `walk-G4.md`), not `os.walk` of the run dir; keep the archive exemption outside `--p5`'s GATE-7.

**DEV-R12-02 · blocker — the pre-commit GATE-5 arm (F-112) refuses to commit a new plan whose Non-vacuity cells cite run-time evidence files.**
Did: wrote `runs/261006-order-export-r2/PLAN.md` per P2 with Non-vacuity cells `… ev:file{runs/261006-order-export-r2/evidence/U1/nv-T01.txt}` (same shape as the r1 plan that committed under v0.7.4), `git commit`.
Saw: `GATE-5: runs/261006-order-export-r2/PLAN.md:33 cites ev:file{runs/261006-order-export-r2/evidence/U1/nv-T01.txt} — GONE at its cited path and at the archive rewrite (runs/<id>/x → runs/archive/<id>/x); a durable document's citation into an archived run is re-pointed at P5, not left to dangle (prodsim/F-112)` ×3, commit refused. `gate-8` and `gate-13` had just PASSED the same plan.
Expected: G2 commits. GATE-13 asks the cell to "cite something runnable"; the evidence file is what the executor produces. INSTALL's row says "(advisory on unmodified docs)" — a new plan is blocking, and the diagnosis (archived run) is wrong for a run that has not started. Only way through was rewriting every cell as `ev:cmd{…}`.
Fix: in the bare/anchored preflight, treat a target under the citing run's own `runs/<id>/evidence/**` (or any path a unit `owns:`) as a promise, not GONE, while the run is active; or make the arm advisory outside durable docs (`docs/**`), which is the F-112 case.

**DEV-R12-03 · blocker — GATE-7's VF double-definition arm fires on the RUN-REPORT `## defects` row; INSTALL's remedy does not apply.**
Did: `gate-7 --run 260915-order-export-r1` (and `sweep --p5 --run` after archiving). RUN-REPORT has `| VF-U1-01 | buffered stdout reorders … | COMPLETED ev:commit{…} |` under `## defects`; `reports/U1-verify.md` defines `- VF-U1-01 — …`.
Saw: `GATE-7: VF-U1-01 is DEFINED in 2 report files (runs/…/RUN-REPORT.md, runs/…/reports/U1-verify.md) — one id, two findings; a verifier allocates in its own segment (… VF-AM<nn>-<nn> for an amendment's delta verifier) …`.
Expected: P3 "RUN-REPORT structure" requires `defects` rows "per FORMATS §4–5, one line per row"; FORMATS §1 says the walk/report row carries "the item id whole in the first cell". INSTALL's row says "the amendment verifier allocates VF-AM<nn>-<nn>" — there is no amendment verifier here. Nothing tells me the only escape is to move the id out of the first cell.
Fix: count definitions only in `*-verify.md` (the allocating files) and only where the id heads a heading or list item; a table row elsewhere is a reference.

**DEV-R12-04 · blocker — `capture: <repo-relative path>` goes red at P5 step 6 once the run is archived.**
Did: P3 as written: `capture: runs/260915-order-export-r1/evidence/U1/sample.csv` above the fence in `reports/U1.md` (`gate-3 --paths` PASS, byte-for-byte compare proven to fire on one trailing space). P5 step 3 `git mv runs/<id> runs/archive/<id>`, step 6 `sweep --p5 --run <id>`.
Saw: `runs/archive/260915-order-export-r1/reports/U1.md:11 \`capture: runs/260915-order-export-r1/evidence/U1/sample.csv\` names no file (tried repo-relative and document-relative) — a paste that cites a capture it does not have is an assertion (prodsim/F-96)`.
Expected: the `ev:file` resolver follows the archive rewrite (DEV-R12 confirmed GAPS.md's un-repointed bare citation resolves); the capture line does not. P5 "re-point every durable-document citation" says nothing about capture lines, and the archive is not to be edited. Document-relative `../evidence/U1/sample.csv` survives, but no doc says to prefer it.
Fix: resolve `capture:` through the same archive rewrite; say in P3/FORMATS §3 that the path is document-relative by preference.

**DEV-R12-05 · major — `requirements: none — <why>` enrols every id the `<why>` mentions.**
Did: `gate-2 --spec docs/spec/SPEC-trigger-audit-v1.md` with header `requirements: none — an audit delivers findings, not product; REQ-003 is background only`.
Saw: `obligation set from declarations (requirements:/governs:) — 1 id(s)` … `1 REQ id(s) checked`. Bare `requirements: none` → `0 id(s) … VACUOUS`. (`requirements: [] — …` is refused as "not the empty-set sentinel (^(?:none|\[\])\b)" — ADV-R12-04.)
Expected: P1/GATES-SPEC/INSTALL say `none — <why>` IS the empty set. This is platform/F-100 one clause later: the audit spec cites a requirement as background and the close form will demand its row.
Fix: when the declaration matches the sentinel, stop; never scan the remainder of the line for ids.

**DEV-R12-06 · major — `gate-2 --close` at `--p5` passes vacuously on an archived run that has a walk.**
Did: `sweep --p5 --run 260915-order-export-r1` after archiving (RUN-REPORT has a FAILED and a PARKED row; walk-G4.md has 3 rows; pre-archive it said `walk: 2/2`).
Saw: `PASS gate-2 / run … is archived — governing plan read from runs/archive/…/PLAN.md (F-36) / walk: 0 failed/blocked/parked/defect items — no walk artifact owed`.
Expected: GATES-SPEC says the close form binds "in the P5 sweep"; `_walk_items` reads `runs/<id>/RUN-REPORT.md` only, returns None after the move, and None reads as "nothing owed" — the F-36 "archiving must not launder a failing gate" class.
Fix: resolve RUN-REPORT and walk through the archive like the plan; None ≠ empty.

**DEV-R12-07 · major — the F-99 permission change (`git reset`/`commit --amend`/`rebase` → ask) never reaches an upgraded consumer.**
Did: `grep -n amend scripts/wow/permissions-policy.json` in the consumer after upgrade; `install.sh --check`.
Saw: no match; `ok scripts/wow/permissions-policy.json (repo-owned, not compared to the package)`. The package file carries the ask set under `"version": "0.7.1-draft"`.
Expected: CHANGELOG and README list it as landed. The seed-once rule (F-06) is right; the release notes should say "seed file — copy the `ask` block by hand" and `--check` could note "package seed changed since your copy".
Fix: a one-line note in INSTALL's table and a `--check` line when the seed template's digest differs from install time.

**DEV-R12-08 · major — parity's registry successor-staleness arm runs in a consumer only when parity already failed; a clone and its origin disagree.**
Did: `git clone` the fixture; `gates.sh sweep` in the clone vs in the original.
Saw (clone): `FAIL parity … hook commit-msg is ABSENT … / open row OBL-REPO-01: successor names v0.7.5, at or before the current v0.7.5-draft — that release shipped without discharging the row, so the successor is fiction`. Original: `PARITY PASS`, same GAPS.md. Cause: `check_parity` returns early (`if not msgs: return True, …`) when there is no CHANGELOG.md, before the OBL-PKG-21 arm. Also: my successor cell says "trigger-audit r2 after v0.7.5 upgrade" — a consumer plan keyed to the package version — and the package-registry rule calls it fiction.
Fix: run the arm unconditionally (move the early return after it); in a consumer, only compare versions against the consumer's own stamp or require the backtick-mention form and say so.

**DEV-R12-09 · major — GATE-8's reads-vs-declarations lint binds on SIGNED plans; INSTALL's remedy demands editing a frozen artifact.**
Did: `gate-8 --run 260915-order-export-r1` (plan signed at G2, run at P4) as INSTALL's by-hand list suggests.
Saw: `GATE-8: U1 task …T01 names path 'docs/export-usage.md' which exists nowhere the wave order can deliver … declare it, or accept deliberately with 'lint-ok: <reason>'`.
Expected: GATE-13 says "a signed plan is frozen, and a retroactive rule would demand the edit the framework prohibits" and lints only amended rows (confirmed: `0 row(s) added or changed since the signing commit`). GATE-8 has no such exemption; following the table means an `AM-<nn>` to satisfy a lint on a finished run.
Fix: scope the F-97 arm like F-107 (rows since the signing commit) or state in the table that it is G2-only and a signed plan's red is informational.

**DEV-R12-10 · major — `history --run` refuses with no recovery path, and nothing stops the merge.**
Did: verifier committed `U1-verify.md`, appended a line, `git commit --amend`; `gates.sh history --run 261006-order-export-r2`.
Saw: `HISTORY: wow/261006-order-export-r2/U1: 1 history-rewrite entry since the branch was cut — commit (amend): … — a correction is a NEW commit …` rc=1. `git merge --no-ff` then succeeded.
Expected: P3 §5 says run it before merging; no doc says what to do once the reflog carries the entry (the pre-amend commit is in `git reflog`, restorable as a new commit; the entry itself never goes away). Combined with DEV-R12-07, the hook that would have asked first is not installed either.
Fix: the message names the recovery (`git reflog show <branch>` → re-commit the discarded tip as a new commit on top, record a DEV-ORCH), and P3 says whether a refused branch may still merge.

**DEV-R12-11 · major — the PO "overrule by row" surface for fix-budget classes does not exist.**
Did: per P3 §4 ("which the PO sees in the next gate's divergence list and may overrule"), wrote `| VF-AM01-01 (ORCH bookkeeping, verifier class) | spent | — | spent |` in `divergence-G4.md`; `gate-10 --run … --gate G4`.
Saw: `GATE-10: 2 divergence(s) unclassified in the Classification column (need one of git-wrong/jira-wrong/real-gap)`.
Expected: a row home. `orch_classification: verifier` is the default and the P4 [PO] checklist says classifications "stand or are overruled by row", but no artifact carries `repaired/spent/carry-forward` or `DEV-ORCH-<nn>` for a PO to overrule (AM-<nn>-verify.md is per amendment; a DEV-ORCH outside an amendment has no report).
Fix: name the surface — a `## ORCH classification` table in walk-G4.md (the P4 batch artifact) with an `Overrule` column — and point P3 §4 at it instead of the divergence record.

**DEV-R12-12 · major — AT-2 cannot be computed from its definition; AT-1's example cites a script the package does not ship.**
Did: tried to write the P4 step 5 row for r2. Triggers: gate rejections live in `<git-common-dir>/wow/gate-log` (untracked, 11 kinds logged by then including my own exploratory runs; absent in any clone), review rounds exist only as `reviews: 2`, parks/fix waves are ids in reports. Wrote `evidence/ORCH/at2.sh` over the log + `git log --grep='repairs VF-'` + parks.
Saw: `gate-rejection kinds=11 fix-wave commits=0 parks=0 total=11` — a number straddling the threshold that no second reader could reproduce, which is prodsim/F-91's complaint restated. AT-1's P4 example cites `bash runs/<id>/evidence/ORCH/standins.sh base int => base 15, tip 15, new 0`; nothing ships or describes a stand-in inventory.
Fix: either ship `gates.sh at2 --run <id>` reading the gate log for the run's trailers plus `repairs VF-`/`PARK-` ids, or define AT-2's citable sources as committed artifacts only and say the gate log is out.

**DEV-R12-13 · major — the F-110 ruling check binds only when the attest sits inside the Decision cell.**
Did: `| id | Decision | ev |` / `| D-9 | keep the literal sample for r1 | ev:attest{PO: accepted the literal sample for r1 @2026-09-18} |`; `gate-3 --paths`.
Saw: `GATE-3 PASS`. The check runs `re.finditer(attest, cells[ruling_idx])` — the `ev` column is never read.
Expected: INSTALL/FORMATS say "an attest in a Decision/Ruling column must carry the Q/A form"; the natural layout puts the attest beside it. Inert for the shape pilots write.
Fix: when a table has a ruling column, require the Q/A form of every attest in that ROW.

**DEV-R12-14 · minor — two gate-log homes; the stale one gets committed by the installer's own instruction.**
INSTALL.md §Reliability: "gates.sh logs rejections to `runs/.gate-log`" vs LANES/P5/GATES-SPEC `<git-common-dir>/wow/gate-log`; `commit_trailers.kinds.run.staged_scope` still lists `runs/.gate-log`. After upgrade the v0.7.4 file is left untracked, and `git add -A && git commit -m 'chore: install …'` (the installer's text) committed 41 lines of old rejections (`git show --stat HEAD | grep gate-log → runs/.gate-log | 41 ++`). Fix: INSTALL line; installer deletes or ignores the retired file.

**DEV-R12-15 · minor — "P3 step 10" does not exist.** P2 step 1 ("a P3 step 10 amendment"), P2 step 5 ("before a P3 step 10 amendment is signed"), formats.json `dispatched_at_wave.$comment`. P3 has steps 1–8; the amendment rule is a bullet in the branch-model section. Fix: cite "P3 §branch & merge model, mid-run plan amendment".

**DEV-R12-16 · minor — P1's `kind: fix` Load line names an undefined artifact and a route no doc takes.** "the prior run's `## P4 classification`" — grep finds it nowhere but P1 (it is prodsim's repo-local section; the package artifact is `walk-G4.md`). P4 step 2 and LANES rule 2 route a fix iteration straight to `/wow-plan` on `r<N+1>`, so when P1 runs with `kind: fix` is unstated; I wrote `SPEC-order-export-v3.md` with `kind: fix` and guessed. Fix: "the prior run's `walk-G4.md`", and one sentence on when a fix gets its own P1.

**DEV-R12-17 · minor — GATE-6 and the p0-record disagree across docs.** GATES-SPEC GATE-6: freshness "for every area … — or a P0 completion record in HANDOFF". FORMATS §6: "No map yet? … p0-record". Engine: `p0-record: export = updated` ignored when a map exists: `GATE-6: map 'export' is STALE: content under [...] differs since ebe2d9ea3c (7 commit(s))`. Fix: GATES-SPEC wording "(when no map exists)".

**DEV-R12-18 · minor — the G4 walk population shrank silently.** Same RUN-REPORT: v0.7.4 `walk: 3/3`, v0.7.5 `walk: 2/2`. The `| DEF-plan-01 | … | OPEN |` row under `## defects` is no longer a walk item (walkable statuses only; prose fallback suppressed because a row carries it). A defect recorded as a row with status OPEN now routes nowhere and nothing says so. Fix: enrol a DEF-plan id from a `## defects` row regardless of status, or say the row must read FAILED.

**DEV-R12-19 · minor — anchor refusals name no candidates; em-dash headings slug to a double hyphen.** `ev:file{…RUN-REPORT.md#audit-triggers-recorded-at-p4}` → `has no heading anchored 'audit-triggers-recorded-at-p4'`; the engine's slug is `audit-triggers--recorded-at-p4`. FORMATS §3 still says "content anchors preferred" while the arm demands a heading (ADV-R12-05). Fix: list the target's heading slugs in the message; say "heading anchor" in §3.

**DEV-R12-20 · minor — GATE-9's message asks for "an `AM-01` block" without the one shape that now counts.** `… add an \`AM-01\` block naming what changed and why (FORMATS §1)`. Since only `AM-<nn> — <date> — …` record lines count, `AM-01: changed X` stays red. Fix: print the record form in the message.

**DEV-R12-21 · minor — GATE-10 says a row "needs no classification and may be dropped", then refuses it.** `| REQ-002 | COMPLETED | In Review | — |` → `note: … IS expected-consistent … the row needs no classification` + `1 divergence(s) unclassified`. An empty cell passes; `—` (the dash every other table uses for "none") fails. Fix: treat `—`/`-` as empty on expected-consistent rows.

**DEV-R12-22 · minor — stale quick stubs flip red at P5 with no table row.** `runs/quick/260601-fix-typo/NOTE.md has an empty result and is 128 days old — stale stub, PO confirms deletion` — green on v0.7.4 (mtime), red now (directory date, correctly). Documented in LANES/P5 but absent from INSTALL's "what goes red" table, which is the page an upgrader reads. Fix: one row.

**DEV-R12-23 · minor — small text/engine gaps a new reader trips on.** (a) `K3` (P3 executor, "oracle-shaped (K3)") is undefined anywhere. (b) INSTALL "Running the gates by hand" lacks `verify-cmd`, `history`, `hooks --install`, `check-id --base`. (c) `gate-9 --gate G4 --run <archived-id>` says `no plan, or no spec: header` though the plan is in the archive. (d) `install.sh` prints `wrote CLAUDE.md wow-v2 section (replaced)` when the section is byte-identical. (e) INSTALL's capture remedy "or wrap it in prettier-ignore" does not turn the gate green — only re-pasting does. (f) GATE-9 `--gate G2` PASSES on an uncommitted signature while P2 says the freeze is the commit's. (g) `gate-8 --boundary <wave>` says the input "does not exist on wow/<id>/int" when `int` itself does not exist yet.

## Three best things

1. **The wiring fix is real and visible from the consumer side.** `bash scripts/wow/tests/run-all.sh` inside the upgraded repo: `ALL GATE TESTS PASSED`, where v0.7.4 said six gates were "in no sweep" with a green sweep. Same for the stale-gate-log telemetry: `<git-common-dir>/wow/gate-log` lines carry worktree and branch and survived the branch deletion at P5.
2. **Two fixture reds turned green with zero edits.** `status.mjs` went from "AT-1/AT-2 not derived" to `AT-1 … 0 (>3)` / `AT-2 … 1 (>5)` on the `## audit triggers — recorded at P4` table with bold cells; `gate-7 --run` stopped demanding a registry row for the shorthand `CV-01` whose block carries `discharged: … ev:jira{…}`. That is the pilot's complaint answered as written.
3. **The small new commands are exactly right.** `verify-cmd <task-id>` printed the runnable cell (pipes un-escaped, code span stripped) and `| bash` ran it; `gate-3 --spec …` refused with `this gate reads: --paths, --run`; `gate-8 --boundary 2` named the missing ORCH input and the branch it looked on; `gate-2 --close` named the uncited `resolved-in-run` rows and said why. Messages consistently carry the finding id, the cause and the remedy — when the remedy is right, this package is unusually pleasant to be refused by.
