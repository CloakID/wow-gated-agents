#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""WoW v2 mechanical gates. Entry point is gates.sh; this is its engine.

Every pattern, vocabulary and schema comes from formats.json — the single machine
home shared with status.mjs. Nothing is inlined here. If you find yourself adding
a literal regex to this file, put it in formats.json instead.

Each gate returns (ok: bool, messages: list[str]). A gate that cannot fail is a
defect (inert-gate class); scripts/wow/tests/ holds one negative test per gate.
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


def staged_files():
    out = git("diff", "--cached", "--name-only", "--diff-filter=ACMR")
    return [f for f in out.split("\n") if f.strip()]


def tracked_files():
    out = git("ls-files")
    return [f for f in out.split("\n") if f.strip()]


def log_rejection(gate, messages):
    d = rp("runs")
    if not os.path.isdir(d):
        try:
            os.makedirs(d)
        except Exception:
            return
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S")
    try:
        with open(os.path.join(d, ".gate-log"), "a", encoding="utf-8") as fh:
            for m in messages:
                fh.write("%s\t%s\t%s\n" % (stamp, gate, m))
    except Exception:
        pass


# --------------------------------------------------------------------------
# GATE-1 — commit message carries exactly one lane ref, and it resolves
# --------------------------------------------------------------------------
def gate_1(msgfile):
    msg = read(msgfile)
    body = "\n".join(l for l in msg.split("\n") if not l.startswith("#"))
    kinds = F["commit_trailers"]["kinds"]
    hits = []
    for name, spec in kinds.items():
        for m in re.finditer(spec["pattern"], body):
            hits.append((name, m.group(1)))
    if len(hits) == 0:
        return False, ["no lane reference. Expected exactly one of "
                       "[T:<task-id>] [Q:runs/quick/<dir>] [D:<debug-slug>] [WOW:publish]"]
    if len(hits) > 1:
        return False, ["%d lane references, expected exactly one: %s"
                       % (len(hits), ", ".join(h[1] for h in hits))]
    name, value = hits[0]
    how = kinds[name]["resolves"]
    if how == "none":
        return True, []
    if how == "dir_exists":
        return (True, []) if os.path.isdir(rp(value)) else \
            (False, ["lane ref [Q:%s] names a directory that does not exist" % value])
    if how == "debug_file_exists":
        for cand in ("runs/debug/%s.md" % value, "runs/debug/resolved/%s.md" % value):
            if os.path.isfile(rp(cand)):
                return True, []
        return False, ["lane ref [D:%s] has no file at runs/debug/%s.md" % (value, value)]
    if how == "task_in_plan":
        run_id = value.split(".")[0]
        plan = rp("runs", run_id, "PLAN.md")
        if not os.path.isfile(plan):
            return False, ["lane ref [T:%s] names run %s, which has no PLAN.md" % (value, run_id)]
        if value not in read(plan):
            return False, ["lane ref [T:%s] is not a task in runs/%s/PLAN.md" % (value, run_id)]
        return True, []
    return False, ["unknown resolver %s" % how]


# --------------------------------------------------------------------------
# GATE-5 — file:line citations in the given files pass preflight
# --------------------------------------------------------------------------
def _citations(path):
    pat = F["evidence"]["file_line_citation"]
    return [(m.group(1), int(m.group(2)), i + 1)
            for i, line in enumerate(lines_of(path))
            for m in re.finditer(pat, line)]


def excluded(path):
    return any(fnmatch.fnmatch(path, pat) for pat in F.get("citation_scan_exclude", []))


def gate_5(paths):
    msgs = []
    for p in paths:
        if excluded(p):
            continue
        full = rp(p)
        if not os.path.isfile(full):
            continue
        for target, lineno, at in _citations(full):
            t = rp(target) if not os.path.isabs(target) else target
            if not os.path.exists(t):
                msgs.append("%s:%d cites %s:%d — GONE (no such file)" % (p, at, target, lineno))
            else:
                n = len(lines_of(t))
                if lineno < 1 or lineno > n:
                    msgs.append("%s:%d cites %s:%d — DRIFTED (file has %d lines)"
                                % (p, at, target, lineno, n))
    return (len(msgs) == 0), msgs


# --------------------------------------------------------------------------
# GATE-11 — legacy-framework freeze (inert unless migrated_from_gsd)
# --------------------------------------------------------------------------
def gate_11(paths):
    c = cfg()
    if c.get("migrated_from_gsd") is not True:
        return True, ["inert: wow.config.json migrated_from_gsd is not true"]
    bad = [p for p in paths if p == ".planning" or p.startswith(".planning/")]
    if bad:
        return False, ["commit touches frozen .planning/ (%d file(s)): %s"
                       % (len(bad), ", ".join(bad[:5]))]
    return True, []


