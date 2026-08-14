#!/usr/bin/env bash
# WoW v2 per-repo installer. Idempotent — re-run to upgrade.
#
#   install.sh <target-repo>        install or upgrade
#   install.sh --check <target>     report drift, change nothing
#   install.sh --source <dir> ...   canonical package to install from
#                                   (defaults to the repo holding this script)
#
# Writes only repo-scoped things: the WoW section of CLAUDE.md between its
# markers, docs/process/, scripts/wow/, .claude/commands/wow-*.md, and the git
# hooks. Everything else in the target is left alone. Repos that have not
# adopted WoW are untouched — the frameworks never interact across repos.
#
# Hooks are written to the COMMON git dir, so every worktree inherits them and
# executor enforcement is free.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SELF"   # canonical package = the repo holding this script
CHECK=0
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check)  CHECK=1; shift ;;
    --source) SOURCE="$(cd "$2" && pwd)"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) TARGET="$1"; shift ;;
  esac
done
[ -z "$TARGET" ] && { echo "usage: install.sh [--check] [--source <dir>] <target-repo>" >&2; exit 2; }
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "no such target" >&2; exit 2; }
git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || { echo "target is not a git repo" >&2; exit 2; }

DRIFT=0
say() { [ "$CHECK" -eq 1 ] && echo "  $*" || echo "  $*"; }

copy() { copy_as "$1" "$1"; }

copy_as() { # copy_as <source-relative> <target-relative>
  local rel="$2"
  local src="$SOURCE/$1"
  local dst="$TARGET/$2"
  [ -e "$src" ] || return 0
  # bug 2 guard: installing a repo onto itself is a legitimate no-op (it is how
  # the pilot repo re-runs its own installer), not an error.
  if [ "$src" -ef "$dst" ]; then say "ok       $rel (source is target)"; return 0; fi
  if [ "$CHECK" -eq 1 ]; then
    if [ ! -e "$dst" ]; then say "MISSING  $rel"; DRIFT=1
    elif ! diff -rq "$src" "$dst" >/dev/null 2>&1; then say "DRIFTED  $rel"; DRIFT=1
    else say "ok       $rel"; fi
  else
    if [ -d "$src" ]; then
      # cp -R src dst nests src INSIDE dst when dst already exists. Copy the
      # contents instead, or a re-run produces scripts/wow/tests/tests.
      mkdir -p "$dst"; cp -R "$src/." "$dst/"
    else
      mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"
    fi
    say "wrote    $rel"
  fi
}

echo "WoW v2 $( [ "$CHECK" -eq 1 ] && echo check || echo install ): $SOURCE -> $TARGET"

# 1. process docs and engine
copy docs/process
copy scripts/wow/gates.sh
copy scripts/wow/gates.py
copy scripts/wow/formats.json
copy scripts/wow/status.mjs
copy_as GATES-SPEC.md scripts/wow/GATES-SPEC.md
copy scripts/wow/permissions-policy.json
copy scripts/wow/tests

# 2. wow.config.json — created once, never overwritten (it holds repo-local truth)
if [ ! -e "$TARGET/scripts/wow/wow.config.json" ]; then
  if [ "$CHECK" -eq 1 ]; then say "MISSING  scripts/wow/wow.config.json"; DRIFT=1
  else
    mkdir -p "$TARGET/scripts/wow"
    cat > "$TARGET/scripts/wow/wow.config.json" <<CFG
{
  "wow_version": "0.4-draft",
  "repo": "$(basename "$TARGET")",
  "migrated_from_gsd": false,
  "jira": { "project_key": "<TBD>", "cloud_id": "<TBD>",
            "mapping": { "spec": "Epic", "unit": "Story", "task": "Task", "defect": "Bug" } },
  "merge_to_main": "pr",
  "archive": { "mode": "move", "path": "runs/archive/" },
  "hardening": { "pretooluse_lane_guard": false, "sessionstart_router_injection": false }
}
CFG
    say "wrote    scripts/wow/wow.config.json (template — set the Jira project key)"
  fi
else
  say "ok       scripts/wow/wow.config.json (existing, not overwritten)"
fi

# 3. CLAUDE.md WoW section, between markers, rest of the file untouched
if [ -f "$SOURCE/CLAUDE-WOW-SECTION.md" ]; then
  # Package layout: the router lives in CLAUDE-WOW-SECTION.md, unwrapped. Take
  # everything from the first "## Way of Working" heading and add the markers.
  SECTION="$(printf '<!-- wow-v2:start -->\n%s\n<!-- wow-v2:end -->' \
    "$(awk '/^## Way of Working/,0' "$SOURCE/CLAUDE-WOW-SECTION.md")")"
  SECTION_SRC="$SOURCE/CLAUDE-WOW-SECTION.md"
else
  SECTION_SRC="$SOURCE/CLAUDE.md"
  SECTION="$(awk '/<!-- wow-v2:start -->/,/<!-- wow-v2:end -->/' "$SECTION_SRC" 2>/dev/null)"
