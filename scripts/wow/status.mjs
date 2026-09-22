#!/usr/bin/env node
// WoW v2 — derived status. There is no persistent narrative state: everything
// here is computed from the repo on each run. Continuity is runs/<id>/HANDOFF.md;
// history is git.
//
// Patterns, vocabulary, paths and schemas come from formats.json — the same file
// gates.sh consumes, so enforcement and status derivation cannot disagree about a
// format. Nothing here may hardcode a path or a section name that lives there.
//
//   status.mjs              human summary
//   status.mjs --json       machine output
//   status.mjs --run <id>   scope counters to one run

import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname, isAbsolute, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const F = (() => {
  // F-46/F-39 (v0.7.1): {run_core} and {task_tail} are the single source of
  // the run-id grammar, expanded identically by both engines at load.
  const raw = JSON.parse(readFileSync(join(HERE, 'formats.json'), 'utf8'));
  const subs = [['{run_date}', raw.ids.run_date], ['{run_slug}', raw.ids.run_slug],
    ['{run_iter}', raw.ids.run_iter]];
  const sub = (str, pairs) => pairs.reduce((acc, [k, v]) => acc.split(k).join(v), str);
  subs.push(['{run_core}', sub(raw.ids.run_core, subs)], ['{task_tail}', raw.ids.task_tail]);
  const walk = (n) => typeof n === 'string' ? sub(n, subs)
    : Array.isArray(n) ? n.map(walk)
    : (n && typeof n === 'object') ? Object.fromEntries(Object.entries(n).map(([k, v]) => [k, walk(v)]))
    : n;
  return walk(raw);
})();
const P = F.paths;

