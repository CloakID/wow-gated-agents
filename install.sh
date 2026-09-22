#!/usr/bin/env bash
# WoW v2 per-repo installer. Idempotent — re-run to upgrade.
#
#   install.sh <target-repo>        install or upgrade
#   install.sh --check <target>     report drift, change nothing
#   install.sh --source <dir> ...   canonical package to install from
#                                   (defaults to the repo holding this script)
#
# Prerequisites in the TARGET's environment (also listed in INSTALL.md):
#   bash 3.2+   this script, gates.sh and the negative tests
#   git 2.5+    worktrees and --git-common-dir, so hooks reach every worktree
#   python3     gates.py is the engine gates.sh delegates to
#   node 18+    OPTIONAL — status.mjs only. No node means no derived status;
#               enforcement is unaffected.
#
# Writes only repo-scoped things: the WoW section of CLAUDE.md between its
# markers, docs/process/, scripts/wow/ (engine + tests + GATES-SPEC.md +
# permissions policy + a wow.config.json created once), .claude/commands/wow-*.md,
# and the two git hooks. Everything else in the target is left alone, and an
# existing commit-msg/pre-commit hook is preserved and chained, never destroyed.
#
# Hooks go to the directory git actually reads: core.hooksPath when the repo sets
# one, otherwise the COMMON git dir, so every worktree inherits them.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SELF"   # canonical package = the repo holding this script
CHECK=0
TARGET=""

FORCE_SECTION=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check)  CHECK=1; shift ;;
    --source) SOURCE="$(cd "$2" && pwd)"; shift 2 ;;
    --force-section) FORCE_SECTION=1; shift ;;   # DEV-R9-01: overwrite a locally-edited CLAUDE.md section
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) TARGET="$1"; shift ;;
  esac
done
[ -z "$TARGET" ] && { echo "usage: install.sh [--check] [--source <dir>] <target-repo>" >&2; exit 2; }
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "no such target" >&2; exit 2; }
git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || { echo "target is not a git repo" >&2; exit 2; }

command -v python3 >/dev/null 2>&1 || {
  echo "  MISSING prerequisite: python3 — the engine, and the manifest this installer reads" >&2
  echo "install aborted: install the prerequisites above" >&2; exit 3; }

# ------------------------------------------------------- the install manifest
# What a complete installation is lives in formats.json, like every other format
# in this package. install.sh is its third consumer (gates.sh and status.mjs are
# the others); a private copy here would be one more place to drift.
FORMATS="$SOURCE/scripts/wow/formats.json"
[ -f "$FORMATS" ] || { echo "no formats.json at $FORMATS — is --source a WoW package?" >&2; exit 2; }

# prodsim/F-78 + F-81 (v0.7.4): macOS's stock /bin/bash is 3.2 forever, and
# 3.2 cannot parse a heredoc opened INSIDE command substitution — the parser
# desynchronised on an apostrophe in a Python comment and blamed an innocent
# line 225 lines away. INSTALL.md promises 3.2, so the promise is honored:
# every python-in-$() block is written to a temp file first (a plain heredoc,
# which 3.2 parses fine) and executed by path. A comment's punctuation is no
# longer load-bearing.
PYTMP="$(mktemp)"
trap 'rm -f "$PYTMP"' EXIT
cat > "$PYTMP" <<'MANIFEST_PY'
import json, shlex, sys
D = json.load(open(sys.argv[1]))
I = D["install"]
q = lambda xs: " ".join(shlex.quote(str(x)) for x in xs)
print("WOW_VERSION=%s" % shlex.quote(D["version"]))
# DEV-R9-02: the registry's row schema, so install can seed an empty-but-valid
# docs/GAPS.md instead of letting the first /wow-spec dead-end on GATE-12.
print("GAP_FILE=%s"   % shlex.quote(D["gap_row"]["file"]))
print("GAP_HEADER=%s" % shlex.quote("| " + " | ".join(D["gap_row"]["columns"]) + " |"))
print("GAP_SEP=%s"    % shlex.quote("|" + "|".join("---" for _ in D["gap_row"]["columns"]) + "|"))
print("ENGINE_FILES=(%s)" % q(I["engine_files"]))
print("SEED_FILES=(%s)"   % q(I.get("seed_files", [])))
print("ENGINE_DIRS=(%s)"  % q(I["engine_dirs"]))
print("CONFIG_FILE=%s"    % shlex.quote(I["config_file"]))
print("HOOK_NAMES=(%s)"   % q(I["hooks"]))
print("HOOK_MARKER=%s"    % shlex.quote(I["hook_marker"]))
print("HOOK_KEEP=%s"      % shlex.quote(I["preserved_hook_suffix"]))
# DEV-R11-02 (v0.7.4): the hook BODY has one home — install.hook_template —
# rendered here for install.sh and by `gates.sh hooks --install` for self-heal.
for hname in I["hooks"]:
    body = I["hook_template"].replace("{marker}", I["hook_marker"]) \
        .replace("{keep}", I["preserved_hook_suffix"]) \
        .replace("{gate_lines}", "\n".join(I["hook_gate_lines"][hname]))
    print("HOOK_BODY_%s=%s" % (hname.replace("-", "_"), shlex.quote(body)))
