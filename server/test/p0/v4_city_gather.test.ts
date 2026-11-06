/** v4q(4) ③–⑤ (SGODOT-355; the user, 11-02: 丁9 / 丁10 / 丁11): gathering at a city's point — in that city (on the farm,
 * a home city's from the map too), 3 Energy, 4 h by point id, T1 4 and T2 3, the bag first away and the whole yield or
 * nothing (no Energy, no cooldown), worms that don't fit to storage; on the farm straight to storage; no gloves. */
import { afterEach, describe, expect, it } from 'vitest';
import { count } from '../../src/p0/bag.js';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { gatherCatalogueOf, useGatherCatalogue } from '../../src/p0/gather_points.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { worldOf } from '../../src/p0/world.js';

const SF = 'gn-5391959', TOKYO = 'gn-1850147', T = Date.parse('2026-11-02T18:00:00Z'), H = 3_600_000;
const FIELDS = ['cluster', 'kind', 'n', 'lat', 'lng', 'word'];
const WOOD = `${SF}~wood0`, REED = `${SF}~reed0`, HARD = `${SF}~hardwood0`, HERB = `${SF}~herb0`, TOKYO_WOOD = `${TOKYO}~wood0`;

let content: P0Content | null = null;
afterEach(() => { if (content) useGatherCatalogue(content, null); content = null; });

function setup() {
  const c = loadP0Content(); content = c;
  const w = worldOf(c)!;
  useGatherCatalogue(c, gatherCatalogueOf(c, { seed: w.seed, revision: w.revision, fields: FIELDS, rows: [
    [SF, 'wood', 0, 37.76, -122.43, 'Badger'], [SF, 'reed', 0, 37.77, -122.41, 'Heron'], [SF, 'hardwood', 0, 37.74, -122.45, 'Fox'],
    [SF, 'herb', 0, 37.75, -122.44, 'Sage'], [TOKYO, 'wood', 0, 35.7, 139.7, 'Plum']] }));
  const s = freshState(c, 'city-gather-1', T);
  s.energy.value = 100;
  return { c, s };
}
const run = (c: P0Content, s: P0State, cmd: P0Command, now: number) => applyP0(c, s, cmd, now);
/** The player in Tokyo with its pass running, on the map. */
function inTokyo(s: P0State) {
  s.travel.here = TOKYO;
  s.travel.passes[TOKYO] = { kind: 'day', from: T - H, until: T + 20 * H } as never;
  s.travel.visits[TOKYO] = { n: 1, first_at: T - H, last_at: T - H, deliveries: 0, delivered_day: '' } as never;
}

