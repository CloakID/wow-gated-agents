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
# ---- platform/F-94 (v0.7.5): modified_in_run sees renames' SOURCE and non-ASCII paths
FIX94="$(setup_fixture_repo)"
mkdir -p "$FIX94/helm"
printf 'a: 1\n' > "$FIX94/helm/values.yaml"
( cd "$FIX94" && git add -A >/dev/null && git commit -qm "helm [WOW:publish]" && git branch -q wow/260925-mv-r1/base )
( cd "$FIX94" && git mv helm/values.yaml moved.yaml && printf 'b: 2\n' > "helm/ü-values.yaml" && git add -A >/dev/null && git commit -qm "move [T:260925-mv-r1]" --no-verify )
MOD94="$( cd "$FIX94" && python3 -c "import sys; sys.path.insert(0,'scripts/wow'); import gates; print(' '.join(sorted(gates.modified_in_run('260925-mv-r1'))))" )"
case "$MOD94" in
  *"helm/values.yaml"*"helm/ü-values.yaml"*) echo "  ok   a rename's SOURCE and a non-ASCII path both appear unquoted (platform/F-94)"; PASS=$((PASS+1)) ;;
  *) echo "  FAIL modified_in_run missed the rename source or quoted the path: $MOD94 (platform/F-94)"; FAIL=$((FAIL+1)) ;;