# --------------------------------------------------------------------------
# GATE-3 — completion statuses and done-words carry evidence
# --------------------------------------------------------------------------
def gate3_targets():
    out = []
    for pat in ("docs/REQUIREMENTS.md", "docs/spec/*.md", "runs/*/RUN-REPORT.md",
                "runs/*/reports/*.md", "runs/quick/*/NOTE.md"):
        for f in tracked_files():
            if fnmatch.fnmatch(f, pat):
                out.append(f)
    for f in _untracked_matching(("docs/REQUIREMENTS.md", "docs/spec/*.md",
                                  "runs/*/RUN-REPORT.md", "runs/*/reports/*.md",
                                  "runs/quick/*/NOTE.md")):
        out.append(f)
    return sorted(set(out))


def _untracked_matching(pats):
    out = []
    for base, _dirs, files in os.walk(ROOT):
        if ".git" in base:
            continue
        for fn in files:
            rel = os.path.relpath(os.path.join(base, fn), ROOT)
            for p in pats:
                if fnmatch.fnmatch(rel, p):
                    out.append(rel)
    return out


def gate_3(paths=None):
    sv = F["status_vocab"]
    ev_any = F["evidence"]["any"]
    completion = set(sv["completion_class"])
    done_words = set(w.lower() for w in sv["done_words"])
    forbidden = set(w.upper() for w in sv["forbidden_synonyms"])
    allowed = set(sv["allowed"])
    cascade = sv["cascade_form"]
    targets = paths if paths else gate3_targets()
    msgs = []
    for p in targets:
        if excluded(p):
            continue
        full = rp(p)
        if not os.path.isfile(full):
            continue
        in_fence = False
        for i, line in enumerate(lines_of(full), 1):
            s = line.strip()
            if s.startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence or s.startswith(">"):
                continue
            has_ev = re.search(ev_any, line) is not None
            cells = [c.strip() for c in line.split("|")] if line.count("|") >= 2 else []
            for c in cells:
                bare = re.sub(r"[*`_]", "", c).strip()
                if not bare:
                    continue
                up = bare.upper()
                if up in completion and not has_ev:
                    msgs.append("%s:%d status %s without an ev: citation" % (p, i, bare))
                elif bare.lower() in done_words and len(bare.split()) == 1 and not has_ev:
                    msgs.append("%s:%d done-word '%s' used as a status without an ev: citation"
                                % (p, i, bare))
                elif up in forbidden and up not in allowed:
                    if not re.match(cascade, up):
                        msgs.append("%s:%d '%s' is not in the status vocabulary (%s)"
                                    % (p, i, bare, ", ".join(sorted(allowed))))
            m = re.search(r"\b(status|result)\s*:\s*([A-Za-z][A-Za-z-]*)", line, re.I)
            if m:
                word = m.group(2)
                if (word.upper() in completion or word.lower() in done_words) and not has_ev:
                    msgs.append("%s:%d '%s: %s' without an ev: citation" % (p, i, m.group(1), word))
    return (len(msgs) == 0), msgs


# --------------------------------------------------------------------------
# GATE-2 — REQ ids named by the active spec/plan have rows in REQUIREMENTS.md
# --------------------------------------------------------------------------
def _req_rows():
    schema = F["requirements_row_schema"]
    rows = {}
    for line in lines_of(rp(schema["file"])):
        m = re.match(schema["row"], line)
        if m:
            rows[m.group("req")] = line
    return rows


def gate_2(run_id=None, spec=None):
    req_pat = F["ids"]["requirement"].strip("^$")
    named = set()
    sources = []
    if spec:
        sources.append(spec)
    if run_id:
        d = rp("runs", run_id)
        for base, _dirs, files in os.walk(d):
            for fn in files:
                if fn.endswith(".md"):
                    sources.append(os.path.relpath(os.path.join(base, fn), ROOT))
        for s in list(sources):
            for m in re.finditer(r"docs/spec/(SPEC-[a-z0-9-]+-v[0-9]+\.md)", read(rp(s))):
                sources.append("docs/spec/" + m.group(1))
    if not sources:
        return True, ["no active spec or run named; nothing to check"]
    for s in sorted(set(sources)):
        for m in re.finditer(req_pat, read(rp(s))):
            named.add(m.group(0))
    rows = _req_rows()
    missing = sorted(r for r in named if r not in rows)
    if missing:
        return False, ["REQ id named by the active spec/plan has no row in %s: %s"
                       % (F["requirements_row_schema"]["file"], ", ".join(missing))]
    return True, ["%d REQ id(s) checked, all have rows" % len(named)]