let ROOT = HERE;
try {
  ROOT = execFileSync('git', ['rev-parse', '--show-toplevel'],
    { cwd: HERE, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
} catch { ROOT = join(HERE, '..', '..'); }

function git(...args) {
  try { return execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }); }
  catch { return ''; }
}
const rp = (...p) => join(ROOT, ...p);
const read = (p) => { try { return readFileSync(p, 'utf8'); } catch { return ''; } };
const lsdir = (p) => { try { return readdirSync(p); } catch { return []; } };
// formats.json holds python-flavoured named groups; JS wants plain groups.
const rx = (pat, flags) => new RegExp(String(pat).replace(/\(\?P<\w+>/g, '('), flags);
const fill = (tpl, vars) => Object.entries(vars)
  .reduce((s, [k, v]) => s.split(`{${k}}`).join(v), tpl);
// ADV-R9-02 (v0.7.3 R9): `split('|').slice(1,-1)` dropped the LAST cell of a
// row without a trailing pipe (legal GFM) and split on escaped pipes Python's
// _cells honors (F-18) — two BLOCKED rows counted as one and AT-3 reported a
// real hit green. Same semantics as gates.py _cells: strip outer pipes, split
// on unescaped |, keep every field, unescape \| into cell content.
const cellsOf = (l) => l.trim().replace(/^\|+|\|+$/g, '')
  .split(/(?<!\\)\|/).map(c => c.trim().replace(/\\\|/g, '|'));
// ADV-R10-03 (v0.7.3 R9b): blank the content of fenced code blocks (``` and
// ~~~, the opener token closing only its own kind) so a fenced '# comment'
// cannot terminate a section regex at either consumer — same discipline as
// gates.py _strip_fenced_blocks.
const stripFencedBlocks = (t) => {
  const out = []; let fence = null;
  for (const ln of t.split('\n')) {
    const m = ln.match(/^\s{0,3}(`{3,}|~{3,})/);
    if (fence === null) {
      if (m) { fence = m[1][0]; out.push(''); continue; }
      out.push(ln);
    } else {
      if (m && m[1][0] === fence) fence = null;
      out.push('');
    }
  }
  return out.join('\n');
};

// wow.config.json is repo-local truth (never overwritten by install). PF-d:
// `requirement_id` may override ids.requirement — status.mjs is GATE-2's dual
// consumer and must honor the same effective pattern, or enforcement and
// status derivation disagree about what a requirement row is.
let CFG = {};
try { CFG = JSON.parse(readFileSync(join(HERE, 'wow.config.json'), 'utf8')); } catch { CFG = {}; }
const reqIdPattern = () => CFG.requirement_id || F.ids.requirement;

const args = process.argv.slice(2);
const asJson = args.includes('--json');
const runFilter = args.includes('--run') ? args[args.indexOf('--run') + 1] : null;

// ---------------------------------------------------------------- installation
function hooksDir() {
  // The directory git ACTUALLY reads. Reporting on .git/hooks while the repo set
  // core.hooksPath is how a repo with zero enforcement reported a healthy install.
  const configured = git('config', '--get', 'core.hooksPath').trim();
  if (configured) {
    return { dir: isAbsolute(configured) ? configured : rp(configured), why: 'core.hooksPath' };
  }
  const common = git('rev-parse', '--git-common-dir').trim() || '.git';
  return { dir: isAbsolute(common) ? join(common, 'hooks') : rp(common, 'hooks'),
           why: 'common git dir (inherited by worktrees)' };
}

function installation() {
  const inst = F.install;
  const want = {};
  for (const f of inst.engine_files) want[f] = f;
  for (const d of inst.engine_dirs) want[d + '/'] = d;
  want[inst.config_file] = inst.config_file;
  const present = {}, missing = [];
  for (const [label, path] of Object.entries(want)) {
    present[label] = existsSync(rp(path));
    if (!present[label]) missing.push(label);
  }
  const { dir, why } = hooksDir();
  const hooks = {}, hookState = {};
  for (const h of inst.hooks) {
    const p = join(dir, h);
    const body = read(p);
    // prodsim/F-77 (v0.7.4): 'MISSING' conflated two states and sent an
    // investigation the wrong way — a mechanism states its subject: ABSENT
    // means no file; FOREIGN means a hook exists and carries no WoW marker
    // (a second installer clobbered ours — the class an old checkout's
    // lifecycle script reproduces at will, since .git/hooks is untracked).
    const state = existsSync(p)
      ? (body.includes(inst.hook_marker) ? 'installed' : 'FOREIGN')
      : 'ABSENT';
    hooks[h] = state === 'installed';        // ADV-R11-10: the boolean API stays
    hookState[h] = state;                    // the subject lives beside it
    if (state !== 'installed') missing.push(`hook:${h} (${state})`);
  }
  const gateIds = Object.keys(F.gates).filter(k => !k.startsWith('$'));
  const untested = gateIds.filter(g =>
    !existsSync(rp(fill(F.non_vacuity.gate_test_file, { gate: g.toLowerCase() }))));
  const wiringTest = existsSync(rp(F.non_vacuity.install_test_file));
  if (!wiringTest) missing.push('tests/' + F.non_vacuity.install_test_file.split('/').pop());
  return { present, hooks, hookState, hooksDir: relative(ROOT, dir) || dir, hooksWhy: why,
           missing, gates: gateIds.length, untested, wiringTest,
           node: process.version, recovery: F.gate_failure_recovery };
}

// ---------------------------------------------------------------- requirements
function requirements() {
  const schema = F.requirements_row_schema;
  const rowRe = rx(fill(schema.row, { req: reqIdPattern().replace(/^\^|\$$/g, '') }));
  const vocab = F.status_vocab.allowed;
  const evRe = new RegExp(F.evidence.any);
  const deco = new RegExp(F.status_vocab.cell_decoration, 'g');
  const counts = Object.fromEntries(vocab.map(v => [v, 0]));
  const rows = [];
  let uncited = 0;
  for (const line of read(rp(schema.file)).split('\n')) {
    const m = line.match(rowRe);
    if (!m) continue;
    const id = m[1];
    const cells = cellsOf(line);   // ADV-R10-12: _cells semantics everywhere
    const status = cells.find(c => vocab.includes(c.replace(deco, '').toUpperCase()));
    const s = status ? status.replace(deco, '').toUpperCase() : null;
    if (s) counts[s]++;
    if (s && schema.evidence_required_for.includes(s) && !evRe.test(line)) uncited++;
    rows.push({ id, status: s });
  }
  return { total: rows.length, counts, uncited, rows };
}

// ----------------------------------------------------------------------- specs
function specs() {
  const jm = F.jira_mapping;
  const dir = rp(P.specs_dir);
  const signRe = new RegExp(jm.signoff_record, 'm');
  const statusRe = new RegExp(jm.status_header, 'm');
  const acRe = new RegExp(F.ids.acceptance_criterion);
  return lsdir(dir).filter(f => f.endsWith('.md')).map(f => {
    const txt = read(join(dir, f));
    const head = txt.split('\n').slice(0, jm.header_lines).join('\n');
    const st = head.match(statusRe);
    const acs = new Set();
    for (const line of txt.split('\n')) {
      if ((line.match(/\|/g) || []).length >= 2) {
        const c = cellsOf(line);   // ADV-R10-12: _cells semantics everywhere
        if (c[0] && acRe.test(c[0])) acs.add(c[0]);
      }
    }
    return { file: f, status: st ? st[1].trim() : '(none)', signed: !!head.match(signRe),
             acs: acs.size, nameValid: new RegExp(F.ids.spec_file).test(f) };
  });
}

// ------------------------------------------------------------------ claim labels
function claimLabels() {
  // FORMATS §2 is a CONVENTION: reported, never gated. formats.json says so, and
  // this is the report it exists for.
  const counts = {};
  const files = [];
  for (const g of F.scan_targets.gated_docs) {
    const dir = g.includes('/') ? g.slice(0, g.lastIndexOf('/')) : '.';
    if (dir.includes('*')) {
      const base = dir.slice(0, dir.indexOf('*')).replace(/\/$/, '');
      for (const sub of lsdir(rp(base))) files.push(join(rp(base), sub));
    } else if (existsSync(rp(g))) files.push(rp(g));
  }
  const texts = files.flatMap(f => {
    try { return statSync(f).isDirectory()
      ? lsdir(f).filter(x => x.endsWith('.md')).map(x => read(join(f, x)))
      : [read(f)]; } catch { return []; }
  });
  for (const [k, pat] of Object.entries(F.claim_labels.patterns)) {
    counts[k] = texts.reduce((a, t) => a + (t.match(new RegExp(pat, 'g')) || []).length, 0);
  }
  return { gated: F.claim_labels.gated, counts };
}

// ------------------------------------------------------------------------ runs
function runs() {
  const rl = F.runs_layout;
  const dir = rp(P.runs_dir);
  const runRe = new RegExp(F.ids.run);
  const out = [];
  for (const d of lsdir(dir)) {
    if (rl.reserved_dirs.includes(d) || d.startsWith('.')) continue;
    if (!runRe.test(d)) continue;
    if (runFilter && d !== runFilter) continue;
    const rd = join(dir, d);
    // frisbii S-6 + its v0.6.4 addendum: one git question is not enough.
    // Tracked file => a run. No tracked but an untracked-UNIGNORED file => a
    // run somebody is mid-creating (must stay listed). Neither => a leftover
    // from archiving — a stray .DS_Store or ignored scratch must not keep a
    // phantom listed (the reported defect wearing a new label).
    const relRun = relative(ROOT, rd);
    if (!git('ls-files', '--', relRun).trim()
        && !git('ls-files', '--others', '--exclude-standard', '--', relRun).trim()) continue;
    const handoff = read(rp(fill(rl.handoff, { run_id: d })));
    const report = read(rp(fill(F.report_row_schema.file, { run_id: d })));
    const posRe = new RegExp(fill(rl.handoff_section_heading, { name: rl.handoff_sections[0] }), 'm');
    const pos = handoff.match(posRe);
    // Count as wc -l does: a POSIX text file ends with a newline, and the
    // split's trailing empty element is that newline, not an 81st line —
    // pre-fix, "80" meant 79 and no conforming file could reach the stated
    // limit (frisbii off-by-one, v0.6.2). The limit itself is ADVISORY (PO
    // 2026-08-24): reported here, acted on by no gate.
    const hLines = handoff ? handoff.split('\n') : [];
    if (hLines.length && hLines[hLines.length - 1] === '') hLines.pop();
    const handoffLines = hLines.length;
    // prodsim/F-75 (v0.7.3, ADV-4): a document-wide word match made writing
    // ABOUT a status change the count of it — an amendment explaining what
    // AT-3 counts flipped AT-3 to HIT, and quoting prior text (the honesty
    // contract) inflated the metric being amended. Statuses are counted in
    // TABLE ROWS (status column by header where one resolves — gate-3's own
    // convention; whole row otherwise; blockquoted rows excluded by the
    // ^\s*\| anchor) plus status_prefix sentences outside fences and code
    // spans, which FORMATS sanctions as claims.
    const counts = {};
    for (const v of F.status_vocab.allowed) counts[v] = 0;
    {
      let inFence = false, statusIdx = null, headerCells = null;
      const statusCols = F.status_vocab.status_columns.map(c => c.toLowerCase());
      const prefixRe = new RegExp(F.status_vocab.status_prefix, 'i');
      const stripSpans = (l) => l.replace(/`[^`]*`/g, '');
      for (const rawLine of report.split('\n')) {
        const line = rawLine;
        if (/^\s*```/.test(line)) { inFence = !inFence; continue; }
        if (inFence) continue;
        if (!line.trim()) { statusIdx = null; headerCells = null; continue; }
        if (/^\s*\|/.test(line)) {
          const cells = cellsOf(line);
          if (/^\s*\|[\s:|-]+\|\s*$/.test(line)) {
            if (headerCells) {
              statusIdx = headerCells.findIndex(h => statusCols.includes(h.toLowerCase()));
              if (statusIdx < 0) statusIdx = null;
            }
            continue;
          }
          const scope = statusIdx !== null && statusIdx < cells.length
            ? [cells[statusIdx]] : cells;
          for (const cell of scope) {
            const bare = stripSpans(cell);
            for (const v of F.status_vocab.allowed) {
              if (new RegExp(`\\b${v}\\b`).test(bare)) counts[v] += 1;
            }
          }
          headerCells = cells;
          continue;
        }
        const m = stripSpans(line).match(prefixRe);
        if (m) {
          const word = (m[2] || '').toUpperCase();
          if (word in counts) counts[word] += 1;
        }
      }
    }
    const missingSections = F.report_row_schema.sections.filter(
      s => report && !new RegExp(`^#+\\s*${s}\\b`, 'mi').test(report));
    const ids = {};
    for (const k of ['deviation', 'park', 'verifier_finding', 'plan_defect', 'cannot_validate']) {
      const all = (report + handoff).match(new RegExp(F.ids[k].replace(/^\^|\$$/g, ''), 'g')) || [];
      ids[k] = new Set(all).size;
    }
    out.push({
      id: d,
      position: pos ? pos[1].trim().split('\n').filter(Boolean)[0] : '(no position recorded)',
      handoffLines,
      handoffOverLimit: handoffLines > rl.handoff_max_lines,
      hasPlan: existsSync(rp(fill(F.plan_schema.file, { run_id: d }))),
      hasReport: !!report,
      missingReportSections: report ? missingSections : [],
      constraintsOpen: (handoff.match(new RegExp(rl.open_checkbox, 'gm')) || []).length,
      statuses: counts,
      ids,
      branches: ['base', 'unit', 'integration'].filter(k =>
        git('branch', '--list', '--format=%(refname:short)').split('\n')
          .some(b => new RegExp(F.branch_patterns[k]).test(b.trim()) && b.includes(d))).join(','),
      reports: lsdir(join(rd, 'reports')).filter(f => f.endsWith('.md')).length,
    });
  }
  return out;
}

// ---------------------------------------------------------------- quick / debug
function lanes() {
  const rl = F.runs_layout;
  const q = [];
  const qd = rp(rl.quick_dir);
  const resultRe = new RegExp(rl.quick_result_section, 'mi');
  // DEV-R11-09 (v0.7.4 R11b): a stub a registry row CITES as its proof is not
  // a stale stub whatever its result cell says (platform/F-80's rule, applied
  // to the tool that builds the candidate list — the doc said 'excluded' while
  // the tool still listed it, then refused the deletion it had suggested).
  const registries = [F.gap_row.file, F.paths.requirements].map(f => read(rp(f))).join('\n');
  const citedBy = (path) => {
    const hits = [];
    for (const [i, ln] of registries.split('\n').entries()) {
      if (ln.replace(/`[^`]*`/g, '').includes('ev:file{' + path)) hits.push(i + 1);
    }
    return hits;
  };
  for (const slug of lsdir(qd)) {
    const note = rp(fill(rl.quick, { slug }));
    if (!existsSync(note)) continue;
    const cited = citedBy(fill(rl.quick, { slug }));
    const m = read(note).match(resultRe);
    // platform/F-62 residual (v0.7.2): a pattern that fails to match is an UNREADABLE
    // section, never an empty one — collapsing the two turned a JS-dialect
    // regex miss into a 62-record deletion list a PO had already approved.
    // The subject-absent rule GATES-SPEC states for gates, applied to the
    // deriver: unreadable is reported as its own state and is never stale.
    const unreadable = !m;
    const empty = m ? m[1].trim() === '' : false;
    const ageDays = (Date.now() - statSync(note).mtimeMs) / 86400000;
    q.push({ slug, empty, unreadable, ageDays: Math.round(ageDays), cited,
             stale: empty && ageDays > rl.quick_stale_days && cited.length === 0 });
  }
  const decisionName = rl.debug_decision ? rl.debug_decision.split('/').pop() : null;
  const open = lsdir(rp(rl.debug_dir)).filter(f => f.endsWith('.md') && f !== decisionName);
  const resolved = lsdir(rp(rl.debug_resolved_dir)).filter(f => f.endsWith('.md'));
  // platform/F-81 (v0.7.4): a debug record RENAMED into resolved/ was later
  // "restored" from history as if deleted — two live copies, one slug counted
  // once as open and once as resolved, and the derived view wrong for a day.
  // Two directories holding one lane's records get an intersection test.
  const both = open.filter(f => resolved.includes(f));
  // prodsim/F-80 (v0.7.4): a batch of open records needs a DECISION SURFACE
  // the PO reads instead of the records; its absence is mechanically visible.
  const decision = rl.debug_decision ? rp(rl.debug_decision) : null;
  const decisionPresent = decision ? existsSync(decision) : null;
  return { quick: q, debugOpen: open, debugResolved: resolved.length,
           debugBoth: both, decisionSurface: rl.debug_decision || null, decisionPresent };
}

// -------------------------------------------------------------- audit triggers
function at4Count() {
  // Derived by the gate that owns the citation rule, not re-implemented here.
  const t = F.audit_triggers['AT-4'];
  if (!t.source_command) return null;
  const [cmd, ...rest] = t.source_command;
  if (!existsSync(rp(cmd))) return null;
  try {
    const out = execFileSync(rp(cmd), runFilter ? [...rest, '--run', runFilter] : rest,
      { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    const m = out.match(new RegExp(t.count_pattern));
    return m ? parseInt(m[1], 10) : null;
  } catch (e) {
    const out = (e.stdout || '') + (e.stderr || '');
    const m = out.match(new RegExp(t.count_pattern));
    return m ? parseInt(m[1], 10) : null;
  }
}

function auditTriggers(rs) {
  const t = F.audit_triggers;
  const notes = {
    orch: 'recorded by the ORCH in RUN-REPORT — not derivable from files alone',
    po: 'a judgment call recorded by the PO at G4 — never derived',
  };
  const derived = {};
  // F-34 (v0.6.4): the AT-3 sum was cross-run — BLOCKED tokens accumulated in
  // reports that are never rewritten, so the first run to block twice pinned
  // the trigger HIT forever, and archiving a run CHANGED the number. Scope to
  // the run in question: --run when given, else the newest active run, as the
  // metric's own name (blockers_this_run) and P4's wording both promise.
  const scopeRun = runFilter ? rs.filter(r => r.id === runFilter)
                             : rs.slice(-1);
  // F-33 (v0.6.4): derived_by 'orch' means READ THE DURABLE HOME — the run's
  // RUN-REPORT '## audit triggers' table — never 'give up'. Three of five
  // triggers rendered 'not derived' against numbers that were derived,
  // recorded and cited: PF-03's founding gap, recurring in the file that
  // fixed it.
  // ADV-R9-07 (v0.7.3 R9): this regex was INLINED here (#+) while gate-7's
  // escrow used the ##-only handoff template — '### audit triggers' derived a
  // hit with no escrow row demanded. Both consumers now read the one home.
  const atSec = new RegExp(fill(t.section_heading, { name: t.report_section }), 'mi');
  const atRow = new RegExp(t.report_row, 'm');
  const reported = {};
  // prodsim/F-74 fix 3 (v0.7.3): the deriver states what it SAW, not only
  // what it wanted — 'not recorded, record it there' pointed the operator at
  // a file where the record already was, in a shape the old pattern refused.
  let atRowsSeen = 0, atRowsParsed = 0, atSectionsSeen = 0;
  for (const r of scopeRun) {
    const rep = stripFencedBlocks(read(rp(fill(F.report_row_schema.file, { run_id: r.id }))));
    const sec = rep.match(atSec);   // ADV-R10-03: fenced '#' is not a heading
    if (!sec) continue;
    atSectionsSeen += 1;
    const secLines = sec[1].split('\n');
    for (let i = 0; i < secLines.length; i++) {
      const line = secLines[i];
      const isPipe = /^\s{0,3}\|/.test(line) && !/^\s*\|[\s:|-]+\|\s*$/.test(line);
      // ADV-R9-12 (R9): a header row (the pipe line a separator follows) is
      // not a failed data row — counting it as 'seen' made every healthy
      // table read as one row short of parsing.
      const isHeader = isPipe && /^\s*\|[\s:|-]+\|\s*$/.test(secLines[i + 1] || '');
      if (isPipe && !isHeader) atRowsSeen += 1;
      const m = line.match(atRow);
      if (m) { reported[m[1]] = parseInt(m[2], 10); atRowsParsed += 1; }
    }
  }
  for (const [k, cfgT] of Object.entries(t)) {
    if (k.startsWith('$') || typeof cfgT !== 'object' || !cfgT.metric) continue;
    let value = null, note = notes[cfgT.derived_by] || null;
    if (cfgT.derived_by === 'orch') {
      if (k in reported) { value = reported[k]; note = 'read from RUN-REPORT ## audit triggers (F-33)'; }
      // DEV-R9-09 (v0.7.3 R9): on a repo with no run this diagnostic implied a
      // parse failure the operator should fix — rows-seen/parsed is only said
      // when there was a table to parse.
      else if (scopeRun.length === 0) note = 'no ACTIVE run — the ORCH records it in RUN-REPORT §audit triggers at P4; archived runs are not re-derived (F-36)';
      else if (atSectionsSeen === 0) note = `run has no RUN-REPORT ${t.report_section} section yet — the ORCH records it there at P4 (F-33)`;
      else note = `not parsed from the run RUN-REPORT ## audit triggers table (${atRowsSeen} data row(s) seen, ${atRowsParsed} parsed — a row parses when it starts within 3 spaces of column 0, the AT-id leads cell 1 and an integer leads cell 2; prodsim/F-74)`;
    }
    if (cfgT.derived_by === 'po') {
      // prodsim/F-87e (v0.7.4): F-33's own defect, fixed for orch and left in
      // the po branch of the same function — a PO ruling recorded exactly
      // where the format asks for it (the RUN-REPORT audit-triggers table)
      // was invisible to the tool that reports triggers. A recorded po value
      // is read back; only an UNrecorded one awaits the PO.
      if (k in reported) { value = reported[k]; note = 'PO ruling read from RUN-REPORT §audit triggers (recorded at G4; F-33/F-87e)'; }
      else note = 'awaiting PO at G4 — a judgement, never derived';
    }
    if (k === 'AT-3') value = scopeRun.reduce((a, r) => a + (r.statuses.BLOCKED || 0), 0);
    if (k === 'AT-4') {
      value = at4Count();
      if (value === null) note = `${t['AT-4'].source_command[0]} did not run (python3 missing?)`;
      else note = 'stale file:line refs in docs this run did not modify (gates.sh gate-5 --sweep)';
    }
    derived[k] = { metric: cfgT.metric, value, note,
                   threshold: cfgT.threshold, comparator: cfgT.comparator,
                   hit: value === null ? null
                     : (cfgT.comparator === '>' ? value > cfgT.threshold : value >= cfgT.threshold) };
  }
  return derived;
}

// ---------------------------------------------------------------------- render
// ------------------------------------------------------------ obligations (§12)
// status.mjs answers "what does this state require next", not only "what is the
// state" — the founding gap of PF-03/F-6: an owed audit lived in a signed
// spec's prose, and nothing derived read it.
function obligations() {
  const gr = F.gap_row;
  const p = join(ROOT, gr.file);
  if (!existsSync(p)) return { registry: false, open: [], discharged: 0, problems: [`no ${gr.file}`] };
  const rows = [], problems = [];
  const rowRe = new RegExp(gr.row_start.replace(/^\^/, ''));
  const effRe = new RegExp(gr.effect_cell);
  for (const ln of readFileSync(p, 'utf8').split('\n')) {
    if (!/^\|/.test(ln) || !rowRe.test(ln)) continue;
    const cells = cellsOf(ln);   // ADV-R9-02: same _cells semantics as gates.py
    if (cells.length < gr.columns.length) { problems.push(`short row: ${cells[0] ?? ''}`); continue; }
    const row = Object.fromEntries(gr.columns.map((c, i) => [c, cells[i]]));
    row.open = !new RegExp(gr.discharged_id).test(row.id);
    row.id_plain = row.id.replace(/~~/g, '');
    const m = effRe.exec(row.effect);
    if (!m) { problems.push(`${row.id_plain}: effect outside closed vocabulary: ${row.effect.slice(0, 40)}`); continue; }
    row.effect_value = m[1];
    rows.push(row);
  }
  return {
    registry: true,
    open: rows.filter(r => r.open).map(r => ({ id: r.id_plain, effect: r.effect_value, owner: r.owner, tag: r.tag })),
    discharged: rows.filter(r => !r.open).length,
    problems,
  };
}

const data = {
  repo: relative(dirname(ROOT), ROOT),
  install: installation(),
  requirements: requirements(),
  specs: specs(),
  claimLabels: claimLabels(),
  runs: runs(),
  lanes: lanes(),
  obligations: obligations(),
};
data.auditTriggers = auditTriggers(data.runs);

// prodsim/F-84 (v0.7.4): status.mjs is an engine file the installer
// overwrites, and a consumer with a fact the framework does not model had
// nowhere to surface it but inside this file — lost silently on upgrade.
// Repo-owned extensions live in files the installer never touches:
// wow.config.json `status_extensions` (a list of module paths, default
// ["scripts/status-extras.mjs"] when that file exists), each exporting
// { section, lines } or an async function returning that. A failing
// extension is reported, never swallowed.
const extPaths = Array.isArray(CFG.status_extensions) ? CFG.status_extensions
  : (existsSync(rp('scripts/status-extras.mjs')) ? ['scripts/status-extras.mjs'] : []);
data.extensions = {};
for (const ext of extPaths) {
  const p = rp(ext);
  if (!existsSync(p)) { data.extensions[ext] = { error: 'MISSING — named in wow.config.json status_extensions but not on disk' }; continue; }
  // contract: `export default { section, lines }`, `export default async (ctx) => ({ section, lines })`,
  // or named `export const section = …; export const lines = […]`. Anything else is an ERROR, never an
  // empty section (DEV-R11-10). A module that never settles is a reported timeout, not a hung status
  // (ADV-R11-12); stdout an extension writes is captured so --json stays parseable.
  const realLog = console.log; const swallowed = [];
  console.log = (...a) => { swallowed.push(a.join(' ')); };
  try {
    const timeout = new Promise((_, rej) => setTimeout(() => rej(new Error('extension did not settle within 5s')), 5000).unref());
    const mod = await Promise.race([import(pathToFileURL(p).href), timeout]);
    let val = mod.default;
    if (typeof val === 'function') val = await Promise.race([val({ F, CFG, ROOT, data }), timeout]);
    if (val === undefined && (mod.section !== undefined || mod.lines !== undefined)) val = { section: mod.section, lines: mod.lines };
    if (!val || typeof val !== 'object' || !Array.isArray(val.lines)) {
      throw new Error('no usable export — expected default { section, lines } (or a function returning it), or named `section`/`lines` exports');
    }
    data.extensions[ext] = { section: val.section || ext, lines: val.lines.map(String) };
    if (swallowed.length) data.extensions[ext].note = `extension wrote ${swallowed.length} line(s) to stdout — captured, not rendered`;
  } catch (e) {
    data.extensions[ext] = { error: `FAILED: ${e && e.message ? e.message : e} (reported, not swallowed — prodsim/F-84)` };
  } finally {
    console.log = realLog;
  }
}

if (asJson) {
  console.log(JSON.stringify(data, null, 2));
  process.exit(0);
}

const B = (s) => `\x1b[1m${s}\x1b[0m`;
const dim = (s) => `\x1b[2m${s}\x1b[0m`;
const out = [];
out.push(B(`WoW v2 status — ${data.repo}`));
out.push('');

out.push(B('Installation'));
const i = data.install;
// A6 (audit 2026-09-13): pilots ran v0.6.1 for four releases and every finding
// they filed was against dead code — nothing in their daily loop ever showed
// the installed version, let alone that a newer one existed. This line cannot
// know what upstream has, but it makes the installed version and the check
// command impossible to not see.
out.push(`  engine v${F.version} installed — newer? run install.sh --check from a clone of the package repo`);
// prodsim/F-73 (v0.7.3): every number below is derived from the CURRENT
// CHECKOUT, and a run's state lives on its own branches — the same command on
// two branches gave a resuming agent confident, opposite answers with nothing
// saying which branch either read. The deriver names its subject; when a live
// run owns branches and the checkout is none of them, it says so.
const curBranch = git('rev-parse', '--abbrev-ref', 'HEAD').trim();
out.push(dim(`  derived from checkout: ${curBranch} — figures describe THIS branch only (prodsim/F-73)`));
for (const r of data.runs) {
  if (r.branches && !r.hasReport) {
    const owned = git('branch', '--list', '--format=%(refname:short)').split('\n')
      .filter(b => b.includes(r.id)).map(b => b.trim());
    if (owned.length && !owned.includes(curBranch)) {
      out.push(`  ⚠ run ${r.id} lives on ${owned.join(', ')}; you are on '${curBranch}' — ` +
        `the run's artifacts are NOT in these figures (prodsim/F-73)`);
    }
  }
}
if (i.missing.length === 0) out.push(`  complete — ${i.gates} gates, all with negative tests`);
else out.push(`  INCOMPLETE — missing: ${i.missing.join(', ')}`);
if (i.untested.length) out.push(`  gates with NO negative test (inert-gate risk): ${i.untested.join(', ')}`);
if (!i.wiringTest) out.push(`  NO wiring test — gate logic is proved, gate wiring is not`);
out.push(`  hooks in ${i.hooksDir} ${dim('(' + i.hooksWhy + ')')}: ` +
  Object.entries(i.hookState).map(([k, v]) => `${k}=${v}${v === 'FOREIGN' ? ' (a hook exists and it is not ours — a second installer clobbered the WoW hook; run `scripts/wow/gates.sh hooks --install`, it chains; prodsim/F-77)' : v === 'ABSENT' ? ' (no file — a fresh clone? run `scripts/wow/gates.sh hooks --install`)' : ''}`).join('  '));
out.push(dim(`  recovery: max ${i.recovery.max_fix_forward_attempts} fix-forward attempts, then ${i.recovery.then}` +
  (i.recovery.bypass_allowed ? '' : ' — bypass is never allowed')));
out.push('');

out.push(B('Requirements') + dim('  (technical status — Jira holds workflow status)'));
const r = data.requirements;
out.push(`  ${r.total} row(s): ` + Object.entries(r.counts).filter(([, v]) => v)
  .map(([k, v]) => `${k}=${v}`).join('  ') || '  none');
if (r.uncited) out.push(`  ${r.uncited} row(s) needing evidence with NO ev: citation — GATE-3 blocks`);
out.push('');

out.push(B('Specs'));
for (const s of data.specs) {
  out.push(`  ${s.file}  ${s.status}  ${s.signed ? 'signed' : dim('unsigned')}  ${s.acs} AC(s)` +
    (s.nameValid ? '' : '  NAME DOES NOT MATCH SCHEMA'));
}
if (!data.specs.length) out.push(dim('  none'));
const cl = Object.entries(data.claimLabels.counts).filter(([, v]) => v);
out.push(dim(`  claim labels (convention, not gated): ` +
  (cl.length ? cl.map(([k, v]) => `${k}=${v}`).join('  ') : 'none')));
out.push('');

out.push(B('Runs'));
for (const rr of data.runs) {
  out.push(`  ${rr.id}${rr.branches ? dim('  branches: ' + rr.branches) : ''}`);
  out.push(`    position: ${rr.position}`);
  out.push(`    PLAN=${rr.hasPlan ? 'yes' : 'no'}  RUN-REPORT=${rr.hasReport ? 'yes' : 'no'}  ` +
    `reports=${rr.reports}  open constraints=${rr.constraintsOpen}`);
  const idbits = Object.entries(rr.ids).filter(([, v]) => v).map(([k, v]) => `${k}=${v}`);
  if (idbits.length) out.push(`    ${idbits.join('  ')}`);
  if (rr.missingReportSections.length)
    out.push(`    RUN-REPORT is missing section(s): ${rr.missingReportSections.join(', ')}`);
  if (rr.handoffOverLimit)
    out.push(`    HANDOFF is ${rr.handoffLines} lines, over the ${F.runs_layout.handoff_max_lines}-line limit`);
}
if (!data.runs.length) out.push(dim('  none'));
out.push('');

out.push(B('Lanes'));
const l = data.lanes;
out.push(`  quick: ${l.quick.length}` + (l.quick.filter(q => q.stale).length
  ? `  STALE STUBS: ${l.quick.filter(q => q.stale).map(q => q.slug).join(', ')}` : '')
  + (l.quick.filter(q => q.empty && q.cited.length).length
  ? `  CITED (retain, not stale — platform/F-80): ${l.quick.filter(q => q.empty && q.cited.length).map(q => `${q.slug} by registry line ${q.cited.join('/')}`).join(', ')}` : '')
  + (l.quick.filter(q => q.unreadable).length
  ? `  UNREADABLE result sections (not graded, not stale — platform/F-62): ${l.quick.filter(q => q.unreadable).map(q => q.slug).join(', ')}` : ''));
out.push(`  debug: ${l.debugOpen.length} open, ${l.debugResolved} resolved`
  + (l.debugBoth.length ? `  PHANTOM: ${l.debugBoth.join(', ')} present at BOTH the open and resolved paths — a rename restored as a deletion; delete the open copy (platform/F-81)` : ''));
if (l.debugOpen.length && l.decisionSurface) {
  out.push(l.decisionPresent
    ? `  decision surface: ${l.decisionSurface} (PO decides from this page, not from the records — prodsim/F-80)`
    : `  NO decision surface: ${l.debugOpen.length} open record(s) and no ${l.decisionSurface} — the ORCH owes the PO a one-page classification request (LANES.md, prodsim/F-80)`);
}
out.push('');

out.push(B('Audit triggers') + dim('  (P4 — any hit schedules an audit before new feature work)'));
for (const [k, v] of Object.entries(data.auditTriggers)) {
  const val = v.value === null ? dim('not derived') : `${v.value} (${v.comparator}${v.threshold})`;
  out.push(`  ${k} ${v.metric}: ${val}${v.hit ? '  HIT' : ''}`);
  if (v.note) out.push(dim(`       ${v.note}`));
}

out.push(B('Obligations') + dim('  (docs/GAPS.md — what this state requires next)'));
const ob = data.obligations;
if (!ob.registry) out.push('  NO REGISTRY — gate-12 refuses new feature work until docs/GAPS.md exists');
else {
  const blockingF = ob.open.filter(o => o.effect === 'blocks-new-feature-work');
  const blockingI = ob.open.filter(o => o.effect === 'blocks-install');
  const advisory  = ob.open.filter(o => o.effect === 'advisory');
  if (blockingF.length) out.push(`  BLOCKING new feature work: ${blockingF.map(o => o.id).join(', ')}`);
  if (blockingI.length) out.push(`  BLOCKING install/upgrade: ${blockingI.map(o => o.id).join(', ')}`);
  out.push(`  advisory open: ${advisory.length}   discharged: ${ob.discharged}`);
  for (const pr of ob.problems) out.push(`  MALFORMED: ${pr}`);
  if (!blockingF.length && !blockingI.length && !ob.problems.length)
    out.push(dim('  nothing blocks the next spec or install'));
}
out.push('');

for (const [ext, x] of Object.entries(data.extensions)) {
  if (x.error) { out.push(B(`Extension ${ext}`) + `  ${x.error}`); out.push(''); continue; }
  out.push(B(x.section) + dim('  (repo-owned extension: ' + ext + ')'));
  for (const ln of x.lines) out.push('  ' + ln);
  out.push('');
}

console.log(out.join('\n'));
