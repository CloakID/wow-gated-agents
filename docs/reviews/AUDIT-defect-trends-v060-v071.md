# AUDIT — defect trends & fix quality, v0.6.0 → v0.7.1-draft (pre-push)

Scope: every change from v0.6.0-draft (80f650d) through the uncommitted-to-origin v0.7.1-draft (device e76d5b6). Question set (PO, 2026-09-13): defect trends with conceptual/structural implications · short-term reactive fixes · RCA due but shortcut taken · inference without supporting data. Method: git history + CHANGELOG per release, grep-verified code sites, registry state. Every claim below is cited or labeled INFERENCE. This audit found **four defects in v0.7.1 itself**, listed in §6 — the release is *not* clean as staged.

## 1. The raw trend data

| release | findings absorbed | gates.py LOC | formats.json LOC | assertions |
|---|---|---|---|---|
| v0.6.0 | (review round FR/PR) | 1510 | 723 | 140 |
| v0.6.1 | 4 (PF-a..d) | 1600 | 738 | 165 |
| v0.6.2 | 7 | 1778 | 782 | 193 |
| v0.6.3 | 23 | 1988 | 799 | 223 |
| v0.6.4 | 11 | 2146 | 852 | 247 |
| v0.7.0 | 0 new (discharge) | 2199 | 854 | 255 |
| v0.7.1 | 8 live (+3 pre-fixed) | 2303 | 860 | 275 |

gates.py grew **+52%** in seven releases, all in one file, all hand-rolled parsers and per-gate logic. Assertions grew proportionally (140→275), so test discipline held — but tests grew by *instance*, mirroring the instance-level fixing pattern below.

## 2. Defect families and their recurrence (the trend that matters)

**Family A — malformed/empty input handled permissively.** Founding rule v0.5.3 (subject-absent). Recurred in *every* release since: PF-d (v0.6.1), F-12/F-13/F-14 (v0.6.3), F-36 + GATE-2 scan adoption (v0.6.4), escrow substring-match (v0.7.0), F-44 silent truncation (v0.7.1). Seven rounds, ~10 instances. The class-level *test* rule exists (two negative tests per gate); the class-level *code* rule does not: every parser is hand-rolled and permissive by default, so each new parser re-imports the defect. **Structural.**

