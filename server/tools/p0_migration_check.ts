/**
 * Save migration check for a rehearsal (SGODOT-275, v4 → v5). Reads a copy of a P0 state file, upgrades every
 * player and reports, without writing the file it was given:
 *   - versions before / after;
 *   - fields an upgrade changed or added, per field, with counts (only the expected ones may change);
 *   - that upgrading an upgraded save changes nothing (idempotent) and that it survives a JSON round trip;
 *   - that P0Store keeps a .v<old>.bak copy and reloads its own file unchanged (run on a temp copy).
 * Usage: tsx tools/p0_migration_check.ts <state.json> [--expect travel,v] [--out report.json]
 * Exit 1 when a field outside --expect changed, or an upgrade is not idempotent.
 */
import { copyFileSync, existsSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { loadP0Content } from '../src/p0/content.js';
import { SAVE_VERSION, upgradeState, type P0State } from '../src/p0/state.js';
import { P0Store } from '../src/p0/store.js';

const args = process.argv.slice(2);
const file = args[0];
if (!file || !existsSync(file)) { console.error('usage: p0_migration_check.ts <state.json> [--expect a,b] [--out f]'); process.exit(2); }
const opt = (k: string) => { const i = args.indexOf(k); return i > 0 ? args[i + 1] : undefined; };
const expect = new Set((opt('--expect') ?? 'v,travel').split(','));
const now = Date.now();
const c = loadP0Content();
const saved = JSON.parse(readFileSync(file, 'utf8')) as Record<string, P0State>;
const clone = <T>(x: T): T => structuredClone(x);

const before: Record<string, number> = {}, after: Record<string, number> = {};
const changed: Record<string, number> = {}, added: Record<string, number> = {};
const unexpected: { player: string; field: string }[] = [], notIdempotent: string[] = [];
for (const [id, raw] of Object.entries(saved)) {
  before[raw.v] = (before[raw.v] ?? 0) + 1;
  const up = upgradeState(c, clone(raw), now);
  after[up.v] = (after[up.v] ?? 0) + 1;
  for (const k of new Set([...Object.keys(raw), ...Object.keys(up)])) {
    const a = (raw as unknown as Record<string, unknown>)[k], b = (up as unknown as Record<string, unknown>)[k];
    if (isDeepStrictEqual(a, b)) continue;
    (a === undefined ? added : changed)[k] = ((a === undefined ? added : changed)[k] ?? 0) + 1;
    if (!expect.has(k)) unexpected.push({ player: id, field: k });
  }
  const again = upgradeState(c, JSON.parse(JSON.stringify(up)), now);
  if (!isDeepStrictEqual(JSON.parse(JSON.stringify(again)), JSON.parse(JSON.stringify(up)))) notIdempotent.push(id);
}

// Through the store, on a temp copy: the backup is kept, and the store's own rewrite loads back unchanged.
const dir = mkdtempSync(path.join(os.tmpdir(), 'p0-migcheck-'));
const tmp = path.join(dir, 'p0-state.json');
copyFileSync(file, tmp);
const store = new P0Store(c, tmp);
const first = store.all()[0];
if (first) store.put(first);   // forces the one rewrite a live server does on its first write
const backups = ['v1', 'v2', 'v3', 'v4'].map(v => `${tmp}.${v}.bak`).filter(existsSync).map(f => path.basename(f));
const reloaded = new P0Store(c, tmp);
const storeStable = store.all().every(s => isDeepStrictEqual(JSON.parse(JSON.stringify(s)), JSON.parse(JSON.stringify(reloaded.peek(s.player)))));
const backupMatches = backups.length === 1 && readFileSync(path.join(dir, backups[0]), 'utf8') === readFileSync(file, 'utf8');

const report = {
  file: path.basename(file), players: Object.keys(saved).length, to: SAVE_VERSION, before, after, changed, added,
  unexpected: unexpected.slice(0, 50), unexpected_count: unexpected.length, not_idempotent: notIdempotent,
  store: { migrated: store.migrated, backups, backup_matches_input: backupMatches, reload_stable: storeStable },
};
const ok = unexpected.length === 0 && notIdempotent.length === 0 && storeStable && (store.migrated === 0 || backupMatches);
console.log(JSON.stringify({ ok, ...report }, null, 2));
const out = opt('--out');
if (out) writeFileSync(out, JSON.stringify({ ok, ...report }, null, 2));
process.exit(ok ? 0 : 1);
