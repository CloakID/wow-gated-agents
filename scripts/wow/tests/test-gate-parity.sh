#!/usr/bin/env bash
# Layer-parity negative test (OBL-PKG-08). The parity check exists because
# v0.5.2 shipped GATE-12 on paper only and nothing noticed — and because the
# parity RULE itself then shipped spec-first, unregistered (pilot #2 finding 2).
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "PARITY"

# PF-b's reverse trailer check needs a doc side in the fixture: give it lane
# docs that document every trailer, so the ORIGINAL parity cases still isolate
# their own causes. The reverse direction gets its own cases at the end.
mkdir -p "$FIX/docs/process"
printf 'Lane refs: [T: [Q: [D: [WOW:publish] [WOW:migrate]\n' > "$FIX/docs/process/LANES.md"
printf '## Way of Working\nTrailers: [T: [Q: [D: [WOW:publish] [WOW:migrate]\n' > "$FIX/CLAUDE.md"

spec() { cat > "$FIX/scripts/wow/GATES-SPEC.md"; }
rows_1_12() { for n in $(seq 1 12); do printf '| GATE-%s | check | where | block |\n' "$n"; done; }

# Subject-absent: no spec side at all.
assert_rejects "no GATES-SPEC.md anywhere" "$FIX" "not a pass" parity

# Positive control: table matches the engine registry exactly.
rows_1_12 | spec
assert_accepts "spec table == engine registry" "$FIX" parity

# The founding failure: a spec-only gate with no marker and no obligation.
{ rows_1_12; printf '| GATE-13 | imaginary | nowhere | nothing |\n'; } | spec
assert_rejects "spec-only gate, no marker" "$FIX" "no engine counterpart" parity

# Marked, with the obligation OPEN: legal spec-first change.
mkdir -p "$FIX/docs"
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n| OBL-T-08 | impl_gap | m | advisory | run | lands | ev:commit{abc1234} |\n' > "$FIX/docs/GAPS.md"
{ rows_1_12; printf '| GATE-13 | [DESIGNED-NOT-IMPLEMENTED — OBL-T-08] imaginary | nowhere | nothing |\n'; } | spec
assert_accepts "spec-only gate, marked, obligation open" "$FIX" parity

# Marked, but the obligation is NOT open: a marker pointing at nothing.
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n| ~~OBL-T-08~~ | impl_gap | m | advisory | run | lands | ev:commit{abc1234} |\n' > "$FIX/docs/GAPS.md"
assert_rejects "marker naming a discharged obligation" "$FIX" "decoration" parity

# The other direction: engine gate missing from the spec table.
for n in $(seq 1 11); do printf '| GATE-%s | check | where | block |\n' "$n"; done | spec
assert_rejects "engine gate with no spec row" "$FIX" "declarations of the gate set disagree" parity

# F4: the named-schema half — a schema GATES-SPEC mentions must exist in formats.json.
{ rows_1_12; printf 'The engine also honors the `imaginary_row` schema.\n'; } | spec
assert_rejects "spec names a schema formats.json lacks" "$FIX" "no such key" parity
rows_1_12 | spec

# Version authority: formats.json must equal the CHANGELOG top entry.
rows_1_12 | spec
printf '# Changelog\n\n## v9.9.9 — someday\n- imaginary\n' > "$FIX/CHANGELOG.md"
assert_rejects "formats version != CHANGELOG top" "$FIX" "version authority" parity
FV="$(python3 -c "import json;print(json.load(open('$FIX/scripts/wow/formats.json'))['version'])")"
printf '# Changelog\n\n## v%s — today\n- real\n' "${FV%-draft}" > "$FIX/CHANGELOG.md"
assert_accepts "formats version == CHANGELOG top" "$FIX" parity

# D2: a doc header must equal the version of its last-modifying commit.
mkdir -p "$FIX/docs/process"
printf '# X — DRAFT v0.1.0\nbody\n' > "$FIX/docs/process/X.md"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "v0.2.0: change X [WOW:publish]" )
assert_rejects "stale header vs version-titled commit" "$FIX" "last-modifying commit" parity
( cd "$FIX" && printf '# X — DRAFT v0.2.0\nbody\n' > docs/process/X.md \
  && git add -A >/dev/null && git commit -qm "v0.2.0: fix header [WOW:publish]" )
assert_accepts "header matches its last-modifying commit" "$FIX" parity


# ---- PF-b (pilot #2, v0.6.1): reverse direction for lane refs ---------------
# check_parity only asked "does the engine have what the docs declare?" —
# [WOW:migrate] lived in formats.json/engine/tests and was invisible to an
# operator working from LANES.md or the router.
lanes_full() { printf 'Lane refs: [T: [Q: [D: [WOW:publish] [WOW:migrate]\n' > "$FIX/docs/process/LANES.md"; }
lanes_full
printf '## Way of Working\nTrailers: [T: [Q: [D: [WOW:publish] [WOW:migrate]\n' > "$FIX/CLAUDE.md"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "v0.2.0: lane docs [WOW:publish]" ) >/dev/null 2>&1
assert_accepts "all trailers documented in LANES.md and router (control)" "$FIX" parity

printf 'Lane refs: [T: [Q: [D: [WOW:publish]\n' > "$FIX/docs/process/LANES.md"
assert_rejects "trailer in formats.json but missing from LANES.md" "$FIX" "undocumented in" parity
lanes_full

rm -f "$FIX/CLAUDE.md"
assert_rejects "no router doc at all" "$FIX" "no router doc" parity
printf '## Way of Working\nTrailers: [T: [Q: [D: [WOW:publish] [WOW:migrate]\n' > "$FIX/CLAUDE.md"
assert_accepts "restored (control)" "$FIX" parity
finish
