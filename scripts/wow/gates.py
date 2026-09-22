#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""WoW v2 mechanical gates. Entry point is gates.sh; this is its engine.

Every pattern, vocabulary, path and schema comes from formats.json — the single
machine home shared with status.mjs. Nothing is inlined here. If you find
yourself adding a literal regex, path or status word to this file, put it in
formats.json instead: two consumers with private copies of a format is exactly
how enforcement and status derivation drift apart.

Each gate returns (ok: bool, messages: list[str]). A gate that cannot fail is a
defect (inert-gate class); scripts/wow/tests/ holds one negative test per gate,
and tests/test-install.sh proves the WIRING is live — a gate nothing calls is
inert however good its logic.
"""
import fnmatch
import hashlib
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def repo_root():
    try:
        out = subprocess.check_output(["git", "rev-parse", "--show-toplevel"],
                                      stderr=subprocess.DEVNULL)
        return out.decode().strip()
    except Exception:
        return os.path.abspath(os.path.join(HERE, "..", ".."))


ROOT = repo_root()
F = json.load(open(os.path.join(HERE, "formats.json")))


def _expand_run_core(node, subs):
    """F-46/F-39 (v0.7.1): {run_core} (and the {task_tail} it carries) is the
    ONE source of the run-id grammar; every pattern that embeds it derives
    from it here, at load — the same keys, expanded identically by gates.py
    and status.mjs, so a widening of the slug cap or the task tail can never
    silently narrow a sibling."""
    if isinstance(node, dict):
        return {k: _expand_run_core(v, subs) for k, v in node.items()}
    if isinstance(node, list):
        return [_expand_run_core(v, subs) for v in node]
    if isinstance(node, str):
        for key, val in subs:
            node = node.replace(key, val)
        return node
    return node


_parts = [("{run_date}", F["ids"]["run_date"]),
          ("{run_slug}", F["ids"]["run_slug"]),
          ("{run_iter}", F["ids"]["run_iter"])]
_core = _expand_run_core(F["ids"]["run_core"], _parts)
F = _expand_run_core(F, _parts + [("{run_core}", _core),
                                  ("{task_tail}", F["ids"]["task_tail"])])
P = F["paths"]

_SLUG_CAP = None


def _slug_cap():
    """Audit A1 (engine round 6): the slug cap is DERIVED by probing ids.run_slug,
    never restated — the diagnosis that hardcoded 'cap 48' would lie the day
    the single source moved. Binary search the longest all-'a' slug admitted."""
    global _SLUG_CAP
    if _SLUG_CAP is None:
        lo, hi = 1, 4096
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if re.fullmatch(F["ids"]["run_slug"], "a" * mid):
                lo = mid
            else:
                hi = mid - 1
        _SLUG_CAP = lo
    return _SLUG_CAP


def _run_anatomy(candidate):
    """Match a run-id-SHAPED string against the anatomy with the slug length
    relaxed — composed from the same ids.run_* parts the strict pattern uses
    (audit A1: zero inline restatements). Returns the slug or None."""
    relaxed = re.sub(r"\{\d+,\d+\}|\{0,\d+\}", "*", F["ids"]["run_slug"])
    m = re.match("^%s-(%s)-%s" % (F["ids"]["run_date"], relaxed, F["ids"]["run_iter"]),
                 candidate)
    return m.group(1) if m else None


def fill(tpl, **kw):
    """Substitute {name} placeholders. Deliberately not str.format: these
    templates are regexes, and {6} in [0-9]{6} is a quantifier, not a field."""
    out = tpl
    for k, v in kw.items():
        out = out.replace("{%s}" % k, v)
    return out


def cfg():
    p = os.path.join(HERE, "wow.config.json")
    if os.path.exists(p):
        try:
            return json.load(open(p))
        except Exception:
            return {}
    return {}


def rp(*parts):
    return os.path.join(ROOT, *parts)


def read(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except Exception:
        return ""


def lines_of(path):
    t = read(path)
    return t.split("\n") if t else []


def git(*args, **kw):
    """rc=True returns the boolean success of the command instead of its
    output — for predicates like merge-base --is-ancestor whose answer IS the
    exit code (output-based calls cannot distinguish 'no' from 'no output')."""
    if kw.get("rc"):
        try:
            subprocess.check_call(["git"] + list(args), cwd=ROOT,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        except Exception:
            return False
    try:
        return subprocess.check_output(["git"] + list(args), cwd=ROOT,
                                       stderr=subprocess.DEVNULL).decode()
    except Exception:
        return ""


def staged_files(include_deleted=False):
    """Paths in the index. Deletions are excluded by default (a deleted file has
    no citations to preflight) and included where the gate is about the commit
    touching a path at all — GATE-11's freeze is the case that matters."""
    flt = "ACMRD" if include_deleted else "ACMR"
    out = git("diff", "--cached", "--name-only", "--diff-filter=" + flt)
    return [f for f in out.split("\n") if f.strip()]


def tracked_files():
    out = git("ls-files")
    return [f for f in out.split("\n") if f.strip()]


def read_staged(path):
    """File content as it will be committed, not as it sits in the worktree.
    Staging a broken citation and then fixing only the worktree used to let the
    broken content land."""
    out = git("show", ":%s" % path)
    return out


def staged_lines(path):
    t = read_staged(path)
    return t.split("\n") if t else []


def modified_in_run(run_id=None):
    """What did this run modify? Union of, in order of authority:
      - the working tree (staged, unstaged and untracked),
      - the run base branch to HEAD, when FORMATS §1's base branch exists,
      - failing that, the commits whose messages carry this run's lane refs.
    A run with none of these has modified nothing, which is a legitimate answer."""
    out = set()
    for line in git("status", "--porcelain").split("\n"):
        if len(line) > 3:
            p = line[3:].strip()
            if " -> " in p:
                p = p.split(" -> ")[-1]
            out.add(p.strip('"'))
    if run_id:
        base = fill(F["branch_patterns"]["base_ref"], run_id=run_id)
        if git("rev-parse", "--verify", "--quiet", base).strip():
            for f in git("diff", "--name-only", "%s...HEAD" % base).split("\n"):
                if f.strip():
                    out.add(f.strip())
        else:
            shas = [s for s in git("log", "--format=%H", "--grep", run_id).split("\n") if s.strip()]
            for s in shas:
                for f in git("show", "--pretty=format:", "--name-only", s).split("\n"):
                    if f.strip():
                        out.add(f.strip())
    return out


def log_rejection(gate, messages):
    d = rp(os.path.dirname(P["gate_log"]))
    if not os.path.isdir(d):
        try:
            os.makedirs(d)
        except Exception:
            return
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S")
    try:
        with open(rp(P["gate_log"]), "a", encoding="utf-8") as fh:
            for m in messages:
                fh.write("%s\t%s\t%s\n" % (stamp, gate, m))
    except Exception:
        pass


def excluded(path):
    return any(fnmatch.fnmatch(path, pat) for pat in F.get("citation_scan_exclude", []))


def _untracked_matching(pats):
    out = []
    skip = {".git", "node_modules", ".venv", "__pycache__"}
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in skip]
        for fn in files:
            rel = os.path.relpath(os.path.join(base, fn), ROOT)
            for p in pats:
                if fnmatch.fnmatch(rel, p):
                    out.append(rel)
    return out


def matching_docs(globs):
    out = [f for f in tracked_files() for g in globs if fnmatch.fnmatch(f, g)]
    out += _untracked_matching(tuple(globs))
    return sorted(set(out))


def gated_docs():
    return matching_docs(F["scan_targets"]["gated_docs"])


def discover_run():
    """The run a sweep is about, when the caller named none: the newest run dir
    matching ids.run. A gate that silently checks nothing because no --run was
    passed is inert, and 'the operator forgot a flag' is not a pass."""
    d = rp(P["runs_dir"])
    if not os.path.isdir(d):
        return None
    runs = [x for x in sorted(os.listdir(d)) if re.match(F["ids"]["run"], x)]
    return runs[-1] if runs else None


# --------------------------------------------------------------------------
# GATE-1 — commit message carries exactly one lane ref, and it resolves
# --------------------------------------------------------------------------
def gate_1(msgfile):
    ct = F["commit_trailers"]
    lines = read(msgfile).split("\n")
    cut = len(lines)
    marker = ct.get("strip_from_marker")
    if marker:
        for i, l in enumerate(lines):
            if re.match(marker, l):
                cut = i
                break
    prefix = ct.get("strip_comment_prefix")
    body = "\n".join(l for l in lines[:cut] if not (prefix and l.startswith(prefix)))
    # F-07 (v0.6.3): a body that MENTIONS a trailer was counted as carrying it,
    # so the most relevant commits — the ones about lane behaviour — were the
    # hardest to write. Same mention-vs-claim rule as GATE-3: backticked spans
    # and fenced/indented blocks do not count. A trailer meant to bind is
    # written bare.
    scan = re.sub(r"`[^`]*`", "", body)
    scan_lines, fenced = [], False
    for l in scan.split("\n"):
        if l.strip().startswith("```"):
            fenced = not fenced
            continue
        if fenced or l.startswith("    "):
            continue
        scan_lines.append(l)
    scan = "\n".join(scan_lines)

    hits = []
    for name, spec in ct["kinds"].items():
        for m in re.finditer(spec["pattern"], scan):
            hits.append((name, m.group(1)))
    if len(hits) == 0:
        # F-46/F-39 (v0.7.1): "no lane reference" about a lane reference the
        # operator HAD written cost days of misdiagnosis. A trailer-shaped
        # token that resolves to no pattern gets the real cause named.
        shaped = re.findall(r"\[(?:T|Q|D|WOW)[^\]]*\]", scan)
        if shaped:
            hints = []
            for tok in shaped[:3]:
                inner = tok[1:-1].split(":", 1)[-1]
                run_part = inner.split(".")[0]
                slug = _run_anatomy(run_part)
                if tok.startswith("[T:") and slug is not None \
                        and not re.match(F["ids"]["run"], run_part):
                    if len(slug) > _slug_cap():
                        hints.append("%s: run id fails ids.run — slug '%s' is %d chars (cap %d)"
                                     % (tok, slug, len(slug), _slug_cap()))
                    else:
                        hints.append("%s: run id fails ids.run (shape, not length)" % tok)
                elif tok.startswith("[T:") and "." in inner \
                        and not re.match(F["ids"]["task"], inner):
                    hints.append("%s: task tail must be .T<nn> or .T<nn><letter> (ids.task)" % tok)
                else:
                    hints.append("%s matches no trailer kind" % tok)
            # prodsim/F-79: state the total before the sample
            more = " (+%d more token(s) not shown)" % (len(shaped) - 3) if len(shaped) > 3 else ""
            return False, ["%d trailer-shaped token(s) present but resolving to NO pattern — "
                           "this is not a missing lane ref (F-46/F-39): %s%s"
                           % (len(shaped), "; ".join(hints), more)]
        return False, ["no lane reference. Expected exactly one of "
                       "[T:<task-id>] [Q:runs/quick/<dir>] [D:<debug-slug>] [WOW:publish] (or [WOW:migrate] mid-migration)"]
    if len(hits) > 1:
        return False, ["%d lane references, expected exactly one: %s"
                       % (len(hits), ", ".join(h[1] for h in hits))]
    name, value = hits[0]
    how = ct["kinds"][name]["resolves"]

    if how == "none":
        return True, []
    if how == "mid_migration":
        # [WOW:migrate] is legal only in the migration window: legacy tree
        # present AND the freeze not yet flipped (review PR-4).
        legacy_dir = F["legacy_freeze"]["paths"][0].split("/")[0]
        if not os.path.isdir(rp(legacy_dir)):
            return False, ["[WOW:migrate] outside a migration: no %s/ here — use a task, quick "
                           "or debug lane ref" % legacy_dir]
        if cfg().get(F["legacy_freeze"]["config_key"]):
            return False, ["[WOW:migrate] after the freeze flipped — migration is over; use a "
                           "task, quick or debug lane ref"]
        return True, []
    if how == "dir_exists":
        return (True, []) if os.path.isdir(rp(value)) else \
            (False, ["lane ref [Q:%s] names a directory that does not exist" % value])
    if how == "run_dir_exists":
        # F-08/F-10 (v0.6.3): the bare form [T:<run-id>] carries a run's
        # PHASE-level artifacts (P1 spec + HANDOFF, P4 reconciled spec /
        # divergence / RUN-REPORT) — the run directory may exist before its
        # plan, so the artifact a PO signs is in git at the moment of signing.
        d = os.path.join(rp(P["runs_dir"]), value)
        d_arch = os.path.join(rp(F["runs_layout"]["archive_dir"]), value)
        if not os.path.isdir(d) and not os.path.isdir(d_arch):
            # DEV-R11-06: an ARCHIVED run's phase artifacts (an ADR tweak after
            # P5 step 3) commit under the bare form too — and the old remedy
            # ("create runs/<id>/") manufactured a phantom dir GATE-7 refuses.
            return (False, ["lane ref [T:%s] (bare run form) names a run directory that does "
                            "not exist under runs/ or runs/archive/ — a run directory is created "
                            "at P1 (`/wow-spec`); do not create one by hand for a run that "
                            "never existed" % value])
        # ADV-R11-02: a MERGE commit's staged set is the merged product — not
        # authored work — and every ORCH merge in P3 (unit into int, base into
        # unit after an amendment) and P5 step 0 (main in) commits under the
        # bare form. The scope rule is for authored commits.
        git_dir = git("rev-parse", "--git-dir").strip() or ".git"
        merge_head = os.path.join(git_dir if os.path.isabs(git_dir) else rp(git_dir), "MERGE_HEAD")
        if os.path.exists(merge_head):
            return (True, [])
        # platform/F-72 (v0.7.4): the bare form is for PHASE artifacts, and
        # the gate never looked at what was actually being committed — a
        # phase trailer rode five task-output files and the lane answer in
        # `git log` became self-reported metadata with a syntax check on top.
        # The staged set is right there; phase artifacts live in known places.
        scope = [fill(g, run_id=value)
                 for g in ct["kinds"]["run"].get("staged_scope", [])]
        scope += [fill(str(x), run_id=value)
                  for x in (cfg().get("run_staged_scope_extra") or [])]   # DEV-R11-19
        if scope:
            staged = [f for f in git("diff", "--cached", "--name-only").split("\n")
                      if f.strip()]
            out_of_scope = [f for f in staged
                            if not any(fnmatch.fnmatch(f, g)
                                       or fnmatch.fnmatch(f, g.rstrip("*").rstrip("/") + "/*")
                                       for g in scope)]
            if out_of_scope:
                return (False, ["bare [T:%s] is a PHASE-artifact trailer and %d staged file(s) "
                                "are outside every phase-artifact home: %s%s — task output "
                                "commits under its task id [T:%s.T<nn>] (the plan declares its "
                                "ownership); phase homes are commit_trailers.kinds.run."
                                "staged_scope, extendable via wow.config.json "
                                "run_staged_scope_extra (platform/F-72)"
                                % (value, len(out_of_scope), ", ".join(out_of_scope[:4]),
                                   " …" if len(out_of_scope) > 4 else "", value)])
        return (True, [])
    if how == "debug_file_exists":
        rl = F["runs_layout"]
        for tpl in (rl["debug"], rl["debug_resolved"]):
            if os.path.isfile(rp(fill(tpl, slug=value))):
                return True, []
        return False, ["lane ref [D:%s] has no file at %s"
                       % (value, fill(rl["debug"], slug=value))]
    if how == "task_in_plan":
        run_id = value.split(".")[0]
        rel = fill(F["plan_schema"]["file"], run_id=run_id)
        plan_path = rp(rel)
        if not os.path.isfile(plan_path):
            return False, ["lane ref [T:%s] names run %s, which has no %s"
                           % (value, run_id, rel)]
        plan = _parse_plan(plan_path)
        ids = [t["id"] for u in plan["units"] for t in u["tasks"]]
        if value in ids:
            return True, []
        return False, ["lane ref [T:%s] is not a task row in %s (rows there: %s). A task id "
                       "mentioned in prose or a comment is not a task."
                       % (value, rel, ", ".join(ids[:5]) or "none")]
    return False, ["unknown resolver %s" % how]


# --------------------------------------------------------------------------
# GATE-5 — file:line citations pass preflight, against the content that lands
# --------------------------------------------------------------------------
def _citations(lines):
    pat = F["evidence"]["file_line_citation"]
    return [(m.group(1), int(m.group(2)), i + 1)
            for i, line in enumerate(lines)
            for m in re.finditer(pat, line)]


def _archive_rewrites(target):
    """platform/F-77/F-80 + ADV-R11-01/-08 (v0.7.4): the engine MODELS two moves
    — a run archived to runs/archive/<id>/ at P5 step 3 and a debug record
    resolved into runs/debug/resolved/ — so a citation to the pre-move path is
    a citation to a file that moved, not to one that died. Every resolver that
    asks 'does this target exist' asks the same question the same way; gate-5
    and gate-7 once gave one sweep two verdicts about one row."""
    rl = F["runs_layout"]
    out = [target]
    runs_prefix = P["runs_dir"].rstrip("/") + "/"
    if target.startswith(runs_prefix):
        rest = target[len(runs_prefix):]
        out.append(os.path.join(rl["archive_dir"], rest))
    dbg = rl["debug_dir"].rstrip("/") + "/"
    res = rl["debug_resolved_dir"].rstrip("/") + "/"
    if target.startswith(dbg) and not target.startswith(res):
        out.append(res + target[len(dbg):])
    return out


def _resolve_target(target, staged=False):
    """The first existing candidate among the target and its modeled rewrites,
    or None."""
    for cand in _archive_rewrites(target):
        if staged and read_staged(cand):
            return cand
        full = rp(cand) if not os.path.isabs(cand) else cand
        if os.path.exists(full):
            return cand
    return None


def _target_length(target, staged):
    """Line count of a citation target, read from the index when the citing file
    is being committed, so preflight judges the same snapshot git will store."""
    target = _resolve_target(target, staged) or target
    if staged:
        t = read_staged(target)
        if t:
            return len(t.split("\n"))
    full = rp(target) if not os.path.isabs(target) else target
    if not os.path.exists(full):
        return None
    return len(lines_of(full))


def _target_exists(target, staged):
    return _resolve_target(target, staged) is not None


def _dangling_commit_citations(p, lines):
    """prodsim/F-68 / OBL-PKG-23 (v0.7.3): ev:commit is the one citation kind
    whose truth one command settles — git cat-file -e <sha>^{commit} — and
    four well-formed false ones shipped in a single pilot run (the habit: the
    citation is drafted before the commit it names exists, and the
    placeholder is never revisited). BLOCKING for the run tree and staged
    run files; ADVISORY for durable docs, where a dangling sha is legitimate
    history (platform/F-63's own branch GC, shallow clones, squash-merge publish
    policies, a history rewrite). Ambiguous short shas fail resolution and
    the message says which failure it was."""
    out = []
    doc = "\n".join(lines)
    # order matters (platform/F-75): fences are stripped BEFORE the span mask,
    # or the `*` span regex eats two of a fence line's three backticks and the
    # fence stops being recognizable as one.
    masked = "\n".join(_mask_inline_code_doc(_strip_fenced_blocks(doc)))
    # ADV-R9-03 (v0.7.3 R9, hardened R9b/ADV-R10-07): fenced (``` and ~~~) and
    # indented code blocks are MENTIONS here as everywhere — the F-43 paste
    # rule tells operators to quote gate output verbatim, and this gate's own
    # refusal message contains a literal ev:commit{...}, so a resolver without
    # fence tracking blocked the commit that quoted it (the runs/.gate-log
    # exclusion was this same defect, patched one file wide). Known residual
    # (ADV-R10-07b, structural to toggle-tracking): one UNCLOSED fence marks
    # the rest of the file as mention, so a dangling sha below it is not
    # resolved — the falsifier is the verifier's re-run, not this arm.
    claimable = _blank_indented_code(masked)
    for i, line in enumerate(claimable.split("\n"), 1):
        for m in re.finditer(r"ev:commit\{([0-9a-f]{7,40})\}", line):
            sha = m.group(1)
            if not git("cat-file", "-e", sha + "^{commit}", rc=True):
                out.append((i, sha))
    return out


def _preflight(paths, staged):
    msgs = []
    for p in paths:
        if excluded(p):
            continue
        lines = staged_lines(p) if staged else (
            lines_of(rp(p)) if os.path.isfile(rp(p)) else [])
        if not lines:
            continue
        for target, lineno, at in _citations(lines):
            if not _target_exists(target, staged):
                msgs.append("%s:%d cites %s:%d — GONE (no such file)" % (p, at, target, lineno))
                continue
            n = _target_length(target, staged)
            if n is None:
                continue
            if lineno < 1 or lineno > n:
                msgs.append("%s:%d cites %s:%d — DRIFTED (file has %d lines)"
                            % (p, at, target, lineno, n))
    return msgs


