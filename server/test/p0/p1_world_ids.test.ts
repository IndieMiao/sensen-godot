/**
 * SGODOT-280 (周瑜 on #321): the world's place ids are frozen. A place is saved, visited, passed and requested by its
 * id (`<cluster>~tackle2`), never by its coordinates, so an id must always mean the same place: the same kind, the
 * same name, the same pond for a tackle shop. Tackle shops are numbered by how many have been placed, so a change that
 * skips one pond's shop would quietly renumber the rest; this test catches that and any other change of identity.
 *
 * test/p0/world_ids.snapshot.json holds, per city cluster, a hash of its places' identity lines (id | kind | name |
 * pond site, or the pond a shop stands by) — coordinates are left out: the water table and the hand fixes may move a
 * place, they never change what it is. A city that loses or gains a place, renames one or rebinds a shop fails here.
 *
 * Changing identities on purpose (before the world opens to players outside internal testing, q(114) ⑦): bump
 * world.revision, then rewrite the snapshot with  UPDATE_WORLD_IDS=1 npx vitest run test/p0/p1_world_ids.test.ts
 * and say in the PR which cities changed and why.
 */
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { CityClusters, type CityCluster } from '../../src/p0/clusters.js';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { generateCity, type WorldContent } from '../../src/p0/world.js';
import { writtenCluster } from '../../src/p0/travel.js';

const SNAPSHOT = new URL('./world_ids.snapshot.json', import.meta.url);
const c: P0Content = loadP0Content();
const w = (c as P0Content & { world: WorldContent }).world;
// Every cluster of city_clusters.json, a closed country's too: hidden (q(189)), its places still keep their ids
const clusters = CityClusters.load();

interface Snapshot { _note: string; revision: number; cities: number; places: number; hash: Record<string, string> }

/** One city's identity lines, in id order: what each id means, never where it stands. */
function identity(cl: CityCluster): string[] {
  const d = generateCity(c, cl).detail;
  return [...d.ponds.map(p => `${p.id}|pond|${p.name}|${p.site}`),
    ...d.outposts.map(o => `${o.id}|${o.cabin ? 'cabin' : o.role}|${o.name}|${o.nearest?.name ?? ''}`),
    ...d.huts.map(h => `${h.id}|${h.role}|${h.name}|`)].sort();   // q(204): the Mine Huts (Denver's Golden Mine Hut)
}
const hashOf = (lines: string[]) => createHash('sha256').update(lines.join('\n')).digest('hex').slice(0, 16);

describe('world place ids are frozen (SGODOT-280)', () => {
  it('every city\'s places keep their ids, kinds, names and ponds (test/p0/world_ids.snapshot.json)', () => {
    const home = writtenCluster(c);
    const now: Record<string, string> = {};
    let places = 0;
    for (const cl of clusters.byId.values()) {
      if (cl.id === home) continue;   // hand-written tables (p0_ponds.json / p0_outposts.json), frozen by their own ids
      const lines = identity(cl);
      places += lines.length;
      now[cl.id] = hashOf(lines);
    }
    if (process.env.UPDATE_WORLD_IDS === '1' || !existsSync(SNAPSHOT)) {
      const snap: Snapshot = {
        _note: 'Frozen place identities per city cluster (test/p0/p1_world_ids.test.ts): sha256 of id | kind | name | pond, first 16 hex. Rewrite only on purpose, with world.revision bumped: UPDATE_WORLD_IDS=1 npx vitest run test/p0/p1_world_ids.test.ts',
        revision: w.revision, cities: Object.keys(now).length, places, hash: Object.fromEntries(Object.entries(now).sort()) };
      writeFileSync(SNAPSHOT, JSON.stringify(snap, null, 0).replace(/,"/g, ',\n"') + '\n');
      if (process.env.UPDATE_WORLD_IDS !== '1') throw new Error('test/p0/world_ids.snapshot.json was missing: written now, commit it');
      return;
    }
    const snap = JSON.parse(readFileSync(SNAPSHOT, 'utf8')) as Snapshot;
    const changed = Object.keys({ ...snap.hash, ...now }).filter(id => snap.hash[id] !== now[id]).sort();
    const named = changed.slice(0, 10).map(id => `${id} ${clusters.byId.get(id)?.name ?? '(no such cluster)'}`);
    expect(changed, `${changed.length} cities changed what their place ids mean: ${named.join(', ')}${changed.length > 10 ? ', …' : ''}. `
      + 'Ids are saved by players: if this is on purpose, bump world.revision and rewrite the snapshot (see the file\'s header).').toEqual([]);
    expect(places).toBe(snap.places);
    expect(snap.revision).toBe(w.revision);   // a rewritten snapshot goes with a revision bump
  });

  it('notices a renumbered tackle shop: the same city with one shop\'s pond swapped hashes differently', () => {
    const tokyo = clusters.byId.get('gn-1850147')!;
    const lines = identity(tokyo);
    const shops = lines.filter(l => l.includes('~tackle'));
    expect(shops.length).toBeGreaterThan(1);
    // tackle1 taking tackle0's pond (what a skipped shop would do to the numbering) is a different city
    const [a, b] = [shops[0].split('|'), shops[1].split('|')];
    const swapped = lines.map(l => (l === shops[0] ? [a[0], a[1], b[2], b[3]].join('|') : l === shops[1] ? [b[0], b[1], a[2], a[3]].join('|') : l));
    expect(hashOf(swapped)).not.toBe(hashOf(lines));
  });
});