c = I["claude_md"]
print("CLAUDE_FILE=%s"    % shlex.quote(c["file"]))
print("START=%s"          % shlex.quote(c["start_marker"]))
print("END=%s"            % shlex.quote(c["end_marker"]))
print("SECTION_FILE=%s"   % shlex.quote(c["section_source"]))
print("SECTION_HEAD=%s"   % shlex.quote(c["section_start_heading"]))
print("COMMANDS_DIR=%s"   % shlex.quote(I["commands_dir"]))
print("COMMAND_STUBS=(%s)" % q("%s:%s" % kv for kv in I["command_stubs"].items()))
print("REQ_TOOLS=(%s)"    % q("%s:%s" % kv for kv in I["prerequisites"]["required"].items()))
print("OPT_TOOLS=(%s)"    % q("%s:%s" % kv for kv in I["prerequisites"]["optional"].items()))
MANIFEST_PY
eval "$(python3 "$PYTMP" "$FORMATS")" || true
[ -n "${ENGINE_FILES+set}" ] || { echo "could not read the install manifest from formats.json" >&2; exit 2; }

DRIFT=0
say() { echo "  $*"; }
drift() { say "$*"; DRIFT=1; }

# ---------------------------------------------------------------- prerequisites
missing_prereq=0
need() { # need <command> <why>
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "  MISSING prerequisite: $1 — $2" >&2; missing_prereq=1
}
for spec in ${REQ_TOOLS[@]+"${REQ_TOOLS[@]}"}; do
  need "${spec%%:*}" "required by the package (minimum version ${spec##*:})"
done
for spec in ${OPT_TOOLS[@]+"${OPT_TOOLS[@]}"}; do
  t="${spec%%:*}"
  command -v "$t" >/dev/null 2>&1 || \
    echo "  note: optional tool $t (${spec##*:}+) not found — status.mjs will not run; gates are unaffected." >&2
done
git_ver="$(git --version 2>/dev/null | awk '{print $3}')"
case "$git_ver" in
  1.*|2.[0-4].*) echo "  git $git_ver is older than 2.5 — worktree hook inheritance needs 2.5+" >&2 ;;
esac
[ "$missing_prereq" -eq 1 ] && { echo "install aborted: install the prerequisites above" >&2; exit 3; }

# ------------------------------------------- blocks-install (OBL-PKG-11, §12)
# Before writing anything: an open blocks-install obligation in the PACKAGE's
# own registry refuses install/upgrade into any scope-matched target. The
# package blocks its own distribution while it would do harm. Rows carry
# scope: (repo names or *); an unrecognized effect already failed gate-12's
# validation — here we only honor the closed enum.
cat > "$PYTMP" <<'PY'
import json, os, re, sys
src, target = sys.argv[1], sys.argv[2]
try:
    F = json.load(open(os.path.join(src, "scripts", "wow", "formats.json")))
    gr = F.get("gap_row")
    if gr is None:
        # pre-0.6 source: the schema predates the registry — not a registry
        # error, and the completeness check downstream refuses old sources in
        # its own honest words (frisbii installer-consult finding, v0.6.4).
        raise SystemExit(0)
    p = os.path.join(src, gr["file"])
    if not os.path.isfile(p):
        print("CONSULT-ERROR no %s in the package — absence of the registry is not "
              "absence of obligations (packages >= 0.6 ship one; an empty table is valid)"
              % gr["file"])
        raise SystemExit(0)
    for ln in open(p, encoding="utf-8"):
        if not re.match(gr["row_start"], ln):
            continue
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if len(cells) < len(gr["columns"]):
            # verifier F3: a registry the schema cannot read must refuse, not skip
            print("CONSULT-ERROR row %r has %d cells, schema needs %d"
                  % (cells[0] if cells else "?", len(cells), len(gr["columns"])))
            raise SystemExit(0)
        row = dict(zip(gr["columns"], cells))
        if re.match(gr["discharged_id"], row["id"]):
            continue
        m = re.match(gr["effect_cell"], row["effect"])
        if not m:
            print("CONSULT-ERROR row %s: effect outside the closed vocabulary: %r"
                  % (row["id"], row["effect"][:40]))
            raise SystemExit(0)
        if m.group(1) != "blocks-install":
            continue
        sm = re.search(gr["scope_parse"], row["effect"])
        scope = sm.group(1) if sm else "*"
        if scope == "*" or target in [x.strip() for x in scope.split(",")]:
            print(row["id"])
            raise SystemExit(0)
