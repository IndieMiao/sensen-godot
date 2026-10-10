/** SGODOT-270: P0's pond data agrees with itself. The fishing places and P0's pond list (assets/p0/p0_ponds.json, which
 * the client registers too) name the same ponds; every place is in the home city exactly as notePlace, the save cleanup
 * and pondFor compare it (profile.city lower-cased: "san francisco", never a region id); one beginner pond, a Pond with
 * Pond Crucian (q(32), §6.3.3). */
import { readFileSync } from 'node:fs';
import { pondFishIds } from '../../src/p0/fishing_world.js';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { DEFAULT_P0_CONTENT, loadP0Content } from '../../src/p0/content.js';

const c = loadP0Content();
const list = (JSON.parse(readFileSync(path.join(path.dirname(DEFAULT_P0_CONTENT), 'p0_ponds.json'), 'utf8')) as {
  locations: { id: string; lat: number; lng: number; template_id: string; layout_revision: number; enabled: boolean }[];
}).locations;

describe("P0's pond data (SGODOT-270)", () => {
  it('the fishing places and the pond list name the same six ponds, each with its map point', () => {
    expect(Object.keys(c.fishing.places).sort()).toEqual(list.map(l => l.id).sort());
    expect(list).toHaveLength(6);
    for (const l of list) {
      expect(l.enabled).toBe(true);
      expect(['crescent', 'gourd', 'meander']).toContain(l.template_id);
      expect(c.fishing.places[l.id].at).toEqual([l.lat, l.lng]);
    }
  });

  it('every place is in the home city as the server compares it, and its site is a template', () => {
    const home = c.profile.city.toLowerCase();
    expect(home).toBe('san francisco');
    for (const [id, p] of Object.entries(c.fishing.places)) {
      expect(p.city, id).toBe(home);
      expect(Object.keys(c.fishing.sites), id).toContain(p.site);
    }
  });

  it('exactly one beginner pond: Fern Pond, a Pond that has Pond Crucian', () => {
    const beginners = Object.entries(c.fishing.places).filter(([, p]) => p.beginner);
    expect(beginners.map(([id]) => id)).toEqual(['pond_san_francisco_03']);
    const site = c.fishing.sites[beginners[0][1].site];
    expect(site.template).toBe('Pond');
    expect(pondFishIds(c, beginners[0][0])).toContain('fish_crucian');
  });
});
