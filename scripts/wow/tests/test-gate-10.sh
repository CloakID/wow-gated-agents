#!/usr/bin/env bash
# GATE-10 negative test: a missing divergence record, and one whose rows are not
# classified, must both block gate close.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-10"

mkdir -p "$FIX/runs/260813-x-r1"
assert_rejects "no divergence record at gate open" "$FIX" "no divergence record" gate-10 --run 260813-x-r1 --gate G2

printf '| Item | Git | Jira | Classification |\n|---|---|---|---|\n| REQ-001 | COMPLETED | To Do | |\n' \
  > "$FIX/runs/260813-x-r1/divergence-G2.md"
assert_rejects "divergence row left unclassified" "$FIX" "unclassified" gate-10 --run 260813-x-r1 --gate G2

printf '| Item | Git | Jira | Classification |\n|---|---|---|---|\n| REQ-001 | COMPLETED | To Do | jira-wrong |\n' \
  > "$FIX/runs/260813-x-r1/divergence-G2.md"
assert_accepts "every divergence classified" "$FIX" gate-10 --run 260813-x-r1 --gate G2

printf 'No divergences: git and Jira agree.\n' > "$FIX/runs/260813-x-r1/divergence-G2.md"
assert_accepts "explicit no-divergences statement" "$FIX" gate-10 --run 260813-x-r1 --gate G2
finish
