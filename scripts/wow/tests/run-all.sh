#!/usr/bin/env bash
# Runs every gate's negative test. GATE-4 checks that this directory holds one
# test per gate, so a new gate without a test fails the sweep.
cd "$(dirname "$0")"
rc=0
for t in test-gate-*.sh; do
  bash "$t" || rc=1
done
echo
[ "$rc" -eq 0 ] && echo "ALL GATE TESTS PASSED" || echo "GATE TESTS FAILED"
exit $rc
