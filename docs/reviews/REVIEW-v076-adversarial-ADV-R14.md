# ADV-R14 — adversarial review of v0.7.6-draft (fresh context; test-only portability patch, advisor/F-200)

> **Disposition (R14b, 2026-11-03):** 01 (a helper whose edit does not land now counts a FAIL and returns 1 — M239), 02 (tripwire widened: any `-…i` sed flag without a suffix, `--in-place`, `/usr/bin/sed`, `xargs … -r`, `grep -…P`, `touch --date`, `stat --format`, `readlink -e`, `sort --version-sort`; the exempt line is the definition itself, not a tag; INSTALL/README/CHANGELOG say "listed forms", not "any"; engine files stay unscanned — their only argv is git, stated), 03 (641 re-derived after the R14b changes), 04 (`test-gate-13.sh:512` asserts the marker landed; tally restated as 11 live + 2 dead sites, 12 red assertions), 05 (the parity-control re-derivation is in the CHANGELOG fix bullet), 06 (README/INSTALL hedged to "written to run unchanged … measured on: see CHANGELOG"; the two "every/only" sentences corrected in lib.sh and INSTALL), 07 (noted in the CHANGELOG class-sweep sentence: `install.sh:453`'s `1a\` form is outside the list and exercised by every macOS install since v0.7.4; not a finding).

**Scope.** Test-only portability patch for advisor/F-200: 13 fixture sites moved from `sed -i '…'` / `touch -d` to three python3 helpers in `scripts/wow/tests/lib.sh`; a GNU-only-form tripwire in `test-install.sh`; a raw-string docstring in `gates.py`; version bump 0.7.5 → 0.7.6; GAPS OBL-PKG-25…29 → v0.7.7; README/INSTALL/CHANGELOG text.

**Method (all in copies; `/home/claude/engine` untouched).** Container: Linux, GNU userland, Python 3.13.18, GNU sed. No BSD userland available here, so macOS behaviour is reasoned from BSD semantics, not run.

1. **Fidelity, empirically.** `/tmp/r14/instr` = copy with `lib.sh` instrumented so every `replace_in_file`/`resub_in_file`/`backdate_file` call snapshots the fixture file (and `stat %Y %X`) before and after, plus its arguments, into `/tmp/r14/snap/`. Ran the four touched tests. Then `/tmp/r14/replay2.sh` applies the 11 OLD GNU `sed -i` lines — copied verbatim from the 7fafbaf tree (checked by `diff` against `grep 'sed -i'` of the old files: "REPLAY LINES VERBATIM") — to each `-before` snapshot and `cmp`s against the helper's `-after`.
2. **Semantics.** Occurrence counts per site (literal `str.count` for `replace_in_file`, `re.findall(flags=M)` for `resub_in_file`); mutation of a helper argument to a no-match to see what the suite reports; helpers turned into no-ops to re-derive the "12 red" breakdown.
3. **Tripwire.** 50 probe strings against the exact `GNU_ONLY` regex; two mutation copies (M236/M237 replica; an evasion set).
4. **Sweep.** A ~45-pattern GNU-ism regex over `install.sh`, `gates.sh`, `tests/*.sh`; argv inspection of every `subprocess.*` in `gates.py` and every `execFileSync` in `status.mjs`.
5. **Suite.** `run-all.sh` on the patched copy and on a 7fafbaf checkout (`/tmp/r14/oldtree`); `python3 -W error -c "import ast; …"` on both `gates.py`; `gates.sh parity`.
6. **Stamps/docs.** `git log -1 --format=%s -- <file>` vs each `DRAFT vX` header; formats.json vs CHANGELOG top entry; README/CHANGELOG numbers vs what the tree and the runs show.
7. **Leakage.** `git show 97447a6 | grep -iE 'advisor|/Users/|/home/|…'`.

## Verdict

**Sound to ship after two small edits; not as-is.** Every rewritten site is byte-for-byte what the old GNU sed produced (11/11 `cmp` identical; `backdate_file` sets the mtime the gate reads), no assertion's expected outcome changed, the suite is green (640), the AST warning is gone, parity passes, stamps are consistent, no consumer content leaks. What does not hold is some of the prose: the CHANGELOG's assertion count is wrong (641 vs an actual 640), the "refuses a no-match" property of the helpers is stderr-only and cannot turn the suite red (demonstrated: a failed edit → "29 passed", exit 0 — and one of the 13 sites, `test-gate-13.sh:512`, is already exactly that: dead on both platforms, undetected), and INSTALL's "refuses **any** GNU-only command form … structural" is a regex blocklist that `sed -E -i`, `/usr/bin/sed -i`, `xargs -0 -r` and a `# tripwire-def` suffix all walk past. Fix the number, downgrade the two claims (or make the helpers count a FAIL, five lines), and it ships.

## Findings

**ADV-R14-01 — MEDIUM — CONFIRMED — the helpers' "refuses a no-match" is a stderr line and an exit code nobody reads; a failed fixture edit leaves the suite green**
`scripts/wow/tests/lib.sh:40-47` (`replace_in_file`), `:48-57` (`resub_in_file`); callers at the 11 sites; `lib.sh:13` is `set -uo pipefail` with no `-e`, and no call site does `|| FAIL=…`.
Repro (copy `/tmp/r14/mut1`): change the OLD argument of the `test-gate-13.sh:512` call to `'THIS-DOES-NOT-EXIST'`, run `bash scripts/wow/tests/test-gate-13.sh`:
```
replace_in_file: 'THIS-DOES-NOT-EXIST' not found in /tmp/tmp.72YAlFwWqe/runs/260925-mb-r1/PLAN.md
  ok   verify-cmd drops the lint-ok marker (ADV-R12-17)
  -> 29 passed
exit=0
```
Why it matters: CHANGELOG line 11 sells this as the closing of "a silent no-op is how the defect hid". It is now a *loud* no-op with the same outcome: PASS/FAIL counts and `run-all.sh`'s exit code are unchanged. The suite still relies on the next assertion happening to notice — which is exactly the property the patch itself shows is not guaranteed (see ADV-R14-04: `test-gate-13.sh:512`'s assertion passes with the edit never made, on Linux and on macOS alike). Fix: `FAIL=$((FAIL+1))` on the helper's non-zero path (the helpers run in the test's own shell, `FAIL` is in scope), or `|| { echo "  FAIL fixture edit …"; FAIL=$((FAIL+1)); }` at each site.

