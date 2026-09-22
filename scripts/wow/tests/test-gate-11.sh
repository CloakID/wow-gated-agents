#!/usr/bin/env bash
# GATE-11 negative test. The gate is inert in greenfield repos, so the fixture
# flips migrated_from_gsd to true — otherwise this test would prove nothing,
# which is exactly the inert-gate defect the suite exists to catch.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-11"

assert_accepts "inert while migrated_from_gsd is false" "$FIX" gate-11 --paths .planning/STATE.md

printf '{"migrated_from_gsd": true}\n' > "$FIX/scripts/wow/wow.config.json"
# ADV-R9-09: gate-11 reads the config the COMMIT will carry (the index), so
# flipping the freeze on -- like flipping it off -- must be staged to bind.
( cd "$FIX" && git add scripts/wow/wow.config.json )
assert_rejects "touching frozen .planning/ once migrated" "$FIX" "frozen .planning/" gate-11 --paths .planning/STATE.md
assert_accepts "touching anything else once migrated" "$FIX" gate-11 --paths docs/README.md

# The premise check: the staged set filtered deletions out, so `git rm` on the
# frozen tree — erasing the history the gate exists to preserve — was allowed.
mkdir -p "$FIX/.planning"
printf 'history\n' > "$FIX/.planning/STATE.md"
( cd "$FIX" && git add -A >/dev/null && git commit -qm "planning [WOW:publish]" \
  && git rm -q .planning/STATE.md )
assert_rejects "staged DELETION of frozen history" "$FIX" "frozen .planning/" gate-11 --staged
( cd "$FIX" && git reset -q --hard HEAD )

printf 'edited\n' > "$FIX/.planning/STATE.md"
( cd "$FIX" && git add -A >/dev/null )
assert_rejects "staged EDIT of frozen history" "$FIX" "frozen .planning/" gate-11 --staged

# ---- prodsim/F-60 (v0.7.3): a live runtime path is carved OUT of the freeze
# via wow.config.json legacy_freeze_exclude — telemetry appenders writing
# .planning/history/*.ndjson made the wholesale freeze unusable, and the
# pilot forwent GATE-11 entirely against a demonstrated risk.
( cd "$FIX" && git reset -q --hard HEAD )
python3 - "$FIX/scripts/wow/wow.config.json" <<'PY'
import json,sys
p=sys.argv[1]; c=json.load(open(p)); c["legacy_freeze_exclude"]=[".planning/history/**"]
open(p,"w").write(json.dumps(c)+"\n")
PY
# ADV-R10-02 (R9b): the exclusion binds only once COMMITTED — its own commit.
( cd "$FIX" && git add scripts/wow/wow.config.json \
  && git commit -qm "carve out live telemetry [WOW:publish]" -- scripts/wow/wow.config.json )
mkdir -p "$FIX/.planning/history"
printf '{"outage": 1}\n' > "$FIX/.planning/history/gateway.ndjson"
( cd "$FIX" && git add -A >/dev/null )
assert_accepts "excluded live path commits through the freeze (F-60)" "$FIX" gate-11 --staged
# Control: everything OUTSIDE the exclude stays frozen — the carve-out must
# not have become an off switch.
( cd "$FIX" && git reset -q --hard HEAD )
printf 'edited again\n' > "$FIX/.planning/STATE.md"
( cd "$FIX" && git add -A >/dev/null )
assert_rejects "non-excluded frozen path still refused (F-60 control)" "$FIX" \
  "frozen .planning/" gate-11 --staged

# ---- ADV-R9-09 + ADV-R10-02 (v0.7.3 R9/R9b): only the COMMITTED exclude
# disarms. The R9 index read was defeated by commit-then-amend in two plain
# commands; an exclusion must land as its own reviewable commit first.
( cd "$FIX" && git reset -q --hard HEAD )
python3 - "$FIX/scripts/wow/wow.config.json" <<'PY'
import json,sys
p=sys.argv[1]; c=json.load(open(p)); c["legacy_freeze_exclude"]=[".planning/*", ".planning/**"]
open(p,"w").write(json.dumps(c)+"\n")
PY
( cd "$FIX" && git rm -q .planning/STATE.md )
assert_rejects "worktree-only exclude does not disarm the freeze (ADV-R9-09)" "$FIX" \
  "frozen .planning/" gate-11 --staged
