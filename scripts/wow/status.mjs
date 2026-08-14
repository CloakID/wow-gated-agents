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
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const F = JSON.parse(readFileSync(join(HERE, 'formats.json'), 'utf8'));
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
  const hooks = {};
  for (const h of inst.hooks) {
    const p = join(dir, h);
    const body = read(p);
    hooks[h] = existsSync(p) && body.includes(inst.hook_marker);
    if (!hooks[h]) missing.push(`hook:${h}`);
  }
  const gateIds = Object.keys(F.gates);
  const untested = gateIds.filter(g =>
    !existsSync(rp(fill(F.non_vacuity.gate_test_file, { gate: g.toLowerCase() }))));
  const wiringTest = existsSync(rp(F.non_vacuity.install_test_file));
  if (!wiringTest) missing.push('tests/' + F.non_vacuity.install_test_file.split('/').pop());
  return { present, hooks, hooksDir: relative(ROOT, dir) || dir, hooksWhy: why,
           missing, gates: gateIds.length, untested, wiringTest,
           node: process.version, recovery: F.gate_failure_recovery };
}

// ---------------------------------------------------------------- requirements
function requirements() {
  const schema = F.requirements_row_schema;
  const rowRe = rx(schema.row);
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
    const cells = line.split('|').map(c => c.trim());
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
        const c = line.replace(/^\||\|$/g, '').split('|').map(x => x.trim());
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
    const handoff = read(rp(fill(rl.handoff, { run_id: d })));
    const report = read(rp(fill(F.report_row_schema.file, { run_id: d })));
    const posRe = new RegExp(fill(rl.handoff_section_heading, { name: rl.handoff_sections[0] }), 'm');
    const pos = handoff.match(posRe);
    const handoffLines = handoff ? handoff.split('\n').length : 0;
    const counts = {};
    for (const v of F.status_vocab.allowed) {
      counts[v] = (report.match(new RegExp(`\\b${v}\\b`, 'g')) || []).length;
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
  for (const slug of lsdir(qd)) {
    const note = rp(fill(rl.quick, { slug }));
    if (!existsSync(note)) continue;
    const m = read(note).match(resultRe);
    const empty = !m || m[1].trim() === '';
    const ageDays = (Date.now() - statSync(note).mtimeMs) / 86400000;
    q.push({ slug, empty, ageDays: Math.round(ageDays),
             stale: empty && ageDays > rl.quick_stale_days });
  }
  const open = lsdir(rp(rl.debug_dir)).filter(f => f.endsWith('.md'));
  const resolved = lsdir(rp(rl.debug_resolved_dir)).filter(f => f.endsWith('.md'));
  return { quick: q, debugOpen: open, debugResolved: resolved.length };
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
  for (const [k, cfgT] of Object.entries(t)) {
    if (k.startsWith('$')) continue;
    let value = null, note = notes[cfgT.derived_by] || null;
    if (k === 'AT-3') value = rs.reduce((a, r) => a + (r.statuses.BLOCKED || 0), 0);
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
const data = {
  repo: relative(dirname(ROOT), ROOT),
  install: installation(),
  requirements: requirements(),
  specs: specs(),
  claimLabels: claimLabels(),
  runs: runs(),
  lanes: lanes(),
};
data.auditTriggers = auditTriggers(data.runs);

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
if (i.missing.length === 0) out.push(`  complete — ${i.gates} gates, all with negative tests`);
else out.push(`  INCOMPLETE — missing: ${i.missing.join(', ')}`);
if (i.untested.length) out.push(`  gates with NO negative test (inert-gate risk): ${i.untested.join(', ')}`);
if (!i.wiringTest) out.push(`  NO wiring test — gate logic is proved, gate wiring is not`);
out.push(`  hooks in ${i.hooksDir} ${dim('(' + i.hooksWhy + ')')}: ` +
  Object.entries(i.hooks).map(([k, v]) => `${k}=${v ? 'installed' : 'MISSING'}`).join('  '));
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
  ? `  STALE STUBS: ${l.quick.filter(q => q.stale).map(q => q.slug).join(', ')}` : ''));
out.push(`  debug: ${l.debugOpen.length} open, ${l.debugResolved} resolved`);
out.push('');

out.push(B('Audit triggers') + dim('  (P4 — any hit schedules an audit before new feature work)'));
for (const [k, v] of Object.entries(data.auditTriggers)) {
  const val = v.value === null ? dim('not derived') : `${v.value} (${v.comparator}${v.threshold})`;
  out.push(`  ${k} ${v.metric}: ${val}${v.hit ? '  HIT' : ''}`);
  if (v.note) out.push(dim(`       ${v.note}`));
}
console.log(out.join('\n'));
