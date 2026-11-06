/**
 * Save check for a rehearsal. Since v7 (SGODOT-355 first batch, plan v4 conclusion 20, q row B; SGODOT-396 ②) the
 * server clears saves older than its version instead of bringing them up: P0Store keeps the file as it was in a .bak
 * beside it and loads only the saves at its version. Reads a copy of a P0 state file, without writing the file it was
 * given, and reports:
 *   - versions before; how many saves the store clears and how many it keeps; none from a version this server is older than;
 *   - through P0Store on a temp copy: the .bak it keeps is the input byte for byte; after the store's own rewrite the
 *     file holds the kept saves alone, at this version; loading that again clears nothing, keeps no second .bak and
 *     gives the same saves (a restart after the clear-out is a no-op);
 *   - the kept saves (already at this version): an upgrade only fills fields they lack (`added`) — a value already
 *     there changes only for a field in --expect — and upgrading the upgraded save changes nothing (idempotent).
 * Usage: tsx tools/p0_migration_check.ts <state.json> [--expect a,b] [--out report.json]
 * Exit 1 when any of these fails.
 */
import { copyFileSync, existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { loadP0Content, type P0Content } from '../src/p0/content.js';
import { SAVE_VERSION, upgradeState, type P0State } from '../src/p0/state.js';
import { P0Store } from '../src/p0/store.js';

const plain = <T>(x: T): T => JSON.parse(JSON.stringify(x)) as T;

/** The check of one state file (the CLI below prints it; tests call it). `expect`: fields a kept save's upgrade may change. */
export function migrationCheck(c: P0Content, file: string, expect: Set<string> = new Set(), now = Date.now()) {
  const input = readFileSync(file, 'utf8');
  const saved = JSON.parse(input) as Record<string, P0State>;
  const before: Record<string, number> = {}, changed: Record<string, number> = {}, added: Record<string, number> = {};
  const unexpected: { player: string; field: string }[] = [], notIdempotent: string[] = [], newer: string[] = [];
  let cleared = 0, kept = 0;
  for (const [id, raw] of Object.entries(saved)) {
    const v = raw.v as number;
    before[v] = (before[v] ?? 0) + 1;
    if (v > SAVE_VERSION) newer.push(id);
    if (v < SAVE_VERSION) { cleared++; continue; }
    kept++;
    const up = upgradeState(c, structuredClone(raw), now);
    for (const k of new Set([...Object.keys(raw), ...Object.keys(up)])) {
      const a = (raw as unknown as Record<string, unknown>)[k], b = (up as unknown as Record<string, unknown>)[k];
      if (isDeepStrictEqual(a, b)) continue;
      if (a === undefined) { added[k] = (added[k] ?? 0) + 1; continue; }
      changed[k] = (changed[k] ?? 0) + 1;
      if (!expect.has(k)) unexpected.push({ player: id, field: k });
    }
    const again = upgradeState(c, plain(up), now);
    if (!isDeepStrictEqual(plain(again), plain(up))) notIdempotent.push(id);
  }

  // Through the store, on a temp copy: what a live server does on its first start with this file, and on the next.
  const dir = mkdtempSync(path.join(os.tmpdir(), 'p0-migcheck-'));
  try {
    const tmp = path.join(dir, 'p0-state.json');
    copyFileSync(file, tmp);
    const baks = () => readdirSync(dir).filter(f => f.startsWith('p0-state.json.') && f.endsWith('.bak')).sort();
    const store = new P0Store(c, tmp);
    const first = store.all()[0];
    if (first) store.put(first);   // the rewrite a live server does on its first write
    else if (cleared) store.get('p0-migcheck-probe', now);   // all cleared: a first read makes the file anew
    const afterFirst = baks();
    const backupMatches = afterFirst.length === 1 && readFileSync(path.join(dir, afterFirst[0]), 'utf8') === input;
    const written = JSON.parse(readFileSync(tmp, 'utf8')) as Record<string, P0State>;
    const probe = written['p0-migcheck-probe'] ? 1 : 0;
    const onlyKept = Object.values(written).every(s => (s.v as number) === SAVE_VERSION) && Object.keys(written).length === kept + probe;
    const reloaded = new P0Store(c, tmp);
    const restartNoop = reloaded.migrated === 0 && baks().length === afterFirst.length
      && store.all().every(s => isDeepStrictEqual(plain(s), plain(reloaded.peek(s.player))));
    const storeReport = { cleared: store.migrated, kept: store.size() - probe, backups: afterFirst, backup_matches_input: backupMatches,
      file_holds_kept_only: onlyKept, restart_noop: restartNoop };
    const storeOk = store.migrated === cleared && (cleared === 0 ? afterFirst.length === 0 : backupMatches) && onlyKept && restartNoop;
    const ok = storeOk && newer.length === 0 && unexpected.length === 0 && notIdempotent.length === 0;
    return {
      ok, file: path.basename(file), players: Object.keys(saved).length, to: SAVE_VERSION, before, cleared, kept,
      newer_than_server: newer, kept_changed: changed, kept_added: added,
      unexpected: unexpected.slice(0, 50), unexpected_count: unexpected.length, not_idempotent: notIdempotent, store: storeReport,
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const file = args[0];
  if (!file || !existsSync(file)) { console.error('usage: p0_migration_check.ts <state.json> [--expect a,b] [--out f]'); process.exit(2); }
  const opt = (k: string) => { const i = args.indexOf(k); return i > 0 ? args[i + 1] : undefined; };
  const report = migrationCheck(loadP0Content(), file, new Set((opt('--expect') ?? '').split(',').filter(Boolean)));
  console.log(JSON.stringify(report, null, 2));
  const out = opt('--out');
  if (out) writeFileSync(out, JSON.stringify(report, null, 2));
  process.exit(report.ok ? 0 : 1);
}