def gate_5(paths=None, staged=False, sweep=False, run_id=None):
    """Pre-commit: staged files, blocking. Sweep: docs modified by this run are
    blocking; drift in unmodified docs is advisory and feeds AT-4 (GATES-SPEC)."""
    if staged:
        sf = staged_files()
        msgs = _preflight(sf, True)
        for p in sf:
            if excluded(p) or not p.startswith(P["runs_dir"].rstrip("/") + "/"):
                continue
            for lineno, sha in _dangling_commit_citations(p, staged_lines(p)):
                msgs.append("%s:%d cites ev:commit{%s} which does NOT resolve in this "
                            "repository — commit first, then cite (the citation was written "
                            "before the commit it names existed; prodsim/F-68, OBL-PKG-23)"
                            % (p, lineno, sha))
        return (len(msgs) == 0), msgs + _subject_note("GATE-5", len([p for p in sf
                                                                     if not excluded(p)]))
    if not sweep:
        return (lambda m: (len(m) == 0, m))(_preflight(paths or gated_docs(), False))

    docs = paths or gated_docs()
    changed = modified_in_run(run_id)
    hot = [p for p in docs if p in changed]
    cold = [p for p in docs if p not in changed]
    blocking = _preflight(hot, False)
    advisory = _preflight(cold, False)
    msgs = list(blocking)
    for a in advisory:
        msgs.append("advisory (unmodified doc, not blocking — feeds AT-4): %s" % a)
    msgs.append("AT-4 count this sweep: %d stale file:line ref(s) in unmodified docs "
                "(threshold %s%d)" % (len(advisory),
                                      F["audit_triggers"]["AT-4"]["comparator"],
                                      F["audit_triggers"]["AT-4"]["threshold"]))
    return (len(blocking) == 0), msgs


# --------------------------------------------------------------------------
# GATE-11 — legacy-framework freeze (inert unless migrated_from_gsd)
# --------------------------------------------------------------------------
def _cfg_at(ref):
    """Parse wow.config.json as a git revision sees it (':path' = index,
    'HEAD:path' = last commit). Empty dict when the file is genuinely absent
    from that revision; the sentinel {'$read_failed': True} when git could
    not answer at all.

    prodsim/F-82 (v0.7.4): the old path arithmetic — relpath(HERE, ROOT) —
    compared a module path against git's PHYSICAL toplevel, and on a
    symlinked checkout (macOS /tmp, some CI layouts) the relpath escaped the
    repo, git show failed, and the silent {} emptied the exclude list: the
    freeze failed closed with a hint telling the operator to commit a file
    that was already committed. The config path is now taken from
    install.config_file — the literal repo-relative path, no arithmetic —
    and a FAILED read is distinguished from an absent file (F-12's rule:
    a failed invocation must never report as a passing check)."""
    rel = F["install"]["config_file"]
    if not git("cat-file", "-e", "%s:%s" % (ref, rel), rc=True):
        # no such blob at that revision (or unborn HEAD) — genuinely absent
        return {}
    blob = git("show", "%s:%s" % (ref, rel))
    try:
        return json.loads(blob) if blob.strip() else {"$read_failed": True}
    except Exception:
        return {"$read_failed": True}


def gate_11(paths):
    """ADV-R9-09 (v0.7.3 R9) + ADV-R10-02 (R9b): gate-11 read the WORKTREE
    config at pre-commit, so an uncommitted `legacy_freeze_exclude` edit
    disarmed the freeze for one commit and was reverted after — and the R9
    index read was defeated by commit-then-amend in two plain commands, zero
    committed trace either way. The carve-out therefore honors only the
    COMMITTED config (HEAD): an exclusion disarms nothing until it has landed
    as its own reviewable commit, which raises the bypass bar to overt
    history rewriting, past what any hook can police. The freeze FLAG is
    sticky the other way (fail-safe is freezing more): true in HEAD, index or
    worktree arms the gate."""
    lf = F["legacy_freeze"]
    head_cfg = _cfg_at("HEAD")
    live_cfg = _cfg_at("") or cfg()   # index copy, else worktree (fresh repo)
    # prodsim/F-82: a freeze that silently loses its carve-out list is the
    # F-12 class — a failed read must be loud, never an empty-and-frozen set.
    armed = (head_cfg.get(lf["config_key"]) is True
             or live_cfg.get(lf["config_key"]) is True
             or cfg().get(lf["config_key"]) is True)
    # prodsim/F-82 + ADV-R11-07: a freeze that silently loses its carve-out
    # list is the F-12 class — but a read failure only MATTERS when the
    # freeze is armed by some readable copy, and a readable staged copy is
    # the repair commit for a corrupt HEAD (refusing that made the fix
    # un-committable without --no-verify, which is never allowed).
    if live_cfg.get("$read_failed"):
        return False, ["wow.config.json in the index could not be READ or parsed — gate-11 "
                       "refuses to guess whether the freeze or its exclude list applies "
                       "(a failed invocation is not a passing check, F-12; prodsim/F-82)"]
    if not armed:
        return True, ["inert: wow.config.json %s is not true" % lf["config_key"]]
    if head_cfg.get("$read_failed"):
        return False, ["wow.config.json at HEAD could not be READ or parsed while the freeze is "
                       "armed — its committed exclude list is unknowable, so nothing frozen "
                       "may land until a readable config is committed (a failed invocation is "
                       "not a passing check, F-12; prodsim/F-82)"]
    # prodsim/F-60 (v0.7.3): a brownfield legacy tree can hold LIVE runtime
    # paths; the committed wow.config.json fnmatch list carves them out of
    # the freeze. Everything else stays frozen in every direction.
    excludes = head_cfg.get("legacy_freeze_exclude") or []
    pending = [e for e in (live_cfg.get("legacy_freeze_exclude") or [])
               if e not in excludes]
    bad = []
    for p in paths or []:
        if any(fnmatch.fnmatch(p, e) for e in excludes):
            continue
        for frozen in lf["paths"]:
            if p == frozen or p.startswith(frozen.rstrip("/") + "/"):
                bad.append(p)
    if bad:
        frozen = ", ".join(x.rstrip("/") + "/" for x in lf["paths"])
        hint = ""
        if pending and any(fnmatch.fnmatch(p, e) for p in bad for e in pending):
            hint = (" — a matching legacy_freeze_exclude exists in the staged/worktree "
                    "config but NOT in HEAD: commit the exclusion first, as its own "
                    "reviewable commit (ADV-R10-02)")
        return False, ["commit touches frozen %s (%d file(s)): %s — it is history, in every "
                       "direction including deletion%s"
                       % (frozen, len(bad), ", ".join(sorted(set(bad))[:5]), hint)]
    # ADV-R9-09: an active carve-out is stated on the PASS — a silent exclude
    # list is exactly the deniable knob the finding demonstrated.
    if excludes:
        return True, ["active legacy_freeze_exclude (from the COMMITTED config): %s"
                      % ", ".join(excludes)]
    return True, []


# --------------------------------------------------------------------------
# GATE-3 — completion statuses and done-words carry well-formed evidence
# --------------------------------------------------------------------------
def _evidence_problems(line):
    """Every ev: on the line must match its own type pattern. `any` alone let
    ev:cmd{i ran it and it was fine} satisfy the evidence rule.

    frisbii braces finding (v0.6.2): the body admits one level of balanced
    braces. An ev: opener the kind regex cannot parse (deeper nesting, or an
    unterminated body) is reported as THE FORMAT being unable to express it —
    a diagnostic that misnames the cause sends the writer to fix the wrong
    thing, and in pilot #1 it did."""
    ev = F["evidence"]
    if not ev.get("validate_shape"):
        return []
    bad = []
    spans = []
    for m in re.finditer(ev["kind"], line):
        spans.append(m.span())
        kind = m.group(1)
        whole = m.group(0)
        pat = ev["types"].get(kind)
        if pat and not re.search(pat, whole):
            bad.append(whole)
    for pm in re.finditer(ev["opener"], line):
        # F-27 (v0.6.3): the opener is generic, so an INVENTED kind is caught
        # here too — previously ev:po-attest{...} was not a malformed citation
        # but no citation at all, and the scan simply did not see it.
        if not any(s <= pm.start() < e for s, e in spans):
            bad.append(line[pm.start():pm.start() + 60])
    return bad


def _has_evidence(line):
    return re.search(F["evidence"]["any"], line) is not None and not _evidence_problems(line)


def _has_reference(line, skip_first_cell=False):
    """A blocker/park/successor reference, or evidence. The row's own subject id
    does not count as a reference to anything — a PARKED row whose only id is the
    REQ it is about carries no park record, so the first cell is dropped."""
    scope = line
    if skip_first_cell and line.count("|") >= 2:
        parts = line.strip().strip("|").split("|")
        scope = "|".join(parts[1:])
    if _has_evidence(scope):
        return True
    for key in F["status_vocab"]["reference_id_patterns"]:
        pat = F["ids"][key].strip("^$")
        if re.search(pat, scope):
            return True
    return False


def _mask_inline_code(line):
    """PF-a (pilot #2, v0.6.0): a citation inside backticks is a MENTION, not a
    claim. GATE-3 neither flags a backticked template as malformed nor accepts
    a backticked citation as satisfying evidence — fail-safe in both
    directions. Only the evidence/reference scans use the masked line; cell and
    status parsing still see the original (backticks there are decoration,
    handled by cell_decoration)."""
    return re.sub(r"`[^`]*`", "", line)


def _mask_inline_code_doc(text):
    """F-05 (pilot #2, v0.6.1): the per-line mask leaked on a code span that
    wraps a line break, which CommonMark permits — the closer paired forward
    with the next opener and every subsequent span shifted by one. Mask across
    the whole document instead, replacing each span with its own newlines so
    line numbering is preserved. A candidate containing a blank line is left
    alone (CommonMark: a code span cannot contain one), which also keeps a
    stray unpaired backtick from masking half the file."""
    def repl(m):
        if re.search(r"\n\s*\n", m.group(0)):
            return m.group(0)
        # prodsim/F-72 (v0.7.3): document-wide pairing crossed TABLE ROW
        # boundaries — one stray tick in a cell paired with the next row's
        # opener and blanked the intervening row's citations, so GATE-3
        # reported real evidence as missing (a false negative wearing a false
        # positive's clothes). CommonMark itself would refuse a code span
        # containing a table row separator; a candidate whose interior crosses
        # onto a line beginning a table row is left alone. Boundary is
        # ^\s*\| — the F-05 blockquote-wrapped-span case ('> span ... > more')
        # must keep masking, and its lines do not begin with a pipe. A table
        # quoted inside a blockquote remains crossable; accepted residual.
        # ADV-R9-08 (v0.7.3 R9): begins-with-a-pipe alone also matched a
        # WRAPPED SHELL PIPELINE inside a legitimate span — the span was left
        # unmasked and its citation template scanned as a claim (a mention
        # became a claim, PF-a inverted). The crossing line must look like a
        # table ROW: a second unescaped pipe after the first.
        if re.search(r"\n\s*\|[^\n]*(?<!\\)\|", m.group(0)):
            return m.group(0)
        return "\n" * m.group(0).count("\n")
    # platform/F-75 (v0.7.4): `+` here where the per-line mask uses `*` was a
    # one-character regression from F-05's own rewrite — an EMPTY code span
    # (two adjacent backticks) did not match, the scanner resumed one backtick
    # later, and every span in the rest of the document paired one position
    # out: mentions exposed, claims masked, and GATE-3 naming a correct line.
    # The two functions are two implementations of ONE rule; the suite now
    # asserts their patterns agree.
    return re.sub(r"`[^`]*`", repl, text, flags=re.S).split("\n")


def _is_separator(line):
    return re.match(r"^\s*\|[\s:|-]+\|\s*$", line) is not None


def _cells(line):
    """F-18 (v0.6.4): an escaped pipe `\|` is cell CONTENT anywhere — a field
    that carries a shell command must not be delimited by a character shells
    use. This retires FORMATS §12's old 'escape only in the trailing ev cell'
    caveat: earlier-cell escapes no longer shift columns, because the split
    honors them."""
    parts = re.split(r"(?<!\\)\|", line.strip().strip("|"))
    return [c.strip().replace("\\|", "|") for c in parts]


_FENCE_OPEN = re.compile(r"^\s{0,3}(`{3,}|~{3,})")


def _strip_fenced_blocks(t):
    """ADV-R10-03 (v0.7.3 R9b): blank the CONTENT of fenced code blocks —
    both ``` and ~~~ spellings (CommonMark), the opener token closing only
    its own kind — while keeping every other line intact. For locating
    sections and rows on text where a fenced '# comment' must not read as a
    heading. Fence state is per-document; callers aggregating files strip
    each file separately (ADV-R10-04: one unclosed fence in RUN-REPORT used
    to mark every subsequent verify report as fenced)."""
    out, fence = [], None
    for ln in t.split("\n"):
        m = _FENCE_OPEN.match(ln)
        if fence is None:
            if m:
                fence = m.group(1)[0]
                out.append("")
                continue
            out.append(ln)
        else:
            if m and m.group(1)[0] == fence:
                fence = None
            out.append("")
    return "\n".join(out)


def _blank_indented_code(t):
    """ADV-R10-01: a 4-space/tab INDENTED code block is a mention channel too
    (CommonMark) — the forged 'record format, for reference' re-ran through it
    the day the ``` channel closed. Faithful enough to CommonMark to stay
    safe in both directions: a block starts at an indented line after a blank
    line (so a 2-space CV continuation line, or a lazy 4-space continuation
    directly under its CV line, is NOT code) and runs while lines stay
    indented or blank."""
    out, prev_blank, in_block = [], True, False
    for ln in t.split("\n"):
        indented = re.match(r"^(?: {4}|\t)", ln) is not None
        blank = not ln.strip()
        if in_block:
            if blank:
                out.append(ln)
                prev_blank = True
                continue
            if indented:
                out.append("")
                prev_blank = False
                continue
            in_block = False
        if indented and prev_blank and not blank:
            in_block = True
            out.append("")
            prev_blank = False
            continue
        out.append(ln)
        prev_blank = blank
    return "\n".join(out)


def _claim_text(t):
    """ADV-R9-01/R10-01: the text a gate may SATISFY itself on — fenced blocks
    (``` and ~~~), indented code blocks and inline code are mentions, blanked
    with line structure preserved. Discovery scans stay on the raw text
    (fail-safe there is seeing more; here it is seeing less)."""
    return "\n".join(_mask_inline_code(ln)
                     for ln in _blank_indented_code(_strip_fenced_blocks(t)).split("\n"))


def _subject_note(gate_id, n):
    """prodsim/F-70 fix 2 (v0.7.3): a PASS states its subject count, and zero
    says vacuous — '6/6 passed' over an empty set survived two wave
    boundaries in a pilot as a green check. Labels live in the gate registry
    (gates.<id>.subject); gates with no label report nothing (always-one
    subjects, ADV-12)."""
    label = F["gates"].get(gate_id, {}).get("subject")
    if not label:
        return []
    if n == 0:
        return ["subject: 0 %s — VACUOUS for this checkout (a green over an empty set "
                "certifies nothing; prodsim/F-70)" % label]
    return ["subject: %d %s" % (n, label)]


def gate_3(paths=None):
    sv = F["status_vocab"]
    ev_required = set(sv["evidence_required"])
    ref_required = dict(sv["reference_required"])
    done_words = set(w.lower() for w in sv["done_words"])
    forbidden = set(w.upper() for w in sv["forbidden_synonyms"])
    allowed = set(sv["allowed"])
    status_cols = set(c.lower() for c in sv["status_columns"])
    # F-10 (v0.6.2): a status describes the work; a verdict is an independent
    # judgement ABOUT it. P3 mandates the verifier grade and this gate was
    # rejecting it. A Grade/Verdict column is checked against verdict_vocab
    # instead — with its own evidence discipline (FAIL needs a VF id,
    # PASS-with-carry-forwards a CV id, in the same row).
    verdict_cols = set(c.lower() for c in sv.get("verdict_columns", []))
    verdict_vocab = list(sv.get("verdict_vocab", []))
    verdict_refs = dict(sv.get("verdict_reference_required", {}))
    targets = paths if paths else gated_docs()
    msgs, notes = [], []
    scanned = 0

    for p in targets:
        if excluded(p):
            continue
        full = rp(p)
        if not os.path.isfile(full):
            continue
        in_fence = False
        status_idx = None      # which column of the current table holds status
        verdict_idx = None     # which column holds the verifier verdict (F-10)
        prev_cells = None
        # F-14 addendum (v0.7.2): a report section DECLARED to hold status
        # rows, holding a table with no status column at all, was graded by
        # nothing — the cheapest silent shape, written by giving the table
        # the columns that read most naturally. The gate knows the section is
        # a status section before it reads a row: subject-absent, one level
        # down.
        rs = F["report_row_schema"]
        is_report = (os.path.basename(p) == os.path.basename(rs["file"])
                     or "/reports/" in p.replace(os.sep, "/"))
        cur_sec = None
        scanned += 1
        # F-05: spans may wrap lines; ADV-R11-05: fences stripped FIRST, or a
        # fenced paste with an odd tick count desyncs every span after it
        # (the original lines below still drive fence tracking and cells).
        doc_masked = _mask_inline_code_doc(_strip_fenced_blocks(read(full)))
        # prodsim/F-68 / OBL-PKG-23 (v0.7.3): resolve ev:commit citations —
        # blocking in the run tree (where the write-before-commit habit
        # bites), advisory in durable docs (dangling shas there are
        # legitimate history: branch GC, shallow clones, rewrites).
        in_runs = p.replace(os.sep, "/").startswith(P["runs_dir"].rstrip("/") + "/")
        for lineno, sha in _dangling_commit_citations(p, lines_of(full)):
            if in_runs:
                msgs.append("%s:%d cites ev:commit{%s} which does NOT resolve in this "
                            "repository — commit first, then cite (prodsim/F-68, OBL-PKG-23)"
                            % (p, lineno, sha))
            else:
                notes.append("note: %s:%d cites ev:commit{%s} which does not resolve here — "
                             "advisory outside runs/ (legitimate for pre-rewrite or GC'd "
                             "history; prodsim/F-68)" % (p, lineno, sha))
        for i, line in enumerate(lines_of(full), 1):
            s = line.strip()
            if s.startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            if s.startswith("#"):
                cur_sec = s.lstrip("#").strip().lower()
            if not s:
                status_idx, verdict_idx, prev_cells = None, None, None
                continue

            is_row = line.count("|") >= 2
            if is_row and _is_separator(line):
                if prev_cells:
                    for idx, h in enumerate(prev_cells):
                        if h.lower() in status_cols:
                            status_idx = idx
                        if h.lower() in verdict_cols:
                            verdict_idx = idx
                    if is_report and cur_sec in rs["sections"] \
                            and status_idx is None and verdict_idx is None:
                        msgs.append("%s:%d section '%s' is a DECLARED status section "
                                    "(report_row_schema.sections) and this table resolves no "
                                    "Status or Grade column — its rows would be graded by "
                                    "NOTHING. A status section with no gradeable column is "
                                    "subject-absent, not clean (F-14 addendum)"
                                    % (p, i, cur_sec))
                continue

            # PF-a: mentions are not claims; F-05: mask document-wide so spans
            # wrapping a line break stay masked.
            masked = doc_masked[i - 1] if i - 1 < len(doc_masked) else _mask_inline_code(line)
            for bad in _evidence_problems(masked):
                kind = bad.split("{")[0].split(":")[-1]
                body = bad.split("{", 1)[1] if "{" in bad else ""
                if kind not in F["evidence"]["types"]:
                    msgs.append("%s:%d unknown evidence kind '%s' in '%s' — the vocabulary is "
                                "%s. An invented kind is not a citation and satisfies nothing "
                                "(F-27)" % (p, i, kind, bad,
                                            "|".join(sorted(F["evidence"]["types"]))))
                elif "{" in body:
                    msgs.append("%s:%d citation '%s' — the citation format admits ONE level of "
                                "balanced braces; deeper nesting cannot be expressed. Restructure "
                                "the command or cite a file (frisbii braces finding)"
                                % (p, i, bad))
                else:
                    msgs.append("%s:%d malformed citation '%s' — does not match the %s shape in "
                                "formats.json" % (p, i, bad, kind))

            has_ev = _has_evidence(masked)
            has_ref = _has_reference(masked, skip_first_cell=is_row)
            cells = _cells(line) if is_row else []
            prev_cells = cells if is_row else None
            if status_idx is not None:
                checked = [cells[status_idx]] if status_idx < len(cells) else []
            elif verdict_idx is not None:
                checked = [c for idx, c in enumerate(cells) if idx != verdict_idx]
            else:
                checked = cells

            if verdict_idx is not None and verdict_idx < len(cells):
                v = re.sub(sv["cell_decoration"], "", cells[verdict_idx]).strip()
                if v:
                    if v not in verdict_vocab:
                        msgs.append("%s:%d verdict '%s' is not in the verdict vocabulary (%s) — "
                                    "F-10" % (p, i, v, ", ".join(verdict_vocab)))
                    else:
                        need = verdict_refs.get(v)
                        if need and not re.search(F["ids"][need].strip("^$"), line):
                            msgs.append("%s:%d verdict %s without a %s reference in the same row "
                                        "(F-10: a judgement carries its record)"
                                        % (p, i, v, need.replace("_", "-")))

            # F-19 residual: when a row fails for a missing citation but an ev:
            # opener IS on the line, the real defect is usually a citation the
            # row was mangled around — say so instead of naming the wrong fix.
            ev_hint = ("" if not re.search(F["evidence"]["opener"], masked) else
                       " (an ev: token IS present on this row — an unescaped '|' inside a "
                       "citation splits the table cell, and an invalid shape satisfies nothing; "
                       "see FORMATS §3)")
            for c in checked:
                # F-41 (v0.6.1's mention-vs-claim rule, applied to the third
                # place that lacked it): a backtick-wrapped cell in a
                # checked-in-full table is a MENTION — a verdict-comparison
                # table must be able to say `PASS` about the thing it reports
                # on. A Status/Grade COLUMN's content stays a claim by
                # position (status_idx/verdict_idx paths), so there is no
                # evasion route for real statuses.
                raw = c.strip()
                if status_idx is None and len(raw) > 1 \
                        and raw.startswith("`") and raw.endswith("`"):
                    continue
                bare = re.sub(sv["cell_decoration"], "", c).strip()
                if not bare:
                    continue
                up = bare.upper()
                if bare.startswith(sv["cascade_prefix"]):
                    if not re.match(sv["cascade_form"], bare):
                        msgs.append("%s:%d '%s' is not the cascade form %s"
                                    % (p, i, bare, sv["cascade_form"]))
                    elif not has_ref:
                        msgs.append("%s:%d cascade status '%s' with no blocker reference"
                                    % (p, i, bare))
                elif up in ev_required and not has_ev:
                    msgs.append("%s:%d status %s without an ev: citation%s"
                                % (p, i, bare, ev_hint))
                elif up in ref_required and not has_ref:
                    msgs.append("%s:%d status %s without a %s in the same row"
                                % (p, i, bare, ref_required[up]))
                elif bare.lower() in done_words and len(bare.split()) == 1 and not has_ev:
                    msgs.append("%s:%d done-word '%s' used as a status without an ev: citation"
                                % (p, i, bare))
                elif up in forbidden and up not in allowed:
                    hint = (" — a verdict belongs under a Grade/Verdict header, not a status "
                            "column (F-20)" if up in [v.upper() for v in verdict_vocab] else "")
                    msgs.append("%s:%d '%s' is not in the status vocabulary (%s)%s"
                                % (p, i, bare, ", ".join(sorted(allowed)), hint))
                else:
                    # F-14 (v0.6.3): a cell that BEGINS with a status token and
                    # is not a bare status equalled no vocabulary member and
                    # fell through every branch in silence — 'COMPLETED —
                    # verdict NO' was the run's most consequential claim and
                    # the gate said nothing. Trailing evidence or a reference
                    # id is the sanctioned shape; trailing prose is not.
                    parts = bare.split(None, 1)
                    # Only a token WRITTEN as a status (uppercase) opens the
                    # F-14 branch — 'blocked by PARK-U1-01' in a prose cell is
                    # description, 'COMPLETED — verdict NO' is an ungradeable
                    # claim.
                    w = parts[0] if parts and parts[0].isupper() else ""
                    if w and (w in allowed or w in forbidden or w.lower() in done_words):
                        rest = parts[1] if len(parts) > 1 else ""
                        rest = re.sub(F["evidence"]["any"], "", rest)
                        for key in sv["reference_id_patterns"]:
                            rest = re.sub(F["ids"][key].strip("^$"), "", rest)
                        rest = rest.strip(" .,;:—–-")
                        if rest:
                            msgs.append("%s:%d cell '%s' begins with status token '%s' but is "
                                        "not a bare status — a row that looks like a status row "
                                        "and is not gradeable must not pass quietly (F-14)"
                                        % (p, i, bare[:60], w))
                        elif w in ev_required and not has_ev:
                            msgs.append("%s:%d status %s without an ev: citation%s"
                                        % (p, i, w, ev_hint))
                        elif w in ref_required and not has_ref:
                            msgs.append("%s:%d status %s without a %s in the same row"
                                        % (p, i, w, ref_required[w]))
                        elif w in forbidden and w not in allowed:
                            msgs.append("%s:%d '%s' is not in the status vocabulary (%s)"
                                        % (p, i, w, ", ".join(sorted(allowed))))

            m = re.search(sv["status_prefix"], line, re.I)
            if m:
                word = m.group(2)
                if (word.upper() in ev_required or word.lower() in done_words) and not has_ev:
                    msgs.append("%s:%d '%s: %s' without an ev: citation" % (p, i, m.group(1), word))
                elif word.upper() in ref_required and not has_ref:
                    msgs.append("%s:%d '%s: %s' without a %s"
                                % (p, i, m.group(1), word, ref_required[word.upper()]))
    return (len(msgs) == 0), msgs + notes + _subject_note("GATE-3", scanned)