except SystemExit:
    raise
except Exception as e:
    # review FR-5: a consult that dies silently is a guard that is never
    # allowed to fire — "never silently non-blocking" (pilot N3). Fail CLOSED.
    print("CONSULT-ERROR %s" % e)
PY
BLOCKED_ROW="$(python3 "$PYTMP" "$SOURCE" "$(basename "$TARGET")")"
if [ -n "$BLOCKED_ROW" ]; then
  case "$BLOCKED_ROW" in
    CONSULT-ERROR*)
      MSG="could not evaluate the package registry ($BLOCKED_ROW) — refusing rather than guessing" ;;
    *)
      MSG="open blocks-install obligation $BLOCKED_ROW in the package registry" ;;
  esac
  if [ "$CHECK" = "1" ]; then
    say "NOTE: a plain install would be REFUSED — $MSG"
  else
    echo "REFUSED: $MSG" >&2
    echo "         (docs/GAPS.md in the source). Discharge it, narrow its scope, or fix the registry." >&2
    exit 4
  fi
fi

# ------------------------------------------------------------------- file copy
copy() { copy_as "$1" "$1"; }

# Package self-integrity (review PR-1): every playbook a command stub points at,
# and the CLAUDE.md section source, must exist in the package BEFORE we write a
# single file — a dir-copy of docs/process/ cannot notice an absent member.
MISSING_SRC=""
for stub_target in $(python3 -c "import json;I=json.load(open('$SOURCE/scripts/wow/formats.json'))['install'];print(' '.join(sorted(set(I['command_stubs'].values()))))" 2>/dev/null); do
  [ -f "$SOURCE/docs/process/$stub_target.md" ] || MISSING_SRC="$MISSING_SRC docs/process/$stub_target.md"
done
SECTION_SRC="$(python3 -c "import json;print(json.load(open('$SOURCE/scripts/wow/formats.json'))['install']['claude_md']['section_source'])" 2>/dev/null)"
[ -n "$SECTION_SRC" ] && [ ! -f "$SOURCE/$SECTION_SRC" ] && MISSING_SRC="$MISSING_SRC $SECTION_SRC"
for ef in "${ENGINE_FILES[@]}"; do
  case "$ef" in
    */GATES-SPEC.md) src_rel="$(basename "$ef")" ;;   # root-sourced, installs under scripts/wow/
    *)               src_rel="$ef" ;;
  esac
  # the package repo installing onto itself sources some files from their target path
  [ -e "$SOURCE/$src_rel" ] || [ -e "$SOURCE/$ef" ] || MISSING_SRC="$MISSING_SRC $ef"
done
for sf in ${SEED_FILES[@]+"${SEED_FILES[@]}"}; do
  [ -e "$SOURCE/$sf" ] || MISSING_SRC="$MISSING_SRC $sf"
done
# verifier F1: the refusal must happen BEFORE we write a single file — the old
# placement announced exit 5 after the copy loop, the CLAUDE.md rewrite, the
# stubs and both hooks had already landed in the target.
if [ -n "$MISSING_SRC" ] && [ "$CHECK" != "1" ]; then
  echo "REFUSED before writing anything: the package itself is missing:$MISSING_SRC" >&2
  echo "an incomplete framework must not install (review PR-1 / verifier F1)" >&2
  exit 5
fi

