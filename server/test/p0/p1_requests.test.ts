import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { eligible, regionalPool, settleBoards, visitPlaces } from '../../src/p0/boards.js';
import { matches } from '../../src/p0/requests.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type BoardRequest, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

// P1 system request templates (SGODOT-284; 李白's table in content/requests_p1.json, §9.6.3).
const content = loadP0Content();
const c = { ...content, profile: { ...content.profile, timezone: 'Asia/Shanghai' } };
const T0 = Date.UTC(2026, 9, 10, 2, 0, 0);
const H = 3_600_000, DAY = 24 * H;

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const refuse = (s: P0State, cmd: P0Command, now = T0) => applyP0(c, s, cmd, now);
const fresh = () => ({ ...freshState(c, 'player-p1-req', T0, 3), created_at: T0 - 8 * DAY });
const put = (s: P0State, board: 'stall' | 'market', r: Partial<BoardRequest>) => {
  s.boards[board][0] = { req: { id: 'r1', template: 'req_sys_crop_basic', items: [], kind: 'crop', qty: 2, bonus: 20, drawn_at: T0, status: 'accepted', ...r }, refill_at: 0 };
  return s;
};

describe('the template pool (§9.6.3: 30 at the prototype stage)', () => {
  it('31 templates, every one on a board, each board id exists', () => {
    const all = Object.keys(c.requests.templates);
    expect(all.length).toBeGreaterThanOrEqual(30);
    const listed = [...c.requests.boards.stall.templates, ...c.requests.boards.market.templates];
    expect([...listed].sort()).toEqual([...all].sort());
    for (const id of listed) expect(c.requests.templates[id], id).toBeTruthy();
  });

  it('explore templates other than Stamp Run and together stay off; climate is written as profile.climate is', () => {
    for (const [id, t] of Object.entries(c.requests.templates)) {
      if (t.type === 'together' || (t.type === 'explore' && id !== 'req_sys_explore_outpost')) expect(t.enabled, id).toBe(false);
      for (const z of t.climate ?? []) expect(z[0], id).toBe(z[0].toUpperCase());
    }
  });

  // 周瑜 on #219: every template that is on can be met by something the player can get at its gate.
  it('every template that is on has at least one deliverable item at its gate level', () => {
    for (const [id, t] of Object.entries(c.requests.templates)) {
      if (t.enabled === false || t.need.regional || t.need.kind === 'visit') continue;   // these draw only when drawable (below)
      const lv = (skill: string) => Math.max(1, ...t.gate.filter(([g]) => g === skill).map(([, n]) => n));
      const n = t.need;
      const pool = n.kind === 'crop' ? c.crops.filter(x => x.gate <= lv('farming')).map(x => x.id)
        : n.kind === 'fish' ? c.fish.filter(x => x.level <= lv('fishing')).map(x => x.id)
        : n.kind === 'dish' ? c.cooking.recipes.map(x => x.id)
        : Object.keys(c.materials);
      const ok = pool.filter(item => matches(c, n, n.id ? [n.id] : [], item));
      expect(ok.length, id).toBeGreaterThanOrEqual(n.distinct ?? 1);
    }
  });

  it('Hardwood Beams and Quartz Glass pay their shadow price per piece (#208: Hardwood 4, Quartz 5) plus 40', () => {
    for (const [tpl, item, floor] of [['req_sys_material_hardwood', 'hardwood', 4], ['req_sys_material_quartz', 'quartz', 5]] as const) {
      let s = put(fresh(), 'market', { template: tpl, kind: 'material', items: [item], qty: 3, bonus: 40 });
      s.storage[item] = 3;
      const r = step(s, { type: 'deliver', request: 'r1' });
      expect(r.ev.find(e => e.kind === 'request' && e.status === 'done'), tpl).toMatchObject({ coins: floor * 3 + 40, bonus: 40 });
      s = r.s;
      expect(s.storage[item] ?? 0).toBe(0);
    }
  });

  it('a Homestead gate opens with the Homestead level (Clay for Pots: Lv2)', () => {
    const s = fresh();
    expect(eligible(c, s, 'stall')).not.toContain('req_sys_material_clay');
    s.homestead.level = 2;
    expect(eligible(c, s, 'stall')).toContain('req_sys_material_clay');
  });
});

