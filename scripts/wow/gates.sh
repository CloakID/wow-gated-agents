#!/usr/bin/env bash
# WoW v2 mechanical gates — single entry point.
#
# Patterns, vocabulary and schemas live in scripts/wow/formats.json, shared with
# status.mjs. This wrapper delegates to gates.py, which does the JSON and glob
# work bash cannot do honestly. GATES-SPEC names "gates.sh"; that is this file,
# and it remains the only thing hooks and playbooks call.
#
#   gates.sh list                      what each gate does and where it runs
#   gates.sh gate-1 <msgfile>          commit-msg hook
#   gates.sh gate-5 --staged           pre-commit hook
#   gates.sh gate-11 --staged          pre-commit hook
#   gates.sh gate-8 --run <run-id>     G2, before review
#   gates.sh gate-10 --run <id> --gate G2
#   gates.sh sweep [--run <run-id>]    full sweep at every gate and P5
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gates.py" "$@"
