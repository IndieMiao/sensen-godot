import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, count, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 8, 2, 0, 0); // 10:00 Shanghai, player day 2026-10-08
const H = 3_600_000, DAY = 24 * H;

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const refuse = (s: P0State, cmd: P0Command, now = T0) => applyP0(c, s, cmd, now);
const fresh = () => ({ ...freshState(c, 'player-res-01', T0, 3), created_at: T0 - 8 * DAY });
const aff = (ev: P0Event[]) => ev.find(e => e.kind === 'affinity') as Extract<P0Event, { kind: 'affinity' }>;
const pip = (s: P0State, now = T0) => viewOf(c, s, now).residents.res_pip;

describe('affinity (§9.4.4)', () => {
  it('+2 on the first chat of the day, once per resident per day', () => {
    let r = step(fresh(), { type: 'talk', resident: 'res_pip' });
    expect(aff(r.ev)).toMatchObject({ resident: 'res_pip', delta: 2, total: 2, stage: 'Stranger', reason: 'chat' });
    r = step(r.s, { type: 'talk', resident: 'res_pip' }, T0 + H);
    expect(aff(r.ev)).toBeUndefined();
    expect(aff(step(r.s, { type: 'talk', resident: 'res_old_kai' }).ev)).toMatchObject({ resident: 'res_old_kai', delta: 2 });
    expect(aff(step(r.s, { type: 'talk', resident: 'res_pip' }, T0 + DAY).ev)).toMatchObject({ total: 4 });
    expect(refuse(r.s, { type: 'talk', resident: 'res_mira' })).toMatchObject({ ok: false, code: 'bad_resident' });
  });

  it('gifts: liked style and ≥ Fine +3, liked +2, any dish +1, Perfect +1 (cap 4), once a day; crops are not gifts', () => {
    const s = fresh();
    s.bag.push({ id: 'dish_carrot_cake', qty: 2 }, { id: 'dish_herb_grilled_fish@perfect', qty: 1 }, { id: 'dish_radish_salad', qty: 1 }, { id: 'crop_radish', qty: 3 });
    expect(refuse(s, { type: 'gift', resident: 'res_pip', item: 'crop_radish' })).toMatchObject({ ok: false, code: 'not_giftable' });
    const cake = step(s, { type: 'gift', resident: 'res_pip', item: 'dish_carrot_cake' });   // Dessert, Common: liked
    expect(aff(cake.ev)).toMatchObject({ delta: 2, verdict: 'liked', reason: 'gift' });
    expect(count(cake.s.bag, 'dish_carrot_cake')).toBe(1);
    expect(refuse(cake.s, { type: 'gift', resident: 'res_pip', item: 'dish_carrot_cake' })).toMatchObject({ ok: false, code: 'gift_used_today' });
    // Herb Grilled Fish is Grilled and Fine: Old Kai loves it, +1 for Perfect = 4
    expect(aff(step(s, { type: 'gift', resident: 'res_old_kai', item: 'dish_herb_grilled_fish@perfect' }).ev)).toMatchObject({ delta: 4, verdict: 'loved' });
    expect(aff(step(s, { type: 'gift', resident: 'res_old_kai', item: 'dish_radish_salad' }).ev)).toMatchObject({ delta: 1, verdict: 'received' });
    // Chef's Touch at Cooking Lv9: +1 more, cap 5
    s.skills.cooking = 1700;
    expect(aff(step(s, { type: 'gift', resident: 'res_old_kai', item: 'dish_herb_grilled_fish@perfect' }).ev)).toMatchObject({ delta: 5 });
  });

  it('the Mystery Dish is accepted at −2, never below the floor of the current stage (q(33))', () => {
    const s = fresh();
    s.bag.push({ id: 'dish_mystery', qty: 2 });
    s.residents.res_pip = { affinity: 46, chat_day: '', gift_day: '', next: 0, req: null, done_day: '' };
    const r = step(s, { type: 'gift', resident: 'res_pip', item: 'dish_mystery' });
    expect(aff(r.ev)).toMatchObject({ delta: -1, total: 45, stage: 'Familiar', verdict: 'not_a_fan' });
    expect(refuse(r.s, { type: 'gift', resident: 'res_pip', item: 'dish_mystery' })).toMatchObject({ ok: false, code: 'gift_used_today' });
    expect(aff(step(s, { type: 'gift', resident: 'res_old_kai', item: 'dish_mystery' }).ev)).toMatchObject({ delta: 0, total: 0 });
  });
});