# STAGED is not enough either (the amend bypass) -- and the refusal names the remedy.
( cd "$FIX" && git add scripts/wow/wow.config.json )
assert_rejects "staged-but-uncommitted exclude does not disarm (ADV-R10-02)" "$FIX" \
  "commit the exclusion first" gate-11 --staged
# Control: the exclusion COMMITTED as its own reviewable commit carves out,
# and the PASS names the active list.
( cd "$FIX" && git reset -q -- .planning 2>/dev/null; git checkout -q -- .planning 2>/dev/null
  cd "$FIX" && git commit -qm "carve out live telemetry paths [WOW:publish]" -- scripts/wow/wow.config.json )
( cd "$FIX" && git rm -q .planning/STATE.md )
assert_accepts "committed exclude carves out (ADV-R10-02 control)" "$FIX" gate-11 --staged
assert_output "the PASS names the active committed exclude list (ADV-R9-09)" "$FIX" \
  "active legacy_freeze_exclude" gate-11 --staged
( cd "$FIX" && git reset -q --hard HEAD )
# ---- prodsim/F-82 (v0.7.4): a SYMLINKED checkout must not empty the exclude
# list — macOS /tmp is a symlink, relpath arithmetic escaped the repo, git
# show failed silently and the freeze blocked the very paths F-60 carved out.
LINKBASE="$(mktemp -d)"
ln -s "$FIX" "$LINKBASE/via-symlink"
mkdir -p "$FIX/.planning/history"
printf '{"outage": 2}\n' > "$FIX/.planning/history/edge.ndjson"
( cd "$LINKBASE/via-symlink" && git add .planning/history/edge.ndjson )
assert_accepts "committed exclude still carves out through a symlinked path (F-82)" \
  "$LINKBASE/via-symlink" gate-11 --staged
( cd "$FIX" && git reset -q --hard HEAD )
# corrupt committed config is LOUD, never an empty-and-frozen set (F-12's rule)
( cd "$FIX" && printf 'not json {' > scripts/wow/wow.config.json \
  && git add scripts/wow/wow.config.json \
  && git commit -qm "corrupt [WOW:publish]" --no-verify ) >/dev/null 2>&1
assert_rejects "unreadable committed config refuses loudly, never guesses (F-82/F-12)" "$FIX" \
  "could not be READ" gate-11 --staged
( cd "$FIX" && git reset -q --hard HEAD~1 )
rm -rf "$LINKBASE"
# ---- ADV-R11-07 (R11b): a corrupt HEAD config is repairable, and refuses only when armed
( cd "$FIX" && printf 'not json {' > scripts/wow/wow.config.json \
  && git add scripts/wow/wow.config.json && git commit -qm "corrupt [WOW:publish]" --no-verify ) >/dev/null 2>&1
printf '{"migrated_from_gsd": false}\n' > "$FIX/scripts/wow/wow.config.json"
( cd "$FIX" && git add scripts/wow/wow.config.json )
assert_accepts "the repair commit for a corrupt HEAD config is committable when nothing is frozen (ADV-R11-07)" \
  "$FIX" gate-11 --staged
printf '{"migrated_from_gsd": true}\n' > "$FIX/scripts/wow/wow.config.json"
( cd "$FIX" && git add scripts/wow/wow.config.json && git rm -q --cached .planning/STATE.md 2>/dev/null; true )
assert_rejects "corrupt HEAD while the freeze is ARMED refuses — the committed carve-out is unknowable (ADV-R11-07)" \
  "$FIX" "at HEAD could not be READ" gate-11 --staged
( cd "$FIX" && git reset -q --hard HEAD~1 )
finish
