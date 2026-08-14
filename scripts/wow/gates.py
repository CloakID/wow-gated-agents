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
P = F["paths"]


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


def git(*args):
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

    hits = []
    for name, spec in ct["kinds"].items():
        for m in re.finditer(spec["pattern"], body):
            hits.append((name, m.group(1)))
    if len(hits) == 0:
        return False, ["no lane reference. Expected exactly one of "
                       "[T:<task-id>] [Q:runs/quick/<dir>] [D:<debug-slug>] [WOW:publish]"]
    if len(hits) > 1:
        return False, ["%d lane references, expected exactly one: %s"
                       % (len(hits), ", ".join(h[1] for h in hits))]
    name, value = hits[0]
    how = ct["kinds"][name]["resolves"]

    if how == "none":
        return True, []
    if how == "dir_exists":
        return (True, []) if os.path.isdir(rp(value)) else \
            (False, ["lane ref [Q:%s] names a directory that does not exist" % value])
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


def _target_length(target, staged):
    """Line count of a citation target, read from the index when the citing file
    is being committed, so preflight judges the same snapshot git will store."""
    if staged:
        t = read_staged(target)
        if t:
            return len(t.split("\n"))
    full = rp(target) if not os.path.isabs(target) else target
    if not os.path.exists(full):
        return None
    return len(lines_of(full))


def _target_exists(target, staged):
    if staged and read_staged(target):
        return True
    full = rp(target) if not os.path.isabs(target) else target
    return os.path.exists(full)


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
        return (lambda m: (len(m) == 0, m))(_preflight(staged_files(), True))
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
def gate_11(paths):
    lf = F["legacy_freeze"]
    c = cfg()
    if c.get(lf["config_key"]) is not True:
        return True, ["inert: wow.config.json %s is not true" % lf["config_key"]]
    bad = []
    for p in paths or []:
        for frozen in lf["paths"]:
            if p == frozen or p.startswith(frozen.rstrip("/") + "/"):
                bad.append(p)
    if bad:
        frozen = ", ".join(x.rstrip("/") + "/" for x in lf["paths"])
        return False, ["commit touches frozen %s (%d file(s)): %s — it is history, in every "
                       "direction including deletion"
                       % (frozen, len(bad), ", ".join(sorted(set(bad))[:5]))]
    return True, []


# --------------------------------------------------------------------------
# GATE-3 — completion statuses and done-words carry well-formed evidence
# --------------------------------------------------------------------------
def _evidence_problems(line):
    """Every ev: on the line must match its own type pattern. `any` alone let
    ev:cmd{i ran it and it was fine} satisfy the evidence rule."""
    ev = F["evidence"]
    if not ev.get("validate_shape"):
        return []
    bad = []
    for m in re.finditer(ev["kind"], line):
        kind = m.group(1)
        whole = m.group(0)
        pat = ev["types"].get(kind)
        if pat and not re.search(pat, whole):
            bad.append(whole)
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


def _is_separator(line):
    return re.match(r"^\s*\|[\s:|-]+\|\s*$", line) is not None


