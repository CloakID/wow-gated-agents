# WoW v2 — a gated, evidence-first way of working for AI coding agents

**Status: DRAFT — current release: `v0.7.4-draft` (defect-fix release; the context-reduction round moved to v0.7.5).** The top entry of [CHANGELOG.md](CHANGELOG.md) is the package's single version authority; engine debts are registered in [docs/GAPS.md](docs/GAPS.md). Three pilots running, actively seeking feedback.

> **v0.7.4-draft** — a defect-fix release inserted ahead of the planned reduction round after both active pilots filed serious batches against v0.7.3 (23 findings: prodsim F-77…F-88, platform F-71…F-81). Publish path repaired (P5's own sweep grades the run it just archived; GC cannot delete cited proofs), macOS first contact repaired (`install.sh` parses under stock bash 3.2; symlinked checkouts no longer empty the freeze's carve-out), five high-severity engine defects closed, and three process structures added: a debug-lane decision surface, a P4 walk artifact with a G4 close check, and evidence-provenance clauses for amendments. `formats.json` gains an API contract (`ids_expanded`, `schema_version`, `$removed`).

WoW v2 is a spec→plan→run→report process for building software with AI coding agents (designed against Claude Code, portable in principle to any agent runner). It grew out of six months of running [GSD (get-shit-done)](https://github.com/gsd-build/get-shit-done) across two production repos, auditing what actually failed, and rebuilding around two findings that kept repeating:

1. **Prose rules fail; mechanical gates work.** Nearly every logged process lapse was a rule the model was supposed to remember. Rules that mattered only started holding when they became runnable checks the orchestrator couldn't skip.
2. **Every documentation drift was a copy-sync failure.** Facts duplicated across files (status in four places, decisions in six) diverged, always. The fix is structural: single home per fact, derived views, no persistent narrative state.

Full story with evidence: [DESIGN-RATIONALE.md](DESIGN-RATIONALE.md).

## What's in the box

- **[CLAUDE-WOW-SECTION.md](CLAUDE-WOW-SECTION.md)** — the ~60-line resident router (lanes, non-negotiables, paths) that goes in your agent memory file. Everything else loads on phase entry.
- **[docs/process/](docs/process/)** — phase playbooks **P0 GROUND → P1 SPEC → P2 PLAN → P3 RUN → P4 REPORT & RECONCILE → P5 PUBLISH**, plus [LANES.md](docs/process/LANES.md) (quick/debug lanes and precedence) and [FORMATS.md](docs/process/FORMATS.md) (IDs, evidence citations, status vocabulary, git/tracker ownership split). Every section is audience-tagged `[PO]` / `[ORCH]` / `[AGENT]` so subagents are never shown duties they can't perform.
- **[GATES-SPEC.md](GATES-SPEC.md)** — the fourteen mechanical gates plus the layer-parity check (commit-msg + pre-commit hooks + gate sweeps), each required to ship with a **non-vacuity proof**: the negative test that shows the gate can actually fail.
- **[scripts/wow/](scripts/wow/)** — the reference implementation: `gates.sh` (+ its engine `gates.py`), `formats.json` (the single machine home for every pattern, path and vocabulary), `status.mjs` (derived status), and `tests/` — one negative test per gate plus `test-install.sh`, which drives real commits through the real hooks to prove the gates are *wired*, not merely correct.
- **[install.sh](install.sh)** — per-repo installer. Idempotent, writes only repo-scoped files, preserves an existing hook by chaining to it, and `--check` reports drift against the canonical package.
- **[INSTALL.md](INSTALL.md)** — packaging, the three-layer entry-reliability model, and a migration path from GSD's `.planning/`.
- **[docs/GAPS.md](docs/GAPS.md)** — the package's own obligation registry: every known debt as a structured row with an `effect` the engine consumes (`blocks-new-feature-work` refuses new specs; `blocks-install` refuses distribution). This repo eats its own cooking — it has blocked its own feature work and its own installer when the registry said so.
- **[docs/reviews/](docs/reviews/)** — full findings from independent framework reviews, each run empirically against a consuming repo's real artifacts.
- **[FIELD-MECHANISMS.md](FIELD-MECHANISMS.md)** — deployment-specific mechanisms (invariant suites, gap registration, coevolution stamps…) described by aim + dependencies; implementations are per-project.

## What's new in v0.7.4-draft

**Both pilots upgraded to v0.7.3 (intake-coupling held) and filed 23 findings inside a week — a defect release now, the reduction round moves to v0.7.5.**

- **Publish path** (platform/F-77 + prodsim/F-88, hit independently): at `--p5` GATE-7 grades the run named by `--run` from `runs/archive/` — step 3 archives, step 6 names it, and the phase's own documented command no longer fails after every irreversible step. Registry citations to GC-deleted proofs refuse publish (platform/F-80); P5 step 4 excludes cited files from the candidate set, and dead citations are repaired by first asking whether the target moved or died (F-81).
- **macOS first contact** (prodsim/F-78/F-81/F-82): no heredoc inside `$( )` — `install.sh` parses under stock bash 3.2, as INSTALL.md always promised; the gate-11 config read uses the literal config path (symlinked `/tmp` no longer empties the exclude list and fails the freeze closed with a misdirecting hint), and a failed read is loud.
- **Five engine defects with measured harm**: the doc-wide backtick mask's `+`→`*` (one empty span un-masked the rest of the document, platform/F-75); GATE-9's drift check is per-modification, not a one-time toll (F-71); the wiring test no longer reports every gate unwired whenever one is red (F-78); the escrow discovers deferrals on fence-stripped text and names the file it read (a phantom `32:` over real debt, prodsim/F-87); truncated lists state their count (F-79).
- **Three process structures** (PO decision): the debug lane's PO decision surface (`runs/debug/CLASSIFICATION-REQUEST.md`, ORCH-proposed classification, F-80); the P4 walk artifact + "batch, don't raise" rule with a G4 close check in GATE-10 (F-86); provenance clauses for ORCH-authored amendments in P3 §4 / FORMATS §7 (F-85). Plus reconcile-in-place by spec kind (platform/F-74), `jira.status_conventions` engine-read (F-73), the bare `[T:<run-id>]` trailer bound to phase-artifact homes (F-72), wrapped preamble fields exempt across continuation lines (F-79p), the sweep asserting the hook layer (prodsim/F-77), a repo-owned `status.mjs` extension point (F-84), formatter-safe section guard (F-83), `AT-5` PO rulings read back (F-87e).
- **`formats.json` as an API** (platform/F-76): `ids_expanded` (generated, parity-checked, `gates.sh formats-expand`), `schema_version`, `$removed`.

## What's new in v0.7.3-draft

**Pilot #3 onboarded — and filed the first batch ever aimed entirely at live HEAD** (prodsim/F-60…F-76 + platform F-65…F-70 from the upgrade itself; zero dead-code triage). The round was adversarially reviewed before implementation; three confirmed defects in the draft died before shipping.

**Then the built round itself went under fresh-context attack — twice — before publish.** An adversarial review (ADV-R9, 11 confirmed defects: a forgeable escrow, a false-green audit counter, a resolver that blocked the paste workflow another rule mandates) and a developer-persona review (DEV-R9, 16 findings led by an upgrade path that silently ate repo-local CLAUDE.md content) both returned "not safe as-is"; everything blocking was fixed in the same unpublished round. A delta review then attacked the fixes (ADV-R10) and found three failing inside their own defect class — the forgery re-ran through `~~~`/indented-code channels, the config guard fell to commit-then-amend, a shared regex regressed on fenced comments — all corrected. The full reports are in [docs/reviews/](docs/reviews/); the escrow now satisfies itself only on claim text across every CommonMark mention channel, GATE-11's carve-out binds only from the committed config, and the installer guards, seeds and re-stamps what adopters actually hit first.

- **A mechanism states its subject**: gates with a registered subject label carry their subject count on PASS, a green over zero says VACUOUS, and the sweep summary aggregates the vacuous count (R9); status.mjs names the branch it derived from; the audit-trigger deriver reports rows-seen/parsed. Five findings independently demanded this — it shipped once, generically.
- **`ev:commit` citations resolve** (OBL-PKG-23 discharged): blocking in the run tree and at pre-commit, advisory in durable docs. **The escrow reads verify reports** — the files CV records are born in.
- **Correct repos stop being refused**: `legacy_freeze_exclude`, `run_base` + `check-id --base`, the F-28 header exemption, the cross-row mask fix, row-scoped status counts, and G4 resolving the reconciled spec.
- **New refusal**: a GATE-13 credential-disclosure lint — a Verify that default-expands a credential-named variable (`${V:-w}` forms) into echo/printf is refused with the safe forms named; plain `$VAR` expansion is out of its scope, and `lint-ok <reason>` stays the visible escape.
- **Finding ids qualify on crossing** (`platform/F-58`, `prodsim/F-60`) — repo-local ids collided across three pilots the day arithmetic was tried.

The suite is at **373 assertions**; 36 mutations across the round and its two review passes, each killed by exactly its own tests.

## What's new in v0.7.2-draft

**Pilot batch F-47…platform/F-64** — including the finding that mattered most: seven of twenty targeted code fixed releases ago, the third consecutive dead-code round, so **intake is now coupled to upgrading** (pilots move to the current line and answer the upgrade-RCA question before the next batch is triaged).

- **The branch model delivers declared inputs** (F-58): wave-N branches cut from `int` at wave N-1's close, and a GATE-8 lint on the new `inputs:` field refuses a plan whose input has no producer at a strictly lower wave — the case seven adversarial reviews missed.
- **Merge --no-ff, never rebase** (platform/F-60): a rebase silently invalidated every `ev:commit` citation a run's reports carry. **Archived runs leave no branch refs** (platform/F-63): P5 deletes them, GATE-7 --p5 enforces.
- **GATE-12 gains a `remediation` kind** (F-53): post-run repair justified by the defect record it fixes, not by an overrule. **The escrow recognizes in-run-discharged CVs** (F-51). **AT-1 stops counting non-vacuity controls as drift** (F-47).
- **Parsers stop refusing correct input** (F-55/F-56/F-14 addendum): divergence parsing scoped to its table, gradeless status sections loud, `ids.obligation` widened and wired. **status.mjs reports unreadable-vs-empty distinctly** (platform/F-62 residual).

The suite is at **305 assertions**; 7 new mutations, each killed by exactly its own tests.

## What's new in v0.7.1-draft

**Both-pilot feedback round on v0.7.0** (platform F-38…F-46 + two addenda) — with a meta-finding: every submission targeted v0.6.1, because neither pilot had upgraded; three findings were fixed before they were written. If you consume this package, upgrade — the -draft drop clock only starts when a pilot cycle actually runs the current line.

- **The run id has one definition** (F-46/F-39): every derived shape — task ids, CV ids, branches, trailers — expands from `ids.run_core` at load in both engines. Slug cap raised to **48**; task ids admit a letter suffix (`T07a`) so a mid-run split is committable; `gates.sh check-id` refuses an inexpressible id at run open; GATE-1 diagnoses a trailer-shaped token that resolves to nothing instead of saying "missing lane ref".
- **Registry rows can't silently lose columns** (F-44): an unescaped `|` in a cell used to truncate the row under zip(); the parser now demands exact cell count and names the pipe.
- **Map freshness is content-based** (F-45): `git diff`, not `git log` — merge ripples and revert pairs no longer cry stale, because a gate that cries stale gets its P0 skipped.
- **Verdict comparisons are sayable** (F-41), **citations prove form while the verifier's re-run proves truth** (F-43 — executors paste real output; the mechanical sampler is OBL-PKG-19), **AT-1 counts fixtures that survive the run** (F-40), **shared Jira projects declare their slice** (`jira.scope`, F-42), and the Bash-deny template comment stops overclaiming (F-18 addendum).

A pre-push self-audit of the v0.6.0→v0.7.1 trend ([docs/reviews/](docs/reviews/)) then forced a remediation half-round before release: the run-id grammar's diagnostics now *derive* from the named-parts anatomy instead of restating it, table rows are admitted by table membership (a bare or mangled task id beside valid siblings was previously invisible, its verify unread), the obligation escrow reads status by column header, and two overclaims in this very release's prose were corrected. Two structural obligations (shared parse layer OBL-PKG-20, registry self-staleness OBL-PKG-21) are registered, half of the first already landed.

The audit is now an institution: a monthly trend audit is a standing registry obligation (OBL-PKG-22), the recurring defect families are per-release checks in [CONTRIBUTING.md](CONTRIBUTING.md) §Release quality, parity fails registry rows whose successors name shipped versions, and `status.mjs` shows the installed engine version so a consumer can no longer run four versions behind without seeing it.

The suite is at **285 assertions**, every fix mutation-proven (13 mutations this version, each killed by exactly its own tests — one caught a live restatement before ship, another its own check's first blind spot).

## What's new in v0.7.0-draft

**The blocking registry is empty for the first time.** Every remaining row in [docs/GAPS.md](docs/GAPS.md) is advisory.

- **The obligation escrow parses, resolves, and closes its last declared class.** Registry rows are parsed, never substring-matched (a CV mentioned in prose is not a row); the run-local `CV-<nn>` shorthand resolves to the full id the registry demands — proven against a pilot's real RUN-REPORT, where the old regex saw 0 CV records and the new escrow reports all 8; and an audit-trigger hit recorded in a run now demands its durable row, so an owed audit cannot retire with the archived run.
- **Upgrade policy stated plainly** ([INSTALL.md](INSTALL.md)): the package guarantees that a format mismatch in your durable homes is *seen loudly* — it does not ship per-consumer migration recipes. A repo that upgrades and goes red has been told exactly what to reconcile.
- 0.7 signals *all known debts advisory*, not API stability: formats may still move between drafts pre-1.0.

The suite is at **255 assertions**. The -draft suffix drops after one full pilot cycle on this version with no new high-severity findings.

## What's new in v0.6.4-draft

Eleven new findings from both pilots, running the framework against production infrastructure daily.

- **GATE-14 — what may be committed, not just what must be captured.** Two correct rules composed into committing 159 third-party customer records with every gate green. Staged run evidence is scanned for populated personal-data fields; a deliberate capture is possible and *visible* (`pii-ok:`), and a scrubbed capture declares its trim.
- **GATE-2 takes its obligation set from declarations** (`requirements:` / `governs:`) — a range like `REQ-059 … REQ-063` used to enroll two rows of five, and discussing an id in any scanned doc adopted it. Mention is no longer claim.
- **The shared machine home is dialect-checked**: one regex key had the Python and JavaScript engines disagreeing whether a repo held 0 or 16 stale quick notes; the parity sweep now refuses non-portable escapes in formats.json outright.
- **GATE-7 stops grading other runs' debt** (escrow scoped to the publish), stops re-scanning archives forever (the exemption was dead code), classifies phantom run dirs by asking git rather than the filesystem, and reconciles the feedback log against its write-ups at publish.
- **Audit triggers derive from the durable home or say exactly why not**; the cross-run BLOCKED sum that was permanently HIT is scoped to the run its own name promises.
- **A Verify can carry a pipe** (`\|`), a pre-0.6 install source gets an honest refusal, and archiving a run no longer launders a failing GATE-2 into a passing one.

The suite is at **247 assertions**, every fix mutation-proven.

## What's new in v0.6.3-draft

The brownfield pilot came back from three production-grade runs with twenty-seven findings — a different class than before: not "the engine doesn't match the docs" but *"the process punishes the operator who follows it exactly."* Four were already answered by v0.6.2 (both pilots independently converged on the plan-verify gap that became GATE-13). The rest land here.

- **Every phase can now commit its own artifacts**: the bare `[T:<run-id>]` lane form carries P1/P4 phase artifacts, so the document a PO signs is in git at the moment of signing — and trailer *mentions* in backticks no longer count, so a commit may discuss lanes.
- **GATE-2 has two forms** (sweep = consistency lint, `--close` = the updated-row rule at phase close) — it previously had no phase where it was both in scope and satisfiable.
- **GATE-9 grades the artifact it was asked about** (resolving through the named run, refusing to guess), records may name the gate they attest, and a signed artifact amended afterward must say so (`AM-<nn>`).
- **The empty-is-permissive family is closed at every reported instance**: block-list front-matter parses (a freshness gate could never go stale), zero-parsed-task plans fail loudly, ungradeable status cells fail instead of falling through, CV ids can't collide.
- **Human evidence is first-class** (`ev:attest`), and an invented evidence kind fails loudly instead of being silently invisible.
- **The permissions policy is repo-owned** (seeded once, never overwritten), selects credential material by location rather than filename spelling, denies writes alongside reads, and its comment claims only what it delivers.
- **The process layer absorbed what three runs taught**: mid-run amendment mechanics, a fix-forward counter that counts fixes rather than checks, independent re-validation of ORCH-authored fixes, wave-boundary reconciliation on both sides of the git/Jira split, a plan-level Contracts block that actually reaches every executor, and audit-mode verification for evidence that cannot be re-run.

The suite is at **223 assertions**, every fix mutation-proven.

## What's new in v0.6.2-draft

The first pilot (greenfield) came back after three real runs with eleven upstream files; seven findings were live and all seven are fixed, doc+engine+tests together.

- **GATE-13 — plan Verify non-vacuity.** A task's `Verify` command is the sole mechanical arbiter of `COMPLETED`, and nothing required it to be shown failing — the pilot shipped nine inert verifies in one run, three of them past adversarial review. Every task now carries a `Non-vacuity` cell naming the wrong answer its Verify rejects (or `MANUAL`), and a lint flags five idioms that each shipped a real vacuous check. Binds at G2, on unsigned plans only. Designed and proven by the pilot; adopted whole.
- **Verdicts are not statuses.** A verifier following its own playbook produced reports GATE-3 rejected (56 hits). Grade/Verdict columns now have their own vocabulary — `PASS` / `PASS-with-carry-forwards` (+CV id) / `FAIL` (+VF id) — because a status describes work and a verdict judges it, and `COMPLETED`+`FAIL` is the most important pair a run produces.
- **Citations can contain braces** (one balanced level — `awk '{…}'`, jq objects, regex quantifiers), and when the format still can't express something, the diagnostic says *that* instead of blaming the writer's citation.
- **Dependency probes are allowlisted before they run.** A probe is shell; the pilot demonstrated one writing a marker file while the gate passed. The first word must now match the allowed pattern (default: your repo's request wrapper) — checked before execution, never falling back to the calendar rule.
- **P5 owns the merge to main** (new step 0), and the destructive permissions regeneration refuses on a branch behind main — the pilot showed it would have silently deleted a grant that took a PO decision and two blocked waves to establish.
- **Phantom runs are refused**: archiving strands empty run directories that status derivation then reports as active, visible only to the person who published. Also fixed: the HANDOFF line counter was off by one ("80" meant 79 — five commits trimmed a file that was already right); the limit itself is now explicitly advisory.

The suite is at **193 assertions**; every fix was proven by disabling it and watching exactly its own tests go red.

## What's new in v0.6.1-draft

The second pilot (a brownfield repo migrated off its legacy framework) ran v0.6.0 for a day and filed four findings; all four are fixed here, doc+engine+tests together.

- **Requirement ids are repo-configurable** (`requirement_id` in `wow.config.json`, default `REQ-nnn`). Before, a repo whose stable requirement identities had any other shape got a GATE-2 that passed green *permanently* — the empty named-set was permissive. Now the repo's real scheme binds, and id-shaped `REQUIREMENTS.md` rows the effective pattern cannot read fail loudly instead of parsing as "nothing to check". `status.mjs` honors the same override.
- **Inline code is a mention, not a claim.** GATE-3 flagged a registry that documents its own citation formats in backticks — red before any work existed. Backticked spans are now invisible to the evidence scan in both directions: a template isn't flagged, and a backticked citation can't green a status.
- **The parity sweep gained its reverse direction for lane refs**: every commit trailer the engine accepts must be documented in `LANES.md` and the resident router, or parity fails — `[WOW:migrate]` had been engine-real and doc-invisible at exactly the moment it was the only legal lane.
- **`docs/GAPS.md` is single-table by construction, and now says so** (FORMATS §12, and in the failure message that fires when a second id-shaped table trips row discovery).

The suite is at **165 assertions**; each fix's tests were proven by disabling the fix.

## What's new in v0.6.0-draft

v0.5.0 shipped the engine; **v0.6.0 makes the framework govern itself** — and was built under its own rules.

- **Obligations are machinery now.** `docs/GAPS.md` rows carry a closed `effect` vocabulary the engine consumes: GATE-12 refuses a new-feature spec while a `blocks-new-feature-work` row is open (audit/fix/probe specs referencing the obligation are the discharge path); `install.sh` refuses to distribute while a scope-matched `blocks-install` row is open — the package has used this on itself. GATE-7 gained an escrow check (nothing obligation-shaped may live only in an archivable run), and `status.mjs` now answers *what does this state require next*, not just *what is the state*.
- **The layer-parity check runs first in every sweep**: the GATES-SPEC table, the engine registry and `formats.json` are three declarations of one set, and they must agree — a spec-only gate needs a `DESIGNED-NOT-IMPLEMENTED` marker naming an *open* obligation, version stamps must match the CHANGELOG authority, and doc headers are checked against the commit that actually last modified them.
- **A registry the schema can't read fails loudly** instead of parsing as empty — unreadable tables (any casing, any id shape) and prose-only registries all refuse; only a genuinely empty table passes — found when a pilot's legacy gap table made GATE-12 report "nothing blocks" with 17 real rows on the page. Same principle applied to the installer: a package missing its own manifest files refuses to install (exit 5) rather than shipping dangling stubs.
- **Migration got honest mechanics**: a `[WOW:migrate]` lane ref valid only while `.planning/` exists and the freeze is unflipped; a named pre-freeze risk window; the vacuity report as a written artifact; a documented rollback recipe.
- **Two independent reviews are folded in** ([docs/reviews/](docs/reviews/)) — each reviewer ran this engine against a real consuming repo (one greenfield pilot, one brownfield target) and every finding is fixed here or registered as an open obligation. The test suite grew from 104 to **154 assertions**, including negative tests proven by disabling their fixes.
- Known open debts are in the registry, not in prose — currently one row blocking package feature work (report parsing by column header) and one blocking the pilot's upgrade (row-migration recipe), both by design.

## What's new in v0.5.0

v0.4 was the design. **v0.5.0 adds the reference implementation** — and, more to the point, evidence that it is *connected*.

- **The engine ships.** `install.sh` + `scripts/wow/` (`gates.sh` → `gates.py`, `formats.json`, `status.mjs`, `tests/`). One command installs it into any git repo; `--check` reports drift against the canonical package; re-running upgrades in place.
- **Wiring is now tested, not assumed.** Every gate had a passing negative test while GATE-7 sat in no sweep list, GATE-6's codebase half had no caller, and hooks were written to `.git/hooks` in repos whose `core.hooksPath` meant git never read them — with the installer and the status tool both reporting a healthy install. All of those are fixed, and the new `tests/test-install.sh` installs into throwaway repos and drives real commits through real hooks so the class cannot come back. **104 assertions**, and disabling any gate still fails its own test.
- **Gates that could pass for the wrong reason no longer do.** A lane ref must name a real task *row*, not a task id mentioned in prose; GATE-2 wants the requirement row *updated in this run*, not merely present; GATE-5 judges the staged content rather than the worktree; GATE-8 fails a spec whose ACs it cannot parse instead of calling zero-of-zero total; GATE-9 makes the sign-off record *required* when a gate is actually closing; GATE-10 reads the verdict from the Classification column and wants an empty diff evidenced; GATE-11 blocks deletions of frozen history, not just edits.
- **`formats.json` is genuinely the single machine home.** The scan-target list, the `p0-record` vocabulary, the invariant/non-vacuity markers, the divergence-record columns and the install manifest all used to live inside the engines, where nobody reading the docs could find them. `gates.py`, `status.mjs` **and** `install.sh` are all consumers of it now, so no two of them can disagree about what a format is.
- **Prerequisites are stated and checked** (bash 3.2+, git 2.5+, python3; node optional, for status only). `install.sh` aborts on a missing one instead of installing a half-enforcing repo, an existing `pre-commit`/`commit-msg` hook is preserved and chained rather than overwritten, and the package no longer assumes macOS.

Upgrading a repo installed from v0.4: `./install.sh /path/to/repo`, then `bash scripts/wow/tests/run-all.sh`.

## Core ideas, in one paragraph each

**Bounded autonomy, not perfect plans.** Executors get an explicit autonomy contract: in-contract deviations are decided and logged (`DEV-U2-03`); anything cross-unit, acceptance-criteria-touching, or irreversible is parked with a blocker note and the run continues. No mid-run questions, no silent improvisation.

**Verification is independent and re-validated.** A verifier agent with a fresh context — never shown the implementer's reasoning — re-runs every check itself. Fixes are re-validated (in our field data, 2 of 10 review fixes were themselves wrong). Acceptance criteria are executable, and harness-touching ones carry a written **premise check**: *can this pass for the wrong reason?* (Our worst field failure was a milestone that passed every gate while delivering zero real value.)

**Parallelism is a merge problem.** Units own disjoint path sets (machine-checked), interfaces freeze at plan sign-off, executors commit only to their unit branch, and only the orchestrator merges — sequentially, in wave order, with a defined conflict policy and a serial integration wave last.

**Git owns content; the tracker owns workflow.** Requirement *technical* status (evidence-backed) lives in git; *workflow* status lives in the tracker (Jira in our deployment). Divergence between them is never silently merged — gates open with a diff, and every out-of-mapping pair is classified: git wrong, tracker wrong, or a real gap.

## Prerequisites

The package is plain files — no npm, no vendored engine, no third-party installer. It needs:

| | Version | Needed for | Without it |
|---|---|---|---|
| **bash** | 3.2+ | `install.sh`, `gates.sh`, the negative tests | nothing runs (macOS ships 3.2; nothing here needs bash 4) |
| **git** | 2.5+ | hooks, `git worktree`, `--git-common-dir`, every freshness and modified-file rule | nothing runs |
| **python3** | 3.6+ | `gates.py` — the engine `gates.sh` delegates to; also the in-place CLAUDE.md section edit | **no gates**; `install.sh` refuses to run |
| **node** | 18+ | `status.mjs` only | *optional* — you lose derived status, not enforcement |

`install.sh` checks these before writing anything and aborts with a named prerequisite rather than installing a half-working framework. Nothing else is assumed: no package manager, no CI service, no OS-specific tools (the suite hashes with whichever of `sha256sum`/`shasum`/`python3` exists).

## Adopting it

Read INSTALL.md. Short version:

```sh
git clone <this repo> && cd wow-v2
./install.sh /path/to/your-repo          # idempotent; re-run to upgrade
cd /path/to/your-repo
bash scripts/wow/tests/run-all.sh        # negative test per gate + the wiring test
node scripts/wow/status.mjs              # derived status (optional; needs node)
```

Then set the tracker project key in `scripts/wow/wow.config.json` and enter work through the `/wow-*` commands. `./install.sh --check /path/to/your-repo` reports drift between what is installed and the canonical package — including a hook someone has quietly neutered.

## Feedback

This is a design under review — see [CONTRIBUTING.md](CONTRIBUTING.md) for the specific questions we most want challenged. Issues and discussions welcome.

MIT licensed.
