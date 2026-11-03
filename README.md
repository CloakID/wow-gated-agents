# WoW v2 — a gated, evidence-first way of working for AI coding agents

**Status: DRAFT — current release: `v0.7.6-draft` (2026-11-03; a test-only portability patch: the self-test suite builds its fixtures through python3 instead of GNU-only `sed -i`/`touch -d`, so it runs unchanged on macOS — advisor/F-200; measured green on Linux and on the originating Mac, 2026-11-03). Previous: `v0.7.5-draft` (2026-10-07; the defect-and-process release of 50 pilot findings, and the router trait — the ORCH is a router, not a reader). Next: the context-reduction round, v0.7.7.** The top entry of [CHANGELOG.md](CHANGELOG.md) is the package's single version authority; engine debts are registered in [docs/GAPS.md](docs/GAPS.md). Three pilots running, actively seeking feedback.

> **v0.7.5-draft** — two releases' worth in one version. Part 1 (2026-10-06): 50 pilot findings against v0.7.4 taken as one defect-and-process release — consumer-visible regressions closed, vacuity stated by every gate, the deriver reads what the ORCH recorded, GATE-8's reads-vs-declarations lint, evidence that survives the formatter and the archive, ORCH bookkeeping classified by a fresh verifier. Part 2 (2026-10-07): **the ORCH is a router, not a reader** — GATE-15 hand-backs, delegate reports, `sweep --summary`, HANDOFF `## resume` and AT-6. Each part went through an adversarial and a developer-persona review before publish (docs/reviews/).