def _cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def gate_3(paths=None):
    sv = F["status_vocab"]
    ev_required = set(sv["evidence_required"])
    ref_required = dict(sv["reference_required"])
    done_words = set(w.lower() for w in sv["done_words"])
    forbidden = set(w.upper() for w in sv["forbidden_synonyms"])
    allowed = set(sv["allowed"])
    status_cols = set(c.lower() for c in sv["status_columns"])
    targets = paths if paths else gated_docs()
    msgs = []

    for p in targets:
        if excluded(p):
            continue
        full = rp(p)
        if not os.path.isfile(full):
            continue
        in_fence = False
        status_idx = None      # which column of the current table holds status
        prev_cells = None
        for i, line in enumerate(lines_of(full), 1):
            s = line.strip()
            if s.startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            if not s:
                status_idx, prev_cells = None, None
                continue

            is_row = line.count("|") >= 2
            if is_row and _is_separator(line):
                if prev_cells:
                    for idx, h in enumerate(prev_cells):
                        if h.lower() in status_cols:
                            status_idx = idx
                continue

            for bad in _evidence_problems(line):
                msgs.append("%s:%d malformed citation '%s' — does not match the %s shape in "
                            "formats.json" % (p, i, bad, bad.split("{")[0].split(":")[-1]))

            has_ev = _has_evidence(line)
            has_ref = _has_reference(line, skip_first_cell=is_row)
            cells = _cells(line) if is_row else []
            prev_cells = cells if is_row else None
            checked = cells if status_idx is None else (
                [cells[status_idx]] if status_idx < len(cells) else [])

            for c in checked:
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
                    msgs.append("%s:%d status %s without an ev: citation" % (p, i, bare))
                elif up in ref_required and not has_ref:
                    msgs.append("%s:%d status %s without a %s in the same row"
                                % (p, i, bare, ref_required[up]))
                elif bare.lower() in done_words and len(bare.split()) == 1 and not has_ev:
                    msgs.append("%s:%d done-word '%s' used as a status without an ev: citation"
                                % (p, i, bare))
                elif up in forbidden and up not in allowed:
                    msgs.append("%s:%d '%s' is not in the status vocabulary (%s)"
                                % (p, i, bare, ", ".join(sorted(allowed))))

            m = re.search(sv["status_prefix"], line, re.I)
            if m:
                word = m.group(2)
                if (word.upper() in ev_required or word.lower() in done_words) and not has_ev:
                    msgs.append("%s:%d '%s: %s' without an ev: citation" % (p, i, m.group(1), word))
                elif word.upper() in ref_required and not has_ref:
                    msgs.append("%s:%d '%s: %s' without a %s"
                                % (p, i, m.group(1), word, ref_required[word.upper()]))
    return (len(msgs) == 0), msgs


# --------------------------------------------------------------------------
# GATE-2 — REQ ids named by the active spec/plan have UPDATED rows
# --------------------------------------------------------------------------
def _req_rows():
    schema = F["requirements_row_schema"]
    rows = {}
    for line in lines_of(rp(schema["file"])):
        m = re.match(schema["row"], line)
        if m:
            rows[m.group("req")] = line
    return rows


def _req_rows_touched(run_id):
    """REQ ids whose REQUIREMENTS row appears among this run's added/changed
    lines. 'A row exists' is not what GATE-2 asks for — it asks for an updated
    row, and a row untouched since a previous milestone is the failure case."""
    schema = F["requirements_row_schema"]
    req_pat = F["ids"]["requirement"].strip("^$")
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


def gate_2(run_id=None, spec=None):
    schema = F["requirements_row_schema"]
    req_pat = F["ids"]["requirement"].strip("^$")
    scoped = bool(run_id or spec)
    if not scoped:
        run_id = discover_run()
        if not run_id:
            return True, ["no runs and no --spec: nothing to check"]

    named, sources = set(), []
    if spec:
        sources.append(spec)
    if run_id:
        d = rp(P["runs_dir"], run_id)
        for base, _dirs, files in os.walk(d):
            for fn in files:
                if fn.endswith(".md"):
                    sources.append(os.path.relpath(os.path.join(base, fn), ROOT))
        for s in list(sources):
            for m in re.finditer(P["spec_reference"], read(rp(s))):
                sources.append(os.path.join(P["specs_dir"], m.group(1)))
    for s in sorted(set(sources)):
        for m in re.finditer(req_pat, read(rp(s))):
            named.add(m.group(0))
    if not named:
        return True, ["no REQ ids named by the active spec/plan"]

    rows = _req_rows()
    missing = sorted(r for r in named if r not in rows)
    if missing:
        return False, ["REQ id named by the active spec/plan has no row in %s: %s"
                       % (schema["file"], ", ".join(missing))]
    msgs = ["%d REQ id(s) checked, all have rows" % len(named)]
    if run_id and schema.get("must_be_updated_in_run"):
        touched = _req_rows_touched(run_id)
        stale = sorted(r for r in named if r not in touched)
        if stale:
            return False, msgs + [
                "REQ row(s) never updated in run %s — GATE-2 requires an updated technical-status "
                "row at phase close, not merely a row that exists: %s" % (run_id, ", ".join(stale))]
        msgs.append("%d row(s) updated in this run" % len(touched & named))
    return True, msgs


