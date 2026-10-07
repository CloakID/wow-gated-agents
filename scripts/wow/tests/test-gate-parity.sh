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
rows_1_12() { for n in $(seq 1 15); do printf '| GATE-%s | check | where | block |\n' "$n"; done; }  # through 15 since v0.7.5.1

# Subject-absent: no spec side at all.
assert_rejects "no GATES-SPEC.md anywhere" "$FIX" "not a pass" parity

# Positive control: table matches the engine registry exactly.
rows_1_12 | spec
assert_accepts "spec table == engine registry" "$FIX" parity

# The founding failure: a spec-only gate with no marker and no obligation.
{ rows_1_12; printf '| GATE-16 | imaginary | nowhere | nothing |\n'; } | spec
assert_rejects "spec-only gate, no marker" "$FIX" "no engine counterpart" parity

# Marked, with the obligation OPEN: legal spec-first change.
mkdir -p "$FIX/docs"
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n| OBL-T-08 | impl_gap | m | advisory | run | lands | ev:commit{abc1234} |\n' > "$FIX/docs/GAPS.md"
{ rows_1_12; printf '| GATE-16 | [DESIGNED-NOT-IMPLEMENTED — OBL-T-08] imaginary | nowhere | nothing |\n'; } | spec
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

# ---- F-35 (v0.6.4): the machine home refuses non-portable regex escapes -----
python3 - "$FIX" <<'PY'
import json, sys
p = sys.argv[1] + '/scripts/wow/formats.json'
F = json.load(open(p))
F['runs_layout']['bad_key_for_test'] = 'x\\Zy'
json.dump(F, open(p, 'w'))
PY
assert_rejects "backslash-Z in a shared key: two engines, two dialects (F-35)" "$FIX" \
  "not portable" parity
python3 - "$FIX" <<'PY'
import json, sys
p = sys.argv[1] + '/scripts/wow/formats.json'
F = json.load(open(p))
del F['runs_layout']['bad_key_for_test']
json.dump(F, open(p, 'w'))
PY
assert_accepts "portable subset restored (control)" "$FIX" parity

