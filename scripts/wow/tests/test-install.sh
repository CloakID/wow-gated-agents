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
printf '## what\nx\n## result\ndone ev:commit{abc1234}\n' > "$T/runs/quick/260814-real/NOTE.md"
( cd "$T" && git add -A )
must_land "quick-lane commit with a resolvable ref" "$T" "do a thing [Q:runs/quick/260814-real]"

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
for g in $( cd "$T" && python3 -c "import json;print(' '.join(json.load(open('scripts/wow/formats.json'))['sweep']['always']+json.load(open('scripts/wow/formats.json'))['sweep']['p5_only']))" ); do
  ( cd "$T" && ./scripts/wow/gates.sh sweep --p5 2>&1 | grep "$g" >/dev/null ) \
    && ok_ "sweep --p5 runs $g" || bad_ "$g is in no sweep — a gate nothing calls is inert"
done
printf -- '- [ ] transition ABC-1 to Done\n' > "$T/runs/quick/jira-queue.md"
( cd "$T" && ./scripts/wow/gates.sh sweep --p5 >/dev/null 2>&1 ) \
  && bad_ "GATE-7 did not block the P5 sweep on an unresolved jira-queue" \
  || ok_ "GATE-7 blocks the P5 sweep (the check P5 actually runs)"
rm -f "$T/runs/quick/jira-queue.md"
finish