# --------------------------------------------------------------------------
# GATE-2 — REQ ids named by the active spec/plan have UPDATED rows
# --------------------------------------------------------------------------
def _req_id_pattern():
    """PF-d (pilot #2, v0.6.0): the requirement id shape is repo-local truth.
    wow.config.json may set `requirement_id`; `ids.requirement` is the default.
    A brownfield repo keeps its stable, non-renumberable identities instead of
    choosing between breaking every citation and a permanently-green GATE-2."""
    return cfg().get("requirement_id") or F["ids"]["requirement"]


def _req_row_re():
    """The row regex is DERIVED from the effective id pattern by substituting
    into requirements_row_schema.row (placeholder `{req}`), so gate-2's
    discovery and the row parser can never disagree about the id shape."""
    return re.compile(F["requirements_row_schema"]["row"]
                      .replace("{req}", _req_id_pattern().strip("^$")))


def _req_rows():
    """Returns (rows, unreadable). `unreadable` lists REQUIREMENTS.md table
    rows whose first cell is id-shaped but which the effective row regex
    cannot read — FR-1's rule applied to gate-2 (PF-d): a registry whose rows
    the schema cannot read must fail LOUDLY, never parse as empty. First
    cells wrapped in backticks are mentions, not rows (PF-a convention)."""
    schema = F["requirements_row_schema"]
    row_re = _req_row_re()
    idish = re.compile(r"^\|\s*~{0,2}([A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)+)\s*~{0,2}\s*\|")
    rows, unreadable = {}, []
    for i, line in enumerate(lines_of(rp(schema["file"])), 1):
        m = row_re.match(line)
        if m:
            rows[m.group("req")] = line
            continue
        if _is_separator(line):
            continue
        im = idish.match(line)
        if im and any(ch.isdigit() for ch in im.group(1)):
            unreadable.append("%s:%d first cell %r is id-shaped but the effective "
                              "requirement pattern %r cannot read this row"
                              % (schema["file"], i, im.group(1), _req_id_pattern()))
    return rows, unreadable


def _req_rows_touched(run_id):
    """REQ ids whose REQUIREMENTS row appears among this run's added/changed
    lines. 'A row exists' is not what GATE-2 asks for — it asks for an updated
    row, and a row untouched since a previous milestone is the failure case."""
    schema = F["requirements_row_schema"]
    req_pat = _req_id_pattern().strip("^$")
    diffs = []
    base = fill(F["branch_patterns"]["base_ref"], run_id=run_id) if run_id else None
    if base and git("rev-parse", "--verify", "--quiet", base).strip():
        diffs.append(git("diff", "-U0", "%s...HEAD" % base, "--", schema["file"]))
    elif run_id:
        for s in [x for x in git("log", "--format=%H", "--grep", run_id).split("\n") if x.strip()]:
            diffs.append(git("show", "-U0", "--pretty=format:", s, "--", schema["file"]))
    diffs.append(git("diff", "-U0", "HEAD", "--", schema["file"]))
    diffs.append(git("diff", "-U0", "--cached", "HEAD", "--", schema["file"]))
    touched = set()
    for d in diffs:
        for line in d.split("\n"):
            if line.startswith("+") and not line.startswith("+++"):
                for m in re.finditer(req_pat, line):
                    touched.add(m.group(0))
    return touched


def _governing_sources(run_id):
    """GATE-2's scope: the run's GOVERNING spec and its PLAN.

    GATES-SPEC's GATE-2 row says "every REQ ID named by *the active spec/plan*"
    — singular and definite. It never authorised following references out to
    other specs. Walking every .md under runs/<id>/ and appending every spec
    path any of them mentioned did exactly that, so a HANDOFF pointer to an
    unsigned draft pulled that draft's requirement ids into the set this run
    was required to have updated — including ids belonging to its "owned
    elsewhere" table, which have no technical status to update. `G-11`.

    The governing spec is already declared and already machine-parsed:
    plan_schema.spec_header, which GATE-8 validates. This reads that
    declaration instead of guessing from prose.
    """
    srcs, notes = [], []
    plan_rel = fill(F["plan_schema"]["file"], run_id=run_id)
    if not os.path.isfile(rp(plan_rel)):
        # F-36 (v0.6.4): archiving moved the plan and the gate reported
        # "nothing to check" — a failing gate laundered into a passing one at
        # the last gate a run ever faces. The archived plan is still the
        # governing record; read it from where it lives.
        arch_rel = os.path.join(F["runs_layout"]["archive_dir"], run_id,
                                os.path.basename(plan_rel))
        if os.path.isfile(rp(arch_rel)):
            plan_rel = arch_rel
            notes.append("run %s is archived — governing plan read from %s (F-36)"
                         % (run_id, arch_rel))
        else:
            notes.append("run %s has no %s — no governing spec to resolve; "
                         "REQ scope is empty rather than guessed from run prose"
                         % (run_id, plan_rel))
            return srcs, notes
    srcs.append(plan_rel)
    m = re.search(F["plan_schema"]["spec_header"], read(rp(plan_rel)), re.M)
    if m:
        srcs.append(m.group(1))
    else:
        notes.append("%s declares no 'spec:' header — GATE-2 scope is the plan "
                     "alone (plan structure is GATE-8's)" % plan_rel)
    return srcs, notes


def gate_2(run_id=None, spec=None, close=False):
    """F-09 (v0.6.3): two forms, mirroring GATE-9's own design. The SWEEP form
    is a consistency lint — every named requirement id has a row at all, and
    unreadable rows fail loudly. The CLOSE form (--close, at G4/P4) adds the
    updated-row requirement. Pre-split, the updated-row check fired the moment
    PLAN.md landed: at G2 no work has run, so the gate had no phase where it
    was both in scope and satisfiable before P4 — and updating the row at G2
    to appease it would claim a technical status the run has not earned."""
    schema = F["requirements_row_schema"]
    req_pat = _req_id_pattern().strip("^$")
    scoped = bool(run_id or spec)
    pre_msgs = []
    if not scoped:
        run_id = discover_run()
        if not run_id:
            # DEV-R9-10: same condition, same vocabulary — gate-3 said VACUOUS
            # here while this gate said 'nothing to check', unmarked.
            return True, ["no runs and no --spec: nothing to check — VACUOUS for this "
                          "checkout (a green over an empty set certifies nothing; "
                          "prodsim/F-70)"]

    named, sources = set(), []
    if spec:
        sources.append(spec)
    if run_id:
        srcs, notes = _governing_sources(run_id)
        sources.extend(srcs)
        pre_msgs.extend(notes)
    # F-17 (v0.6.4): declarations over scan. A literal text scan made the
    # obligation set "the ids that happen to be spelled out" — a range enrolled
    # two of five rows, and any scanned doc that DISCUSSED an id adopted it,
    # so a repo's own record of its gate defects was unwritable. When the spec
    # header declares `requirements:` or any unit declares `governs:`, those
    # declarations ARE the set; mention is no longer claim.
    declared = set()
    for s in sorted(set(sources)):
        txt = read(rp(s))
        m = re.search(schema["spec_declaration"],
                      "\n".join(txt.split("\n")[:F["jira_mapping"]["header_lines"]]), re.M)
        if m:
            for dm in re.finditer(req_pat, m.group(1)):
                declared.add(dm.group(0))
        for pat_name in ("inline_list_field", "list_field"):
            for gm in re.finditer(fill(F["plan_schema"][pat_name], name="governs"), txt, re.M):
                for dm in re.finditer(req_pat, gm.group(1)):
                    declared.add(dm.group(0))
    if declared:
        named = declared
        pre_msgs.append("obligation set from declarations (requirements:/governs:) — %d id(s); "
                        "mention is not claim (F-17)" % len(named))
    else:
        for s in sorted(set(sources)):
            for m in re.finditer(req_pat, read(rp(s))):
                named.add(m.group(0))
        if named:
            pre_msgs.append("obligation set built by TEXT SCAN — a range or prose reference "
                            "does not enroll a row; declare requirements:/governs: to make the "
                            "set explicit (F-17)")
    if scoped and run_id and not sources:
        if not os.path.isdir(rp(P["runs_dir"], run_id)):
            return False, pre_msgs + [
                "run %s exists neither active nor archived — a closing gate whose scope "
                "resolves to nothing reports UNGRADED, never passed (F-36)" % run_id]
    rows, unreadable = _req_rows()
    if unreadable:
        # PF-d / FR-1: id-shaped rows the pattern cannot read must fail loudly,
        # never contribute to an empty-and-therefore-permissive named set.
        return False, pre_msgs + unreadable + [
            "%d requirement row(s) exist that GATE-2 cannot read — if this repo's "
            "requirement ids are not %s, set `requirement_id` in wow.config.json "
            "(repo-local truth, never overwritten by install)"
            % (len(unreadable), F["ids"]["requirement"])]
    if not named:
        return True, pre_msgs + ["no requirement ids (pattern %s) named by the "
                                 "active spec/plan" % _req_id_pattern()]

    missing = sorted(r for r in named if r not in rows)
    if missing:
        return False, pre_msgs + ["REQ id named by the active spec/plan has no row in %s: %s"
                                  % (schema["file"], ", ".join(missing))]
    msgs = pre_msgs + ["%d REQ id(s) checked, all have rows" % len(named)]
    if not close:
        msgs.append("consistency form: updated-row check binds at phase close "
                    "(gate-2 --close, at G4/P4) — F-09")
        return True, msgs
    if run_id and schema.get("must_be_updated_in_run"):
        touched = _req_rows_touched(run_id)
        stale = sorted(r for r in named if r not in touched)
        if stale:
            return False, msgs + [
                "REQ row(s) never updated in run %s — GATE-2 requires an updated technical-status "
                "row at phase close, not merely a row that exists: %s" % (run_id, ", ".join(stale))]
        msgs.append("%d row(s) updated in this run" % len(touched & named))
    # prodsim/F-86 (v0.7.4, moved here in R11b — ADV-R11-04/DEV-R11-04): the
    # walk artifact is a CLOSE-form requirement; demanding it from gate-10 at
    # P4 step 1 refused the gate before step 2 had written it, F-77's own
    # ordering class one phase earlier.
    if run_id:
        walk = _walk_check(run_id)
        if walk:
            return False, msgs + walk
        items = _walk_items(run_id) or []
        msgs.append("walk: %d/%d RUN-REPORT item(s) classified in %s"
                    % (len(items), len(items), fill(F["runs_layout"]["walk"], run_id=run_id))
                    if items else "walk: 0 failed/blocked/parked/defect items — no walk artifact owed")
    return True, msgs


# --------------------------------------------------------------------------
# GATE-4 — invariants/checks carry a recorded, citing non-vacuity proof
# --------------------------------------------------------------------------
def gate_4(run_id=None):
    nv = F["non_vacuity"]
    msgs = []
    for gate_id in F["gates"]:
        if gate_id.startswith("$"):
            continue
        want = fill(nv["gate_test_file"], gate=gate_id.lower())
        if not os.path.isfile(rp(want)):
            msgs.append("%s has no negative test at %s" % (gate_id, want))
    wiring = nv.get("install_test_file")
    if wiring and not os.path.isfile(rp(wiring)):
        msgs.append("no wiring test at %s — gate logic and gate wiring are different claims"
                    % wiring)

    if run_id is None:
        run_id = discover_run()
    if run_id:
        d = rp(P["runs_dir"], run_id)
        for base, _dirs, files in os.walk(d):
            for fn in files:
                if not fn.endswith(".md"):
                    continue
                p = os.path.join(base, fn)
                rel = os.path.relpath(p, ROOT)
                txt = read(p)
                n_inv = len(re.findall(nv["invariant_marker"], txt, re.M))
                proofs = re.findall(nv["proof_marker"], txt, re.M)
                if n_inv > len(proofs):
                    msgs.append("%s declares %d invariant(s) but records %d non-vacuity proof(s)"
                                % (rel, n_inv, len(proofs)))
                if nv.get("proof_must_cite"):
                    for proof in proofs:
                        if re.search(F["evidence"]["any"], proof):
                            continue
                        cited = [t for t in re.findall(nv["proof_path_hint"], proof)
                                 if os.path.exists(rp(t))]
                        if not cited:
                            msgs.append("%s non-vacuity proof cites nothing runnable: '%s' — a "
                                        "proof names an ev: citation or an existing file"
                                        % (rel, proof.strip()))
    return (len(msgs) == 0), msgs


# --------------------------------------------------------------------------
# GATE-6 — codebase-map freshness (git) + external-dep freshness (probe hash)
# --------------------------------------------------------------------------
def _frontmatter(path):
    """F-12 (v0.6.3): the YAML block-list form is what a YAML-literate author
    writes by default, and the parser used to read it as an empty scalar —
    which downstream became a freshness gate that could never go stale. Block
    lists now parse; the empty-value case is handled loudly by the callers."""
    fmspec = F["frontmatter"]
    ls = lines_of(path)
    if not ls or ls[0].strip() != fmspec["fence"]:
        return None
    fm, i, last_key = {}, 1, None
    while i < len(ls) and ls[i].strip() != fmspec["fence"]:
        raw = ls[i]
        item = re.match(r"^\s+-\s+(.*)$", raw)
        if item and last_key is not None:
            if not isinstance(fm[last_key], list):
                fm[last_key] = [fm[last_key]] if str(fm[last_key]).strip() else []
            fm[last_key].append(item.group(1).strip().strip('"\''))
            i += 1
            continue
        m = re.match(fmspec["key_value"], raw.strip())
        if m:
            v = m.group(2).strip()
            if v.startswith("["):
                v = [x.strip().strip('"\'') for x in v.strip("[]").split(",") if x.strip()]
            fm[m.group(1)] = v
            last_key = m.group(1)
        i += 1
    return fm


def _dep_fresh(name, probe=True):
    """FORMATS §11. Fresh iff the probe's output hash matches; where no probe
    surface is definable, iff `verified` is within max_age_days."""
    spec = F["dep_frontmatter"]
    rel = fill(spec["file"], name=name)
    mp = rp(rel)
    if not os.path.isfile(mp):
        return False, "no dependency map at %s" % rel
    fm = _frontmatter(mp)
    if not fm:
        return False, "%s has no front-matter" % rel
    for k in spec["required"]:
        if k not in fm:
            return False, "%s front-matter missing '%s'" % (rel, k)
    if fm.get("kind") and fm["kind"] not in spec["kinds"]:
        return False, "%s kind '%s' is not one of %s" % (rel, fm["kind"], spec["kinds"])
    cmd = fm.get("probe")
    if cmd and probe:
        # frisbii S-2 (v0.6.2): the probe is executed as shell, so what it may
        # BE is part of the schema. Checked BEFORE execution — a gate that
        # rejects the map after running the command has prevented nothing —
        # and with NO fall-through to the calendar branch: a rejected probe
        # silently reporting fresh is exactly the failure mode.
        allowed = cfg().get("probe_command_pattern") or spec["probe_allowed"]
        if not re.match(allowed, cmd.strip()):
            return False, ("%s probe %r is outside the allowed command pattern %r — probes route "
                           "through the repo's request wrapper; not executed. Repo-local override: "
                           "probe_command_pattern in wow.config.json (frisbii S-2)"
                           % (name, cmd.strip()[:60], allowed))
        want = fm.get("verified_against_hash")
        if not want:
            return False, "%s defines a probe but no verified_against_hash" % name
        try:
            out = subprocess.check_output(
                cmd, shell=True, cwd=ROOT, stderr=subprocess.DEVNULL,
                timeout=spec["freshness"]["probe_timeout_seconds"])
        except Exception as e:
            return False, "%s probe failed to run (%s) — cannot establish freshness" % (
                name, type(e).__name__)
        algo = spec["freshness"]["hash_algorithm"]
        got = hashlib.new(algo, out).hexdigest()
        if got != want:
            return False, ("%s is STALE: probe hash %s != recorded %s. The vendor surface moved "
                           "since verification — re-verify the map's claims, do not just restamp "
                           "the hash" % (name, got[:12], str(want)[:12]))
        return True, "%s is fresh (probe hash matches)" % name
    why = "no probe defined" if not cmd else "--no-probe"
    max_age = int(fm.get("max_age_days") or spec["freshness"]["default_max_age_days"])
    try:
        v = time.strptime(str(fm["verified"])[:10], "%Y-%m-%d")
    except Exception:
        return False, "%s has an unparseable verified: '%s'" % (name, fm.get("verified"))
    age = (time.time() - time.mktime(v)) / 86400.0
    if age > max_age:
        return False, "%s is STALE: verified %.0f days ago, max_age_days is %d (%s)" % (
            name, age, max_age, why)
    return True, "%s is fresh (verified %.0f days ago, within %d — %s)" % (
        name, age, max_age, why)


def _plan_field_list(run_id, field):
    ps = F["plan_schema"]
    txt = read(rp(fill(ps["file"], run_id=run_id)))
    vals = []
    for m in re.finditer(fill(ps["list_field"], name=field), txt, re.M):
        vals += [l.strip().lstrip("-").strip().strip("`")
                 for l in m.group(1).split("\n") if l.strip()]
    for m in re.finditer(fill(ps["inline_list_field"], name=field), txt, re.M):
        vals += [x.strip().strip('"\'') for x in m.group(1).split(",") if x.strip()]
    return sorted(set(vals))


