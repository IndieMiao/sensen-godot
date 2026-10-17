/**
 * Read-only audit (SGODOT-286 ad0c1580): which saves the first-pick bug left San Francisco visited in, by kind
 * (src/p0/first_pick_visit.ts). Reads a copy of the P0 state file; writes nothing but the report.
 *
 *   node --import tsx tools/audit_first_pick_visits.ts <state copy.json> [<report.json>]
 *
 * Prints the counts only; the player ids go to the report file (default first-pick-audit.json beside the copy).
 */
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { loadP0Content } from '../src/p0/content.js';
import { auditFirstPickVisits } from '../src/p0/first_pick_visit.js';
import type { P0State } from '../src/p0/state.js';

const [file, report = path.join(path.dirname(file ?? '.'), 'first-pick-audit.json')] = process.argv.slice(2);
if (!file) { console.error('usage: audit_first_pick_visits.ts <state copy.json> [<report.json>]'); process.exit(2); }
const saves = JSON.parse(readFileSync(file, 'utf8')) as Record<string, P0State>;
const a = auditFirstPickVisits(loadP0Content(), saves);
const looks = (k: string) => a.changed.filter(x => x.looks === k).length;
console.log(`saves ${Object.keys(saves).length}: never been ${a.never.length}, went later ${a.went.length}, ` +
  `changed home since ${a.changed.length} (first pick ${looks('first_pick')}, played San Francisco ${looks('played_san_francisco')})`);
writeFileSync(report, JSON.stringify(a, null, 2));
console.log(`ids: ${report}`);
