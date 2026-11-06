/** SGODOT-396 ②: tools/p0_migration_check.ts checks the v7 clear-out a live server does on its first start. */
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { freshState, SAVE_VERSION, type P0State } from '../../src/p0/state.js';
import { migrationCheck } from '../../tools/p0_migration_check.js';

const c = loadP0Content();
const T = Date.parse('2026-11-06T10:00:00Z');
const dirs: string[] = [];
afterEach(() => { for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true }); });
/** A state file of these saves: `old` ones written as the version before this one (the saves the clear-out drops). */
function file(players: { id: string; v?: number }[]): string {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'p0-migcheck-test-')); dirs.push(dir);
  const saves: Record<string, P0State> = {};
  for (const p of players) { const s = freshState(c, p.id, T); if (p.v !== undefined) (s as { v: number }).v = p.v; saves[p.id] = s; }
  const f = path.join(dir, 'state.json');
  writeFileSync(f, JSON.stringify(saves));
  return f;
}

describe('the v7 clear-out check (396 ②)', () => {
  it('older saves cleared and kept byte for byte in the .bak, this version kept as it was; a restart is a no-op', () => {
    const r = migrationCheck(c, file([{ id: 'p0-old-0001', v: SAVE_VERSION - 1 }, { id: 'p0-old-0002', v: SAVE_VERSION - 1 }, { id: 'p0-new-0001' }]), new Set(), T);
    expect(r).toMatchObject({ ok: true, players: 3, cleared: 2, kept: 1, newer_than_server: [], unexpected_count: 0, not_idempotent: [],
      before: { [SAVE_VERSION - 1]: 2, [SAVE_VERSION]: 1 } });
    expect(r.store).toMatchObject({ cleared: 2, kept: 1, backup_matches_input: true, file_holds_kept_only: true, restart_noop: true });
    expect(r.store.backups).toEqual([`p0-state.json.v${SAVE_VERSION - 1}.bak`]);
  });

  it('everyone older: all cleared, the .bak still the input; nothing to clear: no .bak at all', () => {
    const all = migrationCheck(c, file([{ id: 'p0-old-0001', v: SAVE_VERSION - 1 }, { id: 'p0-old-0002', v: SAVE_VERSION - 2 }]), new Set(), T);
    expect(all).toMatchObject({ ok: true, cleared: 2, kept: 0, store: { backup_matches_input: true, file_holds_kept_only: true, restart_noop: true } });
    expect(all.store.backups).toEqual([`p0-state.json.v${SAVE_VERSION - 2}.bak`]);   // named by the oldest version in it
    const none = migrationCheck(c, file([{ id: 'p0-new-0001' }, { id: 'p0-new-0002' }]), new Set(), T);
    expect(none).toMatchObject({ ok: true, cleared: 0, kept: 2, store: { backups: [], restart_noop: true } });
  });

  it('a save from a version this server is older than fails the check (an image older than the data)', () => {
    const r = migrationCheck(c, file([{ id: 'p0-new-0001' }, { id: 'p0-future-01', v: SAVE_VERSION + 1 }]), new Set(), T);
    expect(r.ok).toBe(false);
    expect(r.newer_than_server).toEqual(['p0-future-01']);
  });
});