# --------------------------------------------------------------------------
# GATE-4 — invariants/checks carry a recorded non-vacuity proof
# --------------------------------------------------------------------------
def gate_4(run_id=None):
    msgs = []
    tests = os.path.join(HERE, "tests")
    for gate_id in F["gates"]:
        want = os.path.join(tests, "test-%s.sh" % gate_id.lower())
        if not os.path.isfile(want):
            msgs.append("%s has no negative test at scripts/wow/tests/test-%s.sh"
                        % (gate_id, gate_id.lower()))
    if run_id:
        d = rp("runs", run_id)
        for base, _dirs, files in os.walk(d):
            for fn in files:
                if not fn.endswith(".md"):
                    continue
                p = os.path.join(base, fn)
                rel = os.path.relpath(p, ROOT)
                txt = read(p)
                n_inv = len(re.findall(r"^\s*invariant:", txt, re.M))
                n_proof = len(re.findall(r"^\s*non-vacuity:", txt, re.M))
                if n_inv > n_proof:
                    msgs.append("%s declares %d invariant(s) but records %d non-vacuity proof(s)"
                                % (rel, n_inv, n_proof))
    return (len(msgs) == 0), msgs


# --------------------------------------------------------------------------
# GATE-6 — codebase-map freshness (git-only), or a recorded P0 decision
# --------------------------------------------------------------------------
def _frontmatter(path):
    ls = lines_of(path)
    if not ls or ls[0].strip() != "---":
        return None
    fm, i = {}, 1
    while i < len(ls) and ls[i].strip() != "---":
        m = re.match(r"^([a-z_]+):\s*(.*)$", ls[i].strip())
        if m:
            v = m.group(2).strip()
            if v.startswith("["):
                v = [x.strip().strip('"\'') for x in v.strip("[]").split(",") if x.strip()]
            fm[m.group(1)] = v
        i += 1
    return fm


def _dep_map(name):
    return rp(F["dep_frontmatter"]["dir"], "%s.md" % name)


def _dep_fresh(name, probe=True):
    """FORMATS §11. Fresh iff the probe's output hash matches; where no probe
    surface is definable, iff `verified` is within max_age_days."""
    spec = F["dep_frontmatter"]
    mp = _dep_map(name)
    if not os.path.isfile(mp):
        return False, "no dependency map at %s" % os.path.relpath(mp, ROOT)
    fm = _frontmatter(mp)
    if not fm:
        return False, "%s has no front-matter" % os.path.relpath(mp, ROOT)
    for k in spec["required"]:
        if k not in fm:
            return False, "%s front-matter missing '%s'" % (os.path.relpath(mp, ROOT), k)
    if fm.get("kind") and fm["kind"] not in spec["kinds"]:
        return False, "%s kind '%s' is not one of %s" % (os.path.relpath(mp, ROOT),
                                                         fm["kind"], spec["kinds"])
    cmd = fm.get("probe")
    if cmd and probe:
        want = fm.get("verified_against_hash")
        if not want:
            return False, "%s defines a probe but no verified_against_hash" % name
        try:
            out = subprocess.check_output(cmd, shell=True, cwd=ROOT,
                                          stderr=subprocess.DEVNULL, timeout=60)
        except Exception as e:
            return False, "%s probe failed to run (%s) — cannot establish freshness" % (name, type(e).__name__)
        got = hashlib.sha256(out).hexdigest()
        if got != want:
            return False, ("%s is STALE: probe hash %s != recorded %s. The vendor surface moved "
                           "since verification — re-verify the map's claims, do not just restamp "
                           "the hash" % (name, got[:12], str(want)[:12]))
        return True, "%s is fresh (probe hash matches)" % name
    # fallback: calendar. Legitimate here precisely because git is unavailable.
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
    return True, "%s is fresh (verified %.0f days ago, within %d — %s)" % (name, age, max_age, why)


