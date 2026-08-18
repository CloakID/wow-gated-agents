#!/usr/bin/env bash
# GATE-12 negative test — the obligation block at /wow-spec (FORMATS §12).
#
# The gate's job: a new-feature spec is refused while a blocks-new-feature-work
# obligation is open. The controls rule out the two ways it could cheat:
# an advisory row must NOT refuse (or the gate is just an off switch), and a
# discharged row must NOT refuse (or nothing can ever be worked off).
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-12"

gaps() { mkdir -p "$FIX/docs"; cat > "$FIX/docs/GAPS.md"; }
HDR='| id | tag | owner | effect | successor | discharge | ev |
|---|---|---|---|---|---|---|'

# Subject-absent: no registry is not "no obligations".
assert_rejects "no docs/GAPS.md at all (subject-absent)" "$FIX" "not a pass" gate-12 --kind feature

# Positive control 1: an empty registry is a valid registry.
gaps <<< "$HDR"
assert_accepts "empty registry, feature spec" "$FIX" gate-12 --kind feature

# The core refusal.
gaps << G
$HDR
| OBL-T-01 | impl_gap | maintainer | blocks-new-feature-work | fix run | engine lands | ev:commit{abc1234} |
G
assert_rejects "open blocking row refuses a feature spec" "$FIX" "OBL-T-01" gate-12 --kind feature
assert_rejects "default kind is feature (safe default)" "$FIX" "OBL-T-01" gate-12

# Exemption path: discharge specs must name what they discharge.
assert_rejects "fix spec without --ref" "$FIX" "exempt only when it references" gate-12 --kind fix
assert_rejects "fix spec referencing a non-open id" "$FIX" "exempt only when it references" gate-12 --kind fix --ref OBL-T-99
assert_accepts "fix spec referencing the open obligation" "$FIX" gate-12 --kind fix --ref OBL-T-01
assert_accepts "audit spec referencing the open obligation" "$FIX" gate-12 --kind audit --ref OBL-T-01

# Control 2: advisory does not block — or the gate is an off switch.
gaps << G
$HDR
| OBL-T-02 | test_gap | maintainer | advisory | later | tests exist | ev:commit{abc1234} |
G
assert_accepts "advisory-only registry, feature spec" "$FIX" gate-12 --kind feature

# Control 3: a discharged row (struck id) does not block.
gaps << G
$HDR
| ~~OBL-T-01~~ | impl_gap | maintainer | blocks-new-feature-work | fix run | engine lands | ev:commit{abc1234} discharged ev:commit{def5678} |
G
assert_accepts "discharged blocking row, feature spec" "$FIX" gate-12 --kind feature

# Closed enum: an unrecognized effect fails LOUDLY, never as non-blocking
# (v0.5.6, pilot N3 — the silent downgrade was the bad failure mode).
gaps << G
$HDR
| OBL-T-03 | impl_gap | maintainer | blocks-pilot-reinstall | later | later | ev:commit{abc1234} |
G
assert_rejects "effect outside the closed vocabulary fails loudly" "$FIX" "closed vocabulary" gate-12 --kind feature

# blocks-install is install.sh's consumer, not gate-12's: it must not refuse a spec.
gaps << G
$HDR
| OBL-T-04 | process_debt | PO | blocks-install (scope: *) | merge | merged | ev:commit{abc1234} |
G
assert_accepts "blocks-install row does not refuse a spec (wrong consumer)" "$FIX" gate-12 --kind feature

# review FR-1: a registry whose rows the schema cannot read must fail LOUDLY,
# never parse as an empty (= permissive) registry. This is frisbii's real
# legacy table shape: 5 columns, G-nn ids.
gaps << G
| # | Taxonomy | Gap | Owner | Discharge |
|---|---|---|---|---|
| G-17 | framework-defect | gate-6 vacuous without plan | upstream | fixed upstream |
| G-11 | framework-defect | gate-2 scope | upstream | merged |
G
assert_rejects "legacy 5-column G-nn registry fails loudly, not as empty" "$FIX" "cells" gate-12 --kind feature

# Unknown kind is an error, not a bypass.
assert_rejects "unknown --kind" "$FIX" "unknown --kind" gate-12 --kind yolo

finish
