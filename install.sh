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

while [ $# -gt 0 ]; do
  case "$1" in
    --check)  CHECK=1; shift ;;
    --source) SOURCE="$(cd "$2" && pwd)"; shift 2 ;;
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
eval "$(python3 - "$FORMATS" <<'MANIFEST_PY'
import json, shlex, sys
I = json.load(open(sys.argv[1]))["install"]
q = lambda xs: " ".join(shlex.quote(str(x)) for x in xs)
print("WOW_VERSION=%s" % shlex.quote(json.load(open(sys.argv[1]))["version"]))
print("ENGINE_FILES=(%s)" % q(I["engine_files"]))
print("ENGINE_DIRS=(%s)"  % q(I["engine_dirs"]))
print("CONFIG_FILE=%s"    % shlex.quote(I["config_file"]))
print("HOOK_NAMES=(%s)"   % q(I["hooks"]))
print("HOOK_MARKER=%s"    % shlex.quote(I["hook_marker"]))
print("HOOK_KEEP=%s"      % shlex.quote(I["preserved_hook_suffix"]))
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
)" || { echo "could not read the install manifest from formats.json" >&2; exit 2; }

DRIFT=0
say() { echo "  $*"; }
drift() { say "$*"; DRIFT=1; }

# ---------------------------------------------------------------- prerequisites
missing_prereq=0
need() { # need <command> <why>
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "  MISSING prerequisite: $1 — $2" >&2; missing_prereq=1
}
for spec in "${REQ_TOOLS[@]}"; do
  need "${spec%%:*}" "required by the package (minimum version ${spec##*:})"
done
for spec in "${OPT_TOOLS[@]}"; do
  t="${spec%%:*}"
  command -v "$t" >/dev/null 2>&1 || \
    echo "  note: optional tool $t (${spec##*:}+) not found — status.mjs will not run; gates are unaffected." >&2
done
git_ver="$(git --version 2>/dev/null | awk '{print $3}')"
case "$git_ver" in
  1.*|2.[0-4].*) echo "  git $git_ver is older than 2.5 — worktree hook inheritance needs 2.5+" >&2 ;;
esac
[ "$missing_prereq" -eq 1 ] && { echo "install aborted: install the prerequisites above" >&2; exit 3; }

# ------------------------------------------------------------------- file copy
copy() { copy_as "$1" "$1"; }

copy_as() { # copy_as <source-relative> <target-relative>
  local rel="$2"
  local src="$SOURCE/$1"
  local dst="$TARGET/$2"
  [ -e "$src" ] || return 0
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

# 2. wow.config.json — created once, never overwritten (it holds repo-local truth)
if [ ! -e "$TARGET/$CONFIG_FILE" ]; then
  if [ "$CHECK" -eq 1 ]; then drift "MISSING  $CONFIG_FILE"
  else
    mkdir -p "$TARGET/$(dirname "$CONFIG_FILE")"
    cat > "$TARGET/$CONFIG_FILE" <<CFG
{
  "wow_version": "$WOW_VERSION",
  "repo": "$(basename "$TARGET")",
  "migrated_from_gsd": false,
  "jira": { "project_key": "<TBD>", "cloud_id": "<TBD>",
            "mapping": { "spec": "Epic", "unit": "Story", "task": "Task", "defect": "Bug" } },
  "merge_to_main": "pr",
  "archive": { "mode": "move", "path": "runs/archive/" },
  "hardening": { "pretooluse_lane_guard": false, "sessionstart_router_injection": false }
}
CFG
    say "wrote    $CONFIG_FILE (template — set the Jira project key)"
  fi
else
  say "ok       $CONFIG_FILE (existing, not overwritten)"
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
  if [ "$CHECK" -eq 1 ]; then
    if [ ! -f "$DST" ] || ! awk "/$START/,/$END/" "$DST" \
         | diff -q - <(printf '%s\n' "$SECTION") >/dev/null 2>&1; then
      drift "DRIFTED  $CLAUDE_FILE wow-v2 section"
    else say "ok       $CLAUDE_FILE wow-v2 section"; fi
  else
    if [ -f "$DST" ] && grep -q -- "$START" "$DST"; then
      # The section is passed as a FILE, never interpolated into the replacement.
      # As a re.sub replacement string, a backslash in the section is an escape:
      # \d raised re.error (leaving CLAUDE.md untouched while the installer
      # printed success) and \g<0> duplicated the whole block, markers included.
      SECFILE="$(mktemp)"; printf '%s\n' "$SECTION" > "$SECFILE"
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
      then say "wrote    $CLAUDE_FILE wow-v2 section (replaced)"
      else echo "  ERROR    $CLAUDE_FILE section not replaced (python3 exited $?)" >&2; DRIFT=1; fi
      rm -f "$SECFILE"
    else
      # Only separate with a blank line when there is prior content to separate from.
      { [ -f "$DST" ] && { cat "$DST"; echo; }; printf '%s\n' "$SECTION"; } > "$DST.tmp" \
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
Load only the files its Load line names.
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

hook_body() { # hook_body <name>
  local name="$1" gate_lines=""
  case "$name" in
    commit-msg) gate_lines='exec_gate gate-1 --quiet "$1"' ;;
    pre-commit) gate_lines='exec_gate gate-5  --quiet --staged
exec_gate gate-11 --quiet --staged' ;;
  esac
  cat <<HOOK
#!/usr/bin/env bash
# $HOOK_MARKER — installed by the WoW v2 package installer (install.sh).
# GATE-1 runs in commit-msg, not pre-commit: the message does not exist yet at
# pre-commit. GATE-5 and GATE-11 run here, on the staged set.
set -u
root="\$(git rev-parse --show-toplevel)"
prev="\$0$HOOK_KEEP"
[ -x "\$prev" ] && { "\$prev" "\$@" || exit \$?; }
if [ ! -x "\$root/scripts/wow/gates.sh" ]; then
  echo "wow-v2: scripts/wow/gates.sh missing or not executable — gates NOT enforced for this commit" >&2
  exit 0
fi
exec_gate() { "\$root/scripts/wow/gates.sh" "\$@" || exit 1; }
$gate_lines
exit 0
HOOK
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
    if [ -f "$dst" ] && ! grep -q "$HOOK_MARKER" "$dst" && [ ! -f "$dst$HOOK_KEEP" ]; then
      mv "$dst" "$dst$HOOK_KEEP"; chmod +x "$dst$HOOK_KEEP"
      say "kept     hook $name -> $name$HOOK_KEEP (chained, runs first)"
    fi
    printf '%s\n' "$body" > "$dst"; chmod +x "$dst"
    say "wrote    hook $name ($HOOKS_WHY)"
  fi
}
for h in "${HOOK_NAMES[@]}"; do write_hook "$h"; done

echo
if [ "$CHECK" -eq 1 ]; then
  [ "$DRIFT" -eq 0 ] && { echo "no drift"; exit 0; } || { echo "DRIFT FOUND — re-run install.sh to upgrade"; exit 1; }
fi
[ "$DRIFT" -eq 0 ] || { echo "install finished WITH ERRORS (see above)"; exit 1; }
echo "installed. Next, in the target repo:"
echo "  1. set the Jira project key in $CONFIG_FILE"
echo "  2. bash scripts/wow/tests/run-all.sh    (one negative test per gate + the wiring test)"
echo "  3. node scripts/wow/status.mjs          (derived status)"