copy_as() { # copy_as <source-relative> <target-relative>
  local rel="$2"
  local src="$SOURCE/$1"
  local dst="$TARGET/$2"
  # review PR-1: a missing PACKAGE source silently skipped here shipped a repo
  # with dangling command stubs and no router, and --check called it clean.
  # A package that cannot supply its own manifest refuses to install.
  [ -e "$src" ] || { MISSING_SRC="$MISSING_SRC $1"; drift "MISSING-IN-PACKAGE $1"; return 0; }
  # Installing a repo onto itself is a legitimate no-op (it is how the package
  # repo re-runs its own installer), not an error.
  if [ "$src" -ef "$dst" ]; then say "ok       $rel (source is target)"; return 0; fi
  if [ "$CHECK" -eq 1 ]; then
    if [ ! -e "$dst" ]; then drift "MISSING  $rel"
    elif ! diff -rq "$src" "$dst" >/dev/null 2>&1; then drift "DRIFTED  $rel"
    else say "ok       $rel"; fi
    [ -d "$src" ] && check_extra "$1" "$2"
  else
    if [ -d "$src" ]; then
      # cp -R src dst nests src INSIDE dst when dst already exists. Copy the
      # contents instead, or a re-run produces scripts/wow/tests/tests.
      mkdir -p "$dst"; cp -R "$src/." "$dst/"
      prune "$1" "$2"
    else
      mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"
    fi
    say "wrote    $rel"
  fi
}

# A package that drops a file must not leave it behind in every repo that ever
# installed it: "installed == canonical" is what --check claims to verify.
prune() { # prune <source-relative-dir> <target-relative-dir>
  local sd="$SOURCE/$1" td="$TARGET/$2" f rel
  [ -d "$td" ] || return 0
  while IFS= read -r f; do
    rel="${f#$td/}"
    [ -e "$sd/$rel" ] || { rm -f "$f"; say "removed  $2/$rel (no longer in the package)"; }
  done < <(find "$td" -type f 2>/dev/null)
}

check_extra() { # check_extra <source-relative-dir> <target-relative-dir>
  local sd="$SOURCE/$1" td="$TARGET/$2" f rel
  [ -d "$td" ] || return 0
  while IFS= read -r f; do
    rel="${f#$td/}"
    [ -e "$sd/$rel" ] || drift "EXTRA    $2/$rel (not in the package)"
  done < <(find "$td" -type f 2>/dev/null)
}

echo "WoW v2 $( [ "$CHECK" -eq 1 ] && echo check || echo install ): $SOURCE -> $TARGET"

# 1. process docs and engine, per install.engine_dirs / install.engine_files
for d in "${ENGINE_DIRS[@]}"; do copy "$d"; done
for f in "${ENGINE_FILES[@]}"; do
  # GATES-SPEC.md lives at the package root and installs under scripts/wow/, so
  # the repo's CLAUDE.md router can cite a path that exists locally.
  case "$f" in
    */GATES-SPEC.md) copy_as "$(basename "$f")" "$f" ;;
    *)               copy "$f" ;;
  esac
done

# 1b. seed files (F-06, v0.6.3) — copied ONCE from the package template, then
# owned by the repo. permissions-policy.json describes which commands THIS
# repo's verify steps may run; treating it as an engine file meant --check
# reported the repo's own policy as DRIFTED and the next upgrade overwrote it.
for sf in ${SEED_FILES[@]+"${SEED_FILES[@]}"}; do
  if [ ! -e "$TARGET/$sf" ]; then
    if [ "$CHECK" -eq 1 ]; then drift "MISSING  $sf"
    else
      mkdir -p "$TARGET/$(dirname "$sf")"
      cp "$SOURCE/$sf" "$TARGET/$sf"
      say "seeded   $sf (template — now repo-owned, never overwritten)"
    fi
  else
    say "ok       $sf (repo-owned, not compared to the package)"
  fi
done