def _area_fresh(area, run_id):
    cb = F["codebase_frontmatter"]
    rel = fill(cb["file"], area=area)
    mp = rp(rel)
    if not os.path.isfile(mp):
        rec = None
        if run_id:
            p0 = cb["p0_record"]
            h = read(rp(fill(p0["file"], run_id=run_id)))
            pat = fill(p0["pattern"], area=re.escape(area), values="|".join(p0["values"]))
            m = re.search(pat, h, re.M)
            rec = m.group(1) if m else None
        if rec:
            return True, "no map for '%s'; HANDOFF records p0-record = %s" % (area, rec)
        return False, "no codebase map at %s and no p0-record in HANDOFF" % rel
    fm = _frontmatter(mp)
    if not fm:
        return False, "%s has no front-matter" % rel
    for k in cb["required"]:
        if k not in fm:
            return False, "%s front-matter missing '%s'" % (rel, k)
    paths = fm["paths"] if isinstance(fm["paths"], list) else [fm["paths"]]
    paths = [x for x in paths if str(x).strip()]
    # F-12 (v0.6.3): an empty paths list ran `git log -- ''`, git REFUSED the
    # command, the helper swallowed stderr, and the gate reported fresh — it
    # was not observing "no commits touched the map", it was observing a
    # failed invocation and could not tell the two apart. A gate that cannot
    # run its own check must not report the result of having passed it.
    if not paths:
        return False, ("map '%s' resolves to an EMPTY paths list — the freshness check cannot "
                       "run, and that is not fresh. Front-matter paths take the inline "
                       "[a, b] or block-list form (F-12)" % area)
    if not git("rev-parse", "--verify", "--quiet", "%s^{commit}" % fm["verified_against"]).strip():
        return False, ("map '%s' verified_against %r is not a commit this repo can resolve — "
                       "the freshness check cannot run, and that is not fresh (F-12)"
                       % (area, fm["verified_against"]))
    # F-45 (v0.7.1): the verdict follows the DIFF, not the commit list — a
    # content-neutral merge (normal at every run's end) made a fresh map
    # report stale, and a grounding phase whose delta is routinely nothing
    # teaches its reader that the stamp is a formality. Commits still inform
    # the message; only content decides.
    clean = git("diff", "--quiet", fm["verified_against"], "HEAD", "--", *paths, rc=True)
    out = git("log", "--oneline", "%s..HEAD" % fm["verified_against"], "--", *paths)
    n = len(out.strip().split("\n")) if out.strip() else 0
    if not clean:
        return False, "map '%s' is STALE: content under %s differs since %s (%d commit(s))" % (
            area, paths, fm["verified_against"], n)
    if n:
        return True, "map '%s' is fresh (%d commit(s) touch its paths but the tree is "                      "unchanged — F-45)" % (area, n)
    return True, "map '%s' is fresh" % area


def gate_6(area=None, run_id=None, deps=None, probe=True):
    """(a) codebase-map freshness per FORMATS §6 — git rule, for the areas the
       plan declares (or --area). (b) external-dep freshness per FORMATS §11."""
    msgs, ok = [], True
    areas = [area] if area else (_plan_field_list(run_id, "areas") if run_id else [])
    if deps is None:
        deps = _plan_field_list(run_id, "deps") if run_id else []

    if not areas and not deps and not run_id:
        return False, ["nothing to check: pass --area, --deps or --run. A gate invoked with no "
                       "scope is not a pass."]
    if run_id and not area and not areas:
        ps = F["plan_schema"]
        plan_rel = fill(ps["file"], run_id=run_id)
        if not os.path.isfile(rp(plan_rel)):
            # OBL-PKG-02 / PF-04: a run with no plan is not an empty check — it
            # is the subject-absent case, and an absent subject is never a pass.
            ok = False
            msgs.append("no %s — GATE-6 has nothing to check, and that is not a pass "
                        "(subject-absent, GATES-SPEC v0.5.3)" % plan_rel)
        elif not _parse_plan(rp(plan_rel))["units"]:
            ok = False
            msgs.append("%s parses into no units — GATE-6 cannot resolve areas. A plan the "
                        "schema cannot read is not a plan that declares no areas." % plan_rel)
        else:
            ok = False
            msgs.append("PLAN.md declares no 'areas:' for any unit — GATE-6(a) then has nothing "
                        "to check. Declare the codebase areas each unit touches (FORMATS §6).")

    for a in areas:
        good, why = _area_fresh(a, run_id)
        msgs.append(why)
        if not good:
            ok = False
    for d in deps:
        good, why = _dep_fresh(d, probe=probe)
        msgs.append(why)
        if not good:
            ok = False
    return ok, msgs


# --------------------------------------------------------------------------
# GATE-12 — obligation block at /wow-spec (FORMATS §12, OBL-PKG-01)
# --------------------------------------------------------------------------
def _gap_rows():
    """Parse docs/GAPS.md per formats.json gap_row. Returns (rows, problems).

    A malformed effect cell is a PROBLEM, never a silently non-blocking row —
    the enum is closed (v0.5.6, pilot N3: an unrecognized effect downgrading to
    non-blocking would silently disarm the one row guarding a reinstall)."""
    gr = F["gap_row"]
    path = rp(gr["file"])
    if not os.path.isfile(path):
        # DEV-R9-02 (v0.7.3 R9): a fresh adopter dead-ended here — the refusal
        # named the missing registry and no doc the consumer receives carries
        # the row schema. The message hands over the exact header to paste.
        hdr = "| " + " | ".join(gr["columns"]) + " |"
        sep = "|" + "|".join("---" for _ in gr["columns"]) + "|"
        return None, ["no %s — the obligation registry does not exist; an empty table is a "
                      "valid registry — create the file with exactly this header:\n  %s\n  %s"
                      % (gr["file"], hdr, sep)]
    rows, problems = [], []
    for ln in lines_of(path):
        if not re.match(gr["row_start"], ln):
            continue
        cells = _cells(ln)
        if len(cells) > len(gr["columns"]):
            # F-44 (v0.7.1): zip() silently DISCARDED every cell past the
            # seventh — an unescaped pipe in a citation deleted evidence from
            # the registry the gates read, while the rendered file still
            # showed it. Too-many is as loud as too-few.
            problems.append("gap row has %d cells, schema needs exactly %d: %s — an unescaped "
                            "'|' inside a cell (a pipe in an ev:cmd?) splits the row; escape it "
                            "as \\| so the evidence survives (F-44)"
                            % (len(cells), len(gr["columns"]), cells[0] if cells else ln[:40]))
            continue
        if len(cells) < len(gr["columns"]):
            problems.append("gap row has %d cells, schema needs %d: %s — note %s holds exactly "
                            "ONE table (FORMATS §12): any table whose first cell is id-shaped is "
                            "read as gap rows, so non-obligation tables belong in a sibling "
                            "document (or backtick their ids: a backticked id is a mention)"
                            % (len(cells), len(gr["columns"]),
                               cells[0] if cells else ln[:40], gr["file"]))
            continue
        row = dict(zip(gr["columns"], cells))
        _idp = cells[0].strip().strip("~")
        if _idp.startswith("OBL-") and not re.match(F["ids"]["obligation"], _idp):
            # F-55 (v0.7.2): ids.obligation was wrong (two-digit ceiling, a
            # pilot is at 134) AND unconsumed — an inert-and-wrong declaration
            # is worse than an absent one, because the next author to wire it
            # up reasonably assumes it was true. It is consumed HERE now, so
            # it can never again be wrong in silence.
            problems.append("gap row id %r does not match ids.obligation (%s) — fix the id or "
                            "the pattern; a declared shape the live ids violate is a trap for "
                            "the next consumer (F-55)" % (_idp, F["ids"]["obligation"]))
            continue
        row["open"] = not re.match(gr["discharged_id"], row["id"].strip())
        row["id_plain"] = row["id"].strip().strip("~")
        m = re.match(gr["effect_cell"], row["effect"].strip())
        if not m:
            problems.append("row %s: effect %r is outside the closed vocabulary %s — an "
                            "unrecognized effect FAILS loudly, it is never non-blocking"
                            % (row["id_plain"], row["effect"].strip()[:40], gr["effect_enum"]))
            continue
        row["effect_value"] = m.group(1)
        sm = re.search(gr["scope_parse"], row["effect"])
        row["scope"] = sm.group(1) if sm else "*"
        rows.append(row)
    if not rows and not problems:
        # verifier F9: FR-1's loudness covered only uppercase id-shaped rows.
        # A table whose data rows the schema cannot see at all (lowercase ids,
        # numeric ids), or a registry with no table, must not parse as empty.
        text_lines = [l for l in lines_of(path)]
        seps = [l for l in text_lines if re.match(r"^\|[\s:|-]+\|\s*$", l)]
        pipe_rows = [l for l in text_lines if l.lstrip().startswith("|")
                     and not re.match(r"^\|[\s:|-]+\|\s*$", l)]
        if seps and len(pipe_rows) > len(seps):  # header rows pair 1:1 with separators
            problems.append("%s contains a table with %d data-looking row(s) the gap_row schema "
                            "cannot read — an unreadable registry is never an empty one (F9)"
                            % (F["gap_row"]["file"], len(pipe_rows) - len(seps)))
        elif not seps and any(l.strip() for l in text_lines):
            problems.append("%s has content but no table — FORMATS \u00a712 defines the registry AS "
                            "a table; prose obligations are the failure mode this file exists to "
                            "end (F9)" % F["gap_row"]["file"])
    return rows, problems


def gate_12(kind=None, ref=None):
    """Refuse /wow-spec for a NEW FEATURE while a blocks-new-feature-work
    obligation is open. Audit/fix/probe specs are the discharge paths and must
    reference the open obligation they discharge."""
    gr = F["gap_row"]
    kind = kind or "feature"
    if kind not in gr["spec_kinds"]:
        return False, ["unknown --kind %r (one of %s)" % (kind, "|".join(gr["spec_kinds"]))]
    rows, problems = _gap_rows()
    if rows is None:
        # Subject-absent is never a pass: absence of the registry is not
        # absence of obligations. An EMPTY registry file is a valid pass.
        return False, problems + ["cannot prove no blocking obligations — create the registry "
                                  "(an empty table is a valid registry), and that is not a pass"]
    if problems:
        return False, problems
    blocking = [r for r in rows if r["open"] and r["effect_value"] == "blocks-new-feature-work"]
    if not blocking:
        return True, ["no open blocks-new-feature-work obligation (%d open row(s) total)"
                      % sum(1 for r in rows if r["open"])]
    ids = [r["id_plain"] for r in blocking]
    if kind == "feature":
        return False, ["open blocks-new-feature-work obligation(s): %s — new feature work is "
                       "refused until discharged; audit/fix/probe specs referencing the "
                       "obligation (or a remediation spec referencing the defect it repairs) "
                       "are the way through" % ", ".join(ids)]
    if kind == "remediation":
        # F-53 (v0.7.2): repairing a regression a prior run shipped discharges
        # NO blocker, so keying the exemption to blocking rows left only a PO
        # overrule — the route the framework most wants rare. A remediation
        # spec's proof points at the DEFECT RECORD it repairs instead.
        return _remediation_ref_ok(ref)
    if not ref or ref not in ids:
        return False, ["--kind %s is exempt only when it references the open obligation it "
                       "discharges: pass --ref with one of %s" % (kind, ", ".join(ids))]
    return True, ["%s spec discharging %s — exemption applies" % (kind, ref)]


def _remediation_ref_ok(ref):
    """--kind remediation: the ref must be a defect-record id (park, verifier
    finding, plan defect, cannot-validate, or registry row) AND that record
    must exist somewhere durable or in the runs tree — a claim, not a mention
    (backticked occurrences do not count)."""
    if not ref:
        return False, ["--kind remediation requires --ref <defect-record-id> — the park, "
                       "verifier finding, plan defect, CV or registry row this spec repairs "
                       "(F-53)"]
    shapes = ["park", "verifier_finding", "plan_defect", "cannot_validate", "obligation"]
    if not any(re.match(F["ids"][k], ref) for k in shapes):
        return False, ["--ref %r matches no defect-record shape (%s) — a remediation is "
                       "justified by a recorded defect, and this id cannot be one (F-53)"
                       % (ref, ", ".join("ids." + k for k in shapes))]
    homes = [rp(F["gap_row"]["file"])]
    runs_dir = rp(P["runs_dir"]) if "runs_dir" in P else rp("runs")
    for root, _dirs, files in os.walk(runs_dir):
        for fn in files:
            if fn.endswith(".md"):
                homes.append(os.path.join(root, fn))
    for h in homes:
        if not os.path.isfile(h):
            continue
        if re.search(r"(?<![`\w-])" + re.escape(ref) + r"(?![\w-])",
                     "\n".join(_mask_inline_code_doc(read(h)))):
            return True, ["remediation spec repairing recorded defect %s (found in %s) — "
                          "exemption applies (F-53)" % (ref, os.path.relpath(h, ROOT))]
    return False, ["--ref %s resolves to NO recorded defect in runs/ or %s — a remediation "
                   "justified by a record nobody can read is a feature spec wearing a flag "
                   "(F-53)" % (ref, F["gap_row"]["file"])]


# --------------------------------------------------------------------------
# GATE-13 — plan Verify non-vacuity (F-9, pilot #1; their local GATE-12)
# --------------------------------------------------------------------------
def gate_13(run_id=None):
    """A task's Verify command is the sole mechanical arbiter of COMPLETED,
    and GATE-4's scope predicate (invariant_marker) cannot see a markdown task
    row — so the highest-volume checks in the system were the only ones never
    required to be shown failing. Nine inert verifies shipped in one pilot
    run; adversarial review caught six and missed three.

    Two halves: (1) a Non-vacuity cell per task naming a plausible wrong
    answer the Verify rejects, citing something runnable (gate-4's own proof
    rule) or MANUAL; (2) a lint over Verify cells for idioms that each
    shipped a real inert check, accepted only deliberately and visibly via
    the lint-ok marker. Binds while the plan is UNSIGNED: a signed plan is
    frozen, and a retroactive rule would demand exactly the edit the
    framework prohibits."""
    ps = F["plan_schema"]
    vl = F["verify_lint"]
    if not run_id:
        run_id = discover_run()
    if not run_id:
        return False, ["nothing to check: pass --run or create a run. A gate invoked with no "
                       "scope is not a pass."]
    plan_rel = fill(ps["file"], run_id=run_id)
    if not os.path.isfile(rp(plan_rel)):
        return False, ["no %s — GATE-13 has nothing to check, and that is not a pass" % plan_rel]
    head = "\n".join((read(rp(plan_rel)) or "").split("\n")[:F["jira_mapping"]["header_lines"]])
    if re.search(F["jira_mapping"]["signoff_record"], head, re.M):
        return True, ["plan is signed — a frozen artifact; GATE-13 binds while the plan is "
                      "being written, at G2"]
    plan = _parse_plan(rp(plan_rel))
    if not plan["units"]:
        return False, ["%s parses into no units — a plan the schema cannot read is not a plan "
                       "with proven verifies" % plan_rel]
    if sum(len(u["tasks"]) for u in plan["units"]) == 0:
        return False, ["%s parses into units but ZERO task rows — GATE-13 cannot lint verifies "
                       "it cannot see; task ids must be fully qualified (%s) (F-13's shape, "
                       "applied here before it applied)" % (plan_rel, F["ids"]["task"])]
    msgs = []
    exempt = ps["task_verify_exempt_marker"]
    nv_name = ps["non_vacuity_column"]
    for u in plan["units"]:
        if u["tasks"] and not u.get("nv_header_seen"):
            msgs.append("unit %s's task table has no '%s' column — every Verify states the "
                        "wrong answer it rejects, or the check is only believed to check (F-9)"
                        % (u["id"], nv_name))
        for t in u["tasks"]:
            # DEV-R9-05 (v0.7.3 R9): a row whose cell count disagrees with its
            # header parses into a DIFFERENT table (F-18) — GATE-8 said so
            # while GATE-13, reading the same shifted row at the same G2
            # moment, blamed a healthy Non-vacuity cell under the wrong rule.
            # Same guard, same wording, then stop reading the broken row.
            if t.get("header_n") and t.get("cells_n") != t["header_n"]:
                msgs.append("task %s: %d columns expected, %d found — an unescaped '|' in a "
                            "cell (a shell pipe?). Escape it as \\| or route the command "
                            "through a file (F-18); GATE-13 reads no cell of a shifted row"
                            % (t["id"], t["header_n"], t["cells_n"]))
                continue
            nv = (t.get("nonvac") or "").strip()
            ver = (t.get("verify") or "").strip()
            if u.get("nv_header_seen"):
                if not nv:
                    msgs.append("task %s has an empty %s cell — name the plausible wrong answer "
                                "its Verify rejects, or mark it %s" % (t["id"], nv_name, exempt))
                elif nv != exempt:
                    if not (re.search(F["evidence"]["any"], nv)
                            or any(os.path.exists(rp(x))
                                   for x in re.findall(F["non_vacuity"]["proof_path_hint"], nv))):
                        msgs.append("task %s %s cell cites nothing runnable: '%s' — a proof "
                                    "names an ev: citation or an existing file (gate-4's rule)"
                                    % (t["id"], nv_name, nv[:60]))
            marker_ok = vl["accept_marker"] in nv or vl["accept_marker"] in ver
            for idiom, pat in vl["idioms"].items():
                if idiom.startswith("$"):
                    continue
                if re.search(pat, ver) and not marker_ok:
                    if idiom == "credential-default-expansion":
                        # platform/F-69 (v0.7.3): not vacuity — disclosure. A
                        # default-substitution of a credential-named variable
                        # returns the VALUE when set, which is the state a
                        # residue probe exists to detect.
                        msgs.append("task %s Verify expands a credential-named variable in a "
                                    "default-substitution form reaching echo/printf: %r — when "
                                    "the variable IS set this prints its value into a committed, "
                                    "gate-swept document. Safe forms: ${V+word} or ${#V}. Or "
                                    "accept deliberately and visibly with '%s <reason>' "
                                    "(platform/F-69)" % (t["id"], ver[:60], vl["accept_marker"]))
                        continue
                    msgs.append("task %s Verify matches inert idiom '%s' (each of these shipped "
                                "a real vacuous check in pilot #1): %r — fix it, or accept it "
                                "deliberately and visibly with '%s <reason>'"
                                % (t["id"], idiom, ver[:60], vl["accept_marker"]))
    n = sum(len(u["tasks"]) for u in plan["units"])
    if not msgs:
        return True, ["no inert idioms; non-vacuity statements present"] + \
            _subject_note("GATE-13", n)
    return False, msgs + _subject_note("GATE-13", n)


# --------------------------------------------------------------------------
# GATE-14 — personal data in staged run evidence (frisbii PII composition)
# --------------------------------------------------------------------------
def gate_14(paths=None, staged=False):
    """Two correct rules composed into committing 159 third-party customer
    records with every gate green: capture-the-response-whole (evidence
    discipline) + a legitimately widened spec scope. The framework had a rule
    about what must be captured and none about what may be COMMITTED.

    Scans staged files under a run's evidence path for populated
    personal-data field names. Heuristic by design — the visible escape
    marker (`pii-ok: <reason>`) makes a deliberate capture possible and
    visible, and P3's declared-trim convention keeps a scrubbed capture
    honest about having been trimmed."""
    ps = F["pii_scan"]
    if staged:
        paths = staged_files()
    if paths is None:
        return False, ["gate-14 needs --staged or --paths: a gate invoked with no scope is "
                       "not a pass"]
    msgs, in_scope = [], 0
    for p in paths:
        if not any(fnmatch.fnmatch(p, g) for g in ps["paths"]):
            continue
        in_scope += 1
        txt = read_staged(p) if staged else read(rp(p))
        if not txt:
            continue
        if ps["accept_marker"] in txt:
            continue
        for i, line in enumerate(txt.split("\n"), 1):
            for fld in ps["field_names"]:
                if re.search(ps["field_pattern"].replace("{field}", re.escape(fld)), line):
                    msgs.append("%s:%d populated personal-data field '%s' in run evidence — "
                                "third-party data does not land in git by default. Scrub it "
                                "(record the trim, P3), or mark the FILE 'pii-ok: <reason>' to "
                                "commit it deliberately and visibly" % (p, i, fld))
                    break
    return (len(msgs) == 0), msgs + _subject_note("GATE-14", in_scope)


