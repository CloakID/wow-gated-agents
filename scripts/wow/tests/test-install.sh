#!/usr/bin/env bash
# WIRING test — the one the gate tests cannot be.
#
# Every gate had a passing negative test while GATE-7 was in no sweep list,
# GATE-6's area half had no caller, GATE-11 ignored deletions, and hooks were
# written where core.hooksPath meant git would never read them. All of those
# tests called gates.sh directly. This one installs the package into a throwaway
# repo and drives real `git commit`s through the real hooks: it proves the gates
# are CONNECTED, not merely correct.
#
# Skipped when the package root has no install.sh — an installed target repo
# carries the engine and the tests, not the installer.
source "$(dirname "$0")/lib.sh"
echo "INSTALL (wiring)"

# prodsim/F-81 (v0.7.4): if the running bash is older than what install.sh
# needs, say that ONCE instead of reporting 32 unrelated failures.
if [ "${BASH_VERSINFO[0]:-0}" -lt 3 ] || { [ "${BASH_VERSINFO[0]:-0}" -eq 3 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 2 ]; }; then
  echo "  SKIP bash ${BASH_VERSION:-?} is below install.sh's requirement — upgrade bash to run the wiring suite (F-81)"
  finish
fi
INSTALL="$PKG_DIR/install.sh"
if [ ! -f "$INSTALL" ]; then
  # Installed target: no installer here, but the question "are this repo's gates
  # actually connected?" is exactly as worth answering. Run the installed hooks
  # directly against fixtures — no commits, no history touched.
  echo "  (installed target: no install.sh — verifying THIS repo's wiring instead)"
  HOOKS="$(git -C "$PKG_DIR" rev-parse --git-path hooks 2>/dev/null)"
  CFG="$(git -C "$PKG_DIR" config --get core.hooksPath 2>/dev/null)"
  [ -n "$CFG" ] && case "$CFG" in /*) HOOKS="$CFG" ;; *) HOOKS="$PKG_DIR/$CFG" ;; esac
  case "$HOOKS" in /*) ;; *) HOOKS="$PKG_DIR/$HOOKS" ;; esac
  ok_()  { echo "  ok   $1"; PASS=$((PASS+1)); }
  bad_() { echo "  FAIL $1"; [ -n "${2:-}" ] && echo "$2" | sed 's/^/       /'; FAIL=$((FAIL+1)); }
  MSG="$(mktemp)"; trap 'rm -f "$MSG"' EXIT
  for h in commit-msg pre-commit; do
    [ -x "$HOOKS/$h" ] && ok_ "$h hook is installed and executable in $HOOKS" \
      || bad_ "$h hook missing from $HOOKS — git reads that directory, so nothing is enforced"
  done
  printf 'no lane reference here\n' > "$MSG"
  if ( cd "$PKG_DIR" && "$HOOKS/commit-msg" "$MSG" ) >/dev/null 2>&1; then
    bad_ "the installed commit-msg hook accepted a laneless message — GATE-1 is not wired"
  else ok_ "the installed commit-msg hook rejects a laneless message (GATE-1 live)"; fi
  for g in $(python3 -c "import json;F=json.load(open('$WOW_DIR/formats.json'));print(' '.join(F['sweep']['always']+F['sweep']['p5_only']))"); do
    ( cd "$PKG_DIR" && "$WOW_DIR/gates.sh" sweep --p5 2>&1 | grep "$g" >/dev/null ) \
      && ok_ "sweep --p5 runs $g" || bad_ "$g is in no sweep — a gate nothing calls is inert"
  done
  finish
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
new_target() { # new_target <name> [git-config...]
  local t="$WORK/$1"; mkdir -p "$t"
  ( cd "$t" && git init -q . && git config user.email t@t && git config user.name t \
    && printf '# %s\n\nhouse rules\n' "$1" > CLAUDE.md && printf 'x\n' > app.txt \
    && git add -A && git commit -qm "init" ) >/dev/null 2>&1
  echo "$t"
}
ok_()   { echo "  ok   $1"; PASS=$((PASS+1)); }
bad_()  { echo "  FAIL $1"; [ -n "${2:-}" ] && echo "$2" | sed 's/^/       /'; FAIL=$((FAIL+1)); }
must_block() { # must_block <label> <dir> <commit-message>
  local out; out="$( cd "$2" && git commit -qm "$3" 2>&1 )"
  if [ $? -eq 0 ]; then bad_ "commit that must be blocked landed: $1" "$out"
  else ok_ "blocked: $1"; fi
}
must_land() {
  local out; out="$( cd "$2" && git commit -qm "$3" 2>&1 )"
  if [ $? -eq 0 ]; then ok_ "landed: $1"; else bad_ "valid commit was blocked: $1" "$out"; fi
}

# ---- 1. the ordinary repo -------------------------------------------------
T="$(new_target plain)"
bash "$INSTALL" "$T" >/dev/null 2>&1 || bad_ "install.sh failed"
printf 'y\n' >> "$T/app.txt"; ( cd "$T" && git add -A )
must_block "laneless commit (GATE-1 via commit-msg hook)" "$T" "no lane reference here"
mkdir -p "$T/runs/quick/260814-real"
# prodsim/F-68 (v0.7.3): the pre-commit hook now RESOLVES ev:commit shas in
# staged runs/ files, so the fixture must cite a sha that exists — which is
# exactly the discipline the arm enforces.
TSHA="$( cd "$T" && git rev-parse --short=7 HEAD )"
printf '## what\nx\n## result\ndone ev:commit{%s}\n' "$TSHA" > "$T/runs/quick/260814-real/NOTE.md"
( cd "$T" && git add -A )
must_land "quick-lane commit with a resolvable ref" "$T" "do a thing [Q:runs/quick/260814-real]"
printf '## what\nx\n## result\ndone ev:commit{beef042}\n' > "$T/runs/quick/260814-real/NOTE.md"
( cd "$T" && git add -A )
must_block "staged run file citing a nonexistent sha (F-68 via pre-commit)" "$T" \
  "cite before commit [Q:runs/quick/260814-real]"
( cd "$T" && git checkout -q -- runs/quick/260814-real/NOTE.md 2>/dev/null || git reset -q )
printf '## what\nx\n## result\ndone ev:commit{%s}\n' "$TSHA" > "$T/runs/quick/260814-real/NOTE.md"
( cd "$T" && git add -A && git commit -qm "restore [Q:runs/quick/260814-real]" >/dev/null 2>&1 )

printf 'See ev:file{docs/gone.md:5}\n' > "$T/docs/note.md"; ( cd "$T" && git add -A )
must_block "staged stale citation (GATE-5 via pre-commit hook)" "$T" "cite [WOW:publish]"
( cd "$T" && git reset -q && rm -f docs/note.md )

# ---- 2. worktrees inherit the hooks (INSTALL.md's claim) ------------------
( cd "$T" && git worktree add -q "$WORK/wt" -b wow/260814-x-r1/U1 ) >/dev/null 2>&1
printf 'z\n' >> "$WORK/wt/app.txt"; ( cd "$WORK/wt" && git add -A )
must_block "laneless commit in a linked worktree" "$WORK/wt" "laneless in a worktree"

# ---- 3. GATE-11 is wired into pre-commit ---------------------------------
python3 - "$T/scripts/wow/wow.config.json" <<'PY'
import json,sys,io
p=sys.argv[1]; c=json.load(open(p)); c["migrated_from_gsd"]=True
io.open(p,"w",encoding="utf-8").write(json.dumps(c,indent=2)+"\n")
PY
mkdir -p "$T/.planning"; printf 'history\n' > "$T/.planning/STATE.md"
( cd "$T" && git add -A )
must_block "commit touching frozen .planning/ (GATE-11 via pre-commit)" "$T" "freeze [WOW:publish]"
( cd "$T" && git reset -q && rm -rf .planning )

# ---- 4. core.hooksPath: the configuration that silently disabled everything
T2="$(new_target hookspath)"
( cd "$T2" && git config core.hooksPath .githooks && mkdir -p .githooks )
bash "$INSTALL" "$T2" >/dev/null 2>&1
printf 'y\n' >> "$T2/app.txt"; ( cd "$T2" && git add -A )
must_block "laneless commit in a core.hooksPath repo" "$T2" "no lane reference here"
if bash "$INSTALL" --check "$T2" >/dev/null 2>&1; then ok_ "--check reports no drift for it"
else bad_ "--check reports drift on a clean core.hooksPath install"; fi

# ---- 5. an existing project hook is preserved, not clobbered --------------
T3="$(new_target existinghook)"
HOOKS3="$( cd "$T3" && git rev-parse --git-path hooks )"
mkdir -p "$T3/$HOOKS3"
printf '#!/bin/sh\necho "project lint ran"\nexit 0\n' > "$T3/$HOOKS3/pre-commit"
chmod +x "$T3/$HOOKS3/pre-commit"
bash "$INSTALL" "$T3" >/dev/null 2>&1
if [ -f "$T3/$HOOKS3/pre-commit.pre-wow" ]; then ok_ "existing pre-commit hook preserved"
else bad_ "existing pre-commit hook was destroyed"; fi
printf 'y\n' >> "$T3/app.txt"; ( cd "$T3" && git add -A )
out3="$( cd "$T3" && git commit -m "chain [WOW:publish]" 2>&1 )"
grep -q "project lint ran" <<<"$out3" \
  && ok_ "the preserved hook still runs" || bad_ "the preserved hook is no longer called" "$out3"

# ---- 6. --check detects drift, including a neutered hook -----------------
printf '\n# tampered\n' >> "$T/scripts/wow/gates.py"
bash "$INSTALL" --check "$T" >/dev/null 2>&1 && bad_ "--check missed an edited engine file" \
  || ok_ "--check detects an edited engine file"
bash "$INSTALL" "$T" >/dev/null 2>&1
HOOKS="$( cd "$T" && git rev-parse --git-path hooks )"
printf '#!/usr/bin/env bash\n# wow-v2-hook gates.sh\nexit 0\n' > "$T/$HOOKS/commit-msg"
bash "$INSTALL" --check "$T" >/dev/null 2>&1 && bad_ "--check missed a neutered hook" \
  || ok_ "--check detects a hook rewritten to exit 0"
bash "$INSTALL" "$T" >/dev/null 2>&1

# ---- 7. idempotency ------------------------------------------------------
cp -R "$T" "$WORK/snap1"; bash "$INSTALL" "$T" >/dev/null 2>&1
if diff -r -x '.git' "$WORK/snap1" "$T" >/dev/null 2>&1; then ok_ "re-running install.sh changes nothing"
else bad_ "install.sh is not idempotent" "$(diff -r -x '.git' "$WORK/snap1" "$T" | head -5)"; fi

# ---- 7b. blocks-install: the package refuses its own distribution ----------
# (OBL-PKG-11) An open scope-matched blocks-install row in the SOURCE registry
# refuses install with exit 4. Control: a discharged row does not refuse.
PKG2="$WORK/pkg2"; mkdir -p "$PKG2"
( cd "$PKG_DIR" && git ls-files -z 2>/dev/null | tar --null -T - -cf - 2>/dev/null | ( cd "$PKG2" && tar -xf - ) ) \
  || cp -R "$PKG_DIR/." "$PKG2/"
rm -rf "$PKG2/.git"
mkdir -p "$PKG2/docs"
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n| OBL-T-11 | process_debt | PO | blocks-install (scope: *) | merge | merged | ev:commit{abc1234} |\n' > "$PKG2/docs/GAPS.md"
TB="$(new_target blocked)"
if bash "$PKG2/install.sh" "$TB" >/dev/null 2>&1; then
  bad_ "install proceeded past an open blocks-install row"
else
  rc=$?
  [ "$rc" -eq 4 ] && ok_ "install refused on open blocks-install (exit 4)" \
    || bad_ "install refused but with exit $rc, not the documented 4"
fi
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n| ~~OBL-T-11~~ | process_debt | PO | blocks-install (scope: *) | merge | merged | ev:commit{abc1234} discharged ev:commit{def5678} |\n' > "$PKG2/docs/GAPS.md"
bash "$PKG2/install.sh" "$TB" >/dev/null 2>&1 \
  && ok_ "discharged blocks-install row does not refuse (control)" \
  || bad_ "install refused on a DISCHARGED row — nothing could ever ship"
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n| OBL-T-12 | process_debt | PO | blocks-install (scope: some-other-repo) | merge | merged | ev:commit{abc1234} |\n' > "$PKG2/docs/GAPS.md"
bash "$PKG2/install.sh" "$TB" >/dev/null 2>&1 \
  && ok_ "scope-mismatched blocks-install row does not refuse (control)" \
  || bad_ "install refused on a row scoped to a different repo"

# ---- 7c. an incomplete package refuses to install (review PR-1) -------------
PKG3="$WORK/pkg3"; mkdir -p "$PKG3"
cp -R "$PKG2/." "$PKG3/"
rm -f "$PKG3/docs/process/P2-PLAN.md"
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n' > "$PKG3/docs/GAPS.md"
TI="$(new_target incomplete)"
if bash "$PKG3/install.sh" "$TI" >/dev/null 2>&1; then
  bad_ "an incomplete package installed silently (dangling stubs, no playbook)"
else
  rc=$?
  [ "$rc" -eq 5 ] && ok_ "incomplete package refused (exit 5)" \
    || bad_ "incomplete package refused with exit $rc, not the documented 5"
fi
# verifier F1: the refusal must precede ALL writes — a refusal that fires after
# the copy loop leaves dangling stubs and LIVE hooks behind.
if [ -e "$TI/CLAUDE.md.wow" ] || [ -d "$TI/.claude" ] || [ -d "$TI/docs/process" ] \
   || [ -d "$TI/scripts/wow" ] || grep -q wow-v2 "$TI/CLAUDE.md" 2>/dev/null \
   || ls "$(cd "$TI" && git rev-parse --git-path hooks)"/commit-msg >/dev/null 2>&1; then
  bad_ "refusal fired but the target was written anyway (F1: dangling stubs / live hooks)"
else
  ok_ "refused target left untouched (F1: nothing written before the check)"
fi

# verifier F3: the consult mirrors _gap_rows strictness — fail CLOSED, never open.
PKG4="$WORK/pkg4"; mkdir -p "$PKG4"; cp -R "$PKG2/." "$PKG4/"
TC="$(new_target consult)"
printf '| # | Taxonomy | Gap | Owner | Discharge |\n|---|---|---|---|---|\n| G-01 | x | blocks-install (scope: *) | PO | later |\n' > "$PKG4/docs/GAPS.md"
bash "$PKG4/install.sh" "$TC" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 4 ] && ok_ "legacy-shaped registry refuses install (F3 fail-closed, exit $rc)" \
  || bad_ "legacy-shaped registry did not refuse (exit $rc) — fail-open"
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n| OBL-T-13 | x | PO | blocks-everything | s | d | ev:commit{abc1234} |\n' > "$PKG4/docs/GAPS.md"
bash "$PKG4/install.sh" "$TC" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 4 ] && ok_ "unknown effect refuses install (F3 closed enum)" \
  || bad_ "unknown effect did not refuse (exit $rc) — the silent downgrade returns"
rm -f "$PKG4/docs/GAPS.md"
bash "$PKG4/install.sh" "$TC" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 4 ] && ok_ "absent package registry refuses install (F3 subject-absent)" \
  || bad_ "absent registry did not refuse (exit $rc)"
# OBL-PKG-11 stated control: an advisory row must NOT refuse.
printf '| id | tag | owner | effect | successor | discharge | ev |\n|---|---|---|---|---|---|---|\n| OBL-T-14 | x | PO | advisory | s | d | ev:commit{abc1234} |\n' > "$PKG4/docs/GAPS.md"
bash "$PKG4/install.sh" "$TC" >/dev/null 2>&1 \
  && ok_ "advisory row does not refuse (OBL-PKG-11 control)" \
  || bad_ "advisory row refused the install — the consult is an off switch"

# ---- 8. every gate is reachable from a documented command ----------------
# grep must read to EOF (no -q on a live pipeline): under lib.sh's pipefail,
# `| grep -q` closes the pipe at first match, gates.sh dies of SIGPIPE, and the
# pipeline FAILS despite the match — a buffering race that passes on one
# machine and fails on another (TF-01, found in the engine-v0.5.x session).
# platform/F-78 (v0.7.4): under pipefail the sweep's own exit status failed
# this pipeline whatever grep found — in any repo carrying a red gate, all six
# sweep gates were reported unwired, and the operator learns the wiring test
# is noise. Capture first, then match: the gates' verdicts cannot masquerade
# as their wiring.
SWEEP_CAP="$( cd "$T" && ./scripts/wow/gates.sh sweep --p5 2>&1 )" || true
for g in $( cd "$T" && python3 -c "import json;print(' '.join(json.load(open('scripts/wow/formats.json'))['sweep']['always']+json.load(open('scripts/wow/formats.json'))['sweep']['p5_only']))" ); do
  case "$SWEEP_CAP" in
    *"$g"*) ok_ "sweep --p5 runs $g" ;;
    *) bad_ "$g is in no sweep — a gate nothing calls is inert" ;;
  esac
done
# F-78 non-vacuity: with a RED gate in the repo, wiring must still read wired.
mkdir -p "$T/runs/quick"
printf -- '- [ ] transition ABC-9 to Done\n' > "$T/runs/quick/jira-queue.md"
RED_CAP="$( cd "$T" && ./scripts/wow/gates.sh sweep --p5 2>&1 )" && \
  bad_ "planted violation did not turn the sweep red (F-78 fixture inert)" || true
case "$RED_CAP" in
  *gate-3*) ok_ "a red sweep still reports every member as wired (platform/F-78)" ;;
  *) bad_ "red sweep hid gate wiring again (platform/F-78)" ;;
esac
rm -f "$T/runs/quick/jira-queue.md"
printf -- '- [ ] transition ABC-1 to Done\n' > "$T/runs/quick/jira-queue.md"
( cd "$T" && ./scripts/wow/gates.sh sweep --p5 >/dev/null 2>&1 ) \
  && bad_ "GATE-7 did not block the P5 sweep on an unresolved jira-queue" \
  || ok_ "GATE-7 blocks the P5 sweep (the check P5 actually runs)"
rm -f "$T/runs/quick/jira-queue.md"

# ---- GATE-14 wiring (v0.6.4): the pre-commit hook refuses staged PII --------
mkdir -p "$T/runs/260903-w-r1/evidence"
printf '{"email": "jane@example.net"}\n' > "$T/runs/260903-w-r1/evidence/cap.json"
( cd "$T" && git add -A )
must_block "staged evidence with populated email (GATE-14 via pre-commit hook)" "$T" \
  "capture [T:260903-w-r1]"
printf 'pii-ok: PO D-9, synthetic tenant\n{"email": "jane@example.net"}\n' \
  > "$T/runs/260903-w-r1/evidence/cap.json"
( cd "$T" && git add -A )
must_land "pii-ok capture lands through the same hook (control)" "$T" \
  "capture [T:260903-w-r1]"

# ---- F-33/F-34 (v0.6.4): audit triggers derive from the durable home --------
mkdir -p "$T/runs/260903-a-r1"
ATSHA="$( cd "$T" && git rev-parse --short=7 HEAD 2>/dev/null || echo 0000000 )"
# prodsim/F-74 (v0.7.3): the rows use the NATURAL authoring form — metric
# name beside the id, verdict beside the number — which the old pattern
# refused while the deriver said 'not recorded' about a recorded table.
# prodsim/F-75: the prose sentence explaining what AT-3 counts must NOT
# count as a blocked task; only the two table rows do.
printf '# RUN-REPORT\n\nAT-3 sums rows whose status cell is the blocked one; writing the word BLOCKED in prose must not move it.\n\n## audit triggers\n\n```sh\n# how these were counted (ADV-R10-03: a fenced comment must not end the section)\ngrep -c BLOCKED reports/*.md\n```\n\n| AT-1 mocks/fixtures committed, excluding controls | 4 — threshold >3, HIT | ev:commit{%s} |\n| AT-2 remediation cycles | 2 | ev:commit{%s} |\n| AT-5 ac_passed_for_wrong_reason (PO ruling at G4) | 1 | ev:commit{%s} |\n\n## completed\n| id | status | ref |\n|---|---|---|\n| T01 | BLOCKED | PARK-U1-01 |\n| T02 | BLOCKED | PARK-U1-02 |\n' "$ATSHA" "$ATSHA" "$ATSHA" \
  > "$T/runs/260903-a-r1/RUN-REPORT.md"
AT_OUT="$(cd "$T" && node scripts/wow/status.mjs --json --run 260903-a-r1 | python3 -c "import json,sys; a=json.load(sys.stdin)['auditTriggers']; print(a['AT-1']['value'], a['AT-2']['value'], a['AT-3']['value'], a['AT-5']['value'])")"
if [ "$AT_OUT" = "4 2 2 1" ]; then
  echo "  ok   AT-1/AT-2 read from RUN-REPORT; AT-3 scoped; AT-5 PO ruling read back (F-33/F-34/F-87e)"; PASS=$((PASS+1))
else
  echo "  FAIL audit triggers misderived (got '$AT_OUT', want '4 2 2 1')"; FAIL=$((FAIL+1))
fi
rm -rf "$T/runs/260903-a-r1"

# ---- HANDOFF count (v0.6.2, frisbii off-by-one) -----------------------------
# split('\n') counted the trailing newline: 80 meant 79, and five commits in
# pilot #1 trimmed a file that was already right. Count as wc -l does.
# ($T is the installed fixture repo from the cases above.)
mkdir -p "$T/runs/260824-h-r1"
{ printf '## position\nhere\n'; for i in $(seq 3 80); do printf 'line %s\n' "$i"; done; } \
  > "$T/runs/260824-h-r1/HANDOFF.md"
LINES="$(wc -l < "$T/runs/260824-h-r1/HANDOFF.md" | tr -d ' ')"
OVER="$(cd "$T" && node scripts/wow/status.mjs --json | python3 -c "import json,sys; r=[x for x in json.load(sys.stdin)['runs'] if x['id']=='260824-h-r1'][0]; print(r['handoffOverLimit'], r['handoffLines'])")"
if [ "$LINES" = "80" ] && [ "$OVER" = "False 80" ]; then
  echo "  ok   handoff at exactly 80 lines is AT the limit, not over"; PASS=$((PASS+1))
else
  echo "  FAIL 80-line handoff misreported (wc=$LINES, status='$OVER')"; FAIL=$((FAIL+1))
fi
printf 'line 81\n' >> "$T/runs/260824-h-r1/HANDOFF.md"
OVER="$(cd "$T" && node scripts/wow/status.mjs --json | python3 -c "import json,sys; r=[x for x in json.load(sys.stdin)['runs'] if x['id']=='260824-h-r1'][0]; print(r['handoffOverLimit'], r['handoffLines'])")"
if [ "$OVER" = "True 81" ]; then
  echo "  ok   81 lines is over the limit (a counter that rejects everything is ruled out)"; PASS=$((PASS+1))
else
  echo "  FAIL 81-line handoff misreported (status='$OVER')"; FAIL=$((FAIL+1))
fi
rm -rf "$T/runs/260824-h-r1"

# ---- F-06 (v0.6.3): permissions policy is seeded once, then repo-owned ------
POL="scripts/wow/permissions-policy.json"
if [ -f "$T/$POL" ]; then
  printf '{"permissions":{"allow":["Bash(kubectl get:*)"],"deny":[]}}\n' > "$T/$POL"
  # capture first, grep second: --check exits 1 on ANY drift, and under
  # pipefail that fails the pipeline exactly when grep matches (TF-01's cousin
  # — this assertion was inverted-vacuous until a mutation run caught it).
  CHK_OUT="$( cd "$PKG_DIR" && bash install.sh --check "$T" 2>&1 )" || true
  if printf '%s' "$CHK_OUT" | grep "DRIFTED.*permissions-policy" >/dev/null; then
    echo "  FAIL the repo's own policy reported as DRIFTED (F-06: next upgrade would wipe it)"; FAIL=$((FAIL+1))
  else
    echo "  ok   repo-edited policy is not drift (F-06)"; PASS=$((PASS+1))
  fi
  ( cd "$PKG_DIR" && bash install.sh "$T" >/dev/null 2>&1 )
  if grep -q kubectl "$T/$POL"; then
    echo "  ok   re-install does not overwrite the repo's policy (F-06)"; PASS=$((PASS+1))
  else
    echo "  FAIL re-install overwrote the repo-owned policy (F-06)"; FAIL=$((FAIL+1))
  fi
else
  echo "  FAIL $POL was never seeded into the target"; FAIL=$((FAIL+1))
fi
# ---- ADV-R9-02/12 + DEV-R9-09 (v0.7.3 R9): the deriver's own parsing --------
# (a) a status row WITHOUT a trailing pipe (legal GFM) keeps its last cell;
# (b) an AT table indented up to 3 spaces (CommonMark-legal) still parses;
# (c) on a repo with NO runs, the AT diagnostic says so instead of implying a
#     parse failure the operator should fix.
mkdir -p "$T/runs/260920-r9-r1"
printf '## audit triggers\n   | AT-2 remediation cycles | 2 | ev:commit{%s} |\n\n## completed\n| id | status | ref |\n|---|---|---|\n| T01 | BLOCKED | PARK-U1-01 |\n| T02 | BLOCKED\n' "$ATSHA" \
  > "$T/runs/260920-r9-r1/RUN-REPORT.md"
R9_OUT="$(cd "$T" && node scripts/wow/status.mjs --json --run 260920-r9-r1 | python3 -c "import json,sys; d=json.load(sys.stdin); a=d['auditTriggers']; r=[x for x in d['runs'] if x['id']=='260920-r9-r1'][0]; print(a['AT-2']['value'], r['statuses']['BLOCKED'])")"
if [ "$R9_OUT" = "2 2" ]; then
  echo "  ok   no-trailing-pipe row counted; indented AT table parsed (ADV-R9-02/12)"; PASS=$((PASS+1))
else
  echo "  FAIL R9 deriver fixes regressed (got '$R9_OUT', want '2 2')"; FAIL=$((FAIL+1))
fi
rm -rf "$T/runs/260920-r9-r1"
TN="$(new_target norunsyet)"
bash "$INSTALL" "$TN" >/dev/null 2>&1
NOTE_OUT="$(cd "$TN" && node scripts/wow/status.mjs --json | python3 -c "import json,sys; print(json.load(sys.stdin)['auditTriggers']['AT-1']['note'])")"
case "$NOTE_OUT" in
  *"no ACTIVE run"*) echo "  ok   zero-run repo: AT note says no active run, not rows-seen/parsed (DEV-R9-09)"; PASS=$((PASS+1)) ;;
  *) echo "  FAIL zero-run AT note still implies a parse failure: $NOTE_OUT"; FAIL=$((FAIL+1)) ;;
esac
# DEV-R9-10: the sweep SUMMARY carries the vacuous count on an empty repo.
SWEEP_OUT="$(cd "$TN" && ./scripts/wow/gates.sh sweep 2>&1 | tail -1)"
case "$SWEEP_OUT" in
  *vacuous*) echo "  ok   empty-repo sweep summary says vacuous, not bare N/N passed (DEV-R9-10)"; PASS=$((PASS+1)) ;;
  *) echo "  FAIL sweep summary is still a bare pass count: $SWEEP_OUT"; FAIL=$((FAIL+1)) ;;
esac

# ---- DEV-R9-02/04 (v0.7.3 R9): install seeds the registry; upgrades re-stamp
# the one config key the installer owns.
if [ -f "$TN/docs/GAPS.md" ] && grep -q '| id | tag | owner |' "$TN/docs/GAPS.md"; then
  echo "  ok   docs/GAPS.md seeded empty-but-valid (DEV-R9-02)"; PASS=$((PASS+1))
else
  echo "  FAIL docs/GAPS.md not seeded — first /wow-spec dead-ends on GATE-12"; FAIL=$((FAIL+1))
fi
python3 - "$TN/scripts/wow/wow.config.json" <<'PY'
import json, re, sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(re.sub(r'"wow_version"\s*:\s*"[^"]*"', '"wow_version": "0.0.1-old"', s, count=1))
PY
# capture first, grep second: --check exits 1 on drift, and under pipefail
# `| grep -q` fails the pipeline exactly when it matches (TF-01's cousin).
VCHK_OUT="$(bash "$INSTALL" --check "$TN" 2>&1)" || true
printf '%s' "$VCHK_OUT" | grep -q "STALE.*wow_version" \
  && { echo "  ok   --check reports a stale wow_version (DEV-R9-04)"; PASS=$((PASS+1)); } \
  || { echo "  FAIL --check silent on a stale wow_version"; FAIL=$((FAIL+1)); }
bash "$INSTALL" "$TN" >/dev/null 2>&1
grep -q '"wow_version": "0.0.1-old"' "$TN/scripts/wow/wow.config.json" \
  && { echo "  FAIL upgrade left the stale wow_version stamp (DEV-R9-04)"; FAIL=$((FAIL+1)); } \
  || { echo "  ok   upgrade re-stamps wow_version; the rest of the config is untouched (DEV-R9-04)"; PASS=$((PASS+1)); }

# ---- DEV-R9-01 (v0.7.3 R9): a repo-local edit INSIDE the markers refuses a
# plain install (would-be-lost lines shown); --force-section overrides; a
# stamped, unedited section upgrades freely.
TS="$(new_target sectionguard)"
bash "$INSTALL" "$TS" >/dev/null 2>&1
grep -q 'wow-v2-section-hash' "$TS/CLAUDE.md" \
  && { echo "  ok   written section carries its content stamp (DEV-R9-01)"; PASS=$((PASS+1)); } \
  || { echo "  FAIL section written without a stamp"; FAIL=$((FAIL+1)); }
bash "$INSTALL" "$TS" >/dev/null 2>&1 \
  && { echo "  ok   stamped unedited section reinstalls freely (DEV-R9-01 control)"; PASS=$((PASS+1)); } \
  || { echo "  FAIL clean reinstall refused"; FAIL=$((FAIL+1)); }
python3 - "$TS/CLAUDE.md" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
marker = "<!-- wow-v2-section-hash:"
i = s.index(marker)
open(p, "w").write(s[:i] + "PO decision D-42: quick lane widened for hotfixes.\n" + s[i:])
PY
SG_OUT="$(bash "$INSTALL" "$TS" 2>&1)"; SG_RC=$?
if [ "$SG_RC" -ne 0 ] && printf '%s' "$SG_OUT" | grep -q "REFUSED.*CLAUDE.md" \
   && grep -q "D-42" "$TS/CLAUDE.md"; then
  echo "  ok   locally-edited section refused; the decision survives (DEV-R9-01)"; PASS=$((PASS+1))
else
  echo "  FAIL locally-edited section was replaced or refusal malformed (rc=$SG_RC)"; FAIL=$((FAIL+1))
fi
SCHK_OUT="$(bash "$INSTALL" --check "$TS" 2>&1)" || true
printf '%s' "$SCHK_OUT" | grep -q "LOCAL EDITS" \
  && { echo "  ok   --check names the local edits and the refusal (DEV-R9-01)"; PASS=$((PASS+1)); } \
  || { echo "  FAIL --check does not name local edits"; FAIL=$((FAIL+1)); }
bash "$INSTALL" --force-section "$TS" >/dev/null 2>&1
if ! grep -q "D-42" "$TS/CLAUDE.md" && grep -q 'wow-v2-section-hash' "$TS/CLAUDE.md"; then
  echo "  ok   --force-section replaces deliberately and re-stamps (DEV-R9-01 escape)"; PASS=$((PASS+1))
else
  echo "  FAIL --force-section did not replace cleanly"; FAIL=$((FAIL+1))
fi
# ---- ADV-R10-10 (R9b): CRLF conversion is zero semantic change, not local edits.
TCRLF="$(new_target crlf)"
bash "$INSTALL" "$TCRLF" >/dev/null 2>&1
python3 - "$TCRLF/CLAUDE.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, 'rb').read()
open(p, 'wb').write(s.replace(b'\n', b'\r\n'))
PY
bash "$INSTALL" "$TCRLF" >/dev/null 2>&1 \
  && { echo "  ok   CRLF-converted section is not 'local edits' (ADV-R10-10)"; PASS=$((PASS+1)); } \
  || { echo "  FAIL CRLF conversion refused as local edits"; FAIL=$((FAIL+1)); }
# ---- prodsim/F-78 + F-81 (v0.7.4): bash 3.2 parseability is structural ------
# macOS's stock bash cannot parse a heredoc opened inside $( ) — the class
# tripwire is that no line of install.sh opens one. (The suite itself runs
# under whatever bash is present; this guard is what keeps the 3.2 promise
# testable from a newer shell.)
if grep -nE '\$\([^)]*<<' "$PKG_DIR/install.sh" >/dev/null 2>&1; then
  echo "  FAIL install.sh opens a heredoc inside command substitution — bash 3.2 cannot parse it (F-78/F-81)"; FAIL=$((FAIL+1))
else
  echo "  ok   no heredoc inside command substitution in install.sh (bash 3.2, F-78/F-81)"; PASS=$((PASS+1))
fi
# ---- prodsim/F-77 (v0.7.4): the sweep asserts the enforcement layer --------
# A second installer (an old checkout's lifecycle script) clobbers the WoW
# pre-commit hook; .git/hooks is untracked so nothing else notices. Parity —
# first member of every sweep — now refuses in an installed repo.
TH="$(new_target hookint)"
bash "$INSTALL" "$TH" >/dev/null 2>&1
( cd "$TH" && ./scripts/wow/gates.sh parity >/dev/null 2>&1 ) \
  && { echo "  ok   installed repo with intact hooks passes parity (F-77 control)"; PASS=$((PASS+1)); } \
  || { echo "  FAIL intact install fails the enforcement-layer check"; FAIL=$((FAIL+1)); }
THHOOKS="$( cd "$TH" && git rev-parse --git-path hooks )"
printf '#!/bin/sh\nexit 0\n' > "$TH/$THHOOKS/pre-commit"   # the clobber, byte-for-byte foreign
PAR_OUT="$( cd "$TH" && ./scripts/wow/gates.sh parity 2>&1 )"; PAR_RC=$?
ST_OUT="$( cd "$TH" && node scripts/wow/status.mjs 2>&1 )"
case "$ST_OUT" in
  *"pre-commit=FOREIGN"*) echo "  ok   status.mjs states the subject: FOREIGN, not MISSING (F-77)"; PASS=$((PASS+1)) ;;
  *) echo "  FAIL status.mjs still conflates a foreign hook with a missing one (F-77)"; FAIL=$((FAIL+1)) ;;
esac
if [ "$PAR_RC" -ne 0 ] && printf '%s' "$PAR_OUT" | grep -q "FOREIGN"; then
  echo "  ok   clobbered hook fails parity naming FOREIGN, not MISSING (F-77)"; PASS=$((PASS+1))
else
  echo "  FAIL clobbered hook not caught by the sweep's parity member (rc=$PAR_RC)"; FAIL=$((FAIL+1)); printf '%s\n' "$PAR_OUT" | head -4
fi
rm -f "$TH/$THHOOKS/pre-commit"
PAR_OUT="$( cd "$TH" && ./scripts/wow/gates.sh parity 2>&1 )"; PAR_RC=$?
if [ "$PAR_RC" -ne 0 ] && printf '%s' "$PAR_OUT" | grep -q "ABSENT"; then
  echo "  ok   deleted hook fails parity naming ABSENT (F-77)"; PASS=$((PASS+1))
else
  echo "  FAIL deleted hook not caught (rc=$PAR_RC)"; FAIL=$((FAIL+1))
fi
# ---- prodsim/F-83 (v0.7.4): a consumer formatter's output is not local edits.
TPF="$(new_target prettierlike)"
bash "$INSTALL" "$TPF" >/dev/null 2>&1
python3 - "$TPF/CLAUDE.md" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
# a formatter's output: emphasis SPELLING flipped (the shipped section is
# underscore-normalized; a formatter preferring asterisks rewrites it) and
# trailing whitespace added — zero semantic change, must not read as edits
s = re.sub(r'(?<![A-Za-z0-9_])_([^_\n`]+)_(?![A-Za-z0-9_])', r'*\1*', s)
s = "\n".join(ln + "  " if ln.strip() and not ln.startswith("<!--") else ln for ln in s.split("\n"))
open(p, 'w').write(s)
PY
grep -q '\*[^*]*\*' "$TPF/CLAUDE.md" || { echo "  FAIL F-83 fixture inert — no emphasis flipped"; FAIL=$((FAIL+1)); }
# DEV-R11-01: what prettier ACTUALLY does to the section — a blank line after
# the opening marker and before the stamp comment (measured with prettier
# 3.8.1 by the R11 reviewer). Prettier itself when present, else the same edit.
if command -v npx >/dev/null 2>&1 && npx --no-install prettier --version >/dev/null 2>&1; then
  ( cd "$TPF" && npx --no-install prettier --write CLAUDE.md >/dev/null 2>&1 )
else
  python3 - "$TPF/CLAUDE.md" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("<!-- wow-v2:start -->\n", "<!-- wow-v2:start -->\n\n", 1)
i = s.index("<!-- wow-v2-section-hash:")
s = s[:i].rstrip("\n") + "\n\n" + s[i:]
open(p, "w").write(s)
PY
fi
bash "$INSTALL" "$TPF" >/dev/null 2>&1 \
  && { echo "  ok   prettier's blank lines around the markers are not 'local edits' (DEV-R11-01)"; PASS=$((PASS+1)); } \
  || { echo "  FAIL prettier-formatted section refused (DEV-R11-01)"; FAIL=$((FAIL+1)); }
bash "$INSTALL" --check "$TPF" 2>&1 | grep -q "DRIFTED  CLAUDE.md" \
  && { echo "  FAIL --check reports formatting as drift (DEV-R11-01)"; FAIL=$((FAIL+1)); } \
  || { echo "  ok   --check does not report formatting as drift (DEV-R11-01)"; PASS=$((PASS+1)); }
bash "$INSTALL" "$TPF" >/dev/null 2>&1 \
  && { echo "  ok   formatter-normalized section is not 'local edits' (F-83)"; PASS=$((PASS+1)); } \
  || { echo "  FAIL formatter output refused as local edits (F-83)"; FAIL=$((FAIL+1)); }
# substance still refuses (control)
python3 - "$TPF/CLAUDE.md" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
m = "<!-- wow-v2-section-hash:"
i = s.index(m)
open(p, 'w').write(s[:i] + "PO decision D-77: real content.\n" + s[i:])
PY
bash "$INSTALL" "$TPF" >/dev/null 2>&1 \
  && { echo "  FAIL a real local edit slipped through the normalized comparison"; FAIL=$((FAIL+1)); } \
  || { echo "  ok   a real local edit still refuses (F-83 control)"; PASS=$((PASS+1)); }
# and the section source itself ships prettier-clean: no single-asterisk emphasis
if grep -nE '(^|[^*`])\*[^*`\n]+\*([^*`]|$)' "$PKG_DIR/CLAUDE-WOW-SECTION.md" | grep -v '\`' >/dev/null 2>&1; then
  echo "  FAIL CLAUDE-WOW-SECTION.md carries *emphasis* prettier will rewrite (F-83)"; FAIL=$((FAIL+1))
else
  echo "  ok   shipped section source is emphasis-normalized (F-83)"; PASS=$((PASS+1))
fi
# ---- prodsim/F-84 (v0.7.4): a repo-owned status extension survives upgrade --
TX="$(new_target extras)"
bash "$INSTALL" "$TX" >/dev/null 2>&1
mkdir -p "$TX/scripts"
printf 'export default { section: "Migration", lines: ["migration steps: 6/7"] };\n' > "$TX/scripts/status-extras.mjs"
EXT_OUT="$( cd "$TX" && node scripts/wow/status.mjs 2>&1 )"
case "$EXT_OUT" in
  *"migration steps: 6/7"*) echo "  ok   repo-owned status extension is rendered (F-84)"; PASS=$((PASS+1)) ;;
  *) echo "  FAIL status extension not rendered (F-84)"; FAIL=$((FAIL+1)) ;;
esac
bash "$INSTALL" "$TX" >/dev/null 2>&1   # the upgrade that used to eat the line
EXT_OUT="$( cd "$TX" && node scripts/wow/status.mjs 2>&1 )"
case "$EXT_OUT" in
  *"migration steps: 6/7"*) echo "  ok   the extension survives a re-install (F-84 — the whole point)"; PASS=$((PASS+1)) ;;
  *) echo "  FAIL extension lost on re-install (F-84)"; FAIL=$((FAIL+1)) ;;
esac
printf 'throw new Error("boom");\n' > "$TX/scripts/status-extras.mjs"
EXT_OUT="$( cd "$TX" && node scripts/wow/status.mjs 2>&1 )"
case "$EXT_OUT" in
  *"FAILED: boom"*) echo "  ok   a failing extension is reported, not swallowed (F-84)"; PASS=$((PASS+1)) ;;
  *) echo "  FAIL failing extension swallowed (F-84)"; FAIL=$((FAIL+1)) ;;
esac

# ---- platform/F-81 (v0.7.4): a debug record at BOTH open and resolved paths
mkdir -p "$TX/runs/debug/resolved"
printf '# rec\n' > "$TX/runs/debug/260921-twin.md"
printf '# rec\n' > "$TX/runs/debug/resolved/260921-twin.md"
EXT_OUT="$( cd "$TX" && node scripts/wow/status.mjs 2>&1 )"
case "$EXT_OUT" in
  *"PHANTOM: 260921-twin.md"*) echo "  ok   open ∩ resolved intersection names the phantom (platform/F-81)"; PASS=$((PASS+1)) ;;
  *) echo "  FAIL phantom debug record counted twice silently (F-81)"; FAIL=$((FAIL+1)) ;;
esac
# ---- DEV-R11-02/03 (R11b): the self-heal, and the second clobber -------------
TC2="$(new_target clone-heal)"
bash "$INSTALL" "$TC2" >/dev/null 2>&1
( cd "$TC2" && git add -A && git commit -qm "install [WOW:publish]" ) >/dev/null 2>&1
git clone -q "$TC2" "$WORK/fresh-clone" 2>/dev/null
FC_OUT="$( cd "$WORK/fresh-clone" && ./scripts/wow/gates.sh parity 2>&1 )"; FC_RC=$?
if [ "$FC_RC" -ne 0 ] && printf '%s' "$FC_OUT" | grep -q "hooks --install"; then
  echo "  ok   fresh clone: parity refuses ABSENT hooks and names the self-heal (DEV-R11-02)"; PASS=$((PASS+1))
else
  echo "  FAIL fresh clone parity (rc=$FC_RC) did not name the self-heal"; FAIL=$((FAIL+1))
fi
( cd "$WORK/fresh-clone" && ./scripts/wow/gates.sh hooks --install >/dev/null 2>&1 )
( cd "$WORK/fresh-clone" && ./scripts/wow/gates.sh parity >/dev/null 2>&1 ) \
  && { echo "  ok   gates.sh hooks --install heals the clone; parity green (DEV-R11-02)"; PASS=$((PASS+1)); } \
  || { echo "  FAIL self-heal left parity red"; FAIL=$((FAIL+1)); }
# byte-identity with install.sh's rendering: --check must see no drift
bash "$INSTALL" --check "$WORK/fresh-clone" 2>&1 | grep -q "DRIFTED  hook" \
  && { echo "  FAIL self-healed hook drifts from install.sh's rendering (one home violated)"; FAIL=$((FAIL+1)); } \
  || { echo "  ok   self-healed hook is byte-identical to install.sh's (single-home template)"; PASS=$((PASS+1)); }
# advisory mode keeps CI checkouts green while still saying it
git clone -q "$TC2" "$WORK/ci-clone" 2>/dev/null
python3 - "$WORK/ci-clone/scripts/wow/wow.config.json" <<'PY'
import json, sys
p = sys.argv[1]; c = json.load(open(p)); c["enforcement_layer_check"] = "advisory"
open(p, "w").write(json.dumps(c) + "\n")
PY
CI_OUT="$( cd "$WORK/ci-clone" && ./scripts/wow/gates.sh parity 2>&1 )"; CI_RC=$?
if [ "$CI_RC" -eq 0 ] && printf '%s' "$CI_OUT" | grep -q "ABSENT"; then
  echo "  ok   enforcement_layer_check: advisory — green and still named (DEV-R11-02)"; PASS=$((PASS+1))
else
  echo "  FAIL advisory mode (rc=$CI_RC) wrong"; FAIL=$((FAIL+1))
fi
# second clobber: a DIFFERENT foreign hook must not destroy the first chained one
HOOKS2="$( cd "$TC2" && git rev-parse --git-path hooks )"
printf '#!/bin/sh\necho husky-one\n' > "$TC2/$HOOKS2/pre-commit"
( cd "$TC2" && ./scripts/wow/gates.sh hooks --install >/dev/null 2>&1 )
printf '#!/bin/sh\necho husky-two\n' > "$TC2/$HOOKS2/pre-commit"
( cd "$TC2" && ./scripts/wow/gates.sh hooks --install >/dev/null 2>&1 )
if grep -q husky-two "$TC2/$HOOKS2/pre-commit.pre-wow" && grep -q husky-one "$TC2/$HOOKS2/pre-commit.pre-wow.1"; then
  echo "  ok   second clobber rotates the chained copy; nothing destroyed (DEV-R11-03)"; PASS=$((PASS+1))
else
  echo "  FAIL second clobber destroyed a hook (DEV-R11-03)"; ls "$TC2/$HOOKS2" | sed 's/^/       /'; FAIL=$((FAIL+1))
fi
# ---- ADV-R11-10/-11, DEV-R11-10, DEV-R11-03 (R11b) --------------------------
TJ="$(new_target jsonapi)"
bash "$INSTALL" "$TJ" >/dev/null 2>&1
TJHOOKS="$( cd "$TJ" && git rev-parse --git-path hooks )"
printf '#!/bin/sh\nexit 0\n' > "$TJ/$TJHOOKS/pre-commit"
J_OUT="$( cd "$TJ" && node scripts/wow/status.mjs --json | python3 -c "import json,sys; d=json.load(sys.stdin)['install']; print(d['hooks']['pre-commit'], d['hookState']['pre-commit'])" )"
[ "$J_OUT" = "False FOREIGN" ] \
  && { echo "  ok   status --json keeps hooks boolean and adds hookState (ADV-R11-10)"; PASS=$((PASS+1)); } \
  || { echo "  FAIL status --json hook API changed shape: '$J_OUT' (ADV-R11-10)"; FAIL=$((FAIL+1)); }
mkdir -p "$TJ/runs/debug"
printf '# rec\n' > "$TJ/runs/debug/one-thing.md"
printf '# decision page\n' > "$TJ/runs/debug/classification-request.md"
D_OUT="$( cd "$TJ" && node scripts/wow/status.mjs --json | python3 -c "import json,sys; print(len(json.load(sys.stdin)['lanes']['debugOpen']))" )"
[ "$D_OUT" = "1" ] \
  && { echo "  ok   the decision surface is not an open debug record (ADV-R11-11)"; PASS=$((PASS+1)); } \
  || { echo "  FAIL decision surface counted as open ($D_OUT) (ADV-R11-11)"; FAIL=$((FAIL+1)); }
mkdir -p "$TJ/scripts"
printf 'export const section = "Named"; export const lines = ["named export line"];\n' > "$TJ/scripts/status-extras.mjs"
N_OUT="$( cd "$TJ" && node scripts/wow/status.mjs 2>&1 )"
case "$N_OUT" in *"named export line"*) echo "  ok   named exports render (DEV-R11-10)"; PASS=$((PASS+1)) ;; *) echo "  FAIL named exports not rendered (DEV-R11-10)"; FAIL=$((FAIL+1)) ;; esac
printf 'export const unrelated = 1;\n' > "$TJ/scripts/status-extras.mjs"
N_OUT="$( cd "$TJ" && node scripts/wow/status.mjs 2>&1 )"
case "$N_OUT" in *"no usable export"*) echo "  ok   a module with no usable export is an ERROR, not an empty section (DEV-R11-10)"; PASS=$((PASS+1)) ;; *) echo "  FAIL unusable extension rendered silently (DEV-R11-10)"; FAIL=$((FAIL+1)) ;; esac
rm -f "$TJ/scripts/status-extras.mjs"
# install.sh's own second-clobber path rotates too
printf '#!/bin/sh\necho husky-A\n' > "$TJ/$TJHOOKS/pre-commit"
bash "$INSTALL" "$TJ" >/dev/null 2>&1
printf '#!/bin/sh\necho husky-B\n' > "$TJ/$TJHOOKS/pre-commit"
bash "$INSTALL" "$TJ" >/dev/null 2>&1
if grep -q husky-B "$TJ/$TJHOOKS/pre-commit.pre-wow" && grep -q husky-A "$TJ/$TJHOOKS/pre-commit.pre-wow.1"; then
  echo "  ok   install.sh rotates the chained copy on a second clobber (DEV-R11-03)"; PASS=$((PASS+1))
else
  echo "  FAIL install.sh destroyed a hook on the second clobber (DEV-R11-03)"; FAIL=$((FAIL+1))
fi
finish
