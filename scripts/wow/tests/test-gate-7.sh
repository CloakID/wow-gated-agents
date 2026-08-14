#!/usr/bin/env bash
# GATE-7 negative test: an unresolved jira-queue op and a stale quick stub must
# both block publish.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-7"

mkdir -p "$FIX/runs/260813-x-r1"
printf -- '- [ ] transition CLOAKID-1 to Done\n' > "$FIX/runs/260813-x-r1/jira-queue.md"
assert_rejects "unresolved queued Jira op" "$FIX" "unresolved queued op" gate-7

printf -- '- [x] transition CLOAKID-1 to Done\n' > "$FIX/runs/260813-x-r1/jira-queue.md"
assert_accepts "all queued ops applied" "$FIX" gate-7

mkdir -p "$FIX/runs/quick/260701-old-thing"
printf '## what\nx\n## why\ny\n## verify\n`cmd`\n## result\n' \
  > "$FIX/runs/quick/260701-old-thing/NOTE.md"
touch -t 202601010000 "$FIX/runs/quick/260701-old-thing/NOTE.md"
assert_rejects "stale quick stub with an empty result" "$FIX" "stale stub" gate-7
finish