fi
if [ -f "$SECTION_SRC" ]; then
  if [ -n "$SECTION" ]; then
    DST="$TARGET/CLAUDE.md"
    if [ "$CHECK" -eq 1 ]; then
      if [ ! -f "$DST" ] || ! awk '/<!-- wow-v2:start -->/,/<!-- wow-v2:end -->/' "$DST" \
           | diff -q - <(printf '%s\n' "$SECTION") >/dev/null 2>&1; then
        say "DRIFTED  CLAUDE.md wow-v2 section"; DRIFT=1
      else say "ok       CLAUDE.md wow-v2 section"; fi
    else
      if [ -f "$DST" ] && grep -q '<!-- wow-v2:start -->' "$DST"; then
        python3 - "$DST" <<PY
import sys, re, io
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
new = """$SECTION"""
s = re.sub(r"<!-- wow-v2:start -->.*?<!-- wow-v2:end -->", new, s, flags=re.S)
io.open(p, "w", encoding="utf-8").write(s)
PY
        say "wrote    CLAUDE.md wow-v2 section (replaced)"
      else
        # Only separate with a blank line when there is prior content to separate from.
        { [ -f "$DST" ] && { cat "$DST"; echo; }; printf '%s\n' "$SECTION"; } > "$DST.tmp" \
          && mv "$DST.tmp" "$DST"
        say "wrote    CLAUDE.md wow-v2 section (appended)"
      fi
    fi
  fi
fi

# 4. command stubs — pointers only; the playbooks stay the single home
mkcmd() {
  local name="$1"
  local body="$2"
  local dst="$TARGET/.claude/commands/wow-$name.md"
  if [ "$CHECK" -eq 1 ]; then
    # Compare both sides through $( ), which strips trailing newlines from each.
    # Comparing a stripped $(cat) against an unstripped $body reported drift on
    # every stub on a clean install.
    if [ ! -f "$dst" ] || [ "$(cat "$dst")" != "$(printf '%s' "$body")" ]; then
      say "DRIFTED  .claude/commands/wow-$name.md"; DRIFT=1
    else say "ok       .claude/commands/wow-$name.md"; fi
  else
    mkdir -p "$TARGET/.claude/commands"; printf '%s' "$body" > "$dst"
  fi
}
for pair in "ground:P0-GROUND" "spec:P1-SPEC" "plan:P2-PLAN" "run:P3-RUN" \
            "report:P4-REPORT" "publish:P5-PUBLISH" "quick:LANES" "debug:LANES"; do
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
[ "$CHECK" -eq 0 ] && say "wrote    .claude/commands/wow-*.md (9 stubs)"

# 5. git hooks in the COMMON git dir, inherited by every worktree
COMMON="$(git -C "$TARGET" rev-parse --git-common-dir)"
case "$COMMON" in /*) ;; *) COMMON="$TARGET/$COMMON" ;; esac
HOOKS="$COMMON/hooks"
write_hook() {
  local name="$1"
  local body="$2"
  local dst="$HOOKS/$name"
  if [ "$CHECK" -eq 1 ]; then
    if [ ! -f "$dst" ] || ! grep -q 'gates.sh' "$dst"; then say "MISSING  hook $name"; DRIFT=1
    else say "ok       hook $name"; fi
  else
    mkdir -p "$HOOKS"; printf '%s' "$body" > "$dst"; chmod +x "$dst"; say "wrote    hook $name"
  fi
}
write_hook commit-msg '#!/usr/bin/env bash
# WoW v2 GATE-1 — a laneless commit cannot land. Installed by scripts/wow/install.sh.
# GATE-1 runs here, not in pre-commit: the message does not exist yet at pre-commit.
root="$(git rev-parse --show-toplevel)"
[ -x "$root/scripts/wow/gates.sh" ] || exit 0
exec "$root/scripts/wow/gates.sh" gate-1 --quiet "$1"
'
write_hook pre-commit '#!/usr/bin/env bash
# WoW v2 GATE-5 and GATE-11 on staged files. Installed by scripts/wow/install.sh.
root="$(git rev-parse --show-toplevel)"
[ -x "$root/scripts/wow/gates.sh" ] || exit 0
"$root/scripts/wow/gates.sh" gate-5  --quiet --staged || exit 1
"$root/scripts/wow/gates.sh" gate-11 --quiet --staged || exit 1
'

echo
if [ "$CHECK" -eq 1 ]; then
  [ "$DRIFT" -eq 0 ] && { echo "no drift"; exit 0; } || { echo "DRIFT FOUND — re-run install.sh to upgrade"; exit 1; }
fi
echo "installed. Next, in the target repo:"
echo "  1. set the Jira project key in scripts/wow/wow.config.json"
echo "  2. bash scripts/wow/tests/run-all.sh    (one negative test per gate)"
echo "  3. node scripts/wow/status.mjs          (derived status)"