describe('what the new templates take', () => {
  it('Fine Produce takes any Fine crop (by ingredient rarity), not a Common one', () => {
    let s = put(fresh(), 'stall', { template: 'req_sys_crop_fine', rarity: 2 });
    s.bag.push({ id: 'crop_radish', qty: 4 });
    expect(refuse(s, { type: 'deliver', request: 'r1' })).toMatchObject({ ok: false, code: 'not_enough' });
    s.bag.push({ id: 'crop_tomato', qty: 2 });
    expect(viewOf(c, s, T0).boards.stall.slots[0]).toMatchObject({ have: 2, ready: true });
    s = step(s, { type: 'deliver', request: 'r1' }).s;
    expect(s.bag.find(b => b.id === 'crop_tomato')).toBeUndefined();
  });

  it('Packed Lunches takes Grilled or Dessert dishes and the view names both styles', () => {
    let s = put(fresh(), 'market', { template: 'req_sys_dish_trail', kind: 'dish', style: ['Grilled', 'Dessert'] });
    s.bag.push({ id: 'dish_radish_salad', qty: 2 });
    expect(refuse(s, { type: 'deliver', request: 'r1' })).toMatchObject({ ok: false, code: 'not_enough' });
    s.bag.push({ id: 'dish_carrot_cake', qty: 1 }, { id: 'dish_grilled_fish', qty: 1 });
    expect(viewOf(c, s, T0).boards.market.slots[0]).toMatchObject({ style: ['Grilled', 'Dessert'], have: 2, ready: true });
    s = step(s, { type: 'deliver', request: 'r1' }).s;
    expect(s.bag.filter(b => b.id.startsWith('dish_')).map(b => b.id)).toEqual(['dish_radish_salad']);
  });

  it('Orchard Basket takes crops of the Orchard family only', () => {
    const s = put(fresh(), 'stall', { template: 'req_sys_fruit_basket', family: 'O' });
    s.bag.push({ id: 'crop_tomato', qty: 2 });
    expect(refuse(s, { type: 'deliver', request: 'r1' })).toMatchObject({ ok: false, code: 'not_enough' });
    s.bag.push({ id: 'crop_chamomile', qty: 2 });
    expect(viewOf(c, s, T0).boards.stall.slots[0]).toMatchObject({ family: 'O', ready: true });
  });

  it('Wholesale Order draws 1.5 × the band, rounded up, of one crop the player can grow', () => {
    const s = fresh();
    s.skills.farming = 10_000;   // Lv10: band 6–10, so 9–15
    s.homestead.level = 3;
    const qty: number[] = [];
    for (let k = 0; k < 600 && qty.length < 30; k++) {
      s.boards.market = [{ req: null, refill_at: T0 + k }, { req: null, refill_at: T0 + k }];
      settleBoards(c, s, T0 + 600);
      for (const sl of s.boards.market) if (sl.req?.template === 'req_sys_crop_bulk') {
        expect(sl.req.items.length).toBe(1);
        qty.push(sl.req.qty);
      }
    }
    expect(qty.length).toBeGreaterThan(0);
    expect(Math.min(...qty)).toBeGreaterThanOrEqual(9);
    expect(Math.max(...qty)).toBeLessThanOrEqual(15);
    expect(Math.max(...qty)).toBeGreaterThan(10);   // more than the plain band ever gives
  });
});

describe('regional templates (§9.6.3; drawn only once one of their items can be got)', () => {
  // A content copy where the farm line sells the regional seed at the market and the fishing line puts the city's fish in
  // the pond, as their PRs will.
  const opened = () => {
    const k = structuredClone(c);
    k.market.buy = [...k.market.buy, 'seed_pumpkin'];
    k.fishing.sites.pond.fish = [...k.fishing.sites.pond.fish, 'fish_smelt'];
    return k;
  };

  it('nothing regional draws while no regional item can be got', () => {
    const s = fresh();
    s.skills.farming = 10_000; s.skills.fishing = 10_000; s.skills.cooking = 10_000; s.homestead.level = 5;
    const open = eligible(c, s, 'market');
    for (const id of ['req_sys_regional_crop', 'req_sys_regional_fish', 'req_sys_regional_dish', 'req_sys_regional_far_fish', 'req_sys_regional_far_crop'])
      expect(open, id).not.toContain(id);
  });

  it('home climate, home city and other climates pick their own items', () => {
    const k = opened();
    const pools = (need: Parameters<typeof regionalPool>[1]) => regionalPool(k, need);
    expect(pools({ kind: 'crop', regional: 'zone' })).toEqual(['crop_pumpkin']);   // San Francisco is Temperate
    expect(pools({ kind: 'fish', regional: 'city' })).toEqual(['fish_smelt']);     // SF's two are Smelt and Salmon; Salmon is in no pond yet
    expect(pools({ kind: 'crop', regional: 'other_zone' })).toEqual([]);            // the other climates' seeds are not on sale here
    expect(pools({ kind: 'fish', regional: 'other_zone' })).toEqual([]);
    const s = fresh();
    s.skills.farming = 10_000; s.skills.fishing = 10_000;
    expect(eligible(k, s, 'market')).toEqual(expect.arrayContaining(['req_sys_regional_crop', 'req_sys_regional_fish']));
  });

  it('Taste of Home draws the climate crop and takes only that crop', () => {
    const k = opened();
    let s = fresh();
    s.skills.farming = 10_000;
    s.boards.market = [{ req: null, refill_at: T0 }, { req: null, refill_at: T0 }];
    let found: BoardRequest | null = null;
    for (let k2 = 0; k2 < 400 && !found; k2++) {
      s.boards.market = [{ req: null, refill_at: T0 + k2 }, { req: null, refill_at: T0 + k2 }];
      settleBoards(k, s, T0 + 400);
      found = s.boards.market.map(sl => sl.req).find(r => r?.template === 'req_sys_regional_crop') ?? null;
    }
    expect(found).toMatchObject({ items: ['crop_pumpkin'], kind: 'crop' });
  });
});

