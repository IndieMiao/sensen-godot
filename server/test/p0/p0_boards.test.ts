import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, count, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type BoardRequest, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const content = loadP0Content();
// The 04:00 instants in these tests are Shanghai's (UTC+8), whatever the home city is; p0_city_switch checks the city's zone.
const c = { ...content, profile: { ...content.profile, timezone: 'Asia/Shanghai' } };
const T0 = Date.UTC(2026, 9, 8, 2, 0, 0); // 10:00 Shanghai
const H = 3_600_000;

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const refuse = (s: P0State, cmd: P0Command, now = T0) => applyP0(c, s, cmd, now);
const fresh = () => freshState(c, 'player-board-01', T0, 5);
const req = (over: Partial<BoardRequest>): BoardRequest => ({
  id: 'r1', template: 'req_sys_fish_common', items: [], rarity: 1, kind: 'fish', qty: 2, bonus: 10, drawn_at: T0, status: 'open', ...over });
const done = (ev: P0Event[]) => ev.find(e => e.kind === 'request' && e.status === 'done') as Extract<P0Event, { kind: 'request' }>;

describe('Stall Board (§9.6, §14.1.2)', () => {
  it('a new homestead has the tutorial in slot 1 and slot 2 empty for 72 h; the Market Board shows its lowest gate', () => {
    const v = viewOf(c, fresh(), T0);
    expect(v.boards.stall.slots).toHaveLength(2);
    expect(v.boards.stall.slots[0]).toMatchObject({ id: 'req_pond_catch', title: 'Pond Catch', items: ['fish_crucian'], qty: 2, coins: 14, base: 4, bonus: 10, status: 'open', expires_in: null });
    expect(v.boards.stall.slots[1]).toEqual({ empty: true, held: true });   // held 72 h: no countdown, not "Next request" (q(99))
    expect(v.boards.market.slots[0]).toMatchObject({ empty: true, locked: { template: 'req_sys_fish_fine', title: 'Dusk Haul', gate: [['fishing', 3]] } });
  });

  it('the held slot never counts as the next request; after the tutorial the freed slot does (q(99))', () => {
    let s = fresh();
    expect(viewOf(c, s, T0 + 10 * 60_000).stall.board.refill_in).toBe(0);   // legacy shape: no refilling slot yet
    s.bag.push({ id: 'fish_crucian', qty: 2 });
    s = step(s, { type: 'accept', request: 'req_pond_catch' }).s;
    s = step(s, { type: 'deliver', request: 'req_pond_catch' }).s;
    const v = viewOf(c, s, T0);
    expect(v.boards.stall.slots[0]).toEqual({ empty: true, refill_in: 4 * H });   // the tutorial's slot: back in 4 h
    expect(v.boards.stall.slots[1]).toEqual({ empty: true, held: true });          // still held
    expect(v.stall.board.refill_in).toBe(4 * H);
    s = step(s, { type: 'drop', request: (viewOf(c, s, T0 + 5 * H).boards.stall.slots[0] as { id: string }).id }, T0 + 5 * H).s;
    expect(viewOf(c, s, T0 + 5 * H).boards.stall.slots[0]).toEqual({ empty: true, refill_in: 8 * H });   // a drop's wait still counts
  });

  it('slot 2 fills after 72 h; the view and the next command see the same request', () => {
    const s = fresh();
    const at = T0 + 73 * H;
    const shown = viewOf(c, s, at).boards.stall.slots[1] as { id: string; template: string };
    expect(shown.id).toMatch(/^req_sys_/);
    expect(['req_sys_crop_basic', 'req_sys_fish_common', 'req_sys_dish_common']).toContain(shown.template); // Timber Run waits for materials
    const r = step(s, { type: 'accept', request: shown.id }, at);
    expect(r.s.boards.stall[1].req).toMatchObject({ id: shown.id, status: 'accepted' });
  });

  it('delivery pays floor × qty + bonus, frees the slot for 4 h; a repeat says request_done', () => {
    const s = fresh();
    s.boards.stall[1] = { req: req({ id: 'r1' }), refill_at: 0 };
    s.bag.push({ id: 'fish_carp', qty: 1 }, { id: 'fish_crucian', qty: 3 });
    const r = step(s, { type: 'deliver', request: 'r1' });
    expect(count(r.s.bag, 'fish_crucian')).toBe(1);   // the cheapest Common fish go first
    expect(count(r.s.bag, 'fish_carp')).toBe(1);
    expect(done(r.ev)).toMatchObject({ coins: 2 * 2 + 10, bonus: 10 });
    expect(r.s.boards.stall[1]).toEqual({ req: null, refill_at: T0 + 4 * H });
    expect(refuse(r.s, { type: 'deliver', request: 'r1' })).toMatchObject({ ok: false, code: 'request_done' });
  });

  it('a dropped request refills after 8 h; an untaken one is swapped after 72 h', () => {
    const s = fresh();
    s.boards.stall[1] = { req: req({ id: 'r1' }), refill_at: 0 };
    expect(step(s, { type: 'drop', request: 'r1' }).s.boards.stall[1]).toEqual({ req: null, refill_at: T0 + 8 * H });
    const later = viewOf(c, s, T0 + 73 * H).boards.stall.slots[1] as { id: string };
    expect(later.id).not.toBe('r1');
    // the tutorial is never swapped out
    expect(viewOf(c, s, T0 + 30 * 24 * H).boards.stall.slots[0]).toMatchObject({ id: 'req_pond_catch' });
  });

  it('tracks at most 3 requests at once', () => {
    let s = fresh();
    s.homestead.level = 3;
    s.boards.stall = [{ req: req({ id: 'a' }), refill_at: 0 }, { req: req({ id: 'b' }), refill_at: 0 }, { req: req({ id: 'c' }), refill_at: 0 }];
    s.boards.market = [{ req: req({ id: 'd', template: 'req_sys_fish_fine', rarity: 2, bonus: 20 }), refill_at: 0 }];
    for (const id of ['a', 'b', 'c']) s = step(s, { type: 'accept', request: id }).s;
    expect(refuse(s, { type: 'accept', request: 'd' })).toMatchObject({ ok: false, code: 'track_limit', detail: { max: 3 } });
  });

  it('6 system requests a day; completion bonuses share a 100-coin daily cap', () => {
    let s = fresh();
    s.day.sys_done = 5; s.day.bonus = 95;
    s.day.key = '2026-10-08';
    s.boards.stall = [{ req: req({ id: 'a' }), refill_at: 0 }, { req: req({ id: 'b' }), refill_at: 0 }];
    s.bag.push({ id: 'fish_crucian', qty: 4 });
    const r = step(s, { type: 'deliver', request: 'a' });
    expect(done(r.ev)).toMatchObject({ coins: 4 + 5, bonus: 5 });
    expect(refuse(r.s, { type: 'deliver', request: 'b' })).toMatchObject({ ok: false, code: 'daily_limit', detail: { cap: 6 } });
    s = r.s;
    expect(viewOf(c, s, T0).quotas.request_bonus).toMatchObject({ used: 100, cap: 100 });
  });

  it('gift meals are never handed in; short deliveries say what is missing', () => {
    const s = fresh();
    s.boards.stall[1] = { req: req({ id: 'r1', template: 'req_sys_dish_common', kind: 'dish' }), refill_at: 0 };
    s.bag.push({ id: 'dish_carrot_cake', qty: 2, gift: { from: 'res_pip', day: '2026-10-08' } });
    expect(refuse(s, { type: 'deliver', request: 'r1' })).toMatchObject({ ok: false, code: 'not_enough', detail: { need: 2, have: 0 } });
  });
});

