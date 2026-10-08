import { cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it } from 'vitest';
import { AppearanceCatalog, defaultAppearance } from '../../src/realtime/appearance.js';

// NPC-only parts (SGODOT-229) dress the outpost NPCs on the client; no player may send them. With the shipped
// (empty) list, or no list file at all, the catalogue accepts exactly what it did before.
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const regions = path.join(repo, 'assets/farm/data/regions.json');
const look = (hairHat: string) => ({ version: 1, slots: { ...defaultAppearance().slots, hairHat } });
const dirs: string[] = [];
afterEach(() => { for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true }); });

/** A copy of the avatar data with this npc_only.json (undefined = no file), laid out as the catalogue expects. */
function catalogWith(npcOnly: string[] | undefined): AppearanceCatalog {
  const root = mkdtempSync(path.join(tmpdir(), 'npc-only-')); dirs.push(root);
  mkdirSync(path.join(root, 'farm/data'), { recursive: true });
  writeFileSync(path.join(root, 'farm/data/regions.json'), '{}');
  mkdirSync(path.join(root, 'avatar'));
  for (const f of ['parts_manifest.json', 'demo_denylist.json']) cpSync(path.join(repo, 'assets/avatar', f), path.join(root, 'avatar', f));
  if (npcOnly) writeFileSync(path.join(root, 'avatar/npc_only.json'), JSON.stringify({ version: 1, npc_only: npcOnly }));
  return new AppearanceCatalog(path.join(root, 'farm/data/regions.json'));
}

describe('NPC-only avatar parts (SGODOT-229)', () => {
  it('the shipped list and a missing list change nothing', () => {
    expect(new AppearanceCatalog(regions).parse(look('hairhat51'))).toEqual(look('hairhat51'));
    expect(catalogWith(undefined).parse(look('hairhat51'))).toEqual(look('hairhat51'));
    expect(catalogWith([]).parse(look('hairhat51'))).toEqual(look('hairhat51'));
  });
  it('a player cannot send an NPC-only part; other parts still pass', () => {
    const catalog = catalogWith(['hairhat51']);
    expect(() => catalog.parse(look('hairhat51'))).toThrow('APPEARANCE_INVALID');
    expect(catalog.parse(look('hairhat41'))).toEqual(look('hairhat41'));
  });
});
