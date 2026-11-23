/**
 * dynamic-farm-audit --snapshot <dir> --dataset <dir> --out <dir> [--params file.json] [--quiet]
 * Writes <out>/audit-report.json and <out>/audit-summary.md. Exit 0 = pass or warn, 1 = fail, 2 = usage.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { auditDataset } from './audit.js';
import { resolveAuditParams } from './config.js';
import { loadDataset, loadSnapshot, sha256 } from './inputs.js';
import { summaryMarkdown } from './summary.js';

function args(argv: string[]): Record<string, string | true> {
  const out: Record<string, string | true> = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) throw new Error(`unexpected argument ${a}`);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) out[a.slice(2)] = true;
    else { out[a.slice(2)] = next; i++; }
  }
  return out;
}

function main(): number {
  let opts: Record<string, string | true>;
  try {
    opts = args(process.argv.slice(2));
    for (const k of Object.keys(opts)) if (!['snapshot', 'dataset', 'out', 'params', 'quiet'].includes(k)) throw new Error(`unknown option --${k}`);
    for (const k of ['snapshot', 'dataset', 'out']) if (typeof opts[k] !== 'string') throw new Error(`--${k} <dir> is required`);
  } catch (error) {
    console.error(`${(error as Error).message}\nusage: dynamic-farm-audit --snapshot <dir> --dataset <dir> --out <dir> [--params file.json] [--quiet]`);
    return 2;
  }
  const params = resolveAuditParams(typeof opts.params === 'string' ? JSON.parse(readFileSync(opts.params, 'utf8')) : {});
  const snapshot = loadSnapshot(opts.snapshot as string);
  const datasetDir = opts.dataset as string;
  const dataset = loadDataset(datasetDir);
  const manifestSha = sha256(readFileSync(path.join(datasetDir, 'manifest.json')));
  const report = auditDataset(snapshot, dataset, manifestSha, params, opts.quiet ? () => {} : s => console.log(s));
  const out = opts.out as string;
  if (!existsSync(out)) mkdirSync(out, { recursive: true });
  writeFileSync(path.join(out, 'audit-report.json'), `${JSON.stringify(report, null, 2)}\n`);
  const md = summaryMarkdown(report);
  writeFileSync(path.join(out, 'audit-summary.md'), md);
  console.log(md);
  return report.status === 'fail' ? 1 : 0;
}

process.exitCode = main();
