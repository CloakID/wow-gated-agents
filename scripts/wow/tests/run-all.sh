#!/usr/bin/env bash
# Runs every gate's negative test plus the wiring test. GATE-4 checks that this
# directory holds one test per gate AND the wiring test, so a new gate without a
# test — or a gate whose only proof is that gates.sh can be called by hand —
# fails the sweep.
cd "$(dirname "$0")"
rc=0
for t in test-gate-*.sh test-install.sh; do
  [ -f "$t" ] || continue
  bash "$t" || rc=1
done
echo
[ "$rc" -eq 0 ] && echo "ALL GATE TESTS PASSED" || echo "GATE TESTS FAILED"
exit $rc
