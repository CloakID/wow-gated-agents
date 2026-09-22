#!/usr/bin/env bash
# GATE-10 negative test: a missing divergence record, one whose rows are not
# classified in the Classification column, an unevidenced "no divergences" claim,
# and an offline diff with no recorded deferral must all block gate close.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-10"

mkdir -p "$FIX/runs/260813-x-r1"
rec() { cat > "$FIX/runs/260813-x-r1/divergence-G2.md"; }
assert_rejects "no divergence record at gate open" "$FIX" "no divergence record" gate-10 --run 260813-x-r1 --gate G2

rec <<'D'
| Item | Git | Jira | Classification |
|---|---|---|---|
| REQ-001 | COMPLETED | To Do | |
D
assert_rejects "divergence row left unclassified" "$FIX" "unclassified" gate-10 --run 260813-x-r1 --gate G2

# The premise check: a classification token was counted anywhere in the row, so a
# row whose Classification cell was empty passed if the word appeared elsewhere.
rec <<'D'
| Item | Git | Jira | Classification |
|---|---|---|---|
| jira-wrong | COMPLETED | To Do | |
D
assert_rejects "classification token in the wrong column" "$FIX" "unclassified" gate-10 --run 260813-x-r1 --gate G2

# ...and "no divergences" was accepted as a bare assertion. An empty diff is a
# claim like any other and carries the citation of the query that produced it.
rec <<'D'
No divergences: git and Jira agree.
D
assert_rejects "unevidenced 'no divergences' claim" "$FIX" "no ev: citation" gate-10 --run 260813-x-r1 --gate G2

# ...and an offline gate open must leave the deferral somewhere it will be chased.
rec <<'D'
| Item | Git | Jira | Classification |
|---|---|---|---|
| REQ-001 | COMPLETED | unknown — MCP unavailable | real-gap |
D
printf -- '- [x] something else\n' > "$FIX/runs/260813-x-r1/jira-queue.md"
assert_rejects "offline diff with no queued deferral" "$FIX" "no open gate-10 item" \
  gate-10 --run 260813-x-r1 --gate G2

printf -- '- [ ] gate-10 divergence diff for G2, deferred: MCP was unavailable\n' \
  > "$FIX/runs/260813-x-r1/jira-queue.md"
assert_accepts "offline diff with the deferral queued" "$FIX" gate-10 --run 260813-x-r1 --gate G2

rec <<'D'
| Item | Git | Jira | Classification |
|---|---|---|---|
| REQ-001 | COMPLETED | To Do | jira-wrong |
D
assert_accepts "every divergence classified" "$FIX" gate-10 --run 260813-x-r1 --gate G2

rec <<'D'
No divergences: git and Jira agree.
ev:cmd{mcp searchJiraIssuesUsingJql project=ABC => 12 issues, all in mapping @2026-08-14}
D
assert_accepts "evidenced no-divergences statement" "$FIX" gate-10 --run 260813-x-r1 --gate G2

# FORMATS §10's mapping table is data the gate can use: a row recording a pair
# that IS expected-consistent is noise, and saying so is free.
rec <<'D'
| Item | Git | Jira | Classification |
|---|---|---|---|
| REQ-002 | COMPLETED | Done | jira-wrong |
D
assert_output "pair that is expected-consistent is flagged as not a divergence" "$FIX" \
  "IS expected-consistent" gate-10 --run 260813-x-r1 --gate G2

# ---- F-56 (v0.7.2): row-parsing is scoped to the classification TABLE ------
# Any pipe-bearing line used to read as a row: a second table's rows AND its
# header (reported as a divergence named 'Item'), and an ev:cmd whose regex
# alternation carries pipes — the author's route past the refusal was to
# write WORSE evidence.
rec <<'D'
| Item | Git | Jira | Classification |
|---|---|---|---|
| REQ-001 | OPEN | To Do | real-gap |

The expected-consistent pairs, recorded for the reviewer:

| REQUIREMENTS | Jira story |
|---|---|
| OPEN | To Do / In Progress |
| COMPLETED (ev) | In Review / Done |

Checked with ev:cmd{grep -nE "volumeMounts|volumes:|envFrom|configMap" helm/ => no match @2026-09-16}
D
assert_accepts "a second table and a pipe-bearing citation are NOT divergence rows (F-56)" \
  "$FIX" gate-10 --run 260813-x-r1 --gate G2
# Control: an unclassified row inside the REAL table still fails — scoping the
# parser must not have opened a hole.
rec <<'D'
| Item | Git | Jira | Classification |
|---|---|---|---|
| REQ-001 | OPEN | To Do | shrug |

| REQUIREMENTS | Jira story |
|---|---|
| OPEN | To Do |
D
assert_rejects "unclassified row in the real table still fails (F-56 control)" "$FIX" \
  "unclassified" gate-10 --run 260813-x-r1 --gate G2
# ---- platform/F-73 (v0.7.4): a workflow with no Deferred status names its
# equivalent in wow.config.json; the §10 table resolves without relabeling.
rec <<'D'
| Item | Git | Jira | Classification |
|---|---|---|---|
| REQ-003 | DEFERRED | Intake | real-gap |
D
OUT73="$( cd "$FIX" && ./scripts/wow/gates.sh gate-10 --run 260813-x-r1 --gate G2 2>&1 )"
if printf '%s' "$OUT73" | grep -q "IS expected-consistent"; then
  echo "  FAIL DEFERRED/Intake read as consistent with NO convention set (F-73 control)"; FAIL=$((FAIL+1))
else
  echo "  ok   DEFERRED/Intake is a divergence while unconfigured (F-73 control)"; PASS=$((PASS+1))
fi
python3 - "$FIX/scripts/wow/wow.config.json" <<'PY'
import json, sys
p = sys.argv[1]; c = json.load(open(p))
c.setdefault("jira", {})["status_conventions"] = {"deferred_equivalent": "Intake"}
open(p, "w").write(json.dumps(c) + "\n")
PY
assert_output "deferred_equivalent makes DEFERRED/Intake expected-consistent (platform/F-73)" "$FIX" \
  "IS expected-consistent" gate-10 --run 260813-x-r1 --gate G2
# ---- DEV-R11-07 (R11b): an expected-consistent row needs NO classification
rec <<'D'
| Item | Git | Jira | Classification |
|---|---|---|---|
| REQ-003 | DEFERRED | Intake | |
D
assert_accepts "expected-consistent pair left unclassified is not a divergence (DEV-R11-07)" "$FIX" \
  gate-10 --run 260813-x-r1 --gate G2
finish