# 2. wow.config.json — created once, never overwritten (it holds repo-local
# truth) — EXCEPT the wow_version key, which the installer owns (DEV-R9-04:
# after every upgrade the stamp read one version while status.mjs read
# another, and every consumer sweep named the stale stamp as truth).
if [ ! -e "$TARGET/$CONFIG_FILE" ]; then
  if [ "$CHECK" -eq 1 ]; then drift "MISSING  $CONFIG_FILE"
  else
    mkdir -p "$TARGET/$(dirname "$CONFIG_FILE")"
    cat > "$TARGET/$CONFIG_FILE" <<CFG
{
  "wow_version": "$WOW_VERSION",
  "repo": "$(basename "$TARGET")",
  "migrated_from_gsd": false,
  "jira": {
    "project_key": "<TBD>",
    "cloud_id": "<TBD>",
    "mapping": { "spec": "Epic", "unit": "Story", "task": "Task", "defect": "Bug" }
  },
  "\$mapping_note": "check YOUR Jira hierarchy before trusting 'task': standard projects usually want 'Subtask' — a premium multi-level hierarchy wants 'Task' (prodsim/F-61)",
  "merge_to_main": "pr",
  "archive": { "mode": "move", "path": "runs/archive/" },
  "hardening": { "pretooluse_lane_guard": false, "sessionstart_router_injection": false },
  "\$optional_keys": "requirement_id, probe_command_pattern, main_branch, run_base, jira.scope, jira.status_conventions, legacy_freeze_exclude, status_extensions — each defaults sanely when absent; scripts/wow/GATES-SPEC.md §Config keys says what each does (DEV-R9-08)"
}
CFG
    say "wrote    $CONFIG_FILE (template — set the Jira project key)"
  fi
else
  cat > "$PYTMP" <<'PY'
import io, re, sys
p, v, check = sys.argv[1:4]
s = io.open(p, encoding="utf-8").read()
m = re.search(r'"wow_version"\s*:\s*"([^"]*)"', s)
if not m:
    print("no-key"); raise SystemExit(0)
if m.group(1) == v:
    print("current"); raise SystemExit(0)
print(m.group(1))
if check != "1":
    io.open(p, "w", encoding="utf-8").write(s[:m.start(1)] + v + s[m.end(1):])
PY
  STAMPED="$(python3 "$PYTMP" "$TARGET/$CONFIG_FILE" "$WOW_VERSION" "$CHECK")"
  case "$STAMPED" in
    current) say "ok       $CONFIG_FILE (existing, not overwritten; wow_version current)" ;;
    no-key)  say "ok       $CONFIG_FILE (existing, not overwritten; carries no wow_version key)" ;;
    *) if [ "$CHECK" -eq 1 ]; then
         drift "STALE    $CONFIG_FILE wow_version is $STAMPED, package is $WOW_VERSION (a plain install re-stamps this one key)"
       else
         say "stamped  $CONFIG_FILE wow_version: $STAMPED -> $WOW_VERSION (the one key the installer owns; DEV-R9-04)"
       fi ;;
  esac
fi

# 2b. docs/GAPS.md — seeded empty-but-valid (DEV-R9-02: a fresh adopter's first
# /wow-spec dead-ended on GATE-12's 'no registry', and no installed doc carries
# the row schema; an empty table is a valid registry, so install seeds one).
if [ ! -e "$TARGET/$GAP_FILE" ]; then
  if [ "$CHECK" -eq 1 ]; then drift "MISSING  $GAP_FILE (obligation registry — GATE-12 refuses without it)"
  else
    mkdir -p "$TARGET/$(dirname "$GAP_FILE")"
    printf '%s\n\n%s\n%s\n' "# Obligation registry (FORMATS §12)" "$GAP_HEADER" "$GAP_SEP" > "$TARGET/$GAP_FILE"
    say "seeded   $GAP_FILE (empty-but-valid registry — repo-owned from here)"
  fi
else
  say "ok       $GAP_FILE (existing, repo-owned)"
fi

# 3. CLAUDE.md WoW section, between markers, rest of the file untouched
if [ -f "$SOURCE/$SECTION_FILE" ]; then
  # Package layout: the router lives in CLAUDE-WOW-SECTION.md, unwrapped. Take
  # everything from the first "## Way of Working" heading and add the markers.
  SECTION="$(printf '%s\n%s\n%s' "$START" \
    "$(awk -v h="$SECTION_HEAD" '$0 ~ h, 0' "$SOURCE/$SECTION_FILE")" "$END")"
  SECTION_SRC="$SOURCE/$SECTION_FILE"
else
  SECTION_SRC="$SOURCE/$CLAUDE_FILE"
  SECTION="$(awk "/$START/,/$END/" "$SECTION_SRC" 2>/dev/null)"