**Family B — mention-vs-claim surface gaps.** PF-a (v0.6.1, inline code) · F-05 (v0.6.3, doc-wide spans) · F-07 (v0.6.3, trailers) · F-32 (v0.6.4, bare ids — the inverse) · F-41 (v0.7.1, table cells). Five rounds, five surfaces. Grep-verified: the rule now lives in **six distinct code sites** with different mechanics (gates.py 243–252 GATE-1's own fence scan; 494 `_mask_inline_code`; 504 `_mask_inline_code_doc`; 636 F-41 cell special-case; 741/1195 gap-row backtick rule; 1459 escrow handling). Each pilot round finds the next surface that lacked it. **Structural: the rule is a cross-cutting concern implemented per-surface; there is no single masking layer every scan passes through.**

**Family C — the same grammar spelled twice.** PF-b (v0.6.1, reverse trailer parity) · F-35 (v0.6.4, dialect divergence between the two engines) · F-46/F-39 (v0.7.1, run-id spelled 4×+). v0.7.1's templating genuinely closes the *expansion* class — and the mutation run proved its value immediately (mutation 4 exposed the task tail still spelled twice; fixed to `{task_tail}`). But see §6: v0.7.1 itself added two NEW inline restatements. The guard for this family (parity named-key completeness, OBL-PKG-17) has been **open since 2026-08-18 and deferred through five releases** while the number of named keys kept growing. **Structural, and the guard debt is aging faster than the guard.**

**Family D — diagnostics that name the wrong cause.** F-19 residual (v0.6.3) · F-18 wrong cell blamed (v0.6.4) · installer KeyError wearing a registry error (v0.6.4) · F-46 "no lane reference" about a reference the operator wrote (v0.7.1). Every instance was fixed *after* a pilot paid the misdiagnosis cost (F-46: "a full cycle"). No proactive pass over error paths has ever been done; diagnostics are patched one complaint at a time. **Reactive by structure.**

**Family E — process rule ahead of enforcement.** The layer-parity rule exists precisely for this, and it mostly worked: F-25 walker → OBL-PKG-18, F-43 engine half → OBL-PKG-19 (registered correctly this round). But the mechanical parity check covers gate IDs and schema-family names only — config keys and prose-consumed conventions pass beneath it. That is exactly where v0.7.1's F-42 slipped through (§6.2).

## 3. Conceptual/structural challenges the trends point at

1. **Per-surface patching of cross-cutting rules** (Families A, B). The framework's own founding insight — "prose rules fail; mechanical gates work" — has a code-level analogue it hasn't applied to itself: *per-parser conventions fail; shared parse layers work*. A single strict table-parse routine (header-resolve, cell-count-exact, mention-mask, then hand rows to the gate) would have prevented F-13, F-14, F-18, F-32, F-41, F-44 and the latent instance in §6.4 by construction. Instead each was an individual fix with an individual test.
2. **The engine is a 2,300-line accreting monolith.** Not yet a correctness problem (mutation discipline is holding), but the F-18→F-44 pair (§4) is what accretion produces: the same defect in two parsers, fixed twice, two rounds apart, by the same maintainer.
3. **The registry ages silently.** 6 of 11 open rows predate v0.6.0; four name `engine-v0.5.x run` as successor — an event four versions past; OBL-PKG-15/17 name "engine round 3" (two rounds ago). Successor columns have quietly become fiction and nothing checks them — the exact drift class (stale narrative state) the framework was built to kill, in its own registry. Quick-stub staleness is checked; obligation staleness is not.
4. **The feedback loop optimizes for round-trip speed over class closure.** 49 findings absorbed in 5 rounds, typically within days — genuinely good — but the closure question asked each time was "is this finding fixed?" not "is this finding's *family* closed everywhere it can occur?" §4 and §5 are the bill for that.

## 4. Reactive fixes (instance fixed, class left open) — the concrete list

- **F-18 (v0.6.4) → F-44 (v0.7.1): the same defect, fixed twice.** Unescaped `|` silently corrupting a hand-parsed table row: fixed for plan rows in v0.6.4, then again for gap rows in v0.7.1. An RCA at F-18 time ("which other parsers share this?") would have found the gap-row parser — and §6.4's still-latent site — in August. This is the cleanest evidence in the audit that instance-fixing is the operating mode.
- **F-41 (v0.7.1):** a sixth mention-vs-claim site added instead of consolidating the masking layer. Correct behavior, structural debt +1.
- **F-40 (v0.7.1):** metric renamed and derivation documented — but the derivation is prose the ORCH attests; nothing verifies AT-1 against `git diff --diff-filter=A`. Defensible (orch-derived by design) but it is a trust-me metric feeding an audit trigger.
- **F-18 addendum (v0.7.1):** honest-comment-only. Appropriate in isolation — but note the pattern: both F-18-family resolutions are "make the comment honest" rather than any capability narrowing. Fine as an explicit trust-model statement; worth noticing that the deny-list's real value is now purely declarative.
- **Diagnostics fixes generally (Family D):** each is a point patch on the message that a pilot happened to hit.

## 5. RCA due, shortcut taken

1. **The meta-finding got no RCA — and it is the most important finding of the round.** "Pilots never upgraded; three findings were fixed before they were written" was recorded and a recommendation issued ("upgrading is the highest-value action") with **zero analysis of why pilots don't upgrade**. INFERENCE (plausible causes, no data): (a) nothing in a pilot's daily loop ever tells them a newer version exists — no staleness signal in status.mjs or the hooks; (b) the FR-1 contract means upgrading a repo with many artifacts produces immediate loud red, and v0.7.0 *closed OBL-PKG-14 by refusing migration recipes* — the policy may be causally connected to the avoidance it now suffers from; (c) upgrade requires a manual clone-and-run of install.sh from the package repo. Each is checkable by asking two pilots one question. Recommending "just upgrade" without this analysis is treating the symptom.
2. **OBL-PKG-13's discharge applied status-by-header to gate-3 but not to the escrow's own walk** — the escrow still reads status **positionally** (`cells[1]`, gates.py 1538). The discharge criterion said "locates status by COLUMN HEADER not position"; the component the obligation was *about* got the rule, the sibling walk in the same function family did not. Shortcut inside a discharged blocking obligation.
3. **Slug cap 48 is a judgment presented with a rationale it doesn't have data for.** The finding showed one 27-char slug; 48 was chosen as a doubling. The formats.json comment argues "descriptive slugs are what the process asks for" — no slug-length distribution from either pilot was collected (both repos' runs/ trees would give it in one command). The cap is fine as a PO decision; the comment reads as derived when it is chosen.
4. **GATE-8's F-39 check has a known, unrecorded blind spot.** Row admission requires a *valid* task id somewhere on the line, so a malformed id that contains no valid substring (e.g. `T7`) in a unit with valid sibling rows is invisible to the new check — it neither fails F-39 nor F-13. I knew this at implementation time and recorded it nowhere. GATE-1 catches it later at commit time (wrong phase — exactly what F-39 complained about). Should be a recorded residual.
5. **Verification against real pilot artifacts regressed this round.** v0.7.0's discharge was "proven against frisbii's actual RUN-REPORT: 0→8 findings." v0.7.1's fixes were verified against engine-side reproductions and synthetic fixtures only (session had findings files, not the pilot repos). Structural excuse exists; the release notes don't say it.

