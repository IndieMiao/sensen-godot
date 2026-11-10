/** SGODOT-409 (v4q(11) C): gathering points in every pond, worked out from the pond's id; gathered in that pond. */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { count } from '../../src/p0/bag.js';
import { loadP0Content } from '../../src/p0/content.js';
import { cityPondPoints, pondPointById, pondPoints } from '../../src/p0/pond_gather.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const SF = 'gn-5391959', TOKYO = 'gn-1850147', FERN = 'pond_san_francisco_03', T = Date.parse('2026-11-06T18:00:00Z'), H = 3_600_000;
const SLOTS = JSON.parse(readFileSync(new URL('../../data/pond_slots.json', import.meta.url), 'utf8')).shapes as
  Record<string, Record<string, { opening_visible: boolean; spawn_m: number; low_only: boolean; blocks: string[]; near: string[]; pieces?: string[]; x: number; z: number }>>;
const TALL = new Set(['wood', 'hardwood', 'herb']);
const shapeOf = (pts: { slot: string; x: number; z: number }[]) =>
  Object.values(SLOTS).find(sl => pts.every(p => sl[p.slot] && sl[p.slot].x === p.x && sl[p.slot].z === p.z))!;

describe('pond gathering points (409)', () => {
  it("a home city's beginner pond holds Timber 2, Stone 2, Reeds 1, Clay 1 on its fixed slots; the other 10 round its other ponds", () => {
    const sf = cityPondPoints(c, SF);
    expect(pondPoints(c, FERN).map(p => `${p.slot}:${p.kind}`).sort()).toEqual(['C1:wood', 'F2:stone', 'L1:stone', 'L2:wood', 'L3:reed', 'R2:clay']);
    const others = [...sf].filter(([id]) => id !== FERN).flatMap(([, pts]) => pts.map(p => p.kind)).sort();
    expect(others).toEqual(['clay', 'flax', 'flax', 'hardwood', 'hardwood', 'herb', 'herb', 'reed', 'stone', 'wood']);
    for (const [, pts] of sf) expect(pts.length).toBeGreaterThan(0);
    expect(pondPointById(c, `${FERN}#L2`)).toMatchObject({ kind: 'wood', name: 'Grove', yield: [['wood', 4]], energy: 3, cooldown_h: 4 });
    expect(pondPointById(c, `${FERN}#Z9`)).toBeUndefined();
  });

  it('every pond of every city has a point, on slots that keep the layout rules (408 v2), the same every time', () => {
    const clusters = [SF, TOKYO, 'gn-2643743', 'gn-1790437', 'gn-5128581', 'gn-3530597'];   // home cities, and a fallback city of 5 points and 6 ponds
    for (const cl of clusters) {
      for (const [pond, pts] of cityPondPoints(c, cl)) {
        expect(pts.length, pond).toBeGreaterThan(0);
        const shape = shapeOf(pts);
        const vis = pts.filter(p => shape[p.slot].opening_visible).length;
        expect(vis, pond).toBeGreaterThanOrEqual(1);
        expect(vis, pond).toBeLessThanOrEqual(3);
        expect(pts.filter(p => shape[p.slot].spawn_m <= 3).length, pond).toBeLessThanOrEqual(2);
        for (const a of pts) {
          if (TALL.has(a.kind)) expect(shape[a.slot].low_only, `${pond} ${a.slot}`).toBe(false);
          if (shape[a.slot].pieces) expect(shape[a.slot].pieces, `${pond} ${a.slot}`).toContain(a.kind);
          for (const b of pts) if (a !== b && a.kind === b.kind) expect(shape[a.slot].near, `${pond} ${a.slot}/${b.slot}`).not.toContain(b.slot);
          if (TALL.has(a.kind)) for (const b of pts) expect(shape[a.slot].blocks, `${pond} ${a.slot} hides ${b.slot}`).not.toContain(b.slot);
        }
      }
    }
    expect(pondPoints(c, 'gn-1850147~pond2')).toEqual(pondPoints(c, 'gn-1850147~pond2'));
    // every planned point placed (周瑜 on #785): a home city's 16, the fallback city's 5 and one Timber for its sixth pond
    const total = (cl: string) => [...cityPondPoints(c, cl).values()].reduce((n, pts) => n + pts.length, 0);
    for (const cl of [SF, TOKYO, 'gn-2643743', 'gn-5128581', 'gn-3530597']) expect(total(cl), cl).toBe(16);
    expect(total('gn-1790437')).toBe(6);
  });

  it('gathered in that pond only: Reeds into the bag with 2 worms, 3 Energy, ready again in 4 h; another pond says not_here', () => {
    let s = freshState(c, 'pond-gather-1', T);
    s.energy.value = 100;
    const at = (cmd: Record<string, unknown>, now = T) => applyP0(c, s, { space: 'pond', place: FERN, ...cmd } as unknown as P0Command, now);
    const r = at({ type: 'gather', spot: `${FERN}#L3` });
    if (!r.ok) throw new Error(r.code);
    s = r.state;
    expect(s.energy.value).toBe(97);
    expect(count(s.bag, 'fiber')).toBe(4);
    expect(r.events).toContainEqual(expect.objectContaining({ kind: 'gather', spot: `${FERN}#L3`, ready_in: 4 * H }));
    expect(at({ type: 'gather', spot: `${FERN}#L3` }, T + H)).toMatchObject({ ok: false, code: 'not_ready' });
    const v = viewOf(c, s, T + H).gather as { pond: { pond: string; shape: string; points: { id: string; ready_in: number; cooldown_h: number }[] };
      city_ready: Record<string, number>; ponds: Record<string, { points: Record<string, unknown>[] }> };
    expect(v.pond).toMatchObject({ pond: FERN, shape: 'crescent' });
    expect(v.pond.points.find(p => p.id === `${FERN}#L3`)!.ready_in).toBe(3 * H);
    // the whole cooldown beside it (不知火舞's gather-compact spec v1): grown back 1 − 3 / 4; the far ponds' points need none
    expect(v.pond.points.every(p => p.cooldown_h === 4)).toBe(true);
    expect('cooldown_h' in v.ponds[FERN].points[0]).toBe(false);
    expect(v.city_ready[`${FERN}#L3`]).toBe(3 * H);
    const elsewhere = applyP0(c, s, { type: 'gather', spot: `${FERN}#L2`, space: 'pond', place: 'pond_san_francisco_04' } as unknown as P0Command, T + 2 * H);
    expect(elsewhere).toMatchObject({ ok: false, code: 'not_here' });
    const home = applyP0(c, s, { type: 'gather', spot: `${FERN}#L2`, space: 'home' } as unknown as P0Command, T + 2 * H);
    expect(home).toMatchObject({ ok: false, code: 'not_here' });   // not from the farm or the map: in the pond
  });

  it("the town's points still gather as before (the client leaves them later): a home city's from the farm", () => {
    const s = freshState(c, 'pond-gather-2', T);
    s.energy.value = 100;
    const r = applyP0(c, s, { type: 'gather', spot: `${SF}~wood0`, space: 'home' } as unknown as P0Command, T);
    expect(r.ok && r.state.storage.wood).toBe(4);
    expect((viewOf(c, s, T).gather as { pond: unknown }).pond).toBeNull();   // not in a pond
  });
});
