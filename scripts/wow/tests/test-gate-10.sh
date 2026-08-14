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
finish