**ADV-R14-02 — MEDIUM — CONFIRMED — the tripwire is a finite blocklist; INSTALL's "refuses any GNU-only command form" and "structural" are overstated, and an annotation hides a hit**
`scripts/wow/tests/test-install.sh:463` (`GNU_ONLY`), `:464` (`grep -v 'tripwire-def'`); claim at `INSTALL.md:14` and `README.md:28`.
Repro (copy `/tmp/r14/mut3`): append to `scripts/wow/tests/test-gate-1.sh`
```
sed -E -i 's/a/b/' /dev/null
sed -i -e x f  # tripwire-def
/usr/bin/sed -i 's/a/b/' f
find . -print0 | xargs -0 -r echo
```
then `bash scripts/wow/tests/test-install.sh | grep GNU-only` →
```
  ok   no GNU-only command form in scripts/wow/tests/*.sh, install.sh, gates.sh (advisor/F-200)
```
Probe table against the regex (`printf '%s\n' "$s" | grep -qE "$GNU_ONLY"`): misses `sed -Ei`, `sed -E -i`, `sed -n -i`, `sed -ie`, `sed --in-place`, `sed  -i` (two spaces), `$SED -i`, `/usr/bin/sed -i` (the `[^A-Za-z_./-]` prefix class excludes `/`), `grep -oP`, `xargs -0 -r`, `date +%s -d now`, `touch --date=`, `stat --format`, `readlink -e`, `sort --version-sort`, a `-i` on a continuation line, and any line carrying the string `tripwire-def`. Hits correctly: `sed -i 's…`, `sed -i''`, `sed -i""`, `sed -i -e`, `sed -i \`, `$(date -d …)`, `date --date`, `touch -d`, `find … -printf`, `mktemp --suffix`, `head -n -2`. False positives are limited to GNU forms quoted inside a string or trailing comment on a code line (none exist today; the suite is green).
Why it matters: the engine files (`gates.py`, `status.mjs`) are not scanned at all (acceptable today: their only argv is `git`, see Held), and the shell scan is a list, not a grammar. The right wording is "refuses the GNU-only forms F-200 found and the common neighbours (list)" — not "any". The `tripwire-def` exclusion should be anchored to the one defining line (e.g. exclude only `test-install.sh:463` by `grep -v "^$PKG_DIR/scripts/wow/tests/test-install.sh:463:"` or by matching `GNU_ONLY='`), and `sed -[A-Za-z]*i[^.A-Za-z]` would cover the `-Ei`/`-ni`/`-ie` family. Mutation M236/M237 replica (copy `/tmp/r14/mut2`) does go red naming file:line — the tripwire works for the shape that bit.