WoW v2 is a spec→plan→run→report process for building software with AI coding agents (designed against Claude Code, portable in principle to any agent runner). It grew out of six months of running [GSD (get-shit-done)](https://github.com/gsd-build/get-shit-done) across two production repos, auditing what actually failed, and rebuilding around two findings that kept repeating:

1. **Prose rules fail; mechanical gates work.** Nearly every logged process lapse was a rule the model was supposed to remember. Rules that mattered only started holding when they became runnable checks the orchestrator couldn't skip.
2. **Every documentation drift was a copy-sync failure.** Facts duplicated across files (status in four places, decisions in six) diverged, always. The fix is structural: single home per fact, derived views, no persistent narrative state.

Full story with evidence: [DESIGN-RATIONALE.md](DESIGN-RATIONALE.md).

## What's in the box

- **[CLAUDE-WOW-SECTION.md](CLAUDE-WOW-SECTION.md)** — the ~60-line resident router (lanes, non-negotiables, paths) that goes in your agent memory file. Everything else loads on phase entry.
- **[docs/process/](docs/process/)** — phase playbooks **P0 GROUND → P1 SPEC → P2 PLAN → P3 RUN → P4 REPORT & RECONCILE → P5 PUBLISH**, plus [LANES.md](docs/process/LANES.md) (quick/debug lanes and precedence) and [FORMATS.md](docs/process/FORMATS.md) (IDs, evidence citations, status vocabulary, git/tracker ownership split). Every section is audience-tagged `[PO]` / `[ORCH]` / `[AGENT]` so subagents are never shown duties they can't perform (a delegate acting for the ORCH gets the `[AGENT] — delegate` section plus the one `[ORCH]` artifact format its manifest names).
- **[GATES-SPEC.md](GATES-SPEC.md)** — the fifteen mechanical gates plus the layer-parity check (commit-msg + pre-commit hooks + gate sweeps), each required to ship with a **non-vacuity proof**: the negative test that shows the gate can actually fail.
- **[scripts/wow/](scripts/wow/)** — the reference implementation: `gates.sh` (+ its engine `gates.py`), `formats.json` (the single machine home for every pattern, path and vocabulary), `status.mjs` (derived status), and `tests/` — one negative test per gate plus `test-install.sh`, which drives real commits through the real hooks to prove the gates are *wired*, not merely correct.
- **[install.sh](install.sh)** — per-repo installer. Idempotent, writes only repo-scoped files, preserves an existing hook by chaining to it, and `--check` reports drift against the canonical package.
- **[INSTALL.md](INSTALL.md)** — packaging, the three-layer entry-reliability model, and a migration path from GSD's `.planning/`.
- **[docs/GAPS.md](docs/GAPS.md)** — the package's own obligation registry: every known debt as a structured row with an `effect` the engine consumes (`blocks-new-feature-work` refuses new specs; `blocks-install` refuses distribution). This repo eats its own cooking — it has blocked its own feature work and its own installer when the registry said so.
- **[docs/reviews/](docs/reviews/)** — full findings from independent framework reviews, each run empirically against a consuming repo's real artifacts.
- **[FIELD-MECHANISMS.md](FIELD-MECHANISMS.md)** — deployment-specific mechanisms (invariant suites, gap registration, coevolution stamps…) described by aim + dependencies; implementations are per-project.

## What's new in v0.7.6-draft

**A patch, not a round (advisor/F-200).** On macOS 12 of the package's own self-tests failed — not because a gate was wrong, but because twelve fixtures were set up with two GNU-only command forms (`sed -i '…'`, `touch -d '60 days ago'`) that BSD userland rejects; the scenario was never built and the assertion after it checked the wrong thing, so GATE-7/8/13 and parity could not be confirmed on a Mac from the suite alone. All thirteen sites (eleven live, two whose assertions never depended on the edit — F-200 listed twelve) now go through three python3 helpers in `tests/lib.sh` that count a non-landing edit as a failed assertion, and the wiring suite carries a tripwire that refuses the listed GNU-only forms in the suite, `install.sh` or `gates.sh` (mutation-proved: M236 `sed -i`, M237 `touch -d`, M239 a no-match edit). A docstring escape that Python ≥3.12 reports as a SyntaxWarning — two more red assertions on 3.13 — is fixed in the same patch (M238). No gate behaviour changes; the reduction round moves to v0.7.7.

## What's new in v0.7.5-draft

### Part 2 — the router trait

**One trait, PO decision 2026-10-07: the orchestrating session is a router, not a reader.** A run ends when the ORCH's context must be cleared, and what fills that context is the report bodies, finding lists and sweep failure lists it read in order to route. Now every such step is delegated to a fresh-context agent with a closed manifest, and the ORCH consumes a bounded `## hand-back` instead (non-negotiable #8; the per-phase delegation table is FORMATS §14 — map writing, premise attack, preflight, sweep triage, reconciliation walk, RUN-REPORT assembly, walk preparation, publish mechanics).

- **GATE-15 — agent report hand-back**: every `runs/<id>/reports/*.md` and every delegate report `runs/<id>/orch/<role>-<n>.md` opens with `## hand-back` (≤20 lines and ≤2,000 bytes, no paste; `verdict:` · `ids:` · `pointers:` · `parked:`, values read) and **the hand-back must agree with the rows beneath it** — every id the body defines is in `ids:`, a FAIL grade or a FAILED/BLOCKED/PARKED row is named in `verdict:`; in every sweep (and from the archive at `--p5`), and every agent's self-check (`gate-15 --paths`).
- **`sweep --summary`**: PASS/FAIL and subject lines only; the failure list goes to a log whose path is the triage delegate's manifest — the ORCH never has to read it.
- **`## resume` in HANDOFF, written before every delegation batch**, with `clears: <n>` (forced restarts inside a phase — a planned phase-entry session is not a clear) — a fresh ORCH re-dispatches from the record without opening a report. **AT-6**: clears >2 this run is an audit trigger — a self-reported symptom counter, read inside `## resume` and from the RUN-REPORT row once recorded — whose hit is a framework finding naming the step that was not delegated; status.mjs says UNRECORDED rather than 0, and GATE-7 refuses a publish whose RUN-REPORT records fewer trigger rows than there are triggers.
- Executors and verifiers gain the hand-back and (verifier) grading the executor's hand-back against its rows; delegates have a `[AGENT] — delegate` section and a file; ORCH-owned files stay ORCH-accountable when a delegate writes them (FORMATS §9).
- **Reviewed before publish, twice** (R13): an adversarial review (ADV-R13, 13 findings, all confirmed) and a developer-persona upgrade walk on a real v0.7.5 fixture (DEV-R13, 21 findings) both said "not as-is" — the one section the ORCH now routes on was the one section no gate read against anything; every blocking and major finding was remediated in-round with its own test and mutation proof (docs/reviews/).

### Part 1 — the defect-and-process release

**Both pilots filed 50 findings against v0.7.4 inside two weeks (platform F-82…F-105, prodsim F-89…F-114); the PO took the whole slate in one release.** Engine and formats first, process text with it; the reduction round moves to v0.7.6.

- **Consumer-visible regressions closed**: the wiring test's F-78 fix had landed only on the package self-test branch — every consumer with a standing red gate was still told all six sweep gates were unwired (platform/F-82; one probe now, both branches, plus a guard that no test pipes `gates.sh sweep`). GATE-7's shorthand `CV-<nn>` match is a whole-token match (prodsim/F-89 — five recurrences), resolves shorthands to the run's full ids and honours an evidenced in-run discharge (F-102). `requirements: none` declares the EMPTY set instead of falling back to the text scan (platform/F-100, prodsim/F-90). GATE-9 counts amendment RECORD lines, not tokens — a plan citing its spec's AM-29 no longer has to start at AM-30 (platform/F-103, prodsim/F-106). GATE-13 lints the rows an amendment adds to a signed plan (prodsim/F-107). `gate-3 --run` reads the run's findings files, and a flag no gate reads is refused (prodsim/F-94).
- **Vacuity, stated everywhere**: four gates declared a subject label and never emitted it; GATE-4's per-run arm was empty in 14 of 14 pilot runs with nothing saying so; GATE-9's sweep form walks a list and said nothing about its size — all labelled now, and parity fails when a label has no call site (platform/F-83/F-84/F-85).
- **The deriver reads what the ORCH recorded**: heading suffixes and bold cells parse, a bullet section says "present, 0 table rows", an archived run's AT-3/AT-5 are read back instead of printing 0, and the audit-triggers section's own text is never counted as a BLOCKED (platform/F-87/F-88/F-99).
- **New id homes and owners**: `VF-AM<nn>-<nn>` for a plan amendment's delta verifier and `reports/AM-<nn>-verify.md` for its report (platform/F-93/F-95, prodsim/F-105 — one VF id, two findings); `runs/<id>/orch/*` ORCH-owned and declarable as a unit input with a boundary existence check (prodsim/F-108); `dispatched_at_wave:` for a re-dispatched unit (prodsim/F-104); `repairs VF-…` labels a unit's self-repair (platform/F-90).
- **Clauses that point at nothing are refused at G2** (platform/F-97 — 9 of 11 traced plan defects survived every adversarial round, in runs with 5 and 7 rounds; all decidable from the plan text): GATE-8 checks every repo path a task names against the tree, the unit's declarations and the wave order, and every id a clause names against the run's records; `lint-ok` is the escape.
- **Evidence that survives the formatter and the archive**: a `capture: <path>` line binds a fenced paste to its capture and GATE-3 compares them byte for byte after prettier has run (prodsim/F-95/F-96); bare and anchored `ev:file` citations are preflighted, through the archive rewrite (prodsim/F-112); gate rejections log to the common git dir and survive worktree removal (prodsim/F-97); stub age is the directory date (prodsim/F-114); `gates.sh history --run` refuses a rewritten unit branch (prodsim/F-99); `gates.sh verify-cmd` prints the runnable Verify (prodsim/F-111); a ruling attest quotes the question (prodsim/F-110).
- **Process positions the PO took**: a fresh-context verifier classifies ORCH bookkeeping and the PO may overrule by row — never asked per item (platform/F-96, prodsim/F-103, `orch_classification`); AT-1 is stand-ins for real systems, AT-2 is one cycle per trigger with a runnable citation (prodsim/F-100, platform/F-101 + prodsim/F-91); the P1 premise check asks for the weakest passing implementation (prodsim/F-92); P2 preflights live-leg designs (prodsim/F-109) and loads the prior run's VF/CV (platform/F-104); P3 re-runs cited AC checks on the `int` tip before the RUN-REPORT commit (prodsim/F-93); a `resolved-in-run` walk class that must cite (platform/F-98).
- **Package integrity made visible** (platform/F-92): an ownership list may not match its own home (parity), and `install.sh` writes a sha256 manifest of package-owned files that parity compares — advisory by default.
- **Reviewed before publish, twice** (R12): an adversarial review (ADV-R12, 16 confirmed) and a developer-persona upgrade walk on a real v0.7.4 fixture (DEV-R12, 23 findings) both said "not as-is"; three of the round's own fixes had failed inside their defect class, and every blocking and major finding was remediated in-round with its own test and mutation proof (docs/reviews/).

## What's new in v0.7.4-draft

**Both pilots upgraded to v0.7.3 (intake-coupling held) and filed 23 findings inside a week — a defect release now, the reduction round moves to v0.7.5.**

- **Publish path** (platform/F-77 + prodsim/F-88, hit independently): at `--p5` GATE-7 grades the run named by `--run` from `runs/archive/` — step 3 archives, step 6 names it, and the phase's own documented command no longer fails after every irreversible step. Registry citations to GC-deleted proofs refuse publish (platform/F-80); P5 step 4 excludes cited files from the candidate set, and dead citations are repaired by first asking whether the target moved or died (F-81).
- **macOS first contact** (prodsim/F-78/F-81/F-82): no heredoc inside `$( )` — `install.sh` parses under stock bash 3.2, as INSTALL.md always promised; the gate-11 config read uses the literal config path (symlinked `/tmp` no longer empties the exclude list and fails the freeze closed with a misdirecting hint), and a failed read is loud.
- **Five engine defects with measured harm**: the doc-wide backtick mask's `+`→`*` (one empty span un-masked the rest of the document, platform/F-75); GATE-9's drift check is per-modification, not a one-time toll (F-71); the wiring test no longer reports every gate unwired whenever one is red (F-78); the escrow discovers deferrals on fence-stripped text and names the file it read (a phantom `32:` over real debt, prodsim/F-87); truncated lists state their count (F-79).
- **Three process structures** (PO decision): the debug lane's PO decision surface (`runs/debug/classification-request.md`, ORCH-proposed classification, F-80); the P4 walk artifact + "batch, don't raise" rule with a G4 close check in `gate-2 --close` (F-86); provenance clauses for ORCH-authored amendments in P3 §4 / FORMATS §7 (F-85). Plus reconcile-in-place by spec kind (platform/F-74), `jira.status_conventions` engine-read (F-73), the bare `[T:<run-id>]` trailer bound to phase-artifact homes (F-72), wrapped preamble fields exempt across continuation lines (F-79p), the sweep asserting the hook layer (prodsim/F-77), a repo-owned `status.mjs` extension point (F-84), formatter-safe section guard (F-83), `AT-5` PO rulings read back (F-87e).
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