## 6. Defects in v0.7.1 itself, found by this audit

1. **Two new inline restatements of the run-id grammar — in the release whose headline is "the run id has ONE definition."** Grep-verified: gates.py 271 (GATE-1 diagnosis) and 2280 (check-id) both hardcode `^[0-9]{6}-(...)-r[0-9]+`, and 271 additionally hardcodes the cap ("cap 48") in its message while the check uses a literal `> 48`. If run_core's shape or cap changes, the diagnostic lies — Family D seeded by a Family C violation, by me, this week. v0.7.0 had one such literal; v0.7.1 has three.
2. **F-42 `jira.scope` violates the layer-parity rule's spirit with no covering obligation.** Grep-verified: zero consumers in gates.py, status.mjs, or formats.json. The docs say "ANDed into every query the mapping runs" — the consumer is ORCH prose only. Under the v0.5.3 rule, a doc naming machine-shaped configuration with no engine counterpart carries a paired obligation; it slipped through because the mechanical parity check doesn't cover config keys. Either FORMATS §10 must say "convention, ORCH-enforced, not gated" explicitly, or an obligation row is owed.
3. **The F-43 doc text overclaims.** "A paste is exactly what a fabricator cannot produce consistently" — false for the threat actor this rule exists for: an LLM executor fabricates plausible output cheaply. The defensible claim is that pasting raises fabrication effort and gives the verifier a *diffable artifact* for the re-run. As written it invites false confidence in exactly the reports it was meant to make checkable. Same class: "T13b/T07a already in pilots' archives" (formats.json comment) is relayed from the F-39 report, not independently verified; "a gate that cries stale gets its P0 skipped" (F-45 rationale) is a behavioral inference borrowed from GATE-3's origin story, stated as fact.
4. **Latent Family-A/F-44-class instance left live:** the escrow DEFERRED walk (§5.2) — positional status read plus no cell-count guard, in the registry-reading path hardened one release ago.

## 7. What held up well (for balance, and because it's also data)

Mutation discipline: 8/8 mutations killed by exactly their own tests this round, and mutation 4 caught a real restatement before ship — the practice is doing structural work, not ceremony. The obligation mechanism worked where it was pointed (F-43 → OBL-PKG-19 registered, not silently deferred). The decision protocol (options + consequences → PO) was followed on both forks. And the single-source templating is a genuine class closure for the expansion case — the criticism in §6.1 is that its *perimeter* (inline literals) is unguarded, not that the mechanism is wrong.

## 8. Recommended actions (each ≈ effort-tagged; PO decides what folds into v0.7.1 vs. registers)

| # | action | effort | closes |
|---|---|---|---|
| A1 | Derive GATE-1-diagnosis + check-id regexes/cap from `ids.run_core` instead of literals | small | §6.1 |
| A2 | FORMATS §10 + INSTALL: mark `jira.scope` "convention, ORCH-consumed, not gated" (or register OBL row) | tiny | §6.2 |
| A3 | Soften F-43 wording (paste = diffable artifact for the re-run, not fabrication-proof); mark the two relayed claims as pilot-reported | tiny | §6.3 |
| A4 | Register OBL-PKG-20: shared strict table-parse layer (one routine: header-resolve, exact cell count, mention mask) — the Family A+B class closure; fold escrow positional walk + GATE-8 blind spot into its row as named instances | tiny now, medium later | §3.1, §5.2, §5.4, §6.4 |
| A5 | Register OBL-PKG-21: registry staleness — successor columns checked against the release that name them (or renamed to real successors); sweep candidate | tiny now, small later | §3.3 |
| A6 | Pilot-upgrade RCA: one question to each pilot (why not upgraded), plus a cheap staleness signal (status.mjs prints installed-vs-package version when run in the package clone context) — before treating "upgrade" as the standing recommendation | small | §5.1 |
| A7 | Release-note honesty: v0.7.1 CHANGELOG states fixes verified against reproductions, not pilot repos | tiny | §5.5 |
