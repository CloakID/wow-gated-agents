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

# The hash-rule fixtures below use bare printf probes; the default allowlist
# (repo-local scripts only, S-2) would refuse them before execution, so the
# fixture exercises the wow.config.json override — the same repo-local-truth
# path a real repo uses to name its request wrapper.
printf '{"migrated_from_gsd": false, "probe_command_pattern": "^printf "}\n' \
  > "$FIX/scripts/wow/wow.config.json"

# The probe emits the vendor surface; the gate hashes its stdout.
# Portable sha256: coreutils ships sha256sum, macOS ships shasum, and python3 is
# a prerequisite anyway. Hardcoding one of them made the suite OS-specific.
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d" " -f1
  elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 | cut -d" " -f1
  else python3 -c "import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())"
  fi
}
HASH="$(printf 'surface-v1' | sha256)"

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

# ---- FORMATS §6 plan linkage: the areas half needs a machine input ----------
# The premise check: GATE-6(a) used to run only when the operator remembered
# --area, and no playbook, command stub or hook ever passed it. A plan that
# declares no areas: gave the gate nothing to check, and it said PASS.
mkdir -p "$FIX/runs/260815-x-r1"
printf 'spec: s.md\n\n## Units\n\n### U1 — a\nowns:\n- src/a\ntier: mid\nwave: 1\nautonomy: x\n' \
  > "$FIX/runs/260815-x-r1/PLAN.md"
assert_rejects "plan declares no areas: for GATE-6(a) to check" "$FIX" "declares no 'areas:'" \
  gate-6 --run 260815-x-r1

printf 'spec: s.md\n\n## Units\n\n### U1 — a\nowns:\n- src/a\nareas:\n- auth\ntier: mid\nwave: 1\nautonomy: x\n' \
  > "$FIX/runs/260815-x-r1/PLAN.md"
# re-verify the map against the commit that made it stale, as P0 would
NOW="$( cd "$FIX" && git rev-parse HEAD )"
printf -- '---\narea: auth\nverified_against: %s\npaths: ["src/auth/**"]\n---\n# map\n' "$NOW" \
  > "$FIX/docs/codebase/auth.md"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "re-verify map [WOW:publish]" )
assert_accepts "plan-declared area resolves to a fresh map" "$FIX" gate-6 --run 260815-x-r1

printf 'changed again\n' > "$FIX/src/auth/thing.txt"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "touch auth again [WOW:publish]" )
assert_rejects "plan-declared area is stale" "$FIX" "STALE" gate-6 --run 260815-x-r1

assert_rejects "invoked with no scope at all" "$FIX" "nothing to check" gate-6

# ---- OBL-PKG-02 / PF-04: subject-absent is never a pass ---------------------
# gate-6 --run returned PASS for a run with no PLAN.md: zero parsed units
# skipped the no-areas branch. "A gate invoked with no scope is not a pass"
# already existed one branch earlier; these prove the same holds when the scope
# resolves to nothing.

assert_rejects "run id that does not exist (subject-absent)" "$FIX" "not a pass" \
  gate-6 --run 260101-no-such-run-r1

mkdir -p "$FIX/runs/260816-empty-r1"
assert_rejects "run dir exists but has no PLAN.md (subject-absent)" "$FIX" "not a pass" \
  gate-6 --run 260816-empty-r1

printf '# a plan the schema cannot read\nfree prose, no unit headings\n' \
  > "$FIX/runs/260816-empty-r1/PLAN.md"
assert_rejects "PLAN.md whose headings do not match the schema (unparseable = absent)" "$FIX" \
  "parses into no units" gate-6 --run 260816-empty-r1

# Positive control: a well-formed plan declaring areas over a fresh map still
# passes — "the gate now refuses everything" is ruled out.
mkdir -p "$FIX/runs/260816-good-r1" "$FIX/src/auth"
BASE2="$( cd "$FIX" && git rev-parse HEAD )"
printf -- '---\narea: auth\nverified_against: %s\npaths: ["src/auth/**"]\n---\n# map\n' "$BASE2" \
  > "$FIX/docs/codebase/auth.md"
cat > "$FIX/runs/260816-good-r1/PLAN.md" <<'P'
# PLAN — 260816-good-r1
spec: docs/spec/SPEC-x-v1.md

## Units

### U1 — only
owns:
- src/auth/a.py
tier: mid
wave: 1
autonomy: decide-and-log
areas:
- auth

| Task | Action | Verify | Done-means |
|---|---|---|---|
| 260816-good-r1.T01 | do a | `true` | done |

## Coverage matrix

| AC | Tasks |
|---|---|
| AC-1 | 260816-good-r1.T01 |
P
( cd "$FIX" && git add -A >/dev/null && git commit -qm "good plan [T:260816-good-r1.T01]" ) >/dev/null 2>&1 || \
( cd "$FIX" && git add -A >/dev/null && git commit -qm "good plan [WOW:publish]" )
assert_accepts "well-formed plan declaring areas over a fresh map (positive control)" "$FIX" \
  gate-6 --run 260816-good-r1



# ---- S-2 (v0.6.2): the probe is allowlisted BEFORE it runs ------------------
# The pilot's demonstration: a probe that wrote a marker file ran, and the gate
# passed. The half of this test with teeth is that the marker DOES NOT EXIST —
# a gate that rejects the map after running the command has prevented nothing.
printf '{"migrated_from_gsd": false}\n' > "$FIX/scripts/wow/wow.config.json"
dep <<D
---
dependency: vendor-api
kind: external-api
verified: 2026-08-13
probe: touch S-2-marker && printf 'surface-v1'
verified_against_hash: $HASH
---
# map
D
assert_rejects "probe outside the allowed pattern is refused (S-2)" "$FIX" "outside the allowed command pattern" gate-6 --deps vendor-api
if [ -e "$FIX/S-2-marker" ]; then
  echo "  FAIL the disallowed probe RAN (marker exists) — refusing after execution prevents nothing"
  FAIL=$((FAIL+1))
else
  echo "  ok   disallowed probe never executed (no marker)"; PASS=$((PASS+1))
fi

# Control: a probe matching the default allowlist (a repo-local script) runs.
cat > "$FIX/scripts/probe-vendor.sh" <<'S'
#!/bin/sh
printf 'surface-v1'
S
chmod +x "$FIX/scripts/probe-vendor.sh"
dep <<D
---
dependency: vendor-api
kind: external-api
verified: 2026-08-13
probe: scripts/probe-vendor.sh
verified_against_hash: $HASH
---
# map
D
assert_accepts "allowlisted repo-local probe runs and matches (control)" "$FIX" gate-6 --deps vendor-api
finish