describe('gift meal (§3.4.5, K-2, q(33))', () => {
  const familiar = () => {
    const s = fresh();
    s.residents.res_pip = { affinity: 45, chat_day: '', gift_day: '', next: 3, req: null, done_day: '' };
    s.residents.res_old_kai = { affinity: 60, chat_day: '', gift_day: '', next: 1, req: null, done_day: '' };
    return s;
  };

  it('from Familiar, the first resident talked to gives one meal a day into the bag, as its own gifted stack', () => {
    const s = familiar();
    expect(pip(s).meal).toBe('ready');
    const r = step(s, { type: 'talk', resident: 'res_pip' });
    expect(r.ev).toContainEqual({ kind: 'gift_meal', resident: 'res_pip', dish: 'dish_carrot_cake', given: true });
    expect(r.s.bag.find(b => b.gift)).toEqual({ id: 'dish_carrot_cake', qty: 1, gift: { from: 'res_pip', day: '2026-10-08' } });
    const slot = viewOf(c, r.s, T0).bag.slots.find(b => b.gifted)!;
    expect(slot).toMatchObject({ id: 'dish_carrot_cake', gifted: true, from: 'res_pip', expires_in: 18 * H });
    // one meal a day across all residents
    expect(step(r.s, { type: 'talk', resident: 'res_old_kai' }).ev.some(e => e.kind === 'gift_meal')).toBe(false);
    expect(viewOf(c, r.s, T0).residents).toMatchObject({ res_pip: { meal: 'given' }, res_old_kai: { meal: 'none' } });
  });

  it('a full bag holds the meal back without using the day; it can be eaten, not sold or handed in, and is gone at 04:00', () => {
    let s = familiar();
    s.bag = Array.from({ length: 25 }, (_, i) => ({ id: `material_x${i}`, qty: 1 }));
    expect(pip(s).meal).toBe('bag_full');
    let r = step(s, { type: 'talk', resident: 'res_pip' });
    expect(r.ev).toContainEqual({ kind: 'gift_meal', resident: 'res_pip', dish: 'dish_carrot_cake', given: false });
    expect(r.s.day.gift_meal).toBeNull();
    r.s.bag.pop();
    r = step(r.s, { type: 'talk', resident: 'res_pip' }, T0 + H);
    expect(r.s.day.gift_meal).toBe('res_pip');
    s = r.s;
    expect(refuse(s, { type: 'sell', item: 'dish_carrot_cake', qty: 1 })).toMatchObject({ ok: false, code: 'gifted' });
    s.energy = { value: 100, tick_ms: T0 + H };
    expect(step(s, { type: 'eat', item: 'dish_carrot_cake' }, T0 + H).s.energy.value).toBe(120);
    // not eaten: gone after the 04:00 rollover
    expect(count(viewOf(c, s, T0 + 19 * H).bag.slots as never, 'dish_carrot_cake')).toBe(0);
    expect(count(step(s, { type: 'talk', resident: 'res_old_kai' }, T0 + 19 * H).s.bag, 'dish_carrot_cake')).toBe(0);
  });
});

