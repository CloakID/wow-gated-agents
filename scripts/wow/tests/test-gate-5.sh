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
# ---- ADV-R11-01 (v0.7.4 R11b): the archive rewrite is one resolver, shared ---
# A registry row cites runs/<id>/RUN-REPORT.md:2; P5 step 3 archives the run;
# gate-5 and gate-7 must give the SAME verdict about that row.
( cd "$FIX" && git checkout -q -- docs/spec/SPEC-old-v1.md )   # clear the previous case's deliberate drift
mkdir -p "$FIX/runs/archive/260921-pub-r1" "$FIX/runs/debug/resolved"
printf '# RUN-REPORT\nline two\n' > "$FIX/runs/archive/260921-pub-r1/RUN-REPORT.md"
printf '# rec\nline two\n' > "$FIX/runs/debug/resolved/flaky.md"
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n| OBL-T-70 | x | PO | advisory | s | d | ev:file{runs/260921-pub-r1/RUN-REPORT.md:2} ev:file{runs/debug/flaky.md:2} |\n' \
  > "$FIX/docs/GAPS.md"
( cd "$FIX" && git add -A )
assert_accepts "staged citation into an archived run resolves via the archive rewrite (ADV-R11-01)" \
  "$FIX" gate-5 --staged
assert_accepts "modified-doc sweep resolves the archive and resolved/ rewrites (ADV-R11-01/-08)" \
  "$FIX" gate-5 --sweep
# control: a target that exists at NO modeled location is still GONE
printf '| OBL-T-71 | x | PO | advisory | s | d | ev:file{runs/260921-pub-r1/reports/U9.md:1} |\n' >> "$FIX/docs/GAPS.md"
( cd "$FIX" && git add -A )
assert_rejects "a truly deleted target is still GONE (ADV-R11-01 control)" "$FIX" "GONE" gate-5 --staged
finish
