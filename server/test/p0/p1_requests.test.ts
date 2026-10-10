import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { eligible, settleBoards } from '../../src/p0/boards.js';
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

  it('regional, explore and together templates stay off until travel; climate is written as profile.climate is', () => {
    for (const [id, t] of Object.entries(c.requests.templates)) {
      if (t.type && t.type !== 'output') expect(t.enabled, id).toBe(false);
      for (const z of t.climate ?? []) expect(z[0], id).toBe(z[0].toUpperCase());
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