fi
if [ -f "$SECTION_SRC" ] && [ -n "$SECTION" ]; then
  DST="$TARGET/$CLAUDE_FILE"
  # DEV-R9-01 (v0.7.3 R9): a plain install replaced the section WHOLE and a
  # repo-local decision recorded inside the markers vanished with only
  # "(replaced)" — the loss warning lived in the OPTIONAL --check, whose last
  # line then told the reader to run the thing that deletes it. The written
  # section now carries a content stamp; a section whose current content does
  # not match its stamp (or an unstamped one that differs from the incoming
  # section) is REFUSED with the would-be-lost lines shown, unless
  # --force-section. Repo-local router content belongs OUTSIDE the markers.
  STAMP_PREFIX="<!-- wow-v2-section-hash:"
  hash_of() { python3 -c 'import sys,hashlib;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:16])'; }
  # ADV-R10-10: an editor converting CLAUDE.md to CRLF is zero semantic change,
  # not local edits — normalize before stamping/comparing.
  strip_stamp() { tr -d '\r' | grep -v "^$STAMP_PREFIX"; }
  # prodsim/F-83 + DEV-R11-01: a FORMATTER's output is not a local edit —
  # emphasis markers (either spelling), trailing whitespace and BLANK LINES
  # (prettier puts one after the opening marker and one before the stamp) are
  # formatting; the stamp hashes the NORMALIZED section so a formatted section
  # still matches its own stamp, and substance is what the guard refuses.
  normalize() { tr -d '*_' | sed -e 's/[[:space:]]*$//' -e '/^$/d'; }
  SEC_HASH="$(printf '%s\n' "$SECTION" | normalize | hash_of)"
  # written prettier-conformant: blank after the opening marker, blank before the stamp
  SECTION_STAMPED="$(printf '%s\n' "$SECTION" | sed -e "1a\\
" -e "\$i\\
\\
$STAMP_PREFIX $SEC_HASH -->")"
  cur_section() { awk "/$START/,/$END/" "$DST" 2>/dev/null | tr -d '\r'; }
  section_guard() { # returns 0 = safe to write, 1 = refuse
    [ -f "$DST" ] || return 0
    local cur cur_body cur_stamp cur_hash
    cur="$(cur_section)"
    [ -n "$cur" ] || return 0
    cur_body="$(printf '%s\n' "$cur" | strip_stamp)"
    cur_stamp="$(printf '%s\n' "$cur" | sed -n "s|^$STAMP_PREFIX \([0-9a-f]*\) -->\$|\1|p")"
    cur_hash="$(printf '%s\n' "$cur_body" | normalize | hash_of)"
    if [ -n "$cur_stamp" ] && [ "$cur_stamp" = "$cur_hash" ]; then return 0; fi
    # unstamped (pre-R9 install) or a pre-R11b stamp (hashed raw): identical to
    # the incoming section after normalization is a safe no-op re-stamp
    if [ "$(printf '%s\n' "$cur_body" | normalize | hash_of)" \
       = "$(printf '%s\n' "$SECTION" | normalize | hash_of)" ]; then return 0; fi
    return 1
  }
  if [ "$CHECK" -eq 1 ]; then
    if [ ! -f "$DST" ] || [ "$(cur_section | strip_stamp | normalize | hash_of)" != "$(printf '%s\n' "$SECTION" | normalize | hash_of)" ]; then
      drift "DRIFTED  $CLAUDE_FILE wow-v2 section"
      # platform/F-66 (v0.7.3): 'DRIFTED' alone cannot be told apart from a
      # routine version difference. Show the first differing lines so the
      # reader can tell a reverted decision from a version bump BEFORE
      # letting the installer write.
      if [ -f "$DST" ]; then
        cur_section | strip_stamp | diff - <(printf '%s\n' "$SECTION") 2>/dev/null \
          | head -8 | sed 's/^/         | /'
        if section_guard; then
          say "         (installed vs package; < = yours, > = package. A plain install replaces the section whole.)"
        else
          say "         (installed vs package; < = yours, > = package. This section carries LOCAL EDITS — a plain install now REFUSES to replace it; move repo-local lines below the closing marker, or pass --force-section to discard them.)"
        fi
      fi
    else say "ok       $CLAUDE_FILE wow-v2 section"; fi
  else
    if [ -f "$DST" ] && grep -q -- "$START" "$DST"; then
      if [ "$FORCE_SECTION" -eq 0 ] && ! section_guard; then
        echo "  REFUSED  $CLAUDE_FILE wow-v2 section: its content does not match the stamp the installer wrote (or predates stamping and differs from the package) — these lines would be LOST:" >&2
        cur_section | strip_stamp | diff - <(printf '%s\n' "$SECTION") 2>/dev/null \
          | grep '^<' | head -12 | sed 's/^/           /' >&2
        echo "           Move repo-local lines below the closing marker, then re-run; or re-run with --force-section to discard them (DEV-R9-01)." >&2
        DRIFT=1
      else
      # The section is passed as a FILE, never interpolated into the replacement.
      # As a re.sub replacement string, a backslash in the section is an escape:
      # \d raised re.error (leaving CLAUDE.md untouched while the installer
      # printed success) and \g<0> duplicated the whole block, markers included.
      SECFILE="$(mktemp)"; printf '%s\n' "$SECTION_STAMPED" > "$SECFILE"
      if python3 - "$DST" "$SECFILE" "$START" "$END" <<'PY'
