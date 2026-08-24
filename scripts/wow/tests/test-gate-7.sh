#!/usr/bin/env bash
# GATE-7 negative test: an unresolved jira-queue op and a stale quick stub must
# both block publish.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-7"

mkdir -p "$FIX/runs/260813-x-r1"
printf -- '- [ ] transition ABC-1 to Done\n' > "$FIX/runs/260813-x-r1/jira-queue.md"
assert_rejects "unresolved queued Jira op" "$FIX" "unresolved queued op" gate-7

printf -- '- [x] transition ABC-1 to Done\n' > "$FIX/runs/260813-x-r1/jira-queue.md"
assert_accepts "all queued ops applied" "$FIX" gate-7

mkdir -p "$FIX/runs/quick/260701-old-thing"
printf '## what\nx\n## why\ny\n## verify\n`cmd`\n## result\n' \
  > "$FIX/runs/quick/260701-old-thing/NOTE.md"
touch -t 202601010000 "$FIX/runs/quick/260701-old-thing/NOTE.md"
assert_rejects "stale quick stub with an empty result" "$FIX" "stale stub" gate-7
rm -rf "$FIX/runs/quick"   # clear the stale-stub fixture; escrow cases need a clean base

# ---- obligation escrow (FORMATS §12, OBL-PKG-01) ----------------------------
# Nothing obligation-shaped may live only in the runs/ tree being archived.
mkdir -p "$FIX/runs/260816-x-r1" "$FIX/docs"
cat > "$FIX/runs/260816-x-r1/RUN-REPORT.md" << 'R'
## new-gaps
CV-260816-x-r1-01: cannot validate webhook ordering
  reason: sandbox lacks replay
  successor: prod validation phase
  discharge: replayed in prod
R
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n' > "$FIX/docs/GAPS.md"
assert_rejects "CV record only in an archivable run (escrow)" "$FIX" "escrow" gate-7

printf '| CV-260816-x-r1-01 | env_unverified | PO | advisory | prod phase | replayed | ev:file{runs/260816-x-r1/RUN-REPORT.md#new-gaps} |\n' >> "$FIX/docs/GAPS.md"
assert_accepts "CV record escrowed into GAPS.md" "$FIX" gate-7

cat >> "$FIX/runs/260816-x-r1/RUN-REPORT.md" << 'R'
| 260816-x-r1.T02 | DEFERRED | see successor |
R
assert_rejects "DEFERRED row with no registry counterpart (escrow)" "$FIX" "escrow" gate-7
printf '| 260816-x-r1.T02 | impl_gap | run | advisory | r2 | done in r2 | ev:file{runs/260816-x-r1/RUN-REPORT.md} |\n' >> "$FIX/docs/GAPS.md"
assert_accepts "DEFERRED row escrowed" "$FIX" gate-7


# ---- S-6 (v0.6.2): a phantom run — an empty dir archiving strands -----------
mkdir -p "$FIX/runs/260820-ghost-r1/reports"
assert_rejects "empty run-id dir is a phantom, not an active run (S-6)" "$FIX" "phantom run" gate-7
rmdir "$FIX/runs/260820-ghost-r1/reports" "$FIX/runs/260820-ghost-r1"
# Control is the fixture itself: runs/260816-x-r1 holds files and stays legal.
assert_accepts "runs holding files are not phantoms (control)" "$FIX" gate-7

# ---- F-11 (v0.6.2, --p5 only): the run branch may not be behind main --------
( cd "$FIX" && git add -A >/dev/null && git commit -qm "base [WOW:publish]" \
  && git branch -M main && git checkout -qb wow/260816-x-r1/int \
  && git checkout -q main && printf 'grant\n' > grant.txt && git add grant.txt \
  && git commit -qm "grant lands on main [WOW:publish]" \
  && git checkout -q wow/260816-x-r1/int )
assert_rejects "run branch behind main at --p5 (F-11)" "$FIX" "BEHIND" gate-7 --p5
assert_accepts "same branch, no --p5: mid-run being behind is legal" "$FIX" gate-7
( cd "$FIX" && git merge -q --no-edit main >/dev/null 2>&1 )
assert_accepts "main merged in: publish may proceed (control)" "$FIX" gate-7 --p5
finish
