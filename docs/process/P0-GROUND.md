# P0 — GROUND — DRAFT v0.5.0
Entry: `/wow-ground <area|dep>` · Skip: allowed iff maps fresh per FORMATS §6 (codebase, git-checked) and §11 (external deps, probe-checked) — both via GATE-6 · Load: `docs/codebase/<area>.md`, `docs/deps/<name>.md` for declared deps, `wow.config.json`.

## [ORCH]
1. Run the freshness check for the target area(s) and dependencies:

   ```sh
   scripts/wow/gates.sh gate-6 --area <area>          # codebase map, git rule (FORMATS §6)
   scripts/wow/gates.sh gate-6 --deps <name> [...]    # external dep maps, probe rule (FORMATS §11)
   ```

   Fresh → record `ev:cmd` of the check in the upcoming run's HANDOFF and skip to P1. No map for the area yet → record the outcome in HANDOFF as `p0-record: <area> = fresh | not-required | updated` (FORMATS §6), which is what GATE-6 honours in place of a map.
2. Stale → delta-update `docs/codebase/<area>.md`: what changed since `verified_against` (read the commits touching `paths`, update map sections, refresh front-matter `verified`/`verified_against`).
3. **External dependencies (FORMATS §11):** re-run each declared dep's probe. Hash unchanged → record `ev:cmd`, fresh. Hash changed → diff the vendor surface (spec/changelog) against the map's capability claims, update the map, refresh `verified`/`verified_against_hash`. No probe defined → if past `max_age_days`, re-verify claims manually and reset `verified`.
4. Capture environment facts relevant to the planned change (versions, cluster/env state, live-config divergences) as `[FACT|ev:…]` entries in the map or the debug lane if anomalous.
5. Commit map updates `[WOW:publish]`. No gate — P0 output is consumed by G1/G2 review.

## [PO]
Nothing required. Optional: flag areas you know have drifted.