import io, re, sys
dst, secfile, start, end = sys.argv[1:5]
s = io.open(dst, encoding="utf-8").read()
new = io.open(secfile, encoding="utf-8").read().rstrip("\n")
pat = re.compile(re.escape(start) + ".*?" + re.escape(end), re.S)
if not pat.search(s):
    sys.exit(4)
io.open(dst, "w", encoding="utf-8").write(pat.sub(lambda _m: new, s, count=1))
PY
      then say "wrote    $CLAUDE_FILE wow-v2 section (replaced$( [ "$FORCE_SECTION" -eq 1 ] && echo ', --force-section'))"
      else echo "  ERROR    $CLAUDE_FILE section not replaced (python3 exited $?)" >&2; DRIFT=1; fi
      rm -f "$SECFILE"
      fi
    else
      # Only separate with a blank line when there is prior content to separate from.
      { [ -f "$DST" ] && { cat "$DST"; echo; }; printf '%s\n' "$SECTION_STAMPED"; } > "$DST.tmp" \
        && mv "$DST.tmp" "$DST" && say "wrote    $CLAUDE_FILE wow-v2 section (appended)"
    fi
  fi
fi

# 4. command stubs — pointers only; the playbooks stay the single home
mkcmd() {
  local name="$1" body="$2"
  local dst="$TARGET/$COMMANDS_DIR/wow-$name.md"
  if [ "$CHECK" -eq 1 ]; then
    # Compare both sides through $( ), which strips trailing newlines from each.
    if [ ! -f "$dst" ] || [ "$(cat "$dst")" != "$(printf '%s' "$body")" ]; then
      drift "DRIFTED  $COMMANDS_DIR/wow-$name.md"
    else say "ok       $COMMANDS_DIR/wow-$name.md"; fi
  else
    mkdir -p "$TARGET/$COMMANDS_DIR"; printf '%s' "$body" > "$dst"
  fi
}
for pair in "${COMMAND_STUBS[@]}"; do
  n="${pair%%:*}"; d="${pair##*:}"
  mkcmd "$n" "Read \`docs/process/$d.md\` in full and follow it for \$ARGUMENTS.
Load only the files it names (its Load line where it has one).
Do not proceed from memory.
"
done
mkcmd status "Run \`node scripts/wow/status.mjs \$ARGUMENTS\` and report its output.
Load only what that script names; derive nothing from memory.
If the script is absent, say so — do not substitute a narrative status.
"
[ "$CHECK" -eq 0 ] && say "wrote    $COMMANDS_DIR/wow-*.md ($(( ${#COMMAND_STUBS[@]} + 1 )) stubs)"