def _plan_deps(run_id):
    txt = read(rp("runs", run_id, "PLAN.md"))
    deps = []
    for m in re.finditer(r"^deps:\s*$((?:\s*-\s*.+\n?)+)", txt, re.M):
        deps += [l.strip().lstrip("-").strip().strip("`") for l in m.group(1).split("\n") if l.strip()]
    for m in re.finditer(r"^deps:\s*\[(.+?)\]\s*$", txt, re.M):
        deps += [x.strip().strip('"\'') for x in m.group(1).split(",") if x.strip()]
    return sorted(set(deps))


def gate_6(area=None, run_id=None, deps=None, probe=True):
    """(a) codebase-map freshness per FORMATS §6 — git rule.
       (b) external-dep freshness per FORMATS §11 — probe-hash rule.
       Or a recorded P0 decision in HANDOFF."""
    msgs, ok = [], True

    if deps is None:
        deps = _plan_deps(run_id) if run_id else []
    for d in deps:
        good, why = _dep_fresh(d, probe=probe)
        msgs.append(why)
        if not good:
            ok = False

    if area:
        mp = rp("docs", "codebase", "%s.md" % area)
        if not os.path.isfile(mp):
            rec = None
            if run_id:
                h = read(rp("runs", run_id, "HANDOFF.md"))
                m = re.search(r"^p0-record:\s*%s\s*=\s*(fresh|not-required|updated)\b"
                              % re.escape(area), h, re.M)
                rec = m.group(1) if m else None
            if rec:
                msgs.append("no map for '%s'; HANDOFF records p0-record = %s" % (area, rec))
            else:
                return False, msgs + ["no codebase map at docs/codebase/%s.md and no p0-record "
                                      "in HANDOFF" % area]
        else:
            fm = _frontmatter(mp)
            if not fm:
                return False, msgs + ["docs/codebase/%s.md has no front-matter" % area]
            for k in F["codebase_frontmatter"]["required"]:
                if k not in fm:
                    return False, msgs + ["docs/codebase/%s.md front-matter missing '%s'"
                                          % (area, k)]
            paths = fm["paths"] if isinstance(fm["paths"], list) else [fm["paths"]]
            out = git("log", "--oneline", "%s..HEAD" % fm["verified_against"], "--", *paths)
            if out.strip():
                n = len(out.strip().split("\n"))
                return False, msgs + ["map '%s' is STALE: %d commit(s) touch %s since %s"
                                      % (area, n, paths, fm["verified_against"])]
            msgs.append("map '%s' is fresh" % area)

    if not area and not deps:
        msgs.append("nothing to check: no --area, no --deps, and the plan declares no deps:")
    return ok, msgs


# --------------------------------------------------------------------------
# GATE-7 — P5 sweep
# --------------------------------------------------------------------------
def gate_7():
    msgs = []
    for base, _dirs, files in os.walk(rp("runs")):
        if "jira-queue.md" in files:
            p = os.path.join(base, "jira-queue.md")
            txt = read(p)
            open_items = len(re.findall(r"^\s*-\s*\[ \]", txt, re.M))
            if open_items:
                msgs.append("%s has %d unresolved queued op(s)"
                            % (os.path.relpath(p, ROOT), open_items))
    stale_days = F["runs_layout"]["quick_stale_days"]
    qd = rp("runs", "quick")
    if os.path.isdir(qd):
        for slug in sorted(os.listdir(qd)):
            note = os.path.join(qd, slug, "NOTE.md")
            if not os.path.isfile(note):
                continue
            txt = read(note)
            m = re.search(r"^#+\s*result\s*$([\s\S]*?)(?=^#|\Z)", txt, re.M | re.I)
            empty = (m is None) or (m.group(1).strip() == "")
            if empty:
                age = (time.time() - os.path.getmtime(note)) / 86400.0
                if age > stale_days:
                    msgs.append("runs/quick/%s/NOTE.md has an empty result and is %.0f days old "
                                "— stale stub, PO confirms deletion" % (slug, age))
    ad = rp("runs", "archive")
    if os.path.isdir(ad):
        for run in sorted(os.listdir(ad)):
            if os.path.isfile(os.path.join(ad, run, ".active")):
                msgs.append("runs/archive/%s is archived but still marked active" % run)
    return (len(msgs) == 0), msgs