# --------------------------------------------------------------------------
# GATE-7 — P5 sweep
# --------------------------------------------------------------------------
def gate_7(p5=False, run_id=None):
    rl = F["runs_layout"]
    msgs = []
    notes_extra = []
    # frisbii S-6 (v0.6.2): archiving moves tracked paths; git tracks no empty
    # directory, so runs/<id>/ can survive EMPTY in the publisher's tree and
    # status derivation lists a phantom active run — visible to exactly one
    # person, reproducible by nobody they ask. A run-id directory holding no
    # files at all is refused. (Predicate is files-on-disk, not git-tracked:
    # a brand-new run before its first commit is real, not phantom.)
    rd = rp(P["runs_dir"])
    if os.path.isdir(rd):
        for entry in sorted(os.listdir(rd)):
            if not re.match(F["ids"]["run"], entry):
                continue
            # frisbii S-6 addendum (v0.6.4): one git question is not enough.
            # Tracked file => a run. No tracked but untracked-unignored file
            # => a run somebody is mid-creating (the reported defect read
            # backwards). Neither => a leftover — and the WORDING must not
            # depend on ignore configuration: never say "commit it" about an
            # ignored path (git add refuses one outright).
            rel = os.path.join(P["runs_dir"], entry)
            tracked = git("ls-files", "--", rel).strip()
            if tracked:
                continue
            unignored = git("ls-files", "--others", "--exclude-standard", "--", rel).strip()
            if unignored:
                continue
            any_untracked = git("ls-files", "--others", "--", rel).strip()
            if any_untracked:
                msgs.append("%s holds only git-IGNORED files — a leftover from archiving, not a "
                            "run; remove the directory (frisbii S-6 addendum)" % rel)
            else:
                msgs.append("%s holds no files at all — a phantom run left by archiving "
                            "(git tracks no empty directory); prune it or status derivation "
                            "reports it active (frisbii S-6)" % rel)
    # F-11 (v0.6.2), at --p5 only: P5 step 5 regenerates permissions
    # DESTRUCTIVELY from the tree it runs in. A run branch behind main would
    # silently drop grants that landed on main through another lane, so the
    # publish is refused until main is merged in (P5 step 0).
    if p5:
        # platform/F-63 (v0.7.2): P5 archived the run DIRECTORY and nothing ever
        # deleted the run's branches — eleven remote and fourteen local refs
        # accumulated over five months in one pilot. A surviving
        # wow/<run-id>/int is a second, MORE discoverable home for content
        # the archive owns (it shows in branch pickers; runs/archive does
        # not). Local refs are graded here; the P5 clause says local AND
        # remote, because an operator who deletes one assumes the other
        # followed and each side is invisible from the other.
        arch = rp(rl["archive_dir"])
        if os.path.isdir(arch):
            archived = [e for e in sorted(os.listdir(arch))
                        if re.match(F["ids"]["run"], e)]
            refs = git("for-each-ref", "--format=%(refname:short)", "refs/heads/wow/")
            for run in archived:
                leaked = [r for r in refs.split("\n")
                          if r.strip().startswith("wow/%s/" % run)]
                if leaked:
                    # prodsim/F-79 (v0.7.4): the module's own convention — count
                    # BEFORE sample — applied to its two silent truncations; a
                    # clipped list with no marker read as complete, and the
                    # omitted ref was `int`, the load-bearing one.
                    msgs.append("run %s is archived but its branch refs survive (%d): %s%s — a "
                                "second home for content the archive owns; delete local and "
                                "remote wow/%s/* after the merge is confirmed (P5 step 3, "
                                "platform/F-63)"
                                % (run, len(leaked), ", ".join(leaked[:4]),
                                   " …" if len(leaked) > 4 else "", run))
        candidates = [cfg().get("main_branch")] if cfg().get("main_branch") \
            else F["branch_patterns"]["main_candidates"]
        main_ref = next((c for c in candidates
                         if c and git("rev-parse", "--verify", "--quiet", c).strip()), None)
        if main_ref is None:
            msgs.append("no published branch found (tried %s) — gate-7 --p5 cannot prove the run "
                        "branch is not behind it, and that is not a pass; set main_branch in "
                        "wow.config.json (F-11)" % ", ".join(candidates))
        elif not git("merge-base", "--is-ancestor", main_ref, "HEAD", rc=True):
            msgs.append("this branch is BEHIND %s — P5 step 5 regenerates permissions from this "
                        "tree and would silently drop grants that landed on %s via another lane; "
                        "merge it in first (P5 step 0, F-11)" % (main_ref, main_ref))
    for base, _dirs, files in os.walk(rp(P["runs_dir"])):
        if rl["jira_queue"] in files:
            p = os.path.join(base, rl["jira_queue"])
            open_items = len(re.findall(rl["open_checkbox"], read(p), re.M))
            if open_items:
                msgs.append("%s has %d unresolved queued op(s)"
                            % (os.path.relpath(p, ROOT), open_items))
    qd = rp(rl["quick_dir"])
    if os.path.isdir(qd):
        for slug in sorted(os.listdir(qd)):
            note = rp(fill(rl["quick"], slug=slug))
            if not os.path.isfile(note):
                continue
            m = re.search(rl["quick_result_section"], read(note), re.M | re.I)
            if (m is None) or (m.group(1).strip() == ""):
                age = (time.time() - os.path.getmtime(note)) / 86400.0
                if age > rl["quick_stale_days"]:
                    # DEV-R11-09 (platform/F-80's rule at the tool that builds
                    # the candidate list): a stub a registry row CITES is not
                    # a stale stub — the gate once listed it for deletion and
                    # then refused the deletion it had suggested.
                    rel_note = fill(rl["quick"], slug=slug)
                    citing = []
                    for reg in (F["gap_row"]["file"], F["paths"]["requirements"]):
                        for i, ln in enumerate(lines_of(rp(reg)) if os.path.isfile(rp(reg)) else [], 1):
                            if "ev:file{" + rel_note in _mask_inline_code(ln):
                                citing.append("%s:%d" % (reg, i))
                    if citing:
                        notes_extra.append("%s is empty and %.0f days old but CITED by %s — retained, "
                                           "not a stale stub (platform/F-80)" % (rel_note, age, ", ".join(citing[:3])))
                        continue
                    msgs.append("%s has an empty result and is %.0f days old — stale stub, PO "
                                "confirms deletion" % (rel_note, age))
    ad = rp(rl["archive_dir"])
    if os.path.isdir(ad):
        for run in sorted(os.listdir(ad)):
            if os.path.isfile(os.path.join(ad, run, rl["active_marker"])):
                msgs.append("%s/%s is archived but still marked active" % (rl["archive_dir"], run))
    # Obligation escrow (FORMATS §12, OBL-PKG-01): nothing obligation-shaped may
    # live only in the runs/ tree being archived. Every CV id and DEFERRED row
    # in a RUN-REPORT must exist in the durable registry status.mjs reads.
    # OBL-PKG-13 (v0.7.0): the escrow PARSES the registry instead of substring-
    # matching its raw text — a CV id mentioned in another row's prose used to
    # satisfy the escrow with no row existing, and an id the row regex could
    # not read satisfied nothing visibly. Discovery is an INVENTORY scan, so
    # backticked ids in reports ARE found here (mention-vs-claim governs
    # satisfying gates, not discovering debt — fail-safe is seeing more).
    gap_rows, gap_probs = _gap_rows()
    # prodsim/F-87a (v0.7.4): four of five callers discarded the problems the
    # parser computes, and the docstring calls a malformed row LOAD-BEARING —
    # the escrow reading a registry it cannot fully parse must say so.
    # absence stays gate-12's question (an empty tree with no registry is not
    # an escrow failure); a registry that EXISTS and cannot be fully parsed is.
    if gap_rows is not None:
        for gp in gap_probs or []:
            msgs.append("registry problem (escrow reads a registry it cannot fully parse): %s "
                        "(prodsim/F-87)" % gp)
    gap_ids = {r["id_plain"] for r in (gap_rows or [])}
    open_row_texts = [" ".join(v for v in r.values() if isinstance(v, str))
                      for r in (gap_rows or []) if r["open"]]
    cv_pat = re.compile(F["ids"]["cannot_validate"].strip("^$"))
    cv_short = re.compile(F["ids"]["cannot_validate_short"].strip("^$"))
    at_row = re.compile(F["audit_triggers"]["report_row"], re.M)
    # ADV-R9-07 (v0.7.3 R9): was the ##-only handoff template while status.mjs
    # read #+ — '### audit triggers' derived a hit with no escrow row demanded.
    at_sec = re.compile(fill(F["audit_triggers"]["section_heading"],
                             name=F["audit_triggers"]["report_section"]), re.M | re.I)
    # F-36 (v0.6.4): the old exemption compared a relpath against the TEMPLATE
    # 'runs/archive/{run_id}/' — never true, so every archived run was
    # re-scanned at every future P5 despite P5 step 3 saying nothing in
    # archive is load-bearing. And the walk ignored --run, failing a publish
    # on cannot-validate ids belonging to a DIFFERENT run still mid-flight,
    # whose own G4 had not judged them.
    archive_prefix = os.path.relpath(rp(rl["archive_dir"]), rp(P["runs_dir"]))
    escrow_root = rp(P["runs_dir"], run_id) if run_id else rp(P["runs_dir"])
    runs_walked = 0
    verify_only_dirs = []
    # ADV-R9-06 (v0.7.3 R9): an explicit --run naming a directory that does not
    # exist walked zero runs and EXITED ZERO — the gate's own rule ("a gate
    # invoked with no scope is not a pass", gate-13/14) applied everywhere but
    # here, and the vacuity marker was advisory precisely at publish.
    if run_id is not None and not os.path.isdir(escrow_root):
        if os.path.isdir(os.path.join(rp(rl["archive_dir"]), run_id)):
            if p5:
                # platform/F-77 + prodsim/F-88 (v0.7.4, two pilots
                # independently): P5 step 3 archives the run and step 6 then
                # runs `sweep --p5 --run <id>` — the v0.7.3 refusal made the
                # phase's own documented command fail AFTER every irreversible
                # step, and the workaround pilots invented was un-archive/
                # re-archive around a destructive-adjacent point. At --p5 the
                # named run being archived is the SUCCESS condition of the
                # phase, not an operator error: the escrow GRADES it from the
                # archive (its state changed between the pre-archive sweep and
                # now — a GAPS row struck through at step 3 is exactly what
                # the escrow exists to catch). F-36 stays intact for every
                # run this one does not name, and the non-p5 refusal stays:
                # re-grading old archives outside a publish is unsupported.
                escrow_root = os.path.join(rp(rl["archive_dir"]), run_id)
            else:
                # ADV-R10-09: the run exists — one level down, exactly where
                # P5 filed it. Say so instead of sending the operator hunting.
                msgs.append("--run %s is ARCHIVED (%s/%s) — outside --p5, archived runs are "
                            "exempt from escrow (F-36) and are graded under the vocabulary of "
                            "their time (platform/F-65); at --p5 the named run IS graded from "
                            "the archive (platform/F-77, prodsim/F-88)"
                            % (run_id, rl["archive_dir"], run_id))
        else:
            msgs.append("--run %s names no directory under %s/ — an escrow over a missing "
                        "run judges nothing, and that is not a pass (ADV-R9-06)"
                        % (run_id, P["runs_dir"]))
    # F-37 (v0.6.4): the finding log keeps pace and the write-up document does
    # not — twice, with the first occurrence predicting the second. At publish,
    # every logged F-nn owes a write-up under the upstream dir. Runs ONLY when
    # the log exists: repos without a feedback log carry no burden.
    if p5:
        fbk = F.get("feedback", {})
        log_path = rp(fbk.get("log", ""))
        if fbk and os.path.isfile(log_path):
            wd = rp(fbk["writeups_dir"])
            corpus = ""
            if os.path.isdir(wd):
                for b2, _d2, f2 in os.walk(wd):
                    corpus += " ".join(f2) + " "
                    for fn in f2:
                        if fn.endswith(".md"):
                            corpus += read(os.path.join(b2, fn))
            for lm in re.finditer(fbk["log_row"], read(log_path), re.M):
                fid = lm.group(1)
                if fid not in corpus:
                    msgs.append("%s logs %s but %s/ holds no write-up for it — a log row a "
                                "maintainer cannot act on is drift the process predicted (F-37)"
                                % (fbk["log"], fid, fbk["writeups_dir"]))
        # platform/F-80 (v0.7.4): P5 step 4's GC deleted seven files that
        # registry rows cited as their PROOF, and the loss was invisible for
        # twelve days — a deleted proof looks exactly like a proof that never
        # existed. At publish, every ev:file target cited by a durable
        # registry must exist — at its cited path, or at the archive rewrite
        # of it (a run's files legitimately move to runs/archive/<id>/ at
        # step 3; that move is not a loss).
        for reg in (F["gap_row"]["file"], F["paths"]["requirements"]):
            reg_p = rp(reg)
            if not os.path.isfile(reg_p):
                continue
            for i, ln in enumerate(lines_of(reg_p), 1):
                for fm in re.finditer(r"ev:file\{([^}]+)\}", _mask_inline_code(ln)):
                    target = re.split(r"[#:]", fm.group(1), 1)[0].strip()
                    if not target or _resolve_target(target) is not None:
                        continue
                    msgs.append("%s:%d cites ev:file{%s} and the target exists at neither its "
                                "cited path nor the archive rewrite — a registry row's proof "
                                "has been deleted; a deleted proof looks exactly like a proof "
                                "that never existed, so publish is refused until the citation "
                                "is repaired or the row re-evidenced (platform/F-80; the "
                                "archive rewrite = runs/<id>/x resolved at runs/archive/<id>/x, "
                                "and runs/debug/x at runs/debug/resolved/x; the repair rule "
                                "distinguishes moved from deleted: FORMATS §3)"
                                % (reg, i, fm.group(1)))
    rr_name = os.path.basename(F["report_row_schema"]["file"])
    named_archived = run_id is not None and \
        os.path.abspath(escrow_root).startswith(os.path.abspath(rp(rl["archive_dir"])) + os.sep)
    for base, _dirs, files in os.walk(escrow_root):
        rel_base = os.path.relpath(base, rp(P["runs_dir"]))
        if not named_archived and (rel_base == archive_prefix
                                   or rel_base.startswith(archive_prefix + os.sep)):
            continue
        has_rr = rr_name in files
        vf_dir = os.path.join(base, "reports")
        has_vf = os.path.isdir(vf_dir) and any(v.endswith("-verify.md")
                                               for v in os.listdir(vf_dir))
        # ADV-R9-06: a run that died between verify and report assembly holds
        # CVs in reports/*-verify.md and no RUN-REPORT — under the old walk it
        # escaped escrow entirely. An EXPLICITLY named run is under judgment,
        # so its verify reports are walked even without a RUN-REPORT; the
        # unnamed walk keeps F-36's shield (a mid-flight sibling without a
        # RUN-REPORT stays invisible to a publish) but now SAYS what it is
        # skipping, as an advisory note.
        named = run_id is not None and os.path.abspath(base) == os.path.abspath(escrow_root)
        if not has_rr:
            if has_vf and not named and re.match(F["ids"]["run"], os.path.basename(base) or ""):
                verify_only_dirs.append(os.path.relpath(base, ROOT))
            if not (named and has_vf):
                continue
        rr = os.path.join(base, rr_name)
        rr_rel = os.path.relpath(rr, ROOT)
        this_run = os.path.basename(os.path.dirname(rr))
        runs_walked += 1
        text = read(rr) if has_rr else ""
        # prodsim/F-69 (v0.7.3, ADV-3): FORMATS §5 tells the VERIFIER to
        # allocate the CV record — in reports/U<n>-verify.md — while the
        # escrow read only RUN-REPORT.md. The two halves of the mechanism
        # never met: three genuine coverage limits reached no durable home
        # and the escrow reported clean, because it was never looking at the
        # file the record is born in. The run's verify reports join the SAME
        # per-run aggregation (this_run stays the run directory; discharge
        # resolves against the whole set, since allocation and discharge
        # legitimately live in different files — F-51). The walk still enters
        # only run dirs that HAVE a RUN-REPORT, which keeps F-36's shield:
        # a mid-flight sibling without one stays invisible to a publish.
        # prodsim/F-87d (v0.7.4): the aggregation kept content and lost
        # PROVENANCE — every escrow finding was attributed to RUN-REPORT.md
        # whichever file it was read from, and a consumer sent to the named
        # file found nothing there. Each text keeps its name.
        named_texts = [(rr_rel, text)] if has_rr else []
        reports_dir = os.path.join(base, "reports")
        if os.path.isdir(reports_dir):
            for vf in sorted(os.listdir(reports_dir)):
                if vf.endswith("-verify.md"):
                    vfp = os.path.join(reports_dir, vf)
                    named_texts.append((os.path.relpath(vfp, ROOT), read(vfp)))
        texts = [t for _n, t in named_texts]
        text = "\n".join(texts)
        # F-51 (v0.7.2): a CV is obligation-shaped only WHILE its discharge is
        # in the future. A record closed inside its own run (a later wave, a
        # G4 successor decision, the artifact P4 itself produces) carries a
        # `discharged:` field WITH evidence in its own block — and is then a
        # closed question the registry of open obligations need not carry.
        # Eight of eighteen records in one pilot run were closed this way and
        # the escrow demanded rows for all eighteen. A discharged: line
        # WITHOUT evidence stays demanded: an unevidenced closure is an
        # assertion, and the escrow says which it saw.
        # ADV-R9-01 (v0.7.3 R9, hardened R9b/ADV-R10-01/-04): SATISFYING the
        # escrow must not read fenced (``` or ~~~), indented-code or
        # backticked text — a fenced "example of the record format" carrying
        # a fabricated ev: discharged a real CV, and the forgery re-ran
        # through the two adjacent mention channels the day the ``` one
        # closed. Discovery stays on the RAW text (fail-safe there is seeing
        # more); discharge matching reads only claim text. Per FILE, so one
        # unclosed fence in RUN-REPORT cannot mark every verify report as
        # fenced (ADV-R10-04). Per-line span masking leaves a cross-line
        # span's interior readable; accepted residual.
        claim_text = "\n".join(_claim_text(t) for t in texts)
        # ADV-R10-03: sections and rows are located on fence-STRIPPED text —
        # a fenced '# comment' pasted above the audit-trigger table used to
        # terminate the section at both consumers and hide a recorded hit.
        sec_text = "\n".join(_strip_fenced_blocks(t) for t in texts)

        def _cv_discharged_in_run(cv):
            # ADV-R9-04: allocation and discharge legitimately live in
            # DIFFERENT files (F-51) and the aggregate keeps file order — so
            # every block for the id is consulted, not the first one found.
            closed, evidenced = False, False
            for block in re.finditer(re.escape(cv) + r":[^\n]*\n((?:[ \t]+\S[^\n]*\n?)*)",
                                     claim_text):
                dis = re.search(r"^[ \t]+discharged:\s*(.+)$", block.group(1), re.M)
                if not dis:
                    continue
                closed = True
                if re.search(F["evidence"]["opener"], dis.group(1)):
                    evidenced = True
            return closed, evidenced
        seen_cvs = set()
        for src_rel, src_text in named_texts:
            for m in re.finditer(cv_pat.pattern, src_text):
                cv = m.group(0)
                if cv in seen_cvs:  # ADV-R9-04: one verdict per id, not per mention
                    continue
                seen_cvs.add(cv)
                if cv in gap_ids:
                    continue
                closed, evidenced = _cv_discharged_in_run(cv)
                if closed and evidenced:
                    continue
                if closed and not evidenced:
                    msgs.append("%s marks %s discharged WITHOUT an ev: citation — an unevidenced "
                                "closure is an assertion, and the record stays escrow-demanded "
                                "until it cites the event that closed it (F-51; note a backticked "
                                "or fenced ev: is a MENTION and does not satisfy this, PF-a)"
                                % (src_rel, cv))
                    continue
                msgs.append("%s records %s but %s has no ROW with that id — an obligation "
                            "living only in an archivable run (escrow, FORMATS §12; a mention "
                            "in another row's prose is not a row; a record discharged in-run "
                            "carries 'discharged: <date> ev:…' in its block, F-51)"
                            % (src_rel, cv, F["gap_row"]["file"]))
        # CV id policy (OBL-PKG-13): inside its own run's report the shorthand
        # CV-<nn> is legal and resolves to the run's full id — the durable
        # registry requires the FULL form. Real reports use the short form
        # (frisbii's CV-01..05 were invisible to the long regex, so the escrow
        # was vacuous for exactly the records it exists to catch).
        long_spans = [m.span() for m in re.finditer(cv_pat.pattern, text)]
        for m in re.finditer(cv_short.pattern, text):
            if any(s <= m.start() < e for s, e in long_spans):
                continue
            nn = m.group(0).split("-")[-1]
            want = re.compile("^CV-%s-(?:U[1-9][0-9]*-)?%s$" % (re.escape(this_run), nn))
            if not any(want.match(g) for g in gap_ids):
                msgs.append("%s uses shorthand %s but %s has no full-form row "
                            "CV-%s-[U<n>-]%s — the short form is run-local; the registry "
                            "keeps the id that outlives the run (OBL-PKG-13)"
                            % (rr_rel, m.group(0), F["gap_row"]["file"], this_run, nn))
        sv = F["status_vocab"]
        # prodsim/F-87b (v0.7.4): DEFERRED discovery over RAW text parsed a
        # fenced block of pasted `grep -n` output as table rows — the
        # line-number prefix displaced every cell and a REAL deferral was
        # reported under the phantom id `32:`, which the registry cannot hold
        # and the reader dismissed as noise. A false id on a true finding is
        # worse than a false finding. Discovery STAYS on raw text (ADV-R11-03:
        # a status table inside a fence is still an obligation — reading
        # fence-stripped text opened an escape v0.7.3 did not have); what
        # changes is that a row whose first cell is not ID-SHAPED is garbage,
        # not a deferral, and is skipped by shape. Each finding names the
        # file it was read from (F-87d).
        id_shapes = [re.compile(F["ids"][k].strip("^$")) for k in F["ids"] if not k.startswith("$")]
        id_shapes.append(re.compile(_req_id_pattern().strip("^$")))
        id_shapes.append(re.compile(r"[A-Z][A-Z0-9]*-[A-Za-z0-9._-]+"))
        def _id_shaped(rid):
            return any(p.fullmatch(rid) for p in id_shapes)
        for src_rel, src_text in named_texts:
          for kind, cells, colmap, _hdr in _table_scan(src_text.splitlines()):
            # OBL-PKG-20 (audit §5.2): the walk read status POSITIONALLY
            # (cells[1]) — the status-by-header rule OBL-PKG-13 was discharged
            # on reached gate-3 but not the escrow's own walk, so a DEFERRED
            # in any other column retired silently with the archived run.
            # Same convention as gate-3: a named Status column is the claim
            # position; a table without one is checked in full.
            status_cells = cells
            if colmap is not None:
                idx = next((colmap[c.lower()] for c in sv["status_columns"]
                            if c.lower() in colmap), None)
                if idx is not None:
                    status_cells = [cells[idx]] if idx < len(cells) else []
            if any(c.strip().upper().startswith("DEFERRED") for c in status_cells):
                rid = cells[0].strip().strip("`") if cells else ""
                if rid and not _id_shaped(rid):
                    continue   # F-87b: a grep prefix, a heading cell — not an item
                # A deferral's durable home is an OPEN registry row REFERENCING
                # the task (a task id cannot itself be a row id) — parsed rows,
                # not raw text, so a mention outside any row satisfies nothing.
                if rid and not any(rid in t for t in open_row_texts):
                    msgs.append("%s defers %s and no OPEN row in %s references it "
                                "(escrow, FORMATS §12)" % (src_rel, rid, F["gap_row"]["file"]))
        # Escrow third class (verifier F8): an audit-trigger HIT recorded in a
        # RUN-REPORT is an obligation — the audit it schedules must have a
        # durable row, or the hit retires with the archived run.
        sec = at_sec.search(sec_text)   # ADV-R10-03: fenced '#' is not a heading
        if sec:
            for am in at_row.finditer(sec.group(1)):
                at_id, val = am.group(1), int(am.group(2))
                spec = F["audit_triggers"].get(at_id)
                if not isinstance(spec, dict) or "threshold" not in spec:
                    continue
                hit = val > spec["threshold"] if spec["comparator"] == ">"                     else val >= spec["threshold"]
                if hit and not any(re.search(r"\b%s\b" % at_id, t) for t in open_row_texts):
                    msgs.append("%s records %s = %d (%s %s threshold %s) — a trigger hit is an "
                                "owed audit; it needs an OPEN %s row naming %s, or the "
                                "obligation retires with the archived run (F8, escrow third "
                                "class)" % (rr_rel, at_id, val, spec["comparator"],
                                            "over" if hit else "under", spec["threshold"],
                                            F["gap_row"]["file"], at_id))
    if run_id is not None and runs_walked == 0 and os.path.isdir(escrow_root):
        msgs.append("--run %s walked 0 runs — no %s and no reports/*-verify.md under it; "
                    "an escrow that judged nothing is not a pass (ADV-R9-06)"
                    % (run_id, rr_name))
    notes = _subject_note("GATE-7", runs_walked) + notes_extra
    for d in verify_only_dirs:
        notes.append("%s has verify reports but no %s — the escrow cannot judge it "
                     "(mid-flight, or a run that died after verify?); name it with "
                     "--run to force judgment (ADV-R9-06)" % (d, rr_name))
    return (len(msgs) == 0), msgs + notes


