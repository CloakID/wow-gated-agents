# Contributing / giving feedback

This repo is a process design under active review (DRAFT — version per CHANGELOG top entry). The most valuable contribution right now is **criticism of the design**, especially with field experience behind it.

## Release quality — the audit loop (maintainers) — added v0.7.1, PO decision 2026-09-13

The repo audits its own defect **trends**, not just its defects: a monthly trend audit (first: [docs/reviews/AUDIT-defect-trends-v060-v071.md](docs/reviews/AUDIT-defect-trends-v060-v071.md)) is filed in `docs/reviews/` and tracked as an open obligation (OBL-PKG-22). Each audit re-measures the defect families against the last one, so a family that keeps recurring is a structural verdict, not an anecdote.

**Weak points checked at every release** — these are the families the v0.6.0→v0.7.1 audit found recurring, and each is a bias to check the release against before it ships:

| family | release check |
|---|---|
| permissive parsing (F-13/F-18/F-32/F-41/F-44 class) | any NEW parser or scan reads through the shared discipline (`_table_scan`), or its row in OBL-PKG-20 says why not |
| mention-vs-claim surface gaps | any NEW scanned surface states where its mention mask comes from |
| grammar restatement | no new inline pattern/path/vocab literals in either engine (the OBL-PKG-17 scan when it lands; grep + review until then) |
| wrong-cause diagnostics | every new refusal message was read against the fixture that triggers it: does it name the operator's actual mistake? |
| spec-ahead-of-engine | every doc-named machine behavior has an engine counterpart or a registered obligation — including config keys and conventions, which the parity sweep cannot see (the F-42 hole) |

**Two rules that exist because the audit caught their absence:**

1. **The class question is part of every fix.** A finding's CHANGELOG entry states whether the fix is an *instance* fix or a *class* closure, and names the family. "Is this finding's family closed everywhere it can occur?" is asked in writing — F-18 and F-44 were the same defect fixed twice, two rounds apart, because nobody asked it the first time.
2. **Recommendations require RCA or a labeled INFERENCE.** Any recommendation aimed at consumers ("pilots should upgrade") ships with the root-cause analysis behind it, or is labeled INFERENCE together with the data that would settle it. And every release states what its fixes were **proven against** (pilot artifacts vs reproductions vs fixtures) — the verification-honesty line.

Structural feedback from audits (the per-surface-patching pattern, engine accretion, registry self-staleness) feeds the design directly — treat the audit's §3 as standing input to any substantive process change proposed below.

## Where feedback helps most

The six open questions at the end of [DESIGN-RATIONALE.md](DESIGN-RATIONALE.md): park-don't-ask vs mid-run checkpoints · the orchestrator-only sequential merge model · the 50% cascade-termination threshold · the git/tracker divergence-as-signal split · audit-trigger denominators · whether the entry-reliability model needs the optional blocking hook.

Also welcome: reports from your own agent-workflow deployments that confirm or contradict the evidence patterns (E-1…E-7); holes in the gate set (a rule that matters but isn't mechanizable as specified); simplifications — anything here that fails its own value test.

## How

- **Issues** for specific defects or challenges (one issue per point; reference file + section).
- **Discussions** for experience reports and design debate.
- **PRs**: fine for wording/consistency fixes anytime. For substantive process changes, open an issue first — process changes here follow the repo's own rule: if it matters, it needs a gate or an explicit "judgment, not gate" classification, and a stated failure mode it addresses.

## Conventions

Keep the audience labels (`[PO]`/`[ORCH]`/`[AGENT]`) intact in playbook edits. `FORMATS.md` defers to `formats.json` — propose format changes against both. Evidence over opinion where possible: the repo exists because "sounds right" lost to field data repeatedly.

MIT licensed; contributions are accepted under the same license.