**ADV-R14-03 — LOW — CONFIRMED — CHANGELOG states "639 → 641 assertions green"; the suite has 640**
`CHANGELOG.md:13`.
Repro: `bash scripts/wow/tests/run-all.sh 2>&1 | grep -E '^\s+-> ' | awk '{p+=$2} END{print p}'` → `640` (per file: 33 17 15 29 29 6 38 35 81 9 24 31 84 46 29 36 98). Old tree (`/tmp/r14/oldtree`, 7fafbaf): 637 passed + 2 FAILED = 639. The patch adds exactly one assertion (the tripwire); the two 3.13 reds were already counted in 639. 639 + 1 = 640.
Why it matters: the top CHANGELOG entry is the package's single authority and the number is the entry's evidence line; v0.7.5's entry carries a per-file breakdown that this one will be read against.

**ADV-R14-04 — LOW — CONFIRMED — the "one dead site" narrative is incomplete: `test-gate-13.sh:512` (ADV-R12-17) is a second site nothing depends on, and the 12-red tally balances only because `test-gate-8.sh:986` yields two reds**
`CHANGELOG.md:10` ("counted the `touch -d` at `:529`, which nothing has depended on … the 12 red assertions are the same 12 either way"), `README.md:28`.
Repro (copy `/tmp/r14/noop`, all three helpers `return 0`): per-file reds are 13:1, 7:2, 8:8, parity:1 = 12 — matches the entry. But the 8 in gate-8 come from 7 sed sites (`:986` is followed by two `assert_rejects`), and in test-gate-13 only the `:477` site goes red; `:512` prints `ok   verify-cmd drops the lint-ok marker (ADV-R12-17)` with its edit never applied, because `verify-cmd` prints `printf 'a|b' | grep -c a` whether or not ` lint-ok: deliberate` is in the cell. So the honest count is 11 live sites + 2 dead (`7:529`, `13:512`), 12 assertions. On macOS v0.7.5 that assertion was green for the wrong reason, and it still would be under this patch if the edit ever stopped matching (ADV-R14-01). Suggested one-line hardening at `test-gate-13.sh:513`: also assert the marker is present in the PLAN before calling `verify-cmd` (`grep -q 'lint-ok: deliberate' …PLAN.md`), or make the helper count.

**ADV-R14-05 — LOW — CONFIRMED — a 14th code change (parity control re-derived from formats.json) is load-bearing for the bump and absent from CHANGELOG/README**
`scripts/wow/tests/test-gate-parity.sh:224-225` (diff lines 279-281).
Repro (copy `/tmp/r14/mut6`): restore the old `printf '# Changelog\n\n## v0.7.5-draft …'` line and run `bash scripts/wow/tests/test-gate-parity.sh` → `FAIL rejected valid input: x.y.z-draft in both authorities passes (control)` / `-> 35 passed, 1 FAILED`.
Why it matters: the entry says "every site rewritten … no assertion's expected outcome changed" and lists three helpers and a tripwire; a reader diffing the suite finds a fourth kind of change whose only explanation is the trailing comment on the line. It is the right fix (the control pinned the version), it is just unrecorded. One clause in the Fix bullet suffices.

**ADV-R14-06 — LOW — CONFIRMED — README/INSTALL assert macOS behaviour as fact; CHANGELOG says the macOS run is pending; two "every/only" sentences are literally false**
`README.md:3` ("the self-test suite now builds its fixtures identically on macOS and Linux"), `INSTALL.md:14` ("runs unchanged on macOS (BSD userland, stock bash 3.2) … structural since v0.7.6"), vs `CHANGELOG.md:13` ("macOS: PO run on the originating machine … recorded in this entry when it comes back"). Also `INSTALL.md:14` "every in-place fixture edit or back-dating goes through python3" and `lib.sh:23-24` "these three helpers are the only in-place edit and back-dating the suite performs" — `scripts/wow/tests/test-gate-7.sh:18` back-dates with `touch -t 202601010000` (portable, but not python3), and a dozen `python3 - "$FIX/…" <<'PY'` blocks rewrite fixtures in place without the helpers (e.g. `test-gate-7.sh:128,295,468`, `test-gate-15.sh:62`).
Why it matters: the CHANGELOG is honest; the two consumer-facing docs are not hedged the same way. Nothing I can see in the helpers would fail on BSD/bash 3.2 (`python3 - … <<'PY'` in a function, no heredoc inside `$( )`, `grep -nE` with POSIX classes, a literal `'` in the ERE), so this is a wording risk, not a code risk — but the entry's own "Proven against" line is what the README should mirror until the macOS result lands.