describe('Stamp Run (§9.6.3 explore: check in at another outpost)', () => {
  const stamp = (place = 'sh_tea_1'): P0State => {
    const s = fresh();
    s.homestead.level = 2;
    s.boards.market[0] = { req: { id: 'v1', template: 'req_sys_explore_outpost', items: [], kind: 'visit', qty: 1, bonus: 40, drawn_at: T0,
      status: 'open', visit: { place, done: false } }, refill_at: 0 };
    return s;
  };

  it('opens at Homestead Lv2 and sends the player to an outpost other than the market square', () => {
    const s = fresh();
    expect(eligible(c, s, 'market')).not.toContain('req_sys_explore_outpost');
    s.homestead.level = 2;
    expect(eligible(c, s, 'market')).toContain('req_sys_explore_outpost');
    expect(visitPlaces(c, 'market')).not.toContain('sh_market_1');
    expect(visitPlaces(c, 'market').length).toBe(3);
  });

  it('a tracked Stamp Run checks in when the player enters its outpost, then pays 40 at the board', () => {
    let s = step(stamp(), { type: 'accept', request: 'v1' }).s;
    expect(refuse(s, { type: 'deliver', request: 'v1' })).toMatchObject({ ok: false, code: 'not_visited', detail: { place: 'sh_tea_1' } });
    expect(viewOf(c, s, T0).map_markers).toContainEqual({ place: 'sh_tea_1', kind: 'request', why: { request: 'v1', tracked: true } });
    // entering another outpost does nothing; entering the tea house checks in
    s = step(s, { type: 'read_inbox', keys: [], space: 'outpost', place: 'sh_post_1' }).s;
    expect(s.boards.market[0].req?.visit?.done).toBe(false);
    const r = step(s, { type: 'read_inbox', keys: [], space: 'outpost', place: 'sh_tea_1' });
    expect(r.ev).toContainEqual({ kind: 'visit', id: 'v1', place: 'sh_tea_1' });
    expect(viewOf(c, r.s, T0).boards.market.slots[0]).toMatchObject({ kind: 'visit', visit: { place: 'sh_tea_1', done: true }, have: 1, ready: true });
    const d = step(r.s, { type: 'deliver', request: 'v1', space: 'outpost', place: 'sh_market_1' });
    expect(d.ev.find(e => e.kind === 'request' && e.status === 'done')).toMatchObject({ coins: 40, bonus: 40 });
  });

  it('an untracked one does not check in; the entry read of the outpost checks in too', async () => {
    let s = stamp();
    s = step(s, { type: 'read_inbox', keys: [], space: 'outpost', place: 'sh_tea_1' }).s;
    expect(s.boards.market[0].req?.visit?.done).toBe(false);
    const { default: Fastify } = await import('fastify');
    const { registerP0Routes } = await import('../../src/p0/routes.js');
    const { P0Store } = await import('../../src/p0/store.js');
    const store = new P0Store(c);
    const app = Fastify();
    registerP0Routes(app, { content: c, store, now: () => T0, dev: false });
    try {
      const t = store.get('p1-stamp-run', T0);
      Object.assign(t, step(stamp(), { type: 'accept', request: 'v1' }).s, { player: 'p1-stamp-run' });
      store.put(t);
      await app.inject({ method: 'GET', url: '/v1/p0/state?space=outpost&place=sh_tea_1', headers: { 'x-p0-player': 'p1-stamp-run' } });
      expect(store.get('p1-stamp-run', T0).boards.market[0].req?.visit?.done).toBe(true);
    } finally { await app.close(); }
  });
});
