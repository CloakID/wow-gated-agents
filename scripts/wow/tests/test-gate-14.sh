#!/usr/bin/env bash
# GATE-14 negative test (frisbii PII composition): capture-the-response-whole
# plus a legitimately widened spec scope committed 159 third-party customer
# records with every gate green — the framework had a rule about what must be
# CAPTURED and none about what may be COMMITTED. The controls rule out the two
# ways the gate could cheat: an emptied field must not refuse (or the gate is
# an off switch), and a deliberate capture marked pii-ok must pass VISIBLY.
source "$(dirname "$0")/lib.sh"
FIX="$(setup_fixture_repo)"
echo "GATE-14"

mkdir -p "$FIX/runs/260903-x-r1/evidence"

printf '{"id": 7, "email": "jane@example.net", "plan": "pro"}\n' \
  > "$FIX/runs/260903-x-r1/evidence/customers.json"
assert_rejects "populated email in staged evidence" "$FIX" "personal-data field 'email'" \
  gate-14 --paths runs/260903-x-r1/evidence/customers.json

printf 'name: acme\naddress: 12 Main St\n' > "$FIX/runs/260903-x-r1/evidence/vendor.yaml"
assert_rejects "populated address in staged evidence" "$FIX" "personal-data field 'address'" \
  gate-14 --paths runs/260903-x-r1/evidence/vendor.yaml

# Control 1: the same capture with the field emptied is a declared trim.
printf '{"id": 7, "email": "", "plan": "pro"}\n' \
  > "$FIX/runs/260903-x-r1/evidence/customers.json"
assert_accepts "emptied field passes (declared-trim shape)" "$FIX" \
  gate-14 --paths runs/260903-x-r1/evidence/customers.json

# Control 2: a deliberate capture is possible — and visible.
printf 'pii-ok: PO decision D-9, synthetic tenant only\n{"email": "jane@example.net"}\n' \
  > "$FIX/runs/260903-x-r1/evidence/deliberate.json"
assert_accepts "pii-ok marker admits a deliberate capture visibly" "$FIX" \
  gate-14 --paths runs/260903-x-r1/evidence/deliberate.json

# Control 3: the scan is scoped to evidence paths — source code mentioning an
# email FIELD is not run evidence.
mkdir -p "$FIX/src"
printf 'user.email = form.email\n' > "$FIX/src/form.py"
assert_accepts "non-evidence paths are out of scope" "$FIX" gate-14 --paths src/form.py

# Subject-absent: no scope is not a pass.
assert_rejects "no scope given" "$FIX" "not a pass" gate-14

finish
