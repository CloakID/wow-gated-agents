#!/usr/bin/env bash
# GATE-5 negative test: a citation to a missing file (GONE) and one past the end
# of an existing file (DRIFTED) must both be rejected; an in-range one must pass.
# Pre-commit judges the STAGED content, and the sweep does not block on drift in
# docs this run did not modify.
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

# The premise check: preflight must judge what git will store. Staging a broken
# citation and then fixing only the worktree used to let the broken content land.
printf 'See ev:file{docs/nope.md:3} for detail.\n' > "$FIX/docs/staged.md"
( cd "$FIX" && git add docs/staged.md >/dev/null )
printf 'See ev:file{docs/target.md:2} for detail.\n' > "$FIX/docs/staged.md"
assert_rejects "broken citation in the index, fixed only in the worktree" "$FIX" "GONE" \
  gate-5 --staged
( cd "$FIX" && git reset -q && rm -f docs/staged.md )

# GATES-SPEC: sweep-found drift in UNMODIFIED docs is not blocking — it feeds AT-4.
mkdir -p "$FIX/docs/spec"
printf '# SPEC old\n\nSee ev:file{docs/target.md:99}\n' > "$FIX/docs/spec/SPEC-old-v1.md"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "old spec [WOW:publish]" )
assert_accepts "sweep does not block on drift in an unmodified doc" "$FIX" gate-5 --sweep
assert_output "sweep reports that drift as an AT-4 advisory" "$FIX" "AT-4 count this sweep" \
  gate-5 --sweep

# ...but the same drift in a doc this run touched still blocks.
printf '# SPEC old\n\nSee ev:file{docs/target.md:99} (touched now)\n' > "$FIX/docs/spec/SPEC-old-v1.md"
assert_rejects "sweep blocks on drift in a doc this run modified" "$FIX" "DRIFTED" gate-5 --sweep
finish
