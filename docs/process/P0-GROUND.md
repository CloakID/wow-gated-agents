# P0 — GROUND — DRAFT v0.4
Entry: `/wow-ground <area>` · Skip: allowed iff map fresh per FORMATS §6 (machine-checked, GATE-6) · Load: `docs/codebase/<area>.md`, `wow.config.json`.

## [ORCH]
1. Run freshness check for the target area(s). Fresh → record `ev:cmd` of the check in the upcoming run's HANDOFF and skip to P1.
2. Stale → delta-update `docs/codebase/<area>.md`: what changed since `verified_against` (read the commits touching `paths`, update map sections, refresh front-matter `verified`/`verified_against`).
3. Capture environment facts relevant to the planned change (versions, cluster/env state, live-config divergences) as `[FACT|ev:…]` entries in the map or the debug lane if anomalous.
4. Commit map update `[WOW:publish]`. No gate — P0 output is consumed by G1/G2 review.

## [PO]
Nothing required. Optional: flag areas you know have drifted.