esac
# ---- prodsim/F-97 (v0.7.5): a rejection hit inside a WORKTREE lands in the common log
WT="$(mktemp -d)/wt"
( cd "$FIX94" && git worktree add -q --detach "$WT" HEAD )
mkdir -p "$WT/runs/quick"
printf -- '- [ ] transition ABC-1 to Done\n' > "$WT/runs/quick/jira-queue.md"
( cd "$WT" && bash scripts/wow/gates.sh sweep --p5 >/dev/null 2>&1 ) || true
COMMON_LOG="$( cd "$FIX94" && git rev-parse --git-common-dir )/wow/gate-log"
case "$COMMON_LOG" in /*) ;; *) COMMON_LOG="$FIX94/$COMMON_LOG" ;; esac
( cd "$FIX94" && git worktree remove --force "$WT" )
if [ -f "$COMMON_LOG" ] && grep -q "unresolved queued op" "$COMMON_LOG" && grep -q "$WT" "$COMMON_LOG"; then
  echo "  ok   a worktree's gate rejection survives the worktree's removal, in the common git dir, naming the worktree (prodsim/F-97)"; PASS=$((PASS+1))
else
  echo "  FAIL worktree rejection lost or unattributed (prodsim/F-97)"; [ -f "$COMMON_LOG" ] && head -3 "$COMMON_LOG"; FAIL=$((FAIL+1))
fi
[ -f "$FIX94/runs/.gate-log" ] && { echo "  FAIL the retired per-worktree runs/.gate-log was still written (F-97)"; FAIL=$((FAIL+1)); } \
  || { echo "  ok   the retired per-worktree runs/.gate-log is not written (F-97)"; PASS=$((PASS+1)); }
# ---- prodsim/F-112 (v0.7.5): bare and anchored ev:file citations are preflighted
FIX112="$(setup_fixture_repo)"
mkdir -p "$FIX112/runs/260926-d-r1/evidence" "$FIX112/runs/archive"
printf '# RUN-REPORT\n\n## audit triggers\n| AT-1 | 0 |\n' > "$FIX112/runs/260926-d-r1/RUN-REPORT.md"
printf 'x\n' > "$FIX112/runs/260926-d-r1/evidence/at2-timeline.txt"
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n| OBL-T-38 | x | PO | advisory | s | d | ev:file{runs/260926-d-r1/evidence/at2-timeline.txt} ev:file{runs/260926-d-r1/RUN-REPORT.md#audit-triggers} |\n' > "$FIX112/docs/GAPS.md"
assert_accepts "bare and anchored citations into an ACTIVE run resolve (F-112 control)" "$FIX112" gate-5 --paths docs/GAPS.md
( cd "$FIX112" && mv runs/260926-d-r1 runs/archive/260926-d-r1 )
assert_accepts "after P5 archives the run, the citations resolve through the archive rewrite (prodsim/F-112)" "$FIX112" gate-5 --paths docs/GAPS.md
( cd "$FIX112" && rm runs/archive/260926-d-r1/evidence/at2-timeline.txt )
assert_rejects "a bare ev:file whose target exists nowhere is GONE (prodsim/F-112)" "$FIX112" \
  "cites ev:file{runs/260926-d-r1/evidence/at2-timeline.txt} — GONE" gate-5 --paths docs/GAPS.md
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n| OBL-T-38 | x | PO | advisory | s | d | ev:file{runs/260926-d-r1/RUN-REPORT.md#new-gaps} |\n' > "$FIX112/docs/GAPS.md"
assert_rejects "an anchor naming no heading in the target is refused (F-112)" "$FIX112" \
  "no heading slugs to 'new-gaps' and the text 'new-gaps' appears nowhere" gate-5 --paths docs/GAPS.md
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n| OBL-T-38 | x | PO | advisory | s | d | ev:file{runs/260926-d-r1/RUN-REPORT.md#AT-1} ev:file{runs/260926-d-r1/RUN-REPORT.md#audit-triggers} |\n' > "$FIX112/docs/GAPS.md"
assert_accepts "a CONTENT anchor (a table row's first cell) and a heading slug both resolve (ADV-R12-05)" "$FIX112" gate-5 --paths docs/GAPS.md
mkdir -p "$FIX112/runs/260927-new-r1"
printf '# PLAN\n| Task | Verify | Non-vacuity |\n|---|---|---|\n| 260927-new-r1.T01 | `x` | ev:file{runs/260927-new-r1/evidence/U1/nv-T01.txt} |\n' > "$FIX112/runs/260927-new-r1/PLAN.md"
assert_accepts "a run document citing evidence the run will produce is a promise, not GONE (DEV-R12-02)" "$FIX112" gate-5 --paths runs/260927-new-r1/PLAN.md
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n| OBL-T-38 | x | PO | advisory | s | d | `ev:file{runs/<id>/RUN-REPORT.md#new-gaps}` is the template |\n' > "$FIX112/docs/GAPS.md"
assert_accepts "a backticked template is a mention, not preflighted (F-112 control)" "$FIX112" gate-5 --paths docs/GAPS.md
# ---- prodsim/F-99 (v0.7.5): a rewritten unit branch is refused at the boundary
FIX99="$(setup_fixture_repo)"
( cd "$FIX99" && git checkout -q -b wow/260926-h-r1/U4 && printf 'r1\n' > report.md && git add -A >/dev/null \
  && git commit -qm "verify 1 [T:260926-h-r1]" --no-verify && printf 'r2\n' > report.md && git add -A >/dev/null \
  && git commit -qm "verify 2 [T:260926-h-r1]" --no-verify )
( cd "$FIX99" && bash scripts/wow/gates.sh history --run 260926-h-r1 >/dev/null 2>&1 ) \
  && { echo "  ok   a unit branch with only commits passes history (F-99 control)"; PASS=$((PASS+1)); } \
  || { echo "  FAIL clean history refused (F-99)"; FAIL=$((FAIL+1)); }
( cd "$FIX99" && git reset -q --soft HEAD~1 && git commit -qm "verify 2 again [T:260926-h-r1]" --no-verify )
H_OUT="$( cd "$FIX99" && bash scripts/wow/gates.sh history --run 260926-h-r1 2>&1 )" && H_RC=0 || H_RC=1
if [ "$H_RC" = "1" ] && printf '%s' "$H_OUT" | grep -q "wow/260926-h-r1/U4: 1 history-rewrite entry"; then
  echo "  ok   a soft-reset unit branch is refused and named (prodsim/F-99)"; PASS=$((PASS+1))
else
  echo "  FAIL rewritten branch not refused: $H_OUT (F-99)"; FAIL=$((FAIL+1))
fi
H_V="$( cd "$FIX99" && bash scripts/wow/gates.sh history --run 260999-none-r1 2>&1 )"
case "$H_V" in *VACUOUS*) echo "  ok   no unit branches → VACUOUS, loudly (F-99)"; PASS=$((PASS+1)) ;; *) echo "  FAIL silent over no branches (F-99)"; FAIL=$((FAIL+1)) ;; esac
# ---- R12b: ADV-R12-13 — branch -f is a rewrite too
( cd "$FIX99" && git checkout -q -b wow/260926-h-r1/U5 && printf 'u5\n' > u5.md && git add -A >/dev/null && git commit -qm "u5 [T:260926-h-r1]" --no-verify && git checkout -q master 2>/dev/null || git checkout -q main; git branch -f wow/260926-h-r1/U5 HEAD )
H5="$( cd "$FIX99" && bash scripts/wow/gates.sh history --run 260926-h-r1 2>&1 )" && H5RC=0 || H5RC=1
if [ "$H5RC" = "1" ] && printf '%s' "$H5" | grep -q "wow/260926-h-r1/U5: 1 history-rewrite"; then
  echo "  ok   git branch -f on a unit branch is refused (ADV-R12-13)"; PASS=$((PASS+1))
else
  echo "  FAIL branch -f not refused: $H5 (ADV-R12-13)"; FAIL=$((FAIL+1))
fi
finish