describe('Market Board (§9.6.3, §9.13.2)', () => {
  it('opens Dusk Haul at Fishing Lv3 with a 20 bonus; quantity follows the skill band', () => {
    const s = fresh();
    s.skills.fishing = 220; // Lv3
    const slots = viewOf(c, s, T0).boards.market.slots as { template: string; bonus: number; qty: number }[];
    // Lv3 opens Dusk Haul and, from P1, Local Waters (the city's regional fish swim in its ponds, SGODOT-283)
    for (const x of slots) expect(['req_sys_fish_fine', 'req_sys_regional_fish']).toContain(x.template);
    for (const x of slots.filter(x => x.template === 'req_sys_fish_fine')) {
      expect(x.bonus).toBe(20); expect(x.qty).toBeGreaterThanOrEqual(2); expect(x.qty).toBeLessThanOrEqual(3);
    }
  });

  it('Market Basket takes N of each of three crops; A Proper Meal pays the quality bonus on the whole request', () => {
    let s = fresh();
    s.boards.market = [
      { req: req({ id: 'mb', template: 'req_sys_crop_mixed', kind: 'crop', items: ['crop_radish', 'crop_lettuce', 'crop_herb'], rarity: undefined, qty: 2, bonus: 20 }), refill_at: 0 },
      { req: req({ id: 'pm', template: 'req_sys_dish_fine', kind: 'dish', rarity: 2, qty: 2, bonus: 20 }), refill_at: 0 },
    ];
    s.bag.push({ id: 'crop_radish', qty: 2 }, { id: 'crop_lettuce', qty: 2 }, { id: 'crop_herb', qty: 1 });
    expect(refuse(s, { type: 'deliver', request: 'mb' })).toMatchObject({ ok: false, code: 'not_enough', detail: { item: 'crop_herb', need: 2, have: 1 } });
    s.bag.push({ id: 'crop_herb', qty: 1 });
    const mb = step(s, { type: 'deliver', request: 'mb' });
    expect(done(mb.ev).coins).toBe((4 + 6 + 0) * 2 + 20);   // floors: radish 4, lettuce 6, herb 0
    s = mb.s;
    s.bag.push({ id: 'dish_fish_soup@perfect', qty: 1 }, { id: 'dish_fish_soup@good', qty: 1 });
    const pm = step(s, { type: 'deliver', request: 'pm' });
    // Fresh Fish Soup buyback 6 each (§7.14, q(42)); the lowest quality handed in is Good: +10% on the whole request
    expect(done(pm.ev)).toMatchObject({ coins: Math.floor(12 * 1.1) + Math.floor(20 * 1.1), bonus: 22 });
  });

  it('a third Stall Board slot opens at Homestead Lv3', () => {
    const s = fresh();
    s.homestead.level = 3;
    expect(viewOf(c, s, T0).boards.stall.slots).toHaveLength(3);
    expect(viewOf(c, s, T0).stall.board.slots).toBe(3);
  });
});