**ADV-R14-07 — LOW — PLAUSIBLE — `install.sh:453` `sed -e "1a\\<newline>"` (append an empty line) is outside the tripwire's list and not verified on BSD here**
`install.sh:453-456`: `sed -e "1a\\` + newline + `" -e "\$i\\` + continuation lines. GNU accepts `a\` followed by an empty text line; BSD sed's `a\` text grammar is stricter (FreeBSD `compile_text`) and I cannot run it in this container. Reachable on macOS at every install that writes the CLAUDE.md section. It predates the patch and the three macOS pilots have presumably exercised it, so this is a note for the "class sweep" claim ("none in an engine or installer file" holds for the patch's pattern list, not for every BSD-divergent sed form), not a defect I can confirm.

## Held (tried, and it held)

- **Fidelity, 11/11 byte-identical.** `/tmp/r14/replay2.sh` output: `SAME` for `test-gate-13.sh-01` (`\|\|` → `; rc=$?; case $rc in 0\|1) …`), `test-gate-13.sh-02` (the `"| \`printf 'a\\|b' \\| grep -c a\` |"` double-quoted site: bash yields `` | `printf 'a\|b' \| grep -c a` | `` — the same bytes the old `.a\\|b.` BRE matched), `test-gate-7.sh-03`, `test-gate-8.sh-01…07` (incl. `:986`/`:989` `\&\&` → literal `&&`, and `:1058` `&\n` → `\g<0>\n` producing a real second row), `test-gate-parity.sh-01`. A first replay attempt through `eval` showed three DIFFs — that was my quoting layer, not the patch; the verbatim replay is clean.
- **All-vs-first-per-line is moot at every site.** OLD occurs exactly once in each `replace_in_file` before-file (13-01, 13-02, 7-03, 8-04, 8-05, 8-06, parity-01: 1 each); each `resub_in_file` regex matches exactly once (8-01, 8-02, 8-03, 8-07). Python `^`/`$` under `re.M` equal sed's line anchors here; `\.` escapes added in the regex sites (`notes\.md`, `T31`, `RUN-REPORT\.md`, `a\.py`) are the only BRE→python deltas and they tighten, not loosen.
- **`backdate_file` matches what the gate reads.** `gates.py:2458` reads `os.path.getmtime` only; snapshots show mtime `1793690179 → 1788506179` (now − 60·86400). `%.0f` formatting (`:2572`) tolerates the sub-second drift. Mutating the fallback to `return 0.0` reds `ADV-R12-12` (`-> 83 passed, 1 FAILED`), so the `:614` site is live; `:529` is indeed dead (directory date `260701` parses).
- **Bash quoting of every helper argument** parsed as intended (the snapshot `.args` files show `$?`, `$rc`, `\|`, backticks arriving literally).
- **Tripwire mutation M236/M237** (copy `/tmp/r14/mut2`): both appended lines named as `test-gate-1.sh:245` / `:246`, `rc=1`. The regex does not fire on `sed 's/^/  /'`, `head -n 5`, `date -u`, `sort -k2`, `mktemp -d`, `mktemp -t`, `stat -f`, `touch -t`, `tail -n +2`, pure comment lines (incl. lib.sh's block and the tripwire's own comment), `git submodule update --init` (prefix class), or its own definition line.
- **Class sweep** with ~45 GNU-ism patterns over `install.sh`, `gates.sh`, `tests/*.sh`: only `seq` (present on macOS), `touch -t` (POSIX), `tar --null -T -` (bsdtar supports both), a guarded `sha256sum`, and the install.sh `1a\` note above. `gates.py` subprocesses: `["git", …]` argv only, plus a consumer-supplied probe under `shell=True` (consumer content, out of scope). `status.mjs`: `execFileSync('git', …)` and the gates entry point only. `gates.sh` is a 2-line exec.
- **Suite/AST/parity on the patched copy:** `ALL GATE TESTS PASSED`, 640; `python3 -W error -c "import ast; ast.parse(open('scripts/wow/gates.py').read())"` clean (old `gates.py` → `SyntaxError: invalid escape sequence '\|'`); `gates.sh parity` → `PARITY PASS`. Old tree on 3.13 reds exactly the two `verify-cmd` assertions (M238's claim holds).
- **Stamps/docs:** `formats.json` `0.7.6-draft` = CHANGELOG top entry; `INSTALL.md` `DRAFT v0.7.6` ↔ last commit `v0.7.6-draft`; every other `DRAFT v0.7.5` header ↔ `v0.7.5-draft` last commit; README/GAPS carry no DRAFT header. 13 sites, `:567`/`:529` line numbers, M236–M238 numbering (M235 is v0.7.5's last) all check out. GAPS OBL-PKG-25…29 successor cells read coherently and parity's successor arm accepts them.
- **Leakage:** the diff and commit body contain `advisor/F-200`, "originating machine (stock bash 3.2, BSD userland)" and fixture text only; no paths, hostnames, or consumer repository content.
