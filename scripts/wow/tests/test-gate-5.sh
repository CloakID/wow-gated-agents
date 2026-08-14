#!/usr/bin/env bash
# GATE-5 negative test: a citation to a missing file (GONE) and one past the end
# of an existing file (DRIFTED) must both be rejected; an in-range one must pass.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-5"

printf 'line1\nline2\nline3\n' > "$FIX/docs/target.md"

printf 'See ev:file{docs/nope.md:3} for detail.\n' > "$FIX/docs/cite-gone.md"
assert_rejects "citation to a nonexistent file" "$FIX" "GONE" gate-5 --paths docs/cite-gone.md

printf 'See ev:file{docs/target.md:99} for detail.\n' > "$FIX/docs/cite-drift.md"
assert_rejects "citation past end of file" "$FIX" "DRIFTED" gate-5 --paths docs/cite-drift.md

printf 'See ev:file{docs/target.md:2} for detail.\n' > "$FIX/docs/cite-ok.md"
assert_accepts "in-range citation" "$FIX" gate-5 --paths docs/cite-ok.md
finish