# 5. git hooks, in the directory git actually reads
HOOKS="$(git -C "$TARGET" config --get core.hooksPath 2>/dev/null)"
if [ -n "$HOOKS" ]; then
  case "$HOOKS" in /*) ;; *) HOOKS="$TARGET/$HOOKS" ;; esac
  HOOKS_WHY="core.hooksPath"
else
  COMMON="$(git -C "$TARGET" rev-parse --git-common-dir)"
  case "$COMMON" in /*) ;; *) COMMON="$TARGET/$COMMON" ;; esac
  HOOKS="$COMMON/hooks"; HOOKS_WHY="common git dir (inherited by every worktree)"
fi

hook_body() { # hook_body <name> — rendered from formats.json install.hook_template (one home)
  local var="HOOK_BODY_${1//-/_}"
  printf '%s' "${!var}"
}

write_hook() {
  local name="$1"
  local dst="$HOOKS/$name"
  local body; body="$(hook_body "$name")"
  if [ "$CHECK" -eq 1 ]; then
    if [ ! -f "$dst" ]; then drift "MISSING  hook $name"
    elif ! grep -q "$HOOK_MARKER" "$dst"; then drift "DRIFTED  hook $name (not a WoW hook)"
    elif [ "$(cat "$dst")" != "$body" ]; then
      # Grepping for the string "gates.sh" reported ok for a hook someone had
      # rewritten to `# gates.sh` + `exit 0`. Enforcement is the layer that must
      # not be silently removable, so --check diffs the body.
      drift "DRIFTED  hook $name (body differs from canonical — enforcement may be neutered)"
    else say "ok       hook $name"; fi
  else
    mkdir -p "$HOOKS"
    # Preserve a project's own hook and chain to it, rather than destroying it.
    if [ -f "$dst" ] && ! grep -q "$HOOK_MARKER" "$dst"; then
      if [ ! -f "$dst$HOOK_KEEP" ]; then
        mv "$dst" "$dst$HOOK_KEEP"; chmod +x "$dst$HOOK_KEEP"
        say "kept     hook $name -> $name$HOOK_KEEP (chained, runs first)"
      elif cmp -s "$dst" "$dst$HOOK_KEEP"; then
        : # the same foreign hook re-clobbered ours; the chained copy is already it
      else
        # DEV-R11-03 (v0.7.4): a SECOND, different foreign hook (husky re-installs
        # on every npm install) used to be silently overwritten — "chains, never
        # destroys" was false on the second clobber. Rotate the old chained copy
        # aside and chain the new one; nothing is destroyed, and the rotated
        # copies do not run (the message says so).
        n=1; while [ -f "$dst$HOOK_KEEP.$n" ]; do n=$((n+1)); done
        mv "$dst$HOOK_KEEP" "$dst$HOOK_KEEP.$n"
        mv "$dst" "$dst$HOOK_KEEP"; chmod +x "$dst$HOOK_KEEP"
        say "kept     hook $name -> $name$HOOK_KEEP (chained, runs first); previous chained hook rotated to $name$HOOK_KEEP.$n (kept, NOT run — merge it into $name$HOOK_KEEP if it still matters)"
      fi
    fi
    printf '%s\n' "$body" > "$dst"; chmod +x "$dst"
    say "wrote    hook $name ($HOOKS_WHY)"
  fi
}
for h in "${HOOK_NAMES[@]}"; do write_hook "$h"; done

echo
if [ -n "$MISSING_SRC" ]; then
  echo "PACKAGE INCOMPLETE — missing from the package itself:$MISSING_SRC" >&2
  [ "$CHECK" != "1" ] && echo "NOTE: this fired AFTER the pre-write check — a file vanished mid-install; the target may be partial" >&2
  exit 5
fi
if [ "$CHECK" -eq 1 ]; then
  # DEV-R9-01: the epilogue used to say only "re-run install.sh" right under a
  # warning that re-running would lose lines — the last line a hurried reader
  # follows must not contradict the warning above it.
  [ "$DRIFT" -eq 0 ] && { echo "no drift"; exit 0; } \
    || { echo "DRIFT FOUND — re-run install.sh to upgrade (a $CLAUDE_FILE section carrying local edits is refused with the would-be-lost lines shown; see above)"; exit 1; }
fi
[ "$DRIFT" -eq 0 ] || { echo "install finished WITH ERRORS (see above)"; exit 1; }
# DEV-R9-11: the run-base default chain ends at 'main'; on a repo whose default
# branch is something else, P3's mandated check-id --base assert refuses with a
# finding id and no remedy — warn at the moment the fix is one config key.
if ! git -C "$TARGET" rev-parse --verify --quiet main >/dev/null 2>&1 \
   && [ "$(git -C "$TARGET" symbolic-ref --short HEAD 2>/dev/null)" != "main" ]; then
  grep -q '"main_branch"' "$TARGET/$CONFIG_FILE" 2>/dev/null \
    || say "note: this repo has no 'main' branch — set \"main_branch\" (and, if runs should base elsewhere, \"run_base\") in $CONFIG_FILE, or gate-7 --p5 and check-id --base will refuse with no resolvable default"
fi
echo "installed. Next, in the target repo:"
echo "  1. set the Jira project key in $CONFIG_FILE"
echo "  2. bash scripts/wow/tests/run-all.sh    (one negative test per gate + the wiring test)"
echo "  3. node scripts/wow/status.mjs          (derived status)"
echo "  4. commit the install itself with the framework-maintenance lane trailer:"
echo "       git add -A && git commit -m 'chore: install WoW v2 $WOW_VERSION [WOW:publish]'"
echo "     ([WOW:publish] covers framework maintenance and resolves to no task by design — LANES.md;"
echo "      do not mix application code into this commit)"