describe('city gathering (v4q(4) ③–⑤)', () => {
  it('on the farm a home city\'s point is gathered from the map (丁9): 3 Energy, 4 Timber to storage, ready again in 4 h', () => {
    const { c, s } = setup();
    const r = run(c, s, { type: 'gather', spot: WOOD, space: 'home' } as P0Command, T);
    if (!r.ok) throw new Error(r.code);
    expect(r.state.energy.value).toBe(97);
    expect(r.state.storage.wood).toBe(4);
    expect(count(r.state.bag, 'wood')).toBe(0);
    expect(r.events).toContainEqual({ kind: 'gather', spot: WOOD, items: [['wood', 4, 'storage']], ready_in: 4 * H });
    expect(viewOf(c, r.state, T + H).gather.city_ready).toEqual({ [WOOD]: 3 * H });   // the view says it cools down (亚瑟 on #659)
    expect(viewOf(c, r.state, T + 4 * H).gather.city_ready).toEqual({});              // ready: no longer listed
    const again = run(c, r.state, { type: 'gather', spot: WOOD, space: 'home' } as P0Command, T + 3 * H);
    expect(again).toMatchObject({ ok: false, code: 'not_ready', detail: { ready_in: H } });
    const later = run(c, r.state, { type: 'gather', spot: WOOD, space: 'home' } as P0Command, T + 4 * H);
    expect(later.ok && later.state.storage.wood).toBe(8);
    // a T2 point gives 3, from Homestead Lv1 (丁3)
    const hard = run(c, s, { type: 'gather', spot: HARD, space: 'home' } as P0Command, T);
    expect(hard.ok && hard.state.storage.hardwood).toBe(3);
  });

  it('a cooldown gone by leaves the save at the next command; one still running stays (396 ④)', () => {
    const { c, s } = setup();
    const a = run(c, s, { type: 'gather', spot: WOOD, space: 'home' } as P0Command, T);
    if (!a.ok) throw new Error(a.code);
    const b = run(c, a.state, { type: 'gather', spot: REED, space: 'home' } as P0Command, T + 2 * H);
    if (!b.ok) throw new Error(b.code);
    expect(Object.keys(b.state.gather.ready_at).sort()).toEqual([REED, WOOD].sort());   // both cooling down
    const c2 = run(c, b.state, { type: 'gather', spot: HERB, space: 'home' } as P0Command, T + 5 * H);
    if (!c2.ok) throw new Error(c2.code);
    expect(Object.keys(c2.state.gather.ready_at).sort()).toEqual([HERB, REED].sort());   // Timber's 4 h are over: gone
    expect(viewOf(c, c2.state, T + 5 * H).gather.city_ready).toEqual({ [REED]: H, [HERB]: 4 * H });
    const again = run(c, c2.state, { type: 'gather', spot: WOOD, space: 'home' } as P0Command, T + 5 * H + H);
    expect(again.ok).toBe(true);   // gone means ready, as it always read
  });

  it('taps faster than 0.9 s are refused as tempo (tempo_ms, the farm\'s spots gone: v4q(4) ①)', () => {
    const { c, s } = setup();
    const r = run(c, s, { type: 'gather', spot: WOOD, space: 'home' } as P0Command, T);
    if (!r.ok) throw new Error(r.code);
    expect(run(c, r.state, { type: 'gather', spot: REED, space: 'home' } as P0Command, T + 500)).toMatchObject({ ok: false, code: 'tempo' });
    expect(run(c, r.state, { type: 'gather', spot: REED, space: 'home' } as P0Command, T + c.gather.tempo_ms).ok).toBe(true);
  });

  it('away, in that city, it all goes to the bag, home with the player; another city\'s point is refused (not_here)', () => {
    const { c, s } = setup();
    inTokyo(s);
    const r = run(c, s, { type: 'gather', spot: TOKYO_WOOD, space: 'map' } as P0Command, T);
    if (!r.ok) throw new Error(r.code);
    expect(count(r.state.bag, 'wood')).toBe(4);
    expect(r.state.storage.wood ?? 0).toBe(0);
    expect(run(c, s, { type: 'gather', spot: WOOD, space: 'map' } as P0Command, T)).toMatchObject({ ok: false, code: 'not_here', detail: { cluster: SF } });
    const { s: home } = setup();
    expect(run(c, home, { type: 'gather', spot: TOKYO_WOOD, space: 'home' } as P0Command, T)).toMatchObject({ ok: false, code: 'not_here' });
  });

  it('a full bag gathers nothing — the whole yield must fit — and costs no Energy, starts no cooldown (丁10)', () => {
    const { c, s } = setup();
    inTokyo(s);
    s.bag = [];
    for (let i = 0; i < s.bag_cap - 1; i++) s.bag.push({ id: 'fish_crucian', qty: 10 });
    s.bag.push({ id: 'wood', qty: 97 });   // room for 2 more Timber only (a stack of 99)
    const r = run(c, s, { type: 'gather', spot: TOKYO_WOOD, space: 'map' } as P0Command, T);
    expect(r).toMatchObject({ ok: false, code: 'bag_full', detail: { item: 'wood', need: 4 } });
    expect(s.energy.value).toBe(100);
    expect(s.gather.ready_at[TOKYO_WOOD]).toBeUndefined();
  });

  it('a reed bank\'s worms that don\'t fit go to Farm Storage, the reeds to the bag', () => {
    const { c, s } = setup();
    s.bag = [];
    for (let i = 0; i < s.bag_cap - 1; i++) s.bag.push({ id: 'fish_crucian', qty: 10 });   // one slot free: the reeds'
    const r = run(c, s, { type: 'gather', spot: REED, space: 'map' } as P0Command, T);
    if (!r.ok) throw new Error(r.code);
    expect(count(r.state.bag, 'fiber')).toBe(4);
    expect(count(r.state.bag, 'bait_worm')).toBe(0);
    expect(r.state.storage.bait_worm).toBe(2);
  });

  it('on the farm the bag is not asked: a full bag still gathers to storage; Wild Herb before the Spice Rack to the bag as it fits', () => {
    const { c, s } = setup();
    s.bag = [];
    for (let i = 0; i < s.bag_cap; i++) s.bag.push({ id: 'fish_crucian', qty: 10 });
    const r = run(c, s, { type: 'gather', spot: WOOD, space: 'home' } as P0Command, T);
    expect(r.ok && r.state.storage.wood).toBe(4);
    const { s: lv1 } = setup();
    const herb = run(c, lv1, { type: 'gather', spot: HERB, space: 'home' } as P0Command, T);
    expect(herb.ok && count(herb.state.bag, 'wild_herb')).toBe(4);   // q(46): seasonings travel until the Spice Rack
  });

  it('short of Energy says the gap, and nothing changes', () => {
    const { c, s } = setup();
    s.energy.value = 2;
    const r = run(c, s, { type: 'gather', spot: WOOD, space: 'home' } as P0Command, T);
    expect(r).toMatchObject({ ok: false, code: 'need_energy', detail: { need: 3, have: 2 } });
    expect(s.gather.ready_at[WOOD]).toBeUndefined();
  });

  it('Gather Gloves an old save still owns add nothing at a city point either (丁11)', () => {
    const { c, s } = setup();
    s.owned.push('gather_gloves');
    const r = run(c, s, { type: 'gather', spot: WOOD, space: 'home' } as P0Command, T);
    expect(r.ok && r.state.storage.wood).toBe(4);
  });
});
