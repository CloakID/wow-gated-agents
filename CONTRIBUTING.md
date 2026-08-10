# Contributing / giving feedback

This repo is a process design under active review (DRAFT v0.4, pre-pilot). The most valuable contribution right now is **criticism of the design**, especially with field experience behind it.

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