# --------------------------------------------------------------------------
# GATE-8 — plan structural lint
# --------------------------------------------------------------------------
def _table_scan(lines):
    """OBL-PKG-20 (engine round 6, audit A4): ONE table-walking discipline.
    Yields (kind, cells, colmap) per pipe-line: kind is 'header' before a
    separator, 'row' after one; colmap maps lowercase header text -> index
    once a header+separator was seen, else None (a headerless table). Table
    state resets at every non-pipe line. Consumers that hand-rolled this walk
    re-imported the F-13/F-18/F-32/F-41/F-44 defect family one instance at a
    time — the escrow walk and the plan task-table walk read through this now;
    migrating the remaining consumers is the row's open half."""
    header, colmap = None, None
    for ln in lines:
        if ln.count("|") < 2:
            header, colmap = None, None
            continue
        cells = _cells(ln)
        if _is_separator(ln):
            if header is not None:
                colmap = {h.strip().lower(): i for i, h in enumerate(header)}
            continue
        if colmap is not None:
            yield "row", cells, colmap, header
        else:
            header = cells
            yield "header", cells, None, None


def _table_column(header_cells, name):
    for i, h in enumerate(header_cells):
        if h.strip().lower() == name.lower():
            return i
    return None


def _parse_plan(path):
    txt = read(path)
    ps = F["plan_schema"]
    plan = {"spec": None, "units": [], "coverage": {}, "sections": [], "raw": txt}
    m = re.search(ps["spec_header"], txt, re.M)
    if m:
        plan["spec"] = m.group(1)
    for sec in ps["required_sections"]:
        if re.search(fill(ps["section_heading"], name=re.escape(sec)), txt, re.M):
            plan["sections"].append(sec)

    blocks = re.split(ps["unit_heading"], txt, flags=re.M)
    if len(blocks) > 1:
        it = iter(blocks[1:])
        for uid, _title, body in zip(it, it, it):
            body = re.split(ps["unit_body_end"], body, maxsplit=1, flags=re.M)[0]
            u = {"id": uid, "owns": [], "tasks": [], "fields": {}}
            om = re.search(fill(ps["list_field"], name="owns"), body, re.M)
            if om:
                u["owns"] = [l.strip().lstrip("-").strip().strip("`")
                             for l in om.group(1).split("\n") if l.strip()]
            u["fields"]["owns"] = u["owns"] or None
            im = re.search(fill(ps["list_field"], name="inputs"), body, re.M)
            u["inputs"] = [l.strip().lstrip("-").strip().strip("`")
                           for l in im.group(1).split("\n") if l.strip()] if im else []
            for f, spec in ps["unit_fields"].items():
                if f == "owns":
                    continue
                fm2 = re.search(fill(ps["scalar_field"], name=re.escape(f)), body, re.M)
                if fm2:
                    u["fields"][f] = fm2.group(1).strip()
                elif re.search(fill(ps["list_field"], name=re.escape(f)), body, re.M):
                    u["fields"][f] = "(list)"
                else:
                    u["fields"][f] = None

            u["missing_columns"] = []
            u["nv_header_seen"] = False
            seen_headers = []
            for kind, cells, colmap, header in _table_scan(body.split("\n")):
                # OBL-PKG-20 / audit §5.4: a row is a task row because it sits
                # in a table whose header names a Task column — NOT because a
                # well-formed task id happens to appear on the line. Admission
                # by grammar meant a row whose id the grammar cannot read was
                # not "an invalid task", it was invisible: a bare or mangled
                # id in a unit with valid siblings escaped every task rule.
                if kind == "row":
                    task_col = _table_column(header, ps["task_column"])
                    if task_col is None:
                        # not a task table (coverage matrix etc.): a full task
                        # id on the line keeps the legacy grammar admission
                        if not re.search(F["ids"]["task"].strip("^$"), "|".join(cells)):
                            continue
                        u["tasks"].append({"id": cells[0] if cells else "",
                                           "verify": cells[2] if len(cells) > 2 else "",
                                           "nonvac": "", "cells_n": len(cells),
                                           "header_n": len(header), "header_seen": False})
                        continue
                    verify_col = _table_column(header, ps["verify_column"])
                    nv_col = _table_column(header, ps.get("non_vacuity_column") or "")
                    if header not in seen_headers:
                        seen_headers.append(header)
                        u["nv_header_seen"] = u["nv_header_seen"] or nv_col is not None
                        u["missing_columns"] = [c for c in ps["task_table_columns"]
                                                if _table_column(header, c) is None]
                    tid = cells[task_col] if task_col < len(cells) \
                        else (cells[0] if cells else "")
                    ver = cells[verify_col] if verify_col is not None and verify_col < len(cells) \
                        else (cells[2] if len(cells) > 2 else "")
                    nv = cells[nv_col] if nv_col is not None and nv_col < len(cells) else ""
                    u["tasks"].append({"id": tid, "verify": ver, "nonvac": nv,
                                       "cells_n": len(cells),
                                       "header_n": len(header),
                                       "header_seen": verify_col is not None})
                elif re.search(F["ids"]["task"].strip("^$"), "|".join(cells)):
                    # separator-less table: legacy grammar admission unchanged
                    u["tasks"].append({"id": cells[0] if cells else "",
                                       "verify": cells[2] if len(cells) > 2 else "",
                                       "nonvac": "", "cells_n": len(cells),
                                       "header_n": None, "header_seen": False})
            plan["units"].append(u)

    cm = re.search(fill(ps["section_heading"], name=re.escape(ps["required_sections"][-1]))
                   + r"([\s\S]*?)(?=^##\s|\Z)", txt, re.M)
    if cm:
        ac_col, task_col, header = None, None, None
        for line in cm.group(1).split("\n"):
            if line.count("|") < 2:
                continue
            cells = _cells(line)
            if _is_separator(line):
                if header:
                    ac_col = _table_column(header, ps["coverage_matrix_columns"][0])
                    task_col = _table_column(header, ps["coverage_matrix_columns"][1])
                continue
            a = cells[ac_col] if ac_col is not None and ac_col < len(cells) else (
                cells[0] if cells else "")
            t = cells[task_col] if task_col is not None and task_col < len(cells) else (
                cells[1] if len(cells) > 1 else "")
            if a and re.match(F["ids"]["acceptance_criterion"], a):
                plan["coverage"][a] = t
            header = cells
    return plan


def _static_prefix(glob):
    out = []
    for part in glob.split("/"):
        if any(ch in part for ch in "*?["):
            break
        out.append(part)
    return "/".join(out)


def _spec_acs(spec_txt):
    acs = set()
    for line in spec_txt.split("\n"):
        if line.count("|") >= 2 and not _is_separator(line):
            c = _cells(line)
            if c and re.match(F["ids"]["acceptance_criterion"], c[0]):
                acs.add(c[0])
    return acs


def gate_8(run_id):
    ps = F["plan_schema"]
    if not run_id:
        return False, ["gate-8 needs --run <run-id>"]
    rel = fill(ps["file"], run_id=run_id)
    path = rp(rel)
    if not os.path.isfile(path):
        return False, ["no PLAN.md at %s" % rel]
    plan = _parse_plan(path)
    msgs = []
    for sec in ps["required_sections"]:
        if sec not in plan["sections"]:
            msgs.append("PLAN.md has no '## %s' section (plan_schema.required_sections)" % sec)
    if not plan["units"]:
        msgs.append("PLAN.md declares no units, or unit headings do not match the schema "
                    "(### U<n> — <title>)")
    # F-13 (v0.6.3): bare task ids parsed to ZERO tasks and both task rules held
    # vacuously — 29 verify commands the gate never read, while ownership and
    # coverage kept grading and the gate looked healthy. The AC set already had
    # this guard; the task list now has the same one.
    if plan["units"] and sum(len(u["tasks"]) for u in plan["units"]) == 0:
        msgs.append("plan declares %d unit(s) and ZERO parseable task rows — task ids must be "
                    "fully qualified (%s); a task list the schema cannot read is not a task "
                    "list with nothing to check (F-13)"
                    % (len(plan["units"]), F["ids"]["task"]))
    # F-28 (v0.6.3): the unit section is the only channel to an executor, so
    # normative language outside every unit and outside the Contracts block
    # binds nobody — a credential-safety rule was gated, committed, and inert.
    npat = ps.get("normative_pattern")
    if npat:
        # platform/F-70 (v0.7.3): the walk started at line 1, so the plan's
        # own schema HEADER FIELDS were read as normative prose — a signed
        # plan whose header value contained a normative word failed its own
        # gate for the life of the plan, unsatisfiably (a header field cannot
        # move into a unit section without breaking the schema). ADV-R9-05
        # (R9): the first cut skipped the WHOLE preamble, which reintroduced
        # F-28 for normative prose paragraphs written above the first ## —
        # and ADV-R10-05 (R9b) showed shape alone is a costume: any 'word:'
        # prefix hid a rule. The exemption is by NAME — the schema's
        # preamble_fields list — plus the title line and blanks. A prose
        # sentence, or a rule wearing an unlisted key, is scanned.
        in_unit, in_contracts, in_body = False, False, False
        header_field = re.compile(r"^(?:%s):" % "|".join(
            re.escape(k) for k in ps.get("preamble_fields", ["spec"])))
        # platform/F-79 (v0.7.4): a named field's VALUE may wrap — the
        # exemption carries across continuation lines until a blank line,
        # another named key, a title or a heading. A rule wearing an unlisted
        # key still never opens an exempt region (ADV-R10-05's guarantee),
        # and a bare prose paragraph is not a continuation of anything.
        in_field = False
        for ln_no, ln in enumerate(read(path).split("\n"), 1):
            if not in_body:
                if re.match(r"^##", ln):
                    in_body = True
                elif not ln.strip() or ln.startswith("# "):
                    in_field = False
                    continue
                elif header_field.match(ln):
                    in_field = True
                    continue
                elif re.match(r"^[a-z][a-z0-9_-]*:", ln):
                    in_field = False   # an UNLISTED key ends any exemption
                elif in_field and re.match(r"^\s+\S", ln):
                    continue           # INDENTED continuation of a named field's value
                else:
                    in_field = False   # an unindented line ends the field (ADV-R11-06)
                # a non-header preamble line falls through and is scanned
            if re.match(ps["unit_heading"], ln):
                in_unit, in_contracts = True, False
                continue
            if re.match(r"^##\s", ln):
                in_unit = False
                in_contracts = bool(re.match(
                    fill(ps["section_heading"], name=re.escape(ps["contracts_section"])), ln))
                continue
            if in_unit or in_contracts or ln.lstrip().startswith("#"):
                continue
            if re.search(npat, ln):
                extra = ""
                if not in_body and re.match(r"^[a-z][a-z0-9_-]*:", ln):
                    extra = ("; if this is a descriptive schema header field, not a rule, its "
                             "key belongs in plan_schema.preamble_fields — a PACKAGE change: "
                             "file it upstream rather than editing formats.json, which the "
                             "next upgrade overwrites (ADV-R10-05, DEV-R11-14)")
                msgs.append("%s:%d normative language outside a unit section or the "
                            "'## %s' block reaches NO executor manifest (F-28): '%s' — move "
                            "the rule where its audience will be handed it%s"
                            % (os.path.relpath(path, ROOT), ln_no, ps["contracts_section"],
                               ln.strip()[:70], extra))
    files = tracked_files()

    # (a) ownership: no overlap, no ORCH-owned file claimed
    expanded = {}
    for u in plan["units"]:
        if not u["owns"]:
            msgs.append("%s declares no owns: path list" % u["id"])
        s = set()
        for g in u["owns"]:
            for f in files:
                if fnmatch.fnmatch(f, g) or f.startswith(g.rstrip("*").rstrip("/") + "/"):
                    s.add(f)
            for orch in ps["orch_owned_paths"]:
                if fnmatch.fnmatch(g, orch) or fnmatch.fnmatch(orch, g) or \
                        _static_prefix(g) and fnmatch.fnmatch(orch, g + "*"):
                    msgs.append("%s claims ORCH-owned path '%s' (matches %s)"
                                % (u["id"], g, orch))
        expanded[u["id"]] = (s, u["owns"])
    ids = [u["id"] for u in plan["units"]]
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            a, ga = expanded[ids[i]]
            b, gb = expanded[ids[j]]
            inter = a & b
            if inter:
                msgs.append("%s and %s both own %d existing file(s): %s"
                            % (ids[i], ids[j], len(inter), ", ".join(sorted(inter)[:3])))
            for x in ga:
                for y in gb:
                    if x == y:
                        msgs.append("%s and %s declare the identical path '%s'"
                                    % (ids[i], ids[j], x))
                    else:
                        px, py = _static_prefix(x), _static_prefix(y)
                        if px and py and (px == py or px.startswith(py + "/")
                                          or py.startswith(px + "/")):
                            msgs.append("%s '%s' and %s '%s' have nested path prefixes "
                                        "— ownership may overlap" % (ids[i], x, ids[j], y))

    # F-58 (v0.7.2): declared cross-unit inputs must be DELIVERABLE. Under the
    # branch model a wave-N unit's tree carries only waves <N, so an input is
    # reachable iff some OTHER unit at a STRICTLY LOWER wave owns it. A plan
    # that consolidates work into one unit and consumes it from a same-wave
    # peer passed eight revisions and seven adversarial reviews before an
    # executor would have met a path that does not exist — the check is a
    # plan-time lint precisely so the cost lands at G2, not mid-wave.
    def _wave(u):
        try:
            return int(u["fields"].get("wave") or 0)
        except (TypeError, ValueError):
            return 0
    for u in plan["units"]:
        for inp in u.get("inputs") or []:
            producers = [v for v in plan["units"] if v["id"] != u["id"]
                         and any(fnmatch.fnmatch(inp, o) or inp == o
                                 or (_static_prefix(o) and
                                     inp.startswith(_static_prefix(o) + "/"))
                                 for o in v["owns"])]
            if not producers:
                msgs.append("%s declares input '%s' that NO other unit owns — the input has "
                            "no producer, so the executor meets a missing path and the good "
                            "outcome is only a park (F-58)" % (u["id"], inp))
            elif not any(_wave(v) < _wave(u) for v in producers):
                msgs.append("%s (wave %d) declares input '%s' produced by %s (wave %d) — not "
                            "a STRICTLY LOWER wave, so the input cannot be on the consumer's "
                            "branch under the wave-cut model (F-58: the same-wave-producer "
                            "case adversarial review missed twice)"
                            % (u["id"], _wave(u), inp, producers[0]["id"],
                               _wave(producers[0])))

    # (c) every auto task has a verify command, in the column the header names
    empty = set(x.strip().lower() for x in ps["task_verify_empty"])
    for u in plan["units"]:
        for c in u.get("missing_columns", []):
            msgs.append("%s task table has no '%s' column (plan_schema.task_table_columns)"
                        % (u["id"], c))
        for g in u["owns"]:
            if fnmatch.fnmatch(g, fill(F["runs_layout"]["reports"], run_id="*") + "*") and \
                    not any(fnmatch.fnmatch(g, w) for w in ps["agent_writable_paths"]):
                msgs.append("%s owns '%s' under reports/ but it is not an AGENT-writable path "
                            "(%s) — FORMATS §9" % (u["id"], g, ", ".join(ps["agent_writable_paths"])))
        for t in u["tasks"]:
            # F-39 fix 3 (v0.7.1): a row admitted with an id the trailer
            # grammar cannot express is a task that can never be committed —
            # refused at G2 (an edit) instead of at the first commit (a wave).
            tid = (t.get("id") or "").strip().strip("`")
            if tid and t.get("header_seen") is not False and \
                    not re.match(F["ids"]["task"], tid):
                if re.search(r"\.T", tid):
                    msgs.append("%s task id %r cannot be expressed as a [T:] trailer — the "
                                "legal form is <run-id>.T<nn> with an optional letter suffix "
                                "(ids.task); signed against this id, the task is uncommittable "
                                "(F-39)" % (u["id"], tid))
                else:
                    # OBL-PKG-20 / audit §5.4: with admission by table
                    # membership, an unreadable id is an INVALID task, loudly
                    # — no longer an invisible row whose verify nothing reads.
                    msgs.append("%s task id %r is not a fully-qualified task id (ids.task: "
                                "<run-id>.T<nn> with an optional letter suffix) — the row is "
                                "real work no [T:] trailer can commit (F-13/F-39)"
                                % (u["id"], tid))
            # F-18 (v0.6.4): a row whose cell count disagrees with its header
            # parses into a DIFFERENT table than the one written, and every
            # later message then blames the wrong cell. Name the real cause.
            if t.get("header_n") and t["cells_n"] != t["header_n"]:
                msgs.append("%s task %s: %d columns expected, %d found — an unescaped '|' in a "
                            "cell (a shell pipe?). Escape it as \\| or route the command "
                            "through a file (F-18)"
                            % (u["id"], t["id"], t["header_n"], t["cells_n"]))
            if not ps.get("task_verify_required"):
                break
            if not t["header_seen"]:
                msgs.append("%s task %s sits in a table with no '%s' column header — GATE-8 "
                            "cannot tell which cell is the verify command"
                            % (u["id"], t["id"], ps["verify_column"]))
                continue
            v = (t["verify"] or "").strip()
            if v.lower() in empty:
                msgs.append("%s task %s has no verify command" % (u["id"], t["id"]))
            elif v.startswith(ps["task_verify_exempt_marker"]):
                if ps["manual_owner_marker"] not in v:
                    msgs.append("%s task %s is MANUAL but names no %s"
                                % (u["id"], t["id"], ps["manual_owner_marker"]))
        for f, spec in ps["unit_fields"].items():
            if spec["required"] and not u["fields"].get(f):
                msgs.append("%s is missing required field '%s:'" % (u["id"], f))
            if spec.get("kind") == "enum" and u["fields"].get(f) and \
                    u["fields"][f] not in spec["values"]:
                msgs.append("%s field '%s: %s' is not one of %s"
                            % (u["id"], f, u["fields"][f], spec["values"]))

    # (b) coverage matrix present and total
    if not plan["coverage"]:
        msgs.append("no Coverage matrix section, or no AC rows in it")
    spec_path = plan["spec"]
    if not spec_path:
        msgs.append("PLAN.md header has no 'spec:' line — cannot check coverage totality")
    else:
        spec_txt = read(rp(spec_path))
        if not spec_txt:
            msgs.append("PLAN.md spec: points at %s, which does not exist" % spec_path)
        else:
            acs = _spec_acs(spec_txt)
            if not acs and ps.get("spec_must_declare_acs"):
                msgs.append("%s declares no parseable AC rows — 'every AC mapped' would be "
                            "vacuously true. State the ACs as table rows (%s | ...)"
                            % (spec_path, F["ids"]["acceptance_criterion"]))
            unmapped = sorted(acs - set(plan["coverage"].keys())) \
                if ps.get("coverage_must_be_total") else []
            if unmapped:
                msgs.append("coverage matrix is not total: %d AC(s) unmapped: %s"
                            % (len(unmapped), ", ".join(unmapped)))
            for ac, tasks in plan["coverage"].items():
                if tasks.strip().lower() in empty:
                    msgs.append("coverage matrix maps %s to no task" % ac)
    return (len(msgs) == 0), msgs + _subject_note("GATE-8", len(plan["units"]))


