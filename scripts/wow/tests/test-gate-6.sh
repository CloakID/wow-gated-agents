#!/usr/bin/env bash
# GATE-6 negative test: a map whose paths have commits since verified_against is
# stale; a missing map with no p0-record is stale; freshness is git-only.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-6"

assert_rejects "no map and no p0-record" "$FIX" "no p0-record" gate-6 --area auth --run 260813-x-r1

mkdir -p "$FIX/runs/260813-x-r1"
printf 'p0-record: auth = not-required\n' > "$FIX/runs/260813-x-r1/HANDOFF.md"
assert_accepts "no map but a p0-record in HANDOFF" "$FIX" gate-6 --area auth --run 260813-x-r1

mkdir -p "$FIX/docs/codebase" "$FIX/src/auth"
BASE="$( cd "$FIX" && git rev-parse HEAD )"
printf -- '---\narea: auth\nverified_against: %s\npaths: ["src/auth/**"]\n---\n# map\n' "$BASE" \
  > "$FIX/docs/codebase/auth.md"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "map [WOW:publish]" )
assert_accepts "map fresh, no commits since verified_against" "$FIX" gate-6 --area auth

printf 'changed\n' > "$FIX/src/auth/thing.txt"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "touch auth [WOW:publish]" )
assert_rejects "map stale, a commit touched its paths" "$FIX" "STALE" gate-6 --area auth

# ---- FORMATS §11: external-dependency maps, probe-hash rule -----------------
mkdir -p "$FIX/docs/deps"
dep() { cat > "$FIX/docs/deps/vendor-api.md"; }

assert_rejects "declared dep with no map" "$FIX" "no dependency map" gate-6 --deps vendor-api

# The probe emits the vendor surface; the gate hashes its stdout.
HASH="$(printf 'surface-v1' | shasum -a 256 | cut -d" " -f1)"

dep <<D
---
dependency: vendor-api
kind: external-api
verified: 2026-08-13
probe: printf 'surface-v1'
verified_against_hash: $HASH
---
# map
D
assert_accepts "probe hash matches recorded hash" "$FIX" gate-6 --deps vendor-api

dep <<D
---
dependency: vendor-api
kind: external-api
verified: 2026-08-13
probe: printf 'surface-v2-vendor-moved'
verified_against_hash: $HASH
---
# map
D
assert_rejects "vendor surface moved, probe hash differs" "$FIX" "STALE" gate-6 --deps vendor-api

dep <<D
---
dependency: vendor-api
kind: external-api
verified: 2026-08-13
probe: printf 'surface-v1'
---
# map
D
assert_rejects "probe defined but no recorded hash" "$FIX" "no verified_against_hash" gate-6 --deps vendor-api

# No probe surface: the calendar fallback is legitimate here precisely because
# git is unavailable for a surface we do not version.
dep <<'D'
---
dependency: vendor-api
kind: external-api
verified: 2020-01-01
max_age_days: 30
---
# map
D
assert_rejects "no probe, verified past max_age_days" "$FIX" "STALE" gate-6 --deps vendor-api

dep <<D
---
dependency: vendor-api
kind: external-api
verified: $(date +%Y-%m-%d)
max_age_days: 30
---
# map
D
assert_accepts "no probe, verified within max_age_days" "$FIX" gate-6 --deps vendor-api

dep <<D
---
dependency: vendor-api
kind: not-a-real-kind
verified: $(date +%Y-%m-%d)
max_age_days: 30
---
# map
D
assert_rejects "kind outside the vocabulary" "$FIX" "is not one of" gate-6 --deps vendor-api

# A unit declaring deps: in PLAN.md is checked without naming them on the CLI.
dep <<D
---
dependency: vendor-api
kind: external-api
verified: 2020-01-01
max_age_days: 30
---
# map
D
mkdir -p "$FIX/runs/260814-x-r1"
printf 'spec: s.md\n\n### U1 — a\nowns:\n- src/a\ndeps:\n- vendor-api\ntier: mid\nwave: 1\nautonomy: x\n' \
  > "$FIX/runs/260814-x-r1/PLAN.md"
assert_rejects "plan-declared dep is stale" "$FIX" "STALE" gate-6 --run 260814-x-r1
finish
