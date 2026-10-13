/** MAP-8 Nearby cities (§11.8.1; the user on 10-13: this page only): the view names each near10 city's state or province. */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { freshState } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { clusterAdmin } from '../../src/p0/world.js';

const c = loadP0Content();
const now = Date.parse('2026-10-13T03:00:00Z');

describe('MAP-8: the near10 cities\' states in the view (不知火舞 on 301 / MAP-8)', () => {
  it('reads a cluster\'s state from its seed city', () => {
    expect(clusterAdmin('gn-5391295')).toBe('California');   // Salinas
    expect(clusterAdmin('gn-1850147')).toBe('Tokyo');
    expect(clusterAdmin('gn-nothing')).toBe('');
  });

  it('names every near10 city of a San Francisco home, and only those', () => {
    const s = freshState(c, 'nearby-player-01', now);
    const near10 = s.travel.fallback.near10;
    expect(near10.length).toBeGreaterThan(0);
    const admins = viewOf(c, s, now).travel.admins as Record<string, string>;
    expect(Object.keys(admins).sort()).toEqual(near10.filter(id => clusterAdmin(id) !== '').sort());
    for (const id of near10) if (admins[id]) expect(admins[id]).toBe(clusterAdmin(id));
    expect(Object.values(admins)).toContain('California');
  });
});
