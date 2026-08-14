#!/usr/bin/env bash
# GATE-1 negative test: a laneless commit message, a double lane ref, and a lane
# ref pointing at a task that does not exist must all be rejected.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-1"

printf 'Add a thing\n\nNo lane here.\n' > "$FIX/msg-none"
assert_rejects "laneless message" "$FIX" "no lane reference" gate-1 msg-none

printf 'Two lanes [WOW:publish] [D:some-bug]\n' > "$FIX/msg-two"
assert_rejects "two lane refs" "$FIX" "expected exactly one" gate-1 msg-two

printf 'Do work [T:260813-nope-r1.T01]\n' > "$FIX/msg-ghost"
assert_rejects "lane ref to a run with no PLAN.md" "$FIX" "which has no PLAN.md" gate-1 msg-ghost

mkdir -p "$FIX/runs/260813-real-r1"
printf 'spec: docs/spec/S.md\n\n| 260813-real-r1.T01 | do | `cmd` | done |\n' \
  > "$FIX/runs/260813-real-r1/PLAN.md"
printf 'Do work [T:260813-real-r1.T01]\n' > "$FIX/msg-ok"
assert_accepts "resolvable task lane ref" "$FIX" gate-1 msg-ok

printf 'Framework change [WOW:publish]\n' > "$FIX/msg-pub"
assert_accepts "publish lane ref" "$FIX" gate-1 msg-pub
finish