# ---- OBL-PKG-21 (audit A5): successor staleness — a version stamp pointing
# backward. Four real rows aged this way across four versions before the
# 2026-09-13 audit caught them; the registry checked quick-stub staleness and
# never its own.
printf '# Changelog\n\n## v0.7.1-draft — x\n' > "$FIX/CHANGELOG.md"
python3 - "$FIX" <<'PY'
import json, sys
p = sys.argv[1] + '/scripts/wow/formats.json'
F = json.load(open(p)); F['version'] = '0.7.1-draft'
json.dump(F, open(p, 'w'))
PY
gaps21() { printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n%s\n' "$1" > "$FIX/docs/GAPS.md"; }
gaps21 '| OBL-T-21 | impl_gap | m | advisory | engine-v0.5.x run | lands | ev:commit{abc1234} |'
assert_rejects "open row whose successor names a shipped version (OBL-PKG-21)" "$FIX" \
  "the successor is fiction" parity
# Controls, each ruling out a way the check could cheat:
gaps21 '| OBL-T-21 | impl_gap | m | advisory | v0.9 release | lands | ev:commit{abc1234} |'
assert_accepts "successor naming a FUTURE version is a real successor" "$FIX" parity
gaps21 '| ~~OBL-T-21~~ | impl_gap | m | advisory | engine-v0.5.x run | lands | ev:commit{abc1234} |'
assert_accepts "discharged row keeps its historical successor untouched" "$FIX" parity
gaps21 '| OBL-T-21 | impl_gap | m | advisory | engine round 7 (was `engine-v0.5.x`) | lands | ev:commit{abc1234} |'
assert_accepts "backticked old version is a MENTION of history, not a claim" "$FIX" parity
# ---- platform/F-76 (v0.7.4): ids_expanded is generated and must not drift --
FIXX="$(setup_fixture_repo)"
rows_1_12 > "$FIXX/scripts/wow/GATES-SPEC.md"
python3 - "$FIXX/scripts/wow/formats.json" <<'PY'
import json, sys
p = sys.argv[1]; s = open(p).read()
import re
i = s.index('"ids_expanded": {')
m = re.compile(r'"run": "[^"]*"').search(s, i)
s = s[:m.start()] + '"run": "^stale$"' + s[m.end():]
open(p, 'w').write(s)
json.load(open(p))
PY
assert_rejects "a stale ids_expanded entry fails parity (platform/F-76)" "$FIXX" \
  "ids_expanded.run is stale" parity
# ---- platform/F-83 (v0.7.5): a subject label is a promise the engine keeps
FIX83="$(setup_fixture_repo)"
rows_1_12 > "$FIX83/scripts/wow/GATES-SPEC.md"
mkdir -p "$FIX83/docs/process"
printf 'Lane refs: [T: [Q: [D: [WOW:publish] [WOW:migrate]\n' > "$FIX83/docs/process/LANES.md"
printf '## Way of Working\nTrailers: [T: [Q: [D: [WOW:publish] [WOW:migrate]\n' > "$FIX83/CLAUDE.md"
python3 - "$FIX83/scripts/wow/formats.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); s = open(p).read()
s = s.replace('"GATE-1": {', '"GATE-1": {"subject": "commit(s)", ', 1)
open(p, 'w').write(s); json.load(open(p))
PY
assert_rejects "a label with no _subject_note call site fails parity and NAMES the gate (platform/F-83)" "$FIX83" \
  "GATE-1 declares a subject label" parity
cp "$WOW_DIR/formats.json" "$FIX83/scripts/wow/formats.json"
sed -i 's/_subject_note("GATE-3", scanned)/[]/' "$FIX83/scripts/wow/gates.py"
assert_rejects "a call site removed from a labelled gate fails parity and names GATE-3 (F-83)" "$FIX83" \
  "GATE-3 declares a subject label" parity
cp "$WOW_DIR/gates.py" "$FIX83/scripts/wow/gates.py"
assert_accepts "registry and call sites agree (F-83 control)" "$FIX83" parity
# ---- v0.7.5.1: a registry row that says "sweep" runs in a sweep list, and vice versa
python3 - "$FIX83/scripts/wow/formats.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["sweep"]["always"] = [g for g in d["sweep"]["always"] if g != "gate-15"]
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PY
assert_rejects "a sweep-'where' gate missing from sweep.always fails parity and names it (v0.7.5.1)" "$FIX83" \
  "GATE-15 says \`where: sweep + agent self-check (--paths)\` in formats.json and is not in sweep.always" parity
python3 - "$FIX83/scripts/wow/formats.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["sweep"]["p5_only"].append("gate-15")
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PY
assert_rejects "a wave-boundary sweep gate parked in p5_only alone is NOT in a sweep list that counts (ADV-R13-08)" "$FIX83" \
  "GATE-15 says \`where: sweep + agent self-check (--paths)\` in formats.json and is not in sweep.always" parity
cp "$WOW_DIR/formats.json" "$FIX83/scripts/wow/formats.json"
python3 - "$FIX83/scripts/wow/formats.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["sweep"]["always"].append("gate-7")
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PY
assert_rejects "a gate in both lists is refused (ADV-R13-08)" "$FIX83" \
  "gate-7 is in BOTH sweep lists" parity
python3 - "$FIX83/scripts/wow/formats.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["sweep"]["always"] = [g for g in d["sweep"]["always"] if g != "gate-7"]; d["sweep"]["p5_only"] = []
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PY
assert_rejects "a P5-sweep gate missing from p5_only is refused (ADV-R13-08)" "$FIX83" \
  "GATE-7 says \`where: p5 sweep\` in formats.json and is not in sweep.p5_only" parity
cp "$WOW_DIR/formats.json" "$FIX83/scripts/wow/formats.json"
python3 - "$FIX83/scripts/wow/formats.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["sweep"]["always"].append("gate-8")
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PY
assert_rejects "a sweep-list entry whose registry row does not say sweep fails parity (v0.7.5.1)" "$FIX83"   "GATE-8 is in a sweep list but its registry row says" parity
python3 - "$FIX83/scripts/wow/formats.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["sweep"]["always"] = [g for g in d["sweep"]["always"] if g != "gate-8"] + ["gate-99"]
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PY
assert_rejects "a sweep-list entry with no registry gate fails parity (v0.7.5.1)" "$FIX83"   "sweep list names gate-99 and the registry has no such gate" parity
cp "$WOW_DIR/formats.json" "$FIX83/scripts/wow/formats.json"
assert_accepts "sweep lists and registry where-cells agree (v0.7.5.1 control)" "$FIX83" parity
# ---- platform/F-92 fix 1 (v0.7.5): an ownership list may not cover its own home
python3 - "$FIX83/scripts/wow/formats.json" <<'PY'
import json, sys
p = sys.argv[1]; s = open(p).read()
s = s.replace('"agent_writable_paths": [', '"agent_writable_paths": ["scripts/wow/*", ', 1)
open(p, 'w').write(s); json.load(open(p))
PY
assert_rejects "agent_writable_paths covering scripts/wow/** is self-licensing — parity fails naming the key (platform/F-92)" "$FIX83" \
  "plan_schema.agent_writable_paths contains 'scripts/wow/*'" parity
finish