# --------------------------------------------------------------------------
# GATE-8 — plan structural lint
# --------------------------------------------------------------------------
def _parse_plan(path):
    txt = read(path)
    ps = F["plan_schema"]
    plan = {"spec": None, "units": [], "coverage": {}, "raw": txt}
    m = re.search(r"^spec:\s*(\S+)", txt, re.M)
    if m:
        plan["spec"] = m.group(1)
    blocks = re.split(ps["unit_heading"], txt, flags=re.M)
    if len(blocks) > 1:
        it = iter(blocks[1:])
        for uid, _title, body in zip(it, it, it):
            u = {"id": uid, "owns": [], "tasks": [], "fields": {}}
            om = re.search(r"^owns:\s*$((?:\s*-\s*.+\n?)+)", body, re.M)
            if om:
                u["owns"] = [l.strip().lstrip("-").strip().strip("`")
                             for l in om.group(1).split("\n") if l.strip()]
            u["fields"]["owns"] = u["owns"] or None
            for f in ("tier", "wave", "autonomy"):
                fm2 = re.search(r"^%s:\s*(.+)$" % f, body, re.M)
                u["fields"][f] = fm2.group(1).strip() if fm2 else None
            for line in body.split("\n"):
                if line.count("|") >= 4 and re.search(r"\.T[0-9]{2}", line):
                    cells = [c.strip() for c in line.strip().strip("|").split("|")]
                    if len(cells) >= 3:
                        u["tasks"].append({"id": cells[0], "action": cells[1],
                                           "verify": cells[2]})
            plan["units"].append(u)
    cm = re.search(r"^##\s*Coverage matrix\s*$([\s\S]*?)(?=^##\s|\Z)", txt, re.M)
    if cm:
        for line in cm.group(1).split("\n"):
            if line.count("|") >= 2:
                cells = [c.strip() for c in line.strip().strip("|").split("|")]
                if len(cells) >= 2 and re.match(F["ids"]["acceptance_criterion"], cells[0]):
                    plan["coverage"][cells[0]] = cells[1]
    return plan


def _static_prefix(glob):
    out = []
    for part in glob.split("/"):
        if any(ch in part for ch in "*?["):
            break
        out.append(part)
    return "/".join(out)


def gate_8(run_id):
    ps = F["plan_schema"]
    path = rp("runs", run_id, "PLAN.md")
    if not os.path.isfile(path):
        return False, ["no PLAN.md at runs/%s/PLAN.md" % run_id]
    plan = _parse_plan(path)
    msgs = []
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

    # (c) every auto task has a verify command
    for u in plan["units"]:
        for t in u["tasks"]:
            v = t["verify"]
            if not v or v in ("-", "—", "TBD"):
                msgs.append("%s task %s has no verify command" % (u["id"], t["id"]))
            elif v.startswith(ps["task_verify_exempt_marker"]):
                if "owner=" not in v:
                    msgs.append("%s task %s is MANUAL but names no owner=" % (u["id"], t["id"]))
        for f, spec in ps["unit_fields"].items():
            if spec["required"] and not u["fields"].get(f):
                msgs.append("%s is missing required field '%s:'" % (u["id"], f))

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
            acs = set()
            for line in spec_txt.split("\n"):
                if line.count("|") >= 2:
                    c = [x.strip() for x in line.strip().strip("|").split("|")]
                    if c and re.match(F["ids"]["acceptance_criterion"], c[0]):
                        acs.add(c[0])
            unmapped = sorted(acs - set(plan["coverage"].keys()))
            if unmapped:
                msgs.append("coverage matrix is not total: %d AC(s) unmapped: %s"
                            % (len(unmapped), ", ".join(unmapped)))
            for ac, tasks in plan["coverage"].items():
                if not tasks.strip() or tasks.strip() in ("-", "—"):
                    msgs.append("coverage matrix maps %s to no task" % ac)
    return (len(msgs) == 0), msgs


# --------------------------------------------------------------------------
# GATE-9 — gate-closure record
# --------------------------------------------------------------------------
def gate_9(artifacts=None):
    pat = F["jira_mapping"]["signoff_record"]
    msgs = []
    if artifacts is None:
        artifacts = [f for f in tracked_files() + _untracked_matching(("docs/spec/*.md",))
                     if fnmatch.fnmatch(f, "docs/spec/*.md")]
        artifacts += [f for f in _untracked_matching(("runs/*/PLAN.md",))]
        artifacts = sorted(set(artifacts))
    for a in artifacts:
        txt = read(rp(a))
        if not txt:
            continue
        head = "\n".join(txt.split("\n")[:25])
        claims_signed = re.search(F["jira_mapping"]["signed_status_token"], head, re.M)
        has_record = re.search(pat, head, re.M)
        if claims_signed and not has_record:
            msgs.append("%s claims SIGNED but has no 'signed: <date> ev:jira{KEY-nn}' record" % a)
        if has_record and not claims_signed:
            msgs.append("%s carries a signed: record but its status is not SIGNED" % a)
    return (len(msgs) == 0), msgs


