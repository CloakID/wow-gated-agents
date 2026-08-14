#!/usr/bin/env node
// WoW v2 — derived status. There is no persistent narrative state: everything
// here is computed from the repo on each run. Continuity is runs/<id>/HANDOFF.md;
// history is git.
//
// Patterns, vocabulary and schemas come from formats.json — the same file gates.sh
// consumes, so enforcement and status derivation cannot disagree about a format.
//
//   status.mjs              human summary
//   status.mjs --json       machine output
//   status.mjs --run <id>   scope counters to one run

import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const F = JSON.parse(readFileSync(join(HERE, 'formats.json'), 'utf8'));

function git(...args) {
  try { return execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }); }
  catch { return ''; }
}
let ROOT = HERE;
try {
  ROOT = execFileSync('git', ['rev-parse', '--show-toplevel'],
    { cwd: HERE, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
} catch { ROOT = join(HERE, '..', '..'); }

const rp = (...p) => join(ROOT, ...p);
const read = (p) => { try { return readFileSync(p, 'utf8'); } catch { return ''; } };
const lsdir = (p) => { try { return readdirSync(p); } catch { return []; } };

const args = process.argv.slice(2);
const asJson = args.includes('--json');
const runFilter = args.includes('--run') ? args[args.indexOf('--run') + 1] : null;

// ---------------------------------------------------------------- installation
function installation() {
  const want = {
    'gates.sh': 'scripts/wow/gates.sh',
    'gates.py': 'scripts/wow/gates.py',
    'formats.json': 'scripts/wow/formats.json',
    'status.mjs': 'scripts/wow/status.mjs',
    'wow.config.json': 'scripts/wow/wow.config.json',
    'permissions-policy.json': 'scripts/wow/permissions-policy.json',
    'GATES-SPEC.md': 'scripts/wow/GATES-SPEC.md',
    'tests/': 'scripts/wow/tests',
  };
  const present = {}, missing = [];
  for (const [k, v] of Object.entries(want)) {
    present[k] = existsSync(rp(v));
    if (!present[k]) missing.push(k);
  }
  const common = git('rev-parse', '--git-common-dir').trim() || '.git';
  const hooksDir = common.startsWith('/') ? join(common, 'hooks') : rp(common, 'hooks');
  const hooks = {};
  for (const h of ['commit-msg', 'pre-commit']) {
    const p = join(hooksDir, h);
    hooks[h] = existsSync(p) && read(p).includes('gates.sh');
    if (!hooks[h]) missing.push(`hook:${h}`);
  }
  const gateIds = Object.keys(F.gates);
  const untested = gateIds.filter(g => !existsSync(rp('scripts/wow/tests', `test-${g.toLowerCase()}.sh`)));
  return { present, hooks, missing, gates: gateIds.length, untested };
}

// ---------------------------------------------------------------- requirements
function requirements() {
  const schema = F.requirements_row_schema;
  const rowRe = new RegExp(schema.row.replace(/\(\?P<\w+>/g, '('));
  const vocab = F.status_vocab.allowed;
  const evRe = new RegExp(F.evidence.any);
  const counts = Object.fromEntries(vocab.map(v => [v, 0]));
  const rows = [];
  let uncited = 0;
  for (const line of read(rp(schema.file)).split('\n')) {
    const m = line.match(rowRe);
    if (!m) continue;
    const id = m[1];
    const cells = line.split('|').map(c => c.trim());
    const status = cells.find(c => vocab.includes(c.replace(/[*`]/g, '').toUpperCase()));
    const s = status ? status.replace(/[*`]/g, '').toUpperCase() : null;
    if (s) counts[s]++;
    if (s && schema.evidence_required_for.includes(s) && !evRe.test(line)) uncited++;
    rows.push({ id, status: s });
  }
  return { total: rows.length, counts, uncited, rows };
}

// ----------------------------------------------------------------------- specs
function specs() {
  const dir = rp('docs/spec');
  const signRe = new RegExp(F.jira_mapping.signoff_record, 'm');
  return lsdir(dir).filter(f => f.endsWith('.md')).map(f => {
    const txt = read(join(dir, f));
    const head = txt.split('\n').slice(0, 25).join('\n');
    const st = head.match(/^status:\s*(.+)$/m);
    const sg = head.match(signRe);
    const acs = new Set();
    for (const line of txt.split('\n')) {
      if ((line.match(/\|/g) || []).length >= 2) {
        const c = line.replace(/^\||\|$/g, '').split('|').map(x => x.trim());
        if (c[0] && new RegExp(F.ids.acceptance_criterion).test(c[0])) acs.add(c[0]);
      }
    }
    const schemaOk = new RegExp(F.ids.spec_file).test(f);
    return { file: f, status: st ? st[1].trim() : '(none)', signed: !!sg,
             acs: acs.size, nameValid: schemaOk };
  });
}

// ------------------------------------------------------------------------ runs
function runs() {
  const dir = rp('runs');
  const out = [];
  for (const d of lsdir(dir)) {
    if (['quick', 'debug', 'archive'].includes(d) || d.startsWith('.')) continue;
    if (!new RegExp(F.ids.run).test(d)) continue;
    if (runFilter && d !== runFilter) continue;
    const rd = join(dir, d);
    const handoff = read(join(rd, 'HANDOFF.md'));
    const report = read(join(rd, 'RUN-REPORT.md'));
    const pos = handoff.match(/^##\s*position\s*$([\s\S]*?)(?=^##|\Z)/m);
    const handoffLines = handoff ? handoff.split('\n').length : 0;
    const counts = {};
    for (const v of F.status_vocab.allowed) {
      counts[v] = (report.match(new RegExp(`\\b${v}\\b`, 'g')) || []).length;
    }
    const ids = {};
    for (const [k, pat] of Object.entries({ deviation: F.ids.deviation, park: F.ids.park,
      verifier_finding: F.ids.verifier_finding, plan_defect: F.ids.plan_defect,
      cannot_validate: F.ids.cannot_validate })) {
      const all = (report + handoff).match(new RegExp(pat.replace(/^\^|\$$/g, ''), 'g')) || [];
      ids[k] = new Set(all).size;
    }
    out.push({
      id: d,
      position: pos ? pos[1].trim().split('\n').filter(Boolean)[0] : '(no position recorded)',
      handoffLines,
      handoffOverLimit: handoffLines > F.runs_layout.handoff_max_lines,
      hasPlan: existsSync(join(rd, 'PLAN.md')),
      hasReport: !!report,
      constraintsOpen: (handoff.match(/^\s*-\s*\[ \]/gm) || []).length,
      statuses: counts,
      ids,
      reports: lsdir(join(rd, 'reports')).filter(f => f.endsWith('.md')).length,
    });
  }
  return out;
}

// ---------------------------------------------------------------- quick / debug
function lanes() {
  const q = [];
  const qd = rp('runs/quick');
  for (const slug of lsdir(qd)) {
    const note = join(qd, slug, 'NOTE.md');
    if (!existsSync(note)) continue;
    const txt = read(note);
    const m = txt.match(/^#+\s*result\s*$([\s\S]*?)(?=^#|\Z)/mi);
    const empty = !m || m[1].trim() === '';
    const ageDays = (Date.now() - statSync(note).mtimeMs) / 86400000;
    q.push({ slug, empty, ageDays: Math.round(ageDays),
             stale: empty && ageDays > F.runs_layout.quick_stale_days });
  }
  const open = lsdir(rp('runs/debug')).filter(f => f.endsWith('.md'));
  const resolved = lsdir(rp('runs/debug/resolved')).filter(f => f.endsWith('.md'));
  return { quick: q, debugOpen: open, debugResolved: resolved.length };
}

// -------------------------------------------------------------- audit triggers
function auditTriggers(rs) {
  const t = F.audit_triggers;
  const derived = {};
  const changed = runFilter ? [] : git('diff', '--name-only', 'HEAD~1..HEAD').split('\n').filter(Boolean);
  derived['AT-1'] = { metric: t['AT-1'].metric, value: null,
    note: 'not derivable from the repo alone — the ORCH records mocks/fixtures added in RUN-REPORT' };
  derived['AT-2'] = { metric: t['AT-2'].metric, value: rs.length ? Math.max(...rs.map(r => {
    const m = r.id.match(/-r([0-9]+)$/); return m ? parseInt(m[1], 10) - 1 : 0; })) : 0 };
  derived['AT-3'] = { metric: t['AT-3'].metric,
    value: rs.reduce((a, r) => a + (r.statuses.BLOCKED || 0), 0) };
  derived['AT-4'] = { metric: t['AT-4'].metric, value: null,
    note: 'derived by gates.sh gate-5 sweep over unmodified docs' };
  derived['AT-5'] = { metric: t['AT-5'].metric, value: null,
    note: 'a judgment call — recorded by the PO at G4, never derived' };
  for (const [k, v] of Object.entries(derived)) {
    const cfgT = t[k];
    v.threshold = cfgT.threshold; v.comparator = cfgT.comparator;
    v.hit = v.value === null ? null
      : (cfgT.comparator === '>' ? v.value > cfgT.threshold : v.value >= cfgT.threshold);
  }
  return derived;
}

// ---------------------------------------------------------------------- render
const data = {
  repo: relative(dirname(ROOT), ROOT),
  install: installation(),
  requirements: requirements(),
  specs: specs(),
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
out.push(`  hooks: ${Object.entries(i.hooks).map(([k, v]) => `${k}=${v ? 'installed' : 'MISSING'}`).join('  ')}`);
out.push('');

out.push(B('Requirements') + dim('  (technical status — Jira holds workflow status)'));
const r = data.requirements;
out.push(`  ${r.total} row(s): ` + Object.entries(r.counts).filter(([, v]) => v)
  .map(([k, v]) => `${k}=${v}`).join('  ') || '  none');
if (r.uncited) out.push(`  ${r.uncited} completion-class row(s) with NO ev: citation — GATE-3 blocks`);
out.push('');

out.push(B('Specs'));
for (const s of data.specs) {
  out.push(`  ${s.file}  ${s.status}  ${s.signed ? 'signed' : dim('unsigned')}  ${s.acs} AC(s)` +
    (s.nameValid ? '' : '  NAME DOES NOT MATCH SCHEMA'));
}
if (!data.specs.length) out.push(dim('  none'));
out.push('');

out.push(B('Runs'));
for (const rr of data.runs) {
  out.push(`  ${rr.id}`);
  out.push(`    position: ${rr.position}`);
  out.push(`    PLAN=${rr.hasPlan ? 'yes' : 'no'}  RUN-REPORT=${rr.hasReport ? 'yes' : 'no'}  ` +
    `reports=${rr.reports}  open constraints=${rr.constraintsOpen}`);
  const idbits = Object.entries(rr.ids).filter(([, v]) => v).map(([k, v]) => `${k}=${v}`);
  if (idbits.length) out.push(`    ${idbits.join('  ')}`);
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
  const flag = v.hit ? '  HIT' : '';
  out.push(`  ${k} ${v.metric}: ${val}${flag}`);
  if (v.note) out.push(dim(`       ${v.note}`));
}
console.log(out.join('\n'));