# --------------------------------------------------------------------------
# GATE-9 — gate-closure record
# --------------------------------------------------------------------------
def _governing_artifact(gate, run_id, spec):
    jm = F["jira_mapping"]
    kind = jm["closing_gates"].get(gate)
    if kind == "plan" and run_id:
        return fill(F["plan_schema"]["file"], run_id=run_id)
    if kind == "spec":
        if spec:
            return spec
        if run_id:
            # F-15 (v0.6.3): with --run and no --spec this fell through to a
            # sorted glob and graded whichever spec sorts LAST — a different
            # run's spec, chosen alphabetically. Resolve through the named
            # run's plan the way GATE-2's _governing_sources does, and refuse
            # rather than guess when that fails (the G-11 principle).
            plan_rel = fill(F["plan_schema"]["file"], run_id=run_id)
            if os.path.isfile(rp(plan_rel)):
                m = re.search(F["plan_schema"]["spec_header"], read(rp(plan_rel)), re.M)
                if m:
                    if gate == "G4":
                        # prodsim/F-76 (v0.7.3): the plan's spec: header names
                        # v<N> — the spec the plan was planned AGAINST — while
                        # P4 produces v<N+1> and the [PO] close line puts the
                        # G4 signature THERE. The resolver and the playbook
                        # disagreed by exactly one version, for every run, by
                        # construction. Resolve EXACTLY v(N+1) when it exists
                        # and is not a blocked draft (ADV-5: never 'highest' —
                        # an abandoned v3, or a legacy tokenless record in the
                        # wrong file, must not close G4; that is F-15's own
                        # bug one door over). Stem split at the RIGHTMOST
                        # -v<N>.md, numeric compare.
                        sm = re.match(r"^(.*)-v([0-9]+)\.md$", m.group(1))
                        if sm:
                            nxt = "%s-v%d.md" % (sm.group(1), int(sm.group(2)) + 1)
                            if os.path.isfile(rp(nxt)):
                                head2 = "\n".join(read(rp(nxt)).split("\n")[:jm["header_lines"]])
                                if not re.search(r"^status:\s*blocked-draft", head2, re.M):
                                    return nxt
                    return m.group(1)
            return None
        specs = matching_docs([P["specs_glob"]])
        return specs[-1] if specs else None
    return None


def gate_9(artifacts=None, gate=None, run_id=None, spec=None):
    jm = F["jira_mapping"]
    pat = jm["signoff_record"]
    msgs = []

    if gate:
        if gate not in jm["closing_gates"]:
            return False, ["%s is not a closing gate (%s)"
                           % (gate, ", ".join(sorted(jm["closing_gates"])))]
        a = _governing_artifact(gate, run_id, spec)
        if not a:
            if run_id:
                return False, ["%s cannot resolve its governing %s from run %s (no plan, or no "
                               "spec: header) — refusing to guess from a glob; pass --spec "
                               "(F-15)" % (gate, jm["closing_gates"][gate], run_id)]
            return False, ["%s closes against a %s artifact, and none was found — pass --spec or "
                           "--run" % (gate, jm["closing_gates"][gate])]
        head = "\n".join(read(rp(a)).split("\n")[:jm["header_lines"]])
        m = re.search(pat, head, re.M)
        if not m:
            hint = ""
            if gate == "G4":
                # ADV-R9-10 (v0.7.3 R9): the F-76 --spec hint fired only on the
                # token-mismatch branch — the pre-0.7.3 layout (signed record
                # living in v<N>, v<N+1> a draft) routes HERE, and the refusal
                # left the operator with a true statement and no route.
                hint = ("; note G4 resolved the highest successor spec — if the signed "
                        "record lives in an earlier version, pass --spec with the file "
                        "that carries it (prodsim/F-76, ADV-R9-10)")
            return False, ["%s cannot close: %s has no 'signed: [G<n>] <date> ev:jira{KEY-nn}' "
                           "record in its header%s" % (gate, a, hint)]
        # F-15 (v0.6.3): the record used to carry no gate token, so any gate's
        # sign-off satisfied any gate — a superseded spec's G1 record closed
        # G4. A token, when present, must match; legacy tokenless records
        # remain valid.
        if m.group(1) and m.group(1) != gate:
            hint = ""
            if gate == "G4":
                # prodsim/F-76 fix 4: the refusal names the likely cause — the
                # reader was debugging a true statement about the wrong file.
                hint = ("; note G4 closes against the RECONCILED spec v<N+1>, which the plan "
                        "does not name — if this resolved to v<N>, pass --spec with the "
                        "reconciled spec (prodsim/F-76)")
            return False, ["%s cannot close against %s: its record signs %s, not %s — a sign-off "
                           "attests the gate it names (F-15)%s" % (gate, a, m.group(1), gate, hint)]
        msgs.append("%s closure record present in %s%s"
                    % (gate, a, " (gate token %s)" % m.group(1) if m.group(1) else
                       " (legacy tokenless record — new sign-offs carry the gate: "
                       "'signed: %s <date> ev:jira{...}')" % gate))
        artifacts = artifacts or [a]

    if artifacts is None:
        artifacts = matching_docs([P["specs_glob"]])
        artifacts += _untracked_matching((fill(F["plan_schema"]["file"], run_id="*"),))
        artifacts = sorted(set(artifacts))
    for a in artifacts:
        txt = read(rp(a))
        if not txt:
            continue
        head = "\n".join(txt.split("\n")[:jm["header_lines"]])
        claims_signed = re.search(jm["signed_status_token"], head, re.M)
        has_record = re.search(pat, head, re.M)
        if claims_signed and not has_record:
            msgs.append("%s claims SIGNED but has no 'signed: <date> ev:jira{KEY-nn}' record" % a)
        if has_record and not claims_signed:
            msgs.append("%s carries a signed: record but its status is not SIGNED" % a)
        # F-29 (v0.6.3): real runs amend signed artifacts — legitimately, by PO
        # decision — and nothing recorded that the text changed after the
        # signature. A signed artifact modified after the commit that
        # introduced its record must carry an AM-<nn> amendment record, so a
        # PO signing at the next gate sees how much postdates the signature.
        if has_record:
            intro = git("log", "--format=%H", "-1", "-S", has_record.group(0), "--", a).strip()
            after = git("log", "--format=%H", "%s..HEAD" % intro, "--", a).strip() if intro else ""
            dirty = intro and bool(git("diff", "--name-only", "HEAD", "--", a).strip())
            if after or dirty:
                # platform/F-71 (v0.7.4): the old test — ANY AM-<nn> anywhere
                # in the document — was a one-time toll: the first amendment a
                # document ever received satisfied it permanently, and a spec
                # with un-propagated PO rulings was absent from the failure
                # list while nine others were named. The amendment record is
                # tied to the MODIFICATION: the AM count must have GROWN since
                # the commit that introduced the signature (count-and-compare,
                # F-71's fix 1 — no format change, mechanically checkable).
                am_re = re.compile(F["ids"]["amendment"].strip("^$"))
                # the comparison base is the state BEFORE the latest
                # modification — comparing against the signature commit would
                # itself be a one-time toll one step later (one amendment
                # licensing every subsequent silent change; F-71's own
                # non-vacuity case: signed + one amendment + modified again
                # with no new amendment must FAIL).
                if dirty:
                    prev_txt = git("show", "HEAD:%s" % a)
                else:
                    last = after.split("\n")[0]
                    prev_txt = git("show", "%s~1:%s" % (last, a))
                    if not prev_txt.strip() and intro:
                        prev_txt = git("show", "%s:%s" % (intro, a))
                base_ams = len(set(am_re.findall(prev_txt)))
                now_ams = len(set(am_re.findall(txt)))
                if now_ams <= base_ams:
                    msgs.append("%s was modified after the commit that introduced its signed: "
                                "record and its AM-<nn> count did not grow across the latest "
                                "modification (%d before this change, %d after) — an amendment "
                                "records THIS modification, not the document's history: add an "
                                "`AM-%02d` block naming what changed and why (FORMATS §1); the "
                                "signature line and the text it signs are otherwise drifting "
                                "apart with no trace (F-29, platform/F-71)"
                                % (a, base_ams, now_ams, now_ams + 1))
    bad = [m for m in msgs if "claims SIGNED" in m or "not SIGNED" in m or "F-29" in m]
    return (len(bad) == 0), msgs


# --------------------------------------------------------------------------
# GATE-10 — divergence diff produced, evidenced and fully classified
# --------------------------------------------------------------------------
def _expected_pairs():
    """platform/F-73 (v0.7.4): FORMATS §10 assumed every tracker workflow has
    a Deferred/Backlog status; a workflow without one made DEFERRED
    permanently unrepresentable and charged a classification round at every
    gate that deferred scope — and the only green path was relabeling the
    work, the exact anti-pattern the divergence diff exists to catch. The
    repo names its local equivalents in wow.config.json
    jira.status_conventions — either `<status>_equivalent: "<Jira status>"`
    (the shape one pilot adopted) or `equivalents: {"DEFERRED": ["Intake"]}`
    — and the engine merges them into the §10 table."""
    jm = F["jira_mapping"]
    expected = {k: list(v) for k, v in jm["expected"].items()}
    conv = (cfg().get("jira") or {}).get("status_conventions") or {}
    for k, v in conv.items():
        if k.endswith("_equivalent") and isinstance(v, str):
            expected.setdefault(k[:-len("_equivalent")].upper(), []).append(v)
    for k, v in (conv.get("equivalents") or {}).items():
        vals = [v] if isinstance(v, str) else list(v)
        expected.setdefault(k.upper(), []).extend(vals)
    return expected


def _walk_items(run_id):
    """prodsim/F-86: every RUN-REPORT item P4 step 2 must classify — rows whose
    status is FAILED/BLOCKED/PARKED (by header-resolved status column, whole
    row otherwise) plus every plan-defect id — read on fence-stripped text."""
    rr = rp(fill(F["report_row_schema"]["file"], run_id=run_id))
    if not os.path.isfile(rr):
        return None
    txt = _strip_fenced_blocks(read(rr))
    sv = F["status_vocab"]
    items = []
    for kind, cells, colmap, _hdr in _table_scan(txt.splitlines()):
        if kind != "row" or not cells:
            continue
        status_cells = cells
        if colmap is not None:
            idx = next((colmap[c.lower()] for c in sv["status_columns"] if c.lower() in colmap), None)
            if idx is not None:
                status_cells = [cells[idx]] if idx < len(cells) else []
        if any(c.strip().upper().startswith(("FAILED", "BLOCKED", "PARKED")) for c in status_cells):
            rid = cells[0].strip().strip("`")
            if rid and rid not in items:
                items.append(rid)
    for m in re.finditer(F["ids"]["plan_defect"].strip("^$"), txt):
        if m.group(0) not in items:
            items.append(m.group(0))
    return items


def _walk_check(run_id):
    """prodsim/F-86 (v0.7.4): P4's walk had no artifact and no batching rule,
    so a mid-walk finding's only move was 'raise it now' — two items out of
    twenty consumed a context window before the walk was enumerated. The
    walk artifact is P4's park: one row per item with its classification;
    G4 close is refused while an item the RUN-REPORT carries is absent."""
    rl = F["runs_layout"]
    items = _walk_items(run_id)
    if not items:
        return []
    wp = rp(fill(rl["walk"], run_id=run_id))
    wrel = fill(rl["walk"], run_id=run_id)
    if not os.path.isfile(wp):
        return ["G4 close: %s carries %d failed/blocked/parked/defect item(s) (%s%s) and there "
                "is no walk artifact %s — P4 step 2's walk is enumerated there, one row per "
                "item with its classification, and findings surfaced mid-walk land there to be "
                "disposed of TOGETHER at the gate, not serially (prodsim/F-86)"
                % (fill(F["report_row_schema"]["file"], run_id=run_id), len(items),
                   ", ".join(items[:4]), " …" if len(items) > 4 else "", wrel)]
    wtxt = _strip_fenced_blocks(read(wp))
    # a walk row's FIRST cell is the RUN-REPORT row's first cell (the item id,
    # DEF-plan-<nn> for defects); word-bounded, so U1 never satisfies U10.
    firsts = [(_cells(ln)[0].strip().strip("`") if _cells(ln) else "")
              for ln in wtxt.splitlines() if ln.count("|") >= 2 and not _is_separator(ln)]
    missing = [i for i in items if not any(re.fullmatch(re.escape(i), c) for c in firsts)]
    if missing:
        return ["G4 close: %d of %d walk item(s) absent from %s: %s%s — every failed/blocked/"
                "parked/defect item in the RUN-REPORT is a walk row whose FIRST cell is that "
                "item's id (FORMATS §4 walk row: `| <item id> | <classification> | <disposition> |`) "
                "before the gate closes (prodsim/F-86)"
                % (len(missing), len(items), wrel, ", ".join(missing[:4]),
                   " …" if len(missing) > 4 else "")]
    return []


def gate_10(run_id, gate):
    jm = F["jira_mapping"]
    if not run_id:
        return False, ["gate-10 needs --run <run-id>"]
    rel = fill(jm["divergence_record"], run_id=run_id, gate=gate)
    p = rp(rel)
    if not os.path.isfile(p):
        return False, ["no divergence record at %s. GATE-10 requires the git-Jira diff at gate "
                       "open; if MCP was unavailable, record the deferral there and in %s"
                       % (rel, fill(jm["offline_deferral"]["record"], run_id=run_id))]
    txt = read(p)
    msgs, unclassified, rows = [], [], 0
    class_col = git_col = jira_col = None
    header, saw_class_table = None, False
    for i, line in enumerate(txt.split("\n"), 1):
        if line.count("|") < 3:
            # F-56 (v0.7.2): a table ends at its first non-pipe line, and the
            # parse state resets WITH it — without the reset, every later
            # pipe-bearing line in the record read as a divergence row: a
            # second table's rows AND its header (reported as a divergence
            # named 'Item'), and an ev:cmd citation whose regex alternation
            # carries pipes. The author's workaround was to write worse
            # evidence, which is the direction a gate must never push.
            class_col = git_col = jira_col = None
            header = None
            continue
        cells = _cells(line)
        if _is_separator(line):
            if header:
                class_col = _table_column(header, jm["classification_column"])
                git_col = _table_column(header, jm["git_column"])
                jira_col = _table_column(header, jm["jira_column"])
                saw_class_table = saw_class_table or class_col is not None
            continue
        if class_col is None:
            header = cells
            continue
        if not cells or not cells[0]:
            continue
        # DEV-R11-07 (R11b): a row recording an expected-consistent pair is NOT
        # a divergence — it used to be noted as one and then counted as an
        # unclassified divergence in the same breath, so the only green path
        # was classifying a non-divergence (the relabeling F-73 set out to end).
        consistent = False
        if git_col is not None and jira_col is not None and \
                git_col < len(cells) and jira_col < len(cells):
            g, j = cells[git_col].strip().upper(), cells[jira_col].strip()
            exp = _expected_pairs()
            if g in exp and j in exp[g]:
                consistent = True
                msgs.append("note: %s:%d records %s/%s, which IS expected-consistent per "
                            "FORMATS §10 (incl. wow.config.json jira.status_conventions) — not "
                            "a divergence; the row needs no classification and may be dropped"
                            % (rel, i, g, j))
        rows += 1
        got = cells[class_col].strip().lower() if class_col < len(cells) else ""
        # an expected-consistent row with an EMPTY classification is not a
        # divergence; a non-vocabulary word in the column is a defect either way
        if got not in jm["classifications"] and not (consistent and got == ""):
            unclassified.append("%s:%d %s" % (rel, i, cells[0]))

    if rows == 0:
        if re.search(jm["no_divergence_statement"], txt, re.M | re.I):
            if jm.get("no_divergence_requires_evidence") and \
                    not re.search(F["evidence"]["any"], txt):
                return False, msgs + ["%s asserts 'no divergences' with no ev: citation of the "
                                      "query that produced it. An empty diff is a claim like any "
                                      "other." % rel]
            return True, msgs + ["%s records no divergences, with evidence" % rel]
        if not saw_class_table:
            return False, msgs + ["%s has no '%s' column — GATE-10 reads the classification from "
                                  "that column, not from anywhere in the row"
                                  % (rel, jm["classification_column"])]
        return False, msgs + ["%s has no divergence rows and no explicit 'no divergences' "
                              "statement" % rel]

    if re.search(jm["offline_deferral"]["claim_marker"], txt, re.I):
        q = rp(fill(jm["offline_deferral"]["record"], run_id=run_id))
        if not re.search(jm["offline_deferral"]["marker"], read(q), re.M | re.I):
            return False, msgs + ["%s reports MCP unavailable but %s carries no open gate-10 item "
                                  "— the deferral is recorded nowhere that will be chased"
                                  % (rel, os.path.relpath(q, ROOT))]
    if unclassified:
        return False, msgs + ["%d divergence(s) unclassified in the %s column (need one of %s): %s"
                              % (len(unclassified), jm["classification_column"],
                                 "/".join(jm["classifications"]), "; ".join(unclassified[:5]))]
    return True, msgs + ["%d divergence(s), all classified" % rows]


# --------------------------------------------------------------------------
# dispatch
# --------------------------------------------------------------------------
def _opt(args, flag):
    if flag in args:
        i = args.index(flag)
        if i + 1 < len(args) and not args[i + 1].startswith("--"):
            return args[i + 1]
    return None


def _list_opt(args, flag):
    if flag not in args:
        return []
    out, i = [], args.index(flag) + 1
    while i < len(args) and not args[i].startswith("--"):
        out.append(args[i])
        i += 1
    return out


def run_gate(name, args):
    if name == "gate-1":
        positional = [a for a in args if not a.startswith("--")]
        if not positional:
            return False, ["gate-1 needs the commit message file (the commit-msg hook passes $1)"]
        return gate_1(positional[0])
    if name == "gate-2":
        return gate_2(run_id=_opt(args, "--run"), spec=_opt(args, "--spec"),
                      close=("--close" in args))
    if name == "gate-3":
        return gate_3(_list_opt(args, "--paths") or None)
    if name == "gate-4":
        return gate_4(run_id=_opt(args, "--run"))
    if name == "gate-5":
        if "--staged" in args:
            return gate_5(staged=True)
        if "--sweep" in args:
            return gate_5(paths=_list_opt(args, "--paths") or None, sweep=True,
                          run_id=_opt(args, "--run"))
        return gate_5(paths=_list_opt(args, "--paths") or None)
    if name == "gate-6":
        return gate_6(area=_opt(args, "--area"), run_id=_opt(args, "--run"),
                      deps=(_list_opt(args, "--deps") or None),
                      probe=("--no-probe" not in args))
    if name == "gate-7":
        return gate_7(p5=("--p5" in args), run_id=_opt(args, "--run"))
    if name == "gate-13":
        return gate_13(run_id=_opt(args, "--run"))
    if name == "gate-14":
        return gate_14(paths=(_list_opt(args, "--paths") or None), staged=("--staged" in args))
    if name == "gate-8":
        return gate_8(_opt(args, "--run"))
    if name == "gate-9":
        return gate_9(_list_opt(args, "--paths") or None, gate=_opt(args, "--gate"),
                      run_id=_opt(args, "--run"), spec=_opt(args, "--spec"))
    if name == "gate-10":
        return gate_10(_opt(args, "--run"), _opt(args, "--gate") or "G2")
    if name == "parity":
        return check_parity()
    if name == "gate-12":
        return gate_12(kind=_opt(args, "--kind"), ref=_opt(args, "--ref"))
    if name == "gate-11":
        paths = staged_files(include_deleted=F["legacy_freeze"]["include_deletions"]) \
            if "--staged" in args else _list_opt(args, "--paths")
        return gate_11(paths)
    return False, ["unknown gate %s" % name]


def _hooks_dir():
    """The directory git ACTUALLY reads: core.hooksPath if set, else the common
    git dir (inherited by every worktree)."""
    hooks_dir = git("config", "--get", "core.hooksPath").strip()
    if hooks_dir:
        return hooks_dir if os.path.isabs(hooks_dir) else rp(hooks_dir)
    common = git("rev-parse", "--git-common-dir").strip() or ".git"
    common = common if os.path.isabs(common) else rp(common)
    return os.path.join(common, "hooks")