# --------------------------------------------------------------------------
# GATE-10 — divergence diff produced and fully classified
# --------------------------------------------------------------------------
def gate_10(run_id, gate):
    jm = F["jira_mapping"]
    rel = jm["divergence_record"].format(run_id=run_id, gate=gate)
    p = rp(rel)
    if not os.path.isfile(p):
        return False, ["no divergence record at %s. GATE-10 requires the git-Jira diff at gate "
                       "open; if MCP was unavailable, record the deferral there and in "
                       "jira-queue.md" % rel]
    rows, unclassified = 0, []
    for i, line in enumerate(lines_of(p), 1):
        if line.count("|") >= 3 and not re.match(r"^\s*\|[\s:-]+\|", line):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if not cells or cells[0].lower() in ("item", "artifact", ""):
                continue
            rows += 1
            if not any(c in jm["classifications"] for c in cells):
                unclassified.append("%s:%d %s" % (rel, i, cells[0]))
    if rows == 0:
        if re.search(r"^\s*no divergences?\b", read(p), re.M | re.I):
            return True, ["%s records no divergences" % rel]
        return False, ["%s has no divergence rows and no explicit 'no divergences' statement" % rel]
    if unclassified:
        return False, ["%d divergence(s) unclassified (need one of %s): %s"
                       % (len(unclassified), "/".join(jm["classifications"]),
                          "; ".join(unclassified[:5]))]
    return True, ["%d divergence(s), all classified" % rows]


# --------------------------------------------------------------------------
# dispatch
# --------------------------------------------------------------------------
def run_gate(name, args):
    if name == "gate-1":
        return gate_1(args[0])
    if name == "gate-2":
        return gate_2(run_id=_opt(args, "--run"), spec=_opt(args, "--spec"))
    if name == "gate-3":
        return gate_3(_list_opt(args, "--paths") or None)
    if name == "gate-4":
        return gate_4(run_id=_opt(args, "--run"))
    if name == "gate-5":
        paths = staged_files() if "--staged" in args else _list_opt(args, "--paths")
        if not paths and not ("--staged" in args):
            paths = gate3_targets()
        return gate_5(paths)
    if name == "gate-6":
        return gate_6(area=_opt(args, "--area"), run_id=_opt(args, "--run"),
                      deps=(_list_opt(args, "--deps") or None),
                      probe=("--no-probe" not in args))
    if name == "gate-7":
        return gate_7()
    if name == "gate-8":
        return gate_8(_opt(args, "--run"))
    if name == "gate-9":
        return gate_9(_list_opt(args, "--paths") or None)
    if name == "gate-10":
        return gate_10(_opt(args, "--run"), _opt(args, "--gate") or "G2")
    if name == "gate-11":
        paths = staged_files() if "--staged" in args else _list_opt(args, "--paths")
        return gate_11(paths)
    return False, ["unknown gate %s" % name]


def _opt(args, flag):
    if flag in args:
        i = args.index(flag)
        if i + 1 < len(args):
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


SWEEP = ["gate-2", "gate-3", "gate-4", "gate-5", "gate-9"]


def main(argv):
    quiet = "--quiet" in argv
    if quiet:
        argv = [a for a in argv if a != "--quiet"]
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        print("usage: gates.sh <gate-1..gate-11|sweep|list> [options]")
        return 0
    cmd, args = argv[0], argv[1:]
    if cmd == "list":
        for g, meta in sorted(F["gates"].items(), key=lambda kv: int(kv[0].split("-")[1])):
            inert = meta.get("inert_when")
            print("%-8s %-18s blocks %-14s %s"
                  % (g, meta["where"], meta["blocks"], ("inert when " + inert) if inert else ""))
        return 0
    if cmd == "sweep":
        run_id = _opt(args, "--run")
        failed, total = [], 0
        for g in SWEEP:
            a = list(args)
            if g in ("gate-2", "gate-4") and run_id:
                a = ["--run", run_id]
            elif g in ("gate-2", "gate-4"):
                a = []
            else:
                a = []
            ok, msgs = run_gate(g, a)
            total += 1
            status = "PASS" if ok else "FAIL"
            print("%s %s" % (status, g))
            for m in msgs:
                print("     %s" % m)
            if not ok:
                failed.append(g)
                log_rejection(g, msgs)
        print("\nsweep: %d/%d passed" % (total - len(failed), total))
        return 1 if failed else 0
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