# --------------------------------------------------------------------------
# GATE-4 — invariants/checks carry a recorded, citing non-vacuity proof
# --------------------------------------------------------------------------
def gate_4(run_id=None):
    nv = F["non_vacuity"]
    msgs = []
    for gate_id in F["gates"]:
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
    fmspec = F["frontmatter"]
    ls = lines_of(path)
    if not ls or ls[0].strip() != fmspec["fence"]:
        return None
    fm, i = {}, 1
    while i < len(ls) and ls[i].strip() != fmspec["fence"]:
        m = re.match(fmspec["key_value"], ls[i].strip())
        if m:
            v = m.group(2).strip()
            if v.startswith("["):
                v = [x.strip().strip('"\'') for x in v.strip("[]").split(",") if x.strip()]
            fm[m.group(1)] = v
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
    out = git("log", "--oneline", "%s..HEAD" % fm["verified_against"], "--", *paths)
    if out.strip():
        n = len(out.strip().split("\n"))
        return False, "map '%s' is STALE: %d commit(s) touch %s since %s" % (
            area, n, paths, fm["verified_against"])
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
        if _parse_plan(rp(fill(ps["file"], run_id=run_id)))["units"]:
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
# GATE-7 — P5 sweep
# --------------------------------------------------------------------------
def gate_7():
    rl = F["runs_layout"]
    msgs = []
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
                    msgs.append("%s has an empty result and is %.0f days old — stale stub, PO "
                                "confirms deletion" % (fill(rl["quick"], slug=slug), age))
    ad = rp(rl["archive_dir"])
    if os.path.isdir(ad):
        for run in sorted(os.listdir(ad)):
            if os.path.isfile(os.path.join(ad, run, rl["active_marker"])):
                msgs.append("%s/%s is archived but still marked active" % (rl["archive_dir"], run))
    return (len(msgs) == 0), msgs


# --------------------------------------------------------------------------
# GATE-8 — plan structural lint
# --------------------------------------------------------------------------
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

            task_col, verify_col, header = None, None, None
            u["missing_columns"] = []
            for line in body.split("\n"):
                if line.count("|") < 2:
                    continue
                cells = _cells(line)
                if _is_separator(line):
                    if header:
                        task_col = _table_column(header, ps["task_column"])
                        verify_col = _table_column(header, ps["verify_column"])
                        u["missing_columns"] = [c for c in ps["task_table_columns"]
                                                if _table_column(header, c) is None]
                    continue
                if re.search(F["ids"]["task"].strip("^$"), line):
                    tid = cells[task_col] if task_col is not None and task_col < len(cells) \
                        else (cells[0] if cells else "")
                    ver = cells[verify_col] if verify_col is not None and verify_col < len(cells) \
                        else (cells[2] if len(cells) > 2 else "")
                    u["tasks"].append({"id": tid, "verify": ver,
                                       "header_seen": verify_col is not None})
                header = cells
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
    return (len(msgs) == 0), msgs


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
            return False, ["%s closes against a %s artifact, and none was found — pass --spec or "
                           "--run" % (gate, jm["closing_gates"][gate])]
        head = "\n".join(read(rp(a)).split("\n")[:jm["header_lines"]])
        if not re.search(pat, head, re.M):
            return False, ["%s cannot close: %s has no 'signed: <date> ev:jira{KEY-nn}' record "
                           "in its header" % (gate, a)]
        msgs.append("%s closure record present in %s" % (gate, a))
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
    bad = [m for m in msgs if "claims SIGNED" in m or "not SIGNED" in m]
    return (len(bad) == 0), msgs