def _render_hook(name):
    """DEV-R11-02: the hook body's ONE home is formats.json install.hook_template;
    install.sh renders the same template, so --check's byte comparison holds."""
    I = F["install"]
    return (I["hook_template"].replace("{marker}", I["hook_marker"])
            .replace("{keep}", I["preserved_hook_suffix"])
            .replace("{gate_lines}", "\n".join(I["hook_gate_lines"][name])))


def hooks_install(check_only=False):
    """`gates.sh hooks --install` — the self-heal for a fresh clone (no hooks:
    .git/hooks is untracked) or a clobbered hook (a second installer, prodsim/
    F-77). Same write discipline as install.sh: a foreign hook is chained
    (moved to <name>.pre-wow), a second different foreign hook rotates the
    older chained copy to .pre-wow.<n> (kept, not run), nothing is destroyed."""
    I = F["install"]
    hooks_dir = _hooks_dir()
    keep = I["preserved_hook_suffix"]
    out, changed = [], 0
    for name in I["hooks"]:
        dst = os.path.join(hooks_dir, name)
        body = _render_hook(name)
        cur = read(dst) if os.path.isfile(dst) else None
        if cur is not None and cur.strip() == body.strip():
            out.append("ok       hook %s" % name)
            continue
        if check_only:
            out.append("%s hook %s" % ("MISSING " if cur is None else
                                       ("FOREIGN " if I["hook_marker"] not in cur else "DRIFTED "), name))
            changed += 1
            continue
        os.makedirs(hooks_dir, exist_ok=True)
        if cur is not None and I["hook_marker"] not in cur:
            kept = dst + keep
            if not os.path.exists(kept):
                os.replace(dst, kept); os.chmod(kept, 0o755)
                out.append("kept     hook %s -> %s%s (chained, runs first)" % (name, name, keep))
            elif read(kept) == cur:
                pass
            else:
                n = 1
                while os.path.exists("%s.%d" % (kept, n)):
                    n += 1
                os.replace(kept, "%s.%d" % (kept, n))
                os.replace(dst, kept); os.chmod(kept, 0o755)
                out.append("kept     hook %s -> %s%s (chained, runs first); previous chained hook "
                           "rotated to %s%s.%d (kept, NOT run — merge it into %s%s if it still "
                           "matters)" % (name, name, keep, name, keep, n, name, keep))
        with open(dst, "w") as fh:
            fh.write(body)
        os.chmod(dst, 0o755)
        out.append("wrote    hook %s (%s)" % (name, os.path.relpath(hooks_dir, ROOT)
                                              if hooks_dir.startswith(ROOT) else hooks_dir))
        changed += 1
    return (changed == 0) if check_only else True, out


def check_parity():
    """OBL-PKG-08 / layer-parity rule (GATES-SPEC v0.5.3): the GATES-SPEC table
    and the engine are two declarations of the same set, and this compares them.
    A spec-only row is legal ONLY with a DESIGNED-NOT-IMPLEMENTED marker naming
    an OPEN obligation. Also the version authority (v0.5.5/N2, v0.5.6/D2):
    formats.json's stamp equals the CHANGELOG top entry, and each versioned doc
    header equals the version of the commit that last modified it."""
    msgs = []
    layer_notes = []
    spec_path = None
    for cand_rel in F["parity"]["spec_locations"]:
        if os.path.isfile(rp(cand_rel)):
            spec_path = rp(cand_rel)
            break
    if spec_path is None:
        return False, ["no GATES-SPEC.md found — parity has no spec side to compare, "
                       "and that is not a pass"]
    text = read(spec_path)
    spec_rows = {}
    for m in re.finditer(r"^\|\s*GATE-(\d+)\s*\|(.*)$", text, re.M):
        spec_rows["GATE-" + m.group(1)] = m.group(2)
    marker_re = re.compile(r"DESIGNED-NOT-IMPLEMENTED\s*[—-]+\s*(OBL-[A-Z0-9]+-[0-9]{2})")
    rows, _problems = _gap_rows()
    open_ids = {r["id_plain"] for r in (rows or []) if r["open"]}
    engine = set(k for k in F["gates"] if not k.startswith("$"))
    for gid, body in sorted(spec_rows.items(), key=lambda kv: int(kv[0].split("-")[1])):
        n = gid.split("-")[1]
        implemented = gid in engine and ("gate_%s" % n) in globals()
        m = marker_re.search(body)
        if implemented:
            continue
        if not m:
            return_msg = ("%s is in GATES-SPEC with no engine counterpart and no "
                          "DESIGNED-NOT-IMPLEMENTED marker — a spec-first change without a "
                          "paired obligation (layer-parity rule)" % gid)
            msgs.append(return_msg)
        elif m.group(1) not in open_ids:
            msgs.append("%s is marked DESIGNED-NOT-IMPLEMENTED under %s, but that obligation "
                        "is not open in %s — a marker pointing at nothing is decoration"
                        % (gid, m.group(1), F["gap_row"]["file"]))
    # F4: the schema half — every schema GATES-SPEC names must exist in formats.json
    for tok in sorted(set(re.findall(F["parity"]["schema_token"], text))):
        if tok not in F:
            msgs.append("GATES-SPEC names schema `%s` but formats.json has no such key — the "
                        "named-schema half of layer parity (verifier F4)" % tok)
    for gid in sorted(engine - set(spec_rows.keys())):
        msgs.append("%s is in the engine registry but has no GATES-SPEC row — the two "
                    "declarations of the gate set disagree" % gid)
    # ---- F-35 (v0.6.4): the machine home is shared by two regex dialects ----
    # \Z is Python end-of-string and a JavaScript literal 'Z' — one key, two
    # engines, opposite answers (16 healthy quick notes proposed for deletion).
    # A shared regex is only shared if every engine reads the same dialect.
    raw = read(os.path.join(HERE, "formats.json"))
    for badesc in ("\\\\Z", "\\\\A"):
        if badesc.replace("\\\\", "\\") in raw:
            msgs.append("formats.json contains %s — not portable between the Python and "
                        "JavaScript engines that share this file; use $(?![\\s\\S]) / ^ "
                        "(F-35)" % badesc.replace("\\\\", "\\"))
    # ---- reverse direction for lane refs (PF-b, pilot #2 on v0.6.0) ---------
    # check_parity asked only "does the engine have what the docs declare?" —
    # engine-ahead-of-docs was invisible. Every commit-trailer kind must be
    # documented in each lane surface (LANES.md and the resident router), or an
    # operator will not know a legal lane exists at exactly the moment it is
    # the only legal one ([WOW:migrate] was the first instance).
    lane_surfaces = []
    for rel in F["parity"]["lane_docs"]:
        if os.path.isfile(rp(rel)):
            lane_surfaces.append((rel, read(rp(rel))))
        else:
            msgs.append("lane doc %s (parity.lane_docs) does not exist — reverse trailer "
                        "parity has no doc side there" % rel)
    router = None
    for rel in F["parity"]["router_locations"]:
        if os.path.isfile(rp(rel)):
            router = (rel, read(rp(rel)))
            break
    if router:
        lane_surfaces.append(router)
    else:
        msgs.append("no router doc found (%s) — reverse trailer parity has no router side "
                    "to compare, and that is not a pass"
                    % ", ".join(F["parity"]["router_locations"]))
    for kind in sorted(F["commit_trailers"]["kinds"]):
        lit = F["commit_trailers"]["kinds"][kind].get("doc_literal")
        if not lit:
            msgs.append("commit_trailers.kinds.%s has no doc_literal — reverse parity cannot "
                        "check what it cannot name" % kind)
            continue
        for rel, txt in lane_surfaces:
            if lit not in txt:
                msgs.append("trailer %s (kind %s) is in formats.json but undocumented in %s "
                            "— engine-ahead-of-docs, the direction the parity sweep could "
                            "not see (PF-b)" % (lit, kind, rel))
    # ---- version authority --------------------------------------------------
    # platform/F-76 (v0.7.4): ids_expanded is the consumer-facing, matchable
    # form of ids.*; it is GENERATED, so drift between it and the load-time
    # expansion is a defect the sweep catches (a consumer matching a stale
    # expansion is the silent-PASS class the finding measured).
    exp = F.get("ids_expanded")
    if not isinstance(exp, dict):
        msgs.append("formats.json has no ids_expanded block — consumers have no matchable form "
                    "of the id grammar (platform/F-76); run `gates.sh formats-expand`")
    else:
        for k, v in F["ids"].items():
            if k.startswith("$"):
                continue
            if exp.get(k) != v:
                msgs.append("ids_expanded.%s is stale (does not equal the load-time expansion of "
                            "ids.%s) — regenerate with `gates.sh formats-expand` (platform/F-76)"
                            % (k, k))
    # prodsim/F-77 (v0.7.4): an installed repo's hooks are a LAYER, and layer
    # parity is exactly this check's job — a checkout of pre-install history
    # let an old lifecycle installer clobber the WoW pre-commit hook, and
    # nothing routine noticed: .git/hooks is untracked, so the loss is
    # invisible to every diff and review, and GATE-14 (commit-time-only) was
    # simply gone. The sweep runs at every phase boundary, so it asserts the
    # enforcement layer here. Binds only where an INSTALL exists: the config
    # file present AND carrying wow_version (the installer always stamps it;
    # the package repo and bare fixtures carry no such file/key by design).
    c = cfg()
    if os.path.isfile(rp(F["install"]["config_file"])) and c.get("wow_version"):
        # DEV-R11-02 (R11b): .git/hooks is untracked, so EVERY fresh clone and
        # CI checkout starts with no enforcement layer — the refusal names the
        # self-heal (`gates.sh hooks --install`, no package clone needed) and a
        # repo may set enforcement_layer_check: "advisory" for checkouts that
        # never commit (CI), keeping the sweep green there while still saying it.
        mode = str(c.get("enforcement_layer_check") or "block")
        sink = msgs if mode != "advisory" else layer_notes
        hooks_dir = _hooks_dir()
        for h in F["install"]["hooks"]:
            hp = os.path.join(hooks_dir, h)
            where = os.path.relpath(hooks_dir, ROOT) if hooks_dir.startswith(ROOT) else hooks_dir
            if not os.path.isfile(hp):
                sink.append("enforcement layer: hook %s is ABSENT from %s — the gates it carries "
                            "do not run at commit time (a fresh clone or CI checkout starts this "
                            "way: .git/hooks is untracked); run `scripts/wow/gates.sh hooks "
                            "--install` — no package clone needed (prodsim/F-77, DEV-R11-02)"
                            % (h, where))
            elif F["install"]["hook_marker"] not in read(hp):
                sink.append("enforcement layer: hook %s in %s exists and is FOREIGN (no WoW marker) "
                            "— a second installer clobbered ours, most likely a lifecycle script "
                            "from an older checkout (.git/hooks is untracked, so nothing else "
                            "notices); run `scripts/wow/gates.sh hooks --install` — it chains "
                            "the foreign hook and rotates an older chained copy aside, never "
                            "destroys (prodsim/F-77)" % (h, where))
    ch = rp("CHANGELOG.md")
    if not os.path.isfile(ch):
        msgs_note = "version authority: package-repo check — skipped here (no CHANGELOG.md); " \
                    "consumer version truth is wow.config.json's installed stamp"
        if not msgs:
            return True, [msgs_note] + layer_notes
        msgs.append(msgs_note)
    if os.path.isfile(ch):
        m = re.search(r"^##\s*v?([0-9][^\s]*)", read(ch), re.M)
        if m:
            top = m.group(1).replace("-draft", "")
            fv = str(F.get("version", "")).replace("-draft", "").lstrip("v")
            if fv != top:
                msgs.append("formats.json version %r != CHANGELOG top entry v%s — the single "
                            "version authority (CHANGELOG preamble)" % (F.get("version"), top))
            hdr_re = re.compile(r"DRAFT\s+v([0-9][^\s]*)")
            title_re = re.compile(r"\bv?([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-draft)?)\b")
            globs = [d for d in F["parity"]["versioned_docs"] if "*" in d]
            names = [d for d in F["parity"]["versioned_docs"] if "*" not in d and os.path.isfile(rp(d))]
            for doc in sorted(set(matching_docs(globs) + names)):
                dm = hdr_re.search(read(rp(doc)) or "")
                if not dm:
                    continue
                title = git("log", "-1", "--format=%s", "--", doc)
                if not title:
                    continue
                tm = title_re.search(title)
                if not tm:
                    continue  # last commit not version-titled: nothing to compare against
                hv = dm.group(1).replace("-draft", "")
                tv = tm.group(1).replace("-draft", "")
                if hv != tv:
                    msgs.append("%s header says v%s but its last-modifying commit is %r — "
                                "header stamps are last-MODIFIED markers, checked against git "
                                "history (pilot D2)" % (doc, dm.group(1), title.strip()[:50]))
    # ---- registry successor staleness (OBL-PKG-21, audit A5) -----------------
    # An OPEN obligation whose successor names an ALREADY-SHIPPED version is a
    # version stamp pointing backward: the named event happened and did not
    # discharge the row, so the cell has quietly become fiction — the stale-
    # narrative-state class, in the registry itself (four rows aged this way
    # across four versions before the 2026-09-13 audit caught them). Round
    # labels ("engine round 7") are not machine-comparable and stay a review
    # concern (the monthly audit's checklist); version tokens are checked here.
    def _ver_tuple(v):
        return tuple(int(x) for x in re.findall(r"\d+", v)[:3])
    cur = _ver_tuple(str(F.get("version", "")))
    rows, _probs = _gap_rows()
    if rows and cur:
        for r in rows:
            if not r["open"]:
                continue
            # mention-vs-claim, uniformly: a backticked version in the cell is
            # history being cited, not the successor being claimed.
            succ = _mask_inline_code(r.get("successor") or "")
            for vm in re.finditer(r"\bv([0-9]+\.[0-9]+(?:\.[0-9]+)?)", succ):
                if _ver_tuple(vm.group(1)) <= cur:
                    msgs.append("open row %s: successor names v%s, at or before the current "
                                "v%s — that release shipped without discharging the row, so "
                                "the successor is fiction; refresh the cell to the real "
                                "successor (OBL-PKG-21)"
                                % (r["id_plain"], vm.group(1), F.get("version")))
                    break
    return (len(msgs) == 0), msgs + layer_notes


def sweep(args):
    run_id = _opt(args, "--run")
    gates = list(F["sweep"]["always"])
    if "--p5" in args:
        gates += F["sweep"]["p5_only"]
    failed, total, vacuous = [], 0, 0
    ok, msgs = check_parity()
    total += 1
    print("%s %s" % ("PASS" if ok else "FAIL", "parity"))
    for m in msgs:
        print("     %s" % m)
    if not ok:
        failed.append("parity")
        log_rejection("PARITY", msgs)
    for g in gates:
        a = []
        if run_id and g in ("gate-2", "gate-4", "gate-5", "gate-7"):
            a = ["--run", run_id]
        if g == "gate-5":
            a = ["--sweep"] + a
        if g == "gate-7" and "--p5" in args:
            a = ["--p5"] + a
        if g == "gate-2" and "--p5" in args:
            a = ["--close"] + a   # F-09: at publish the work has happened; the close form binds
        ok, msgs = run_gate(g, a)
        total += 1
        print("%s %s" % ("PASS" if ok else "FAIL", g))
        for m in msgs:
            print("     %s" % m)
        if ok and any("VACUOUS" in m or "nothing to check" in m for m in msgs):
            vacuous += 1
        if not ok:
            failed.append(g)
            log_rejection(g, msgs)
    # DEV-R9-10 (v0.7.3 R9): the summary line is the one a human reads, and it
    # said exactly the sentence F-70 mocks — '6/6 passed' over an empty set —
    # while the vacuity markers sat above it, per gate, unaggregated.
    print("\nsweep%s: %d/%d passed%s" % (" (P5)" if "--p5" in args else "",
                                         total - len(failed), total,
                                         " (%d vacuous — green over an empty set)" % vacuous
                                         if vacuous else ""))
    return 1 if failed else 0


def main(argv):
    quiet = "--quiet" in argv
    if quiet:
        argv = [a for a in argv if a != "--quiet"]
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        print("usage: gates.sh <gate-1..gate-14 [--run <id>] [--paths …] [--staged] [--close] "
              "[--gate G<n>] [--spec <file>] | sweep [--p5] [--run <id>] | parity | list | "
              "check-id <run-id> [--base <ref>] | hooks --install|--check | formats-expand "
              "(package repo only — rewrites formats.json)>")
        return 0
    cmd, args = argv[0], argv[1:]
    if cmd == "list":
        for g, meta in sorted(((k, v) for k, v in F["gates"].items()
                                if not k.startswith("$")),
                               key=lambda kv: int(kv[0].split("-")[1])):
            inert = meta.get("inert_when")
            print("%-8s %-18s blocks %-14s %s"
                  % (g, meta["where"], meta["blocks"], ("inert when " + inert) if inert else ""))
        print("\nsweep       %s" % " ".join(F["sweep"]["always"]))
        print("sweep --p5  %s" % " ".join(F["sweep"]["always"] + F["sweep"]["p5_only"]))
        return 0
    if cmd == "sweep":
        return sweep(args)
    if cmd == "hooks":
        ok, out = hooks_install(check_only=("--check" in args))
        if "--install" not in args and "--check" not in args:
            print("usage: gates.sh hooks --install | --check", file=sys.stderr)
            return 1
        for ln in out:
            print("  " + ln)
        return 0 if ok else 1
    if cmd == "formats-expand":
        # platform/F-76: regenerate ids_expanded from ids.* in the RAW file.
        p = os.path.join(HERE, "formats.json")
        raw = json.load(open(p))
        ids = raw["ids"]
        parts = [("{run_date}", ids["run_date"]), ("{run_slug}", ids["run_slug"]),
                 ("{run_iter}", ids["run_iter"])]
        core = _expand_run_core(ids["run_core"], parts)
        subs = parts + [("{run_core}", core), ("{task_tail}", ids["task_tail"])]
        gen = {k: _expand_run_core(v, subs) for k, v in ids.items() if not k.startswith("$")}
        txt = open(p).read()
        new_block = json.dumps(gen, indent=4, ensure_ascii=False)
        new_block = "\n".join(("  " + ln) if ln else ln for ln in new_block.split("\n")).lstrip()
        m = re.search(r'"ids_expanded": \{.*?\n  \}', txt, re.S)
        if not m:
            print("no ids_expanded block to regenerate — add one after \"ids\"", file=sys.stderr)
            return 1
        txt = txt[:m.start()] + '"ids_expanded": ' + new_block + txt[m.end():]
        open(p, "w").write(txt)
        json.load(open(p))
        print("ids_expanded regenerated (%d keys)" % len(gen))
        return 0
    if cmd == "check-id":
        # F-46 (v0.7.1): validate the run id WHERE THE RUN IS CREATED (P1),
        # not where it is first referenced — a 27-char slug passed P0→G2 and
        # then no executor commit could carry a legal lane ref, days later.
        rid = args[0] if args else ""
        if not rid:
            print("usage: gates.sh check-id <run-id>", file=sys.stderr)
            return 1
        base = _opt(args, "--base")
        if re.match(F["ids"]["run"], rid):
            if base:
                # prodsim/F-65 (v0.7.3): "from main" produced a run base on
                # which the run did not exist — no PLAN for executors, gates
                # absent, and a 258-commit-stale copy of one source file that
                # two mutation proofs would have "restored". A base without
                # the plan is never correct, whatever the branch is called.
                plan_rel = fill(F["plan_schema"]["file"], run_id=rid)
                if not git("rev-parse", "--verify", "--quiet", base).strip():
                    print("REFUSED: --base %r is not a ref this repo can resolve — if this "
                          "repo's default branch is not 'main', set \"main_branch\" (and "
                          "optionally \"run_base\") in wow.config.json (prodsim/F-65, "
                          "DEV-R9-11)" % base, file=sys.stderr)
                    return 1
                if not git("ls-tree", "--name-only", base, "--", plan_rel).strip():
                    print("REFUSED: %s does not exist on --base %r — a run base that does not "
                          "carry the run's plan gives executors nothing to execute and gates "
                          "nothing to grade; cut the base from the branch the run lives on "
                          "(wow.config.json run_base, prodsim/F-65)" % (plan_rel, base),
                          file=sys.stderr)
                    return 1
                print("ok: %r matches ids.run and --base %r carries %s" % (rid, base, plan_rel))
                return 0
            print("ok: %r matches ids.run" % rid)
            return 0
        slug = _run_anatomy(rid)
        if slug is not None and len(slug) > _slug_cap():
            print("REFUSED: slug %r is %d chars; ids.run caps it at %d — rename before any "
                  "artifact is signed against this id (F-46)"
                  % (slug, len(slug), _slug_cap()), file=sys.stderr)
        else:
            print("REFUSED: %r does not match ids.run (%s) — YYMMDD-<kebab-slug>-r<N>"
                  % (rid, F["ids"]["run"]), file=sys.stderr)
        return 1
    ok, msgs = run_gate(cmd, args)
    if not ok:
        for m in msgs:
            print("%s: %s" % (cmd.upper(), m), file=sys.stderr)
        log_rejection(cmd.upper(), msgs)
        return 1
    if not quiet:
        for m in msgs:
            print("     %s" % m)
        print("%s PASS" % cmd.upper())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
