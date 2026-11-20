/** SGODOT-488 A1: the save's find / remove (no save made on a token's read) and accounts.json in the hourly snapshot
 * beside the save, the same hour, kept the same (tech-plan §1.3). */
import { existsSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { snapshotState } from '../../src/p0/guard.js';
import { P0Store } from '../../src/p0/store.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 10, 13, 3);
const dirs: string[] = [];
afterEach(() => { for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true }); });
const dir = () => { const d = mkdtempSync(path.join(tmpdir(), 'a1-')); dirs.push(d); return d; };

describe('P0Store find / remove', () => {
  it('finds a stored player without making one, and removes it', () => {
    const store = new P0Store(c);
    expect(store.find('p0-nobody', T0)).toBeUndefined();
    expect(store.size()).toBe(0);
    store.get('p0-some', T0);
    expect(store.find('p0-some', T0)?.player).toBe('p0-some');
    expect(store.remove('p0-some')).toBe(true);
    expect(store.find('p0-some', T0)).toBeUndefined();
    expect(store.remove('p0-some')).toBe(false);
  });
});

describe('the hourly snapshot', () => {
  it('copies accounts.json beside the save under the same hour, and keeps as many', () => {
    const d = dir(), snaps = path.join(d, 'snapshots');
    const save = path.join(d, 'p0-state.json'), acc = path.join(d, 'accounts.json');
    writeFileSync(save, '{}'); writeFileSync(acc, '{"v":1}');
    for (let h = 0; h < 4; h++) snapshotState(save, snaps, 2, T0 + h * 3_600_000, acc);
    expect(readdirSync(snaps).sort()).toEqual(['accounts-2026111305.json', 'accounts-2026111306.json',
      'p0-state-2026111305.json', 'p0-state-2026111306.json']);
  });
  it('without accounts.json (an older server, or none made yet) the save alone, as before', () => {
    const d = dir(), snaps = path.join(d, 'snapshots'), save = path.join(d, 'p0-state.json');
    writeFileSync(save, '{}');
    snapshotState(save, snaps, 48, T0, path.join(d, 'accounts.json'));
    expect(readdirSync(snaps)).toEqual(['p0-state-2026111303.json']);
    expect(existsSync(path.join(d, 'accounts.json'))).toBe(false);
  });
});