describe('Pip and Old Kai requests (§9.4.3; Li Bai b7d8b665, 719ce953)', () => {
  it("Pip's three requests come one a player day, regardless of stage, and pay +5 and 20 coins each", () => {
    let s = fresh();
    expect(pip(s)).toMatchObject({ request_state: 'open', request: { id: 'req_res_pip_1', kind: 'fish', qty: 1, have: 0 } });
    expect(refuse(s, { type: 'deliver', request: 'req_res_pip_1' })).toMatchObject({ ok: false, code: 'not_accepted' });
    s = step(s, { type: 'accept', request: 'req_res_pip_1' }).s;
    s.bag.push({ id: 'fish_perch', qty: 1 });   // Fine: not what Pip asked for
    expect(refuse(s, { type: 'deliver', request: 'req_res_pip_1' })).toMatchObject({ ok: false, code: 'not_enough', detail: { need: 1, have: 0 } });
    s.bag.push({ id: 'fish_carp', qty: 1 });
    let r = step(s, { type: 'deliver', request: 'req_res_pip_1' });
    expect(r.s.coins).toBe(200);
    expect(aff(r.ev)).toMatchObject({ delta: 5, reason: 'request' });
    expect(count(r.s.bag, 'fish_carp')).toBe(0);
    expect(pip(r.s)).toMatchObject({ request_state: 'wait', request: { id: 'req_res_pip_2' }, next_in: 18 * H });
    expect(refuse(r.s, { type: 'accept', request: 'req_res_pip_2' })).toMatchObject({ ok: false, code: 'request_wait' });
    // ② next day: five plots sown after accepting (the Row Hoe's three count as three)
    const day2 = T0 + DAY;
    s = step(r.s, { type: 'accept', request: 'req_res_pip_2' }, day2).s;
    s = step(s, { type: 'sow', plot: 0, seed: 'seed_radish' }, day2).s;
    expect(refuse(s, { type: 'deliver', request: 'req_res_pip_2' }, day2)).toMatchObject({ ok: false, code: 'not_ready', detail: { progress: 1, need: 5 } });
    s.skills.farming = 300; s.coins = 400;
    s = step(s, { type: 'buy', item: 'tool_row_hoe', qty: 1, shop: 'market' }, day2).s;
    s = step(s, { type: 'sow', plots: [1, 2, 3], seed: 'seed_radish' }, day2).s;
    s = step(s, { type: 'sow', plots: [4, 5, 6], seed: 'seed_radish' }, day2).s;
    expect(pip(s, day2).request).toMatchObject({ have: 5 });
    r = step(s, { type: 'deliver', request: 'req_res_pip_2' }, day2);
    expect(r.s.residents.res_pip.affinity).toBe(10);
    // ③ day 3: any dish, never the Mystery Dish
    const day3 = T0 + 2 * DAY;
    s = step(r.s, { type: 'accept', request: 'req_res_pip_3' }, day3).s;
    s.bag.push({ id: 'dish_mystery', qty: 1 });
    expect(refuse(s, { type: 'deliver', request: 'req_res_pip_3' }, day3)).toMatchObject({ ok: false, code: 'not_enough' });
    s.bag.push({ id: 'dish_radish_salad', qty: 1 });
    r = step(s, { type: 'deliver', request: 'req_res_pip_3' }, day3);
    expect(pip(r.s, day3 + DAY)).toMatchObject({ request_state: 'none', request: null });
    expect(refuse(r.s, { type: 'deliver', request: 'req_res_pip_3' }, day3)).toMatchObject({ ok: false, code: 'request_done' });
  });

  it("Old Kai's one request takes a Rare fish for 50 coins; resident coins share the 100-coin bonus cap", () => {
    let s = fresh();
    s = step(s, { type: 'accept', request: 'req_res_kai_1' }).s;
    expect(viewOf(c, s, T0).residents.res_old_kai).toMatchObject({ request_state: 'accepted', request: { kind: 'fish', rarity: 3, qty: 1, coins: 50, ready: false } });
    s.bag.push({ id: 'fish_koi', qty: 1 });
    s.day.key = '2026-10-08'; s.day.bonus = 70;
    const r = step(s, { type: 'deliver', request: 'req_res_kai_1' });
    expect(r.ev).toContainEqual({ kind: 'request', id: 'req_res_kai_1', status: 'done', coins: 30, bonus: 30 });
    expect(viewOf(c, r.s, T0 + DAY).residents.res_old_kai.request_state).toBe('none');
    expect(refuse(r.s, { type: 'drop', request: 'req_res_kai_1' })).toMatchObject({ ok: false, code: 'cannot_drop' });
  });

  it('resident requests count towards the 3 tracked requests', () => {
    let s = fresh();
    s.boards.stall[1] = { req: { id: 'b1', template: 'req_sys_crop_basic', items: ['crop_radish'], kind: 'crop', qty: 2, bonus: 10, drawn_at: T0, status: 'open' }, refill_at: 0 };
    s = step(s, { type: 'accept', request: 'req_pond_catch' }).s;
    s = step(s, { type: 'accept', request: 'b1' }).s;
    s = step(s, { type: 'accept', request: 'req_res_pip_1' }).s;
    expect(refuse(s, { type: 'accept', request: 'req_res_kai_1' })).toMatchObject({ ok: false, code: 'track_limit' });
  });
});

describe('keeper greeting facts (Li Bai b7d8b665 D, for SGODOT-224 keeper_lines)', () => {
  it('reports cups, Pip, the Market Board, the Reed Rod and the next fish out of reach', () => {
    const s = fresh();
    s.energy = { value: 150, tick_ms: T0 };
    const k = viewOf(c, s, T0, { online: 12 }).keepers;
    expect(k.tea).toEqual({ cups_left: 3, full: false, greet: 'cups_left', online: 12 });
    expect(k.post).toMatchObject({ greet: 'request', request_by: 'res_pip', board_open: 0 });
    expect(k.tackle).toMatchObject({ greet: 'worms', worms_left: 30, next_fish: { pond: { id: 'fish_perch', level: 2 }, river: { id: 'fish_perch', level: 2 } } });
    expect(k.market).toMatchObject({ greet: 'row_hoe', board_open: 0 });
    s.skills.fishing = 220; s.day.drinks = 3; s.day.key = '2026-10-08';
    const k2 = viewOf(c, s, T0).keepers;
    expect(k2.tackle.greet).toBe('reed_rod');
    expect(k2.post.greet).toBe('cups_out');
    expect(k2.tea.online).toBeNull();
    expect(k2.market).toMatchObject({ board_open: 2, board_templates: ['req_sys_fish_fine', 'req_sys_fish_fine'] });
  });
});