# --------------------------------------------------------------------------
# GATE-10 — divergence diff produced, evidenced and fully classified
# --------------------------------------------------------------------------
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
    header = None
    for i, line in enumerate(txt.split("\n"), 1):
        if line.count("|") < 3:
            continue
        cells = _cells(line)
        if _is_separator(line):
            if header:
                class_col = _table_column(header, jm["classification_column"])
                git_col = _table_column(header, jm["git_column"])
                jira_col = _table_column(header, jm["jira_column"])
            continue
        if class_col is None:
            header = cells
            continue
        header = cells
        if not cells or not cells[0]:
            continue
        rows += 1
        got = cells[class_col].strip().lower() if class_col < len(cells) else ""
        if got not in jm["classifications"]:
            unclassified.append("%s:%d %s" % (rel, i, cells[0]))
        if git_col is not None and jira_col is not None and \
                git_col < len(cells) and jira_col < len(cells):
            g, j = cells[git_col].strip().upper(), cells[jira_col].strip()
            if g in jm["expected"] and j in jm["expected"][g]:
                msgs.append("note: %s:%d records %s/%s, which IS expected-consistent per "
                            "FORMATS §10 — not a divergence" % (rel, i, g, j))

    if rows == 0:
        if re.search(jm["no_divergence_statement"], txt, re.M | re.I):
            if jm.get("no_divergence_requires_evidence") and \
                    not re.search(F["evidence"]["any"], txt):
                return False, msgs + ["%s asserts 'no divergences' with no ev: citation of the "
                                      "query that produced it. An empty diff is a claim like any "
                                      "other." % rel]
            return True, msgs + ["%s records no divergences, with evidence" % rel]
        if class_col is None:
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
        return gate_2(run_id=_opt(args, "--run"), spec=_opt(args, "--spec"))
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
        return gate_7()
    if name == "gate-8":
        return gate_8(_opt(args, "--run"))
    if name == "gate-9":
        return gate_9(_list_opt(args, "--paths") or None, gate=_opt(args, "--gate"),
                      run_id=_opt(args, "--run"), spec=_opt(args, "--spec"))
    if name == "gate-10":
        return gate_10(_opt(args, "--run"), _opt(args, "--gate") or "G2")
    if name == "gate-11":
        paths = staged_files(include_deleted=F["legacy_freeze"]["include_deletions"]) \
            if "--staged" in args else _list_opt(args, "--paths")
        return gate_11(paths)
    return False, ["unknown gate %s" % name]


def sweep(args):
    run_id = _opt(args, "--run")
    gates = list(F["sweep"]["always"])
    if "--p5" in args:
        gates += F["sweep"]["p5_only"]
    failed, total = [], 0
    for g in gates:
        a = []
        if run_id and g in ("gate-2", "gate-4", "gate-5"):
            a = ["--run", run_id]
        if g == "gate-5":
            a = ["--sweep"] + a
        ok, msgs = run_gate(g, a)
        total += 1
        print("%s %s" % ("PASS" if ok else "FAIL", g))
        for m in msgs:
            print("     %s" % m)
        if not ok:
            failed.append(g)
            log_rejection(g, msgs)
    print("\nsweep%s: %d/%d passed" % (" (P5)" if "--p5" in args else "",
                                       total - len(failed), total))
    return 1 if failed else 0


def main(argv):
    quiet = "--quiet" in argv
    if quiet:
        argv = [a for a in argv if a != "--quiet"]
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        print("usage: gates.sh <gate-1..gate-11|sweep [--p5]|list> [options]")
        return 0
    cmd, args = argv[0], argv[1:]
    if cmd == "list":
        for g, meta in sorted(F["gates"].items(), key=lambda kv: int(kv[0].split("-")[1])):
            inert = meta.get("inert_when")
            print("%-8s %-18s blocks %-14s %s"
                  % (g, meta["where"], meta["blocks"], ("inert when " + inert) if inert else ""))
        print("\nsweep       %s" % " ".join(F["sweep"]["always"]))
        print("sweep --p5  %s" % " ".join(F["sweep"]["always"] + F["sweep"]["p5_only"]))
        return 0
    if cmd == "sweep":
        return sweep(args)
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
