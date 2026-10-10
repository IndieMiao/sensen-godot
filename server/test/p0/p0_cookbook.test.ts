/** SGODOT-232 S5: Cookbook page states, Kitchen Mishaps and clues, trial refunds and the P0 Cooking conveniences. */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, count, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 8, 2);   // 10:00 Shanghai
const S = 1000, H = 3_600_000;
const fresh = () => freshState(c, 'cookbook-player', T0, 7);
const veteran = () => ({ ...fresh(), created_at: T0 - 8 * 24 * H });   // past the Newcomer Blessing
function step(s: P0State, cmd: P0Command, at = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, at);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`);
  return { s: r.state, ev: r.events };
}
/** Cook these items and collect when done, Plain (no taps). */
function cookOnce(s: P0State, items: string[], at = T0) {
  const started = step(s, { type: 'cook', items }, at);
  return { ...step(started.s, { type: 'collect' }, at + started.s.stove!.ms + S), pot: started.ev.find(e => e.kind === 'pot')! };
}
const page = (s: P0State, id: string) => viewOf(c, s, T0).cooking.cookbook.find(p => p.id === id)!;

describe('Cookbook pages (§7.5.1, q(39))', () => {
  it('lists 48 pages in order: 24 cookable in this build and 24 silhouettes; the two starting pages are Tasted', () => {
    const v = viewOf(c, fresh(), T0).cooking;
    expect(v.cookbook.map(p => p.n)).toEqual(Array.from({ length: 48 }, (_, i) => i + 1));
    expect(v.cookbook.filter(p => p.p0)).toHaveLength(24);
    expect(v).toMatchObject({ pages_total: 48, discovered: 0, conveniences: [], third_slot: { level: 4, xp_to_go: 220 } });
    expect(v.cookbook.filter(p => p.state === 'tasted').map(p => p.id)).toEqual(['dish_grilled_crucian', 'dish_radish_salad']);
    const hidden = v.cookbook.find(p => p.id === 'dish_carrot_cake')!;
    expect(hidden).toMatchObject({ state: 'hidden', name: null, in: ['?', '?'], families: ['F', 'F'], learn: ['experiment', 'card', 'taught'] });
    const silhouette = v.cookbook.find(p => p.n === 8)!;   // Cabbage Stew: no cabbage yet; its families still show
    expect(silhouette).toMatchObject({ id: 'dish_cabbage_stew', p0: false, name: null, families: ['F', 'F'], can_cook: false, maybe: false });
    expect(v.cookbook.find(p => p.n === 9)).toMatchObject({ id: 'dish_travel_biscuits', p0: false, slots: 0, buy: { at: 'travel_post', price: 40, daily: 3 } });
    expect(v.cookbook.find(p => p.n === 47)).toMatchObject({ rarity: 4, buff: 'buff_creel', regional: true });   // P3 slot: Buff · coming later
    expect(v.cookbook.find(p => p.id === 'dish_fisher_stew')).toMatchObject({ slots: 3, lock: { level: 4, xp_to_go: 220 } });
  });

  it('cooking a page discovers it; ten pots master it and widen its gold arc by 10 points', () => {
    let s = veteran();
    s.bag.push({ id: 'fish_crucian', qty: 10 });
    s.fires = 1;   // past the teaching ring
    for (let i = 0; i < 10; i++) s = cookOnce(s, ['fish_crucian'], T0 + i * 10 * S).s;
    expect(page(s, 'dish_grilled_crucian')).toMatchObject({ state: 'mastered', cooked: true, cooked_total: 10, best: 0, first_at: T0 + 6 * S });
    expect(viewOf(c, s, T0).cooking.discovered).toBe(1);
    s.bag.push({ id: 'fish_crucian', qty: 1 });
    const pot = step(s, { type: 'cook', items: ['fish_crucian'] }, T0 + 200 * S).s.stove!;
    expect(pot.heats[0].width).toBe(0.45);   // Common 0.35 + Mastered 0.10
  });

  it('shows "You might have what it takes" on a Hidden page whose families the stove can fill', () => {
    const s = fresh();
    expect(page(s, 'dish_carrot_cake').maybe).toBe(false);
    s.bag.push({ id: 'crop_carrot', qty: 2 });
    expect(page(s, 'dish_carrot_cake').maybe).toBe(true);
  });
});

describe('Kitchen Mishaps and clues (§7.5.2)', () => {
  it('a new failed combination is recorded and turns one slot of a page that uses it; a repeat only counts', () => {
    let s = veteran();
    s.bag.push({ id: 'crop_radish', qty: 2 }, { id: 'crop_carrot', qty: 2 });
    let r = cookOnce(s, ['crop_radish', 'crop_carrot']);
    expect(r.pot).toMatchObject({ dish: null, tried: false });
    expect(r.ev.find(e => e.kind === 'mishap')).toMatchObject({ tried: false, refund: [],
      clue: { page: 'dish_veggie_plate', slots: [0] } });   // Veggie Plate takes any Common vegetable; Carrot Cake needs Farming Lv2
    expect(page(r.s, 'dish_veggie_plate')).toMatchObject({ state: 'clued', in: ['F1'] });
    expect(count(r.s.bag, 'dish_mystery')).toBe(1);
    s = r.s;
    r = cookOnce(s, ['crop_carrot', 'crop_radish'], T0 + 20 * S);
    expect(r.pot).toMatchObject({ tried: true });
    expect(r.ev.find(e => e.kind === 'mishap')).toMatchObject({ tried: true, clue: null });
    expect(viewOf(c, r.s, T0).cooking.mishaps).toEqual([{ items: ['crop_carrot', 'crop_radish'], n: 2, at: T0 + 5 * S + S }]);
  });

  it('Cooking Lv3 (Double Clue) turns two slots, matching slots first', () => {
    const s = veteran();
    s.skills.cooking = 100;   // Lv3
    s.skills.farming = 50;    // Lv2: carrots can be had
    s.bag.push({ id: 'crop_carrot', qty: 2 }, { id: 'crop_herb', qty: 1 }, { id: 'crop_lettuce', qty: 1 });
    const r = cookOnce(s, ['crop_carrot', 'crop_lettuce']);
    expect(r.ev.find(e => e.kind === 'mishap')).toMatchObject({ clue: { page: 'dish_veggie_plate', slots: [0] } });
    const r2 = cookOnce(r.s, ['crop_carrot', 'crop_herb'], T0 + 20 * S);
    // Carrot Cake (Common, uses carrot, now obtainable) gets both slots at once.
    expect(r2.ev.find(e => e.kind === 'mishap')).toMatchObject({ clue: { page: 'dish_carrot_cake', slots: [0, 1] } });
  });

  it('in the Newcomer Blessing the first 10 failures a day give the ingredients back and make no dish, then Common ones are spent', () => {
    let s = fresh();
    s.bag.push({ id: 'crop_radish', qty: 20 }, { id: 'crop_carrot', qty: 20 });
    expect(viewOf(c, s, T0).cooking.trial_refunds).toBe(10);
    for (let i = 0; i < 10; i++) {
      const r = cookOnce(s, ['crop_radish', 'crop_carrot'], T0 + i * 20 * S);
      expect(r.ev.find(e => e.kind === 'mishap')).toMatchObject({ refund: ['crop_radish', 'crop_carrot'], trial_left: 9 - i });
      // 李白 2026-10-08: no Mystery Dish from a refunded pot (No dish this time · ingredients back)
      expect(r.ev.find(e => e.kind === 'dish')).toMatchObject({ mystery: true, qty: 0, none: true, trial_left: 9 - i });
      expect(r.s.stove).toBeNull();
      s = r.s;
    }
    expect(count(s.bag, 'crop_radish')).toBe(20);
    expect(count(s.bag, c.cooking.mystery.id)).toBe(0);
    const r = cookOnce(s, ['crop_radish', 'crop_carrot'], T0 + 300 * S);
    expect(r.ev.find(e => e.kind === 'mishap')).toMatchObject({ refund: [], trial_left: 0 });
    expect(r.ev.find(e => e.kind === 'dish')).toMatchObject({ mystery: true, qty: 1 });
    expect(r.ev.find(e => e.kind === 'dish')).not.toHaveProperty('none');
    expect(count(r.s.bag, c.cooking.mystery.id)).toBe(1);
    expect(count(r.s.bag, 'crop_radish')).toBe(19);
    expect(viewOf(c, veteran(), T0).cooking.trial_refunds).toBeNull();
  });

  it('Rare and Legendary ingredients always come back from a failed pot', () => {
    const rare = structuredClone(c);
    rare.fish.find(f => f.id === 'fish_bass')!.rarity = 3;
    const s = veteran();
    s.bag.push({ id: 'fish_bass', qty: 1 }, { id: 'crop_radish', qty: 1 }, { id: 'crop_lettuce', qty: 1 });
    const started = applyP0(rare, s, { type: 'cook', items: ['fish_bass', 'crop_radish'] }, T0);
    if (!started.ok) throw new Error(started.code);
    const done = applyP0(rare, started.state, { type: 'collect' }, T0 + started.state.stove!.ms + S);
    if (!done.ok) throw new Error(done.code);
    expect(done.events.find(e => e.kind === 'mishap')).toMatchObject({ refund: ['fish_bass'] });
    expect(count(done.state.bag, 'fish_bass')).toBe(1);
    expect(count(done.state.bag, 'crop_radish')).toBe(0);
  });
});

describe('Cooking Lv1–6 conveniences (q(38))', () => {
  it('lists what the level gives and applies Hearty Mishap, Steady Hand I and Quick Fire', () => {
    const at = (xp: number) => { const s = veteran(); s.skills.cooking = xp; s.fires = 1; return s; };
    expect(viewOf(c, at(30), T0).cooking.conveniences).toEqual(['cook_again']);
    expect(viewOf(c, at(100), T0).cooking.conveniences).toEqual(['cook_again', 'clue_double', 'hearty_mishap']);
    expect(viewOf(c, at(650), T0).cooking.conveniences).toEqual(
      ['cook_again', 'clue_double', 'hearty_mishap', 'steady_hand_1', 'queue_two', 'quick_fire']);
    // Hearty Mishap: a Mystery Dish restores 10 from Lv3 (5 before)
    for (const [xp, gain] of [[0, 5], [100, 10]] as const) {
      const s = at(xp); s.energy = { value: 100, tick_ms: T0 }; s.bag.push({ id: 'dish_mystery', qty: 1 });
      expect(step(s, { type: 'eat', item: 'dish_mystery' }).s.energy.value).toBe(100 + gain);
    }
    // Steady Hand I (Lv5): +5 points of gold; Quick Fire (Lv6): time and heat × 0.8
    const lv5 = at(400); lv5.bag.push({ id: 'fish_crucian', qty: 1 });
    expect(step(lv5, { type: 'cook', items: ['fish_crucian'] }).s.stove!).toMatchObject({ ms: 5000, heats: [{ at: 2500, width: 0.4 }] });
    const lv6 = at(650); lv6.bag.push({ id: 'fish_crucian', qty: 1 });
    expect(step(lv6, { type: 'cook', items: ['fish_crucian'] }).s.stove!).toMatchObject({ ms: 4000, heats: [{ at: 2000, width: 0.4 }] });
  });

  it('the 3-slot lock lifts at Cooking Lv4', () => {
    const s = veteran(); s.skills.cooking = 220;
    const v = viewOf(c, s, T0).cooking;
    expect(v.third_slot).toBeNull();
    expect(v.cookbook.find(p => p.id === 'dish_fisher_stew')!.lock).toBeNull();
  });
});

describe('Queue ×2 (Cooking Lv5; 李白 2026-10-08)', () => {
  const lv5 = () => { const s = veteran(); s.skills.cooking = 400; s.fires = 1; return s; };
  const gold = (h: { at: number; gold: number; width: number; spin: number }) => h.at + (h.gold + h.width / 2) * h.spin;

  it('a second pot waits behind the first and fires when the first is kept, judged on the taps sent while it cooked', () => {
    let s = lv5();
    s.bag.push({ id: 'fish_crucian', qty: 1 }, { id: 'crop_carrot', qty: 2 });
    s = step(s, { type: 'cook', items: ['fish_crucian'] }).s;
    const queued = step(s, { type: 'cook', items: ['crop_carrot', 'crop_carrot'] }, T0 + S);
    expect(queued.ev.find(e => e.kind === 'pot')).toMatchObject({ queued: true });
    expect(count(queued.s.bag, 'crop_carrot')).toBe(0);   // paid when queued
    s = queued.s;
    expect(viewOf(c, s, T0 + 2 * S).cooking.queued).toMatchObject({ rarity: 1, ms: 5000, starts_in: 3000 });
    s = step(s, { type: 'heat', taps: [gold(s.stove!.heats[0])] }, T0 + 3 * S).s;
    // any later command keeps the first pot (Good from its heat tap) and fires the queued one at the first one's end
    const later = step(s, { type: 'read_inbox', keys: [] }, T0 + 7 * S);
    expect(count(later.s.bag, 'dish_grilled_crucian@good')).toBe(1);
    expect(later.ev.find(e => e.kind === 'dish')).toMatchObject({ dish: 'dish_grilled_crucian', quality: 1, auto: true });
    expect(later.ev.find(e => e.kind === 'queue')).toMatchObject({ started_at: T0 + 5 * S });
    expect(later.s.stove).toMatchObject({ dish: 'dish_carrot_cake', started_at: T0 + 5 * S });
    expect(later.s.queue).toBeNull();
    // the view shows the same before any command
    expect(viewOf(c, s, T0 + 7 * S).cooking).toMatchObject({ queued: null, stove: { ready_in: 3000 } });
  });

  it('with no room for the first pot the queued one does not fire until the player collects', () => {
    let s = lv5();
    s.bag.push({ id: 'fish_crucian', qty: 1 }, { id: 'crop_carrot', qty: 2 });
    s = step(s, { type: 'cook', items: ['fish_crucian'] }).s;
    s = step(s, { type: 'cook', items: ['crop_carrot', 'crop_carrot'] }, T0 + S).s;
    while (s.bag.length < s.bag_cap) s.bag.push({ id: 'seed_radish', qty: 1 });
    s = step(s, { type: 'read_inbox', keys: [] }, T0 + 10 * S).s;
    expect(s.stove).toMatchObject({ dish: 'dish_grilled_crucian' });
    expect(s.queue).toMatchObject({ dish: 'dish_carrot_cake' });
    // collect judges it but, with no room, leaves the plate on the stove (SGODOT-226 #20): still no second pot
    const judged = step(s, { type: 'collect' }, T0 + 11 * S);
    expect(judged.ev.find(e => e.kind === 'plate')).toMatchObject({ ids: ['dish_grilled_crucian'] });
    expect(judged.ev.some(e => e.kind === 'queue')).toBe(false);
    s = judged.s;
    s.bag.pop();
    const collected = step(s, { type: 'collect' }, T0 + 12 * S);
    expect(count(collected.s.bag, 'dish_grilled_crucian')).toBe(1);
    expect(collected.ev.find(e => e.kind === 'queue')).toMatchObject({ started_at: T0 + 12 * S });
    expect(collected.s.stove).toMatchObject({ dish: 'dish_carrot_cake', started_at: T0 + 12 * S });
  });

  // PR #22 review (刘邦): heat / collect name their pot, and the waiting pot never fires before it was queued.
  const twoPots = () => {
    let s = lv5();
    s.bag.push({ id: 'fish_crucian', qty: 1 }, { id: 'crop_carrot', qty: 2 });
    const first = step(s, { type: 'cook', items: ['fish_crucian'] });
    s = step(first.s, { type: 'cook', items: ['crop_carrot', 'crop_carrot'] }, T0 + S).s;
    return { s, one: s.stove!.id!, two: s.queue!.id! };
  };

  it('every pot has an id: pot and queue events, dish events and the view carry it', () => {
    const { s, one, two } = twoPots();
    expect(two).toBe(one + 1);
    expect(viewOf(c, s, T0 + 2 * S).cooking).toMatchObject({ stove: { id: one }, queued: { id: two } });
    const later = step(s, { type: 'read_inbox', keys: [] }, T0 + 7 * S);
    expect(later.ev.find(e => e.kind === 'dish')).toMatchObject({ pot: one, auto: true });
    expect(later.ev.find(e => e.kind === 'queue')).toMatchObject({ id: two });
    // tried is on every pot, not only on combinations that will fail
    const fresh = veteran(); fresh.fires = 1; fresh.bag.push({ id: 'fish_crucian', qty: 1 });
    expect(step(fresh, { type: 'cook', items: ['fish_crucian'] }).ev.find(e => e.kind === 'pot')).toMatchObject({ tried: false });
  });

  it('collect naming the done pot judges it with its own taps (COOK-4); the waiting pot fires when the view says', () => {
    const { s, one, two } = twoPots();
    const h = s.stove!.heats[0];
    // the view at 7 s already shows the carrot cake fired at 5 s
    expect(viewOf(c, s, T0 + 7 * S).cooking.stove).toMatchObject({ id: two, ready_in: 3000 });
    const r = step(s, { type: 'collect', pot: one, taps: [gold(h)] }, T0 + 7 * S);
    expect(r.ev.find(e => e.kind === 'dish')).toMatchObject({ pot: one, quality: 1 });
    expect(r.ev.find(e => e.kind === 'dish')).not.toHaveProperty('auto');
    expect(r.ev.find(e => e.kind === 'queue')).toMatchObject({ started_at: T0 + 5 * S });
    expect(r.s.stove).toMatchObject({ dish: 'dish_carrot_cake', started_at: T0 + 5 * S });
  });

  it('collect without a pot sees what the view sees; a pot already kept is refused as stale_pot', () => {
    const { s, one, two } = twoPots();
    // no pot: the done crucian is kept first, as the view shows, and the carrot cake is not ready yet
    expect(applyP0(c, s, { type: 'collect' }, T0 + 7 * S)).toMatchObject({ ok: false, code: 'not_ready', detail: { ready_in: 3000 } });
    const kept = step(s, { type: 'read_inbox', keys: [] }, T0 + 7 * S).s;
    expect(applyP0(c, kept, { type: 'collect', pot: one }, T0 + 11 * S)).toMatchObject({ ok: false, code: 'stale_pot', detail: { pot: two } });
    expect(applyP0(c, kept, { type: 'heat', pot: one, taps: [100] }, T0 + 8 * S)).toMatchObject({ ok: false, code: 'stale_pot' });
    expect(step(kept, { type: 'collect', pot: two }, T0 + 11 * S).ev.find(e => e.kind === 'dish')).toMatchObject({ pot: two });
  });

  it('a late heat tap naming the first pot counts for it, not for the pot that fires after it', () => {
    let s = lv5();
    s.bag.push({ id: 'fish_crucian', qty: 2 });
    s = step(s, { type: 'cook', items: ['fish_crucian'] }).s;
    s = step(s, { type: 'cook', items: ['fish_crucian'] }, T0 + S).s;
    const one = s.stove!.id!, h = s.stove!.heats[0];
    // the tap was made in the ring, but arrives after the pot is done (5.2 s)
    const r = step(s, { type: 'heat', pot: one, taps: [gold(h)] }, T0 + 5 * S + 200);
    expect(r.ev.find(e => e.kind === 'dish')).toMatchObject({ pot: one, quality: 1, auto: true });
    expect(r.s.stove).toMatchObject({ started_at: T0 + 5 * S });
    expect(r.s.stove!.taps ?? []).toEqual([]);
  });

  it('a pot queued behind one already done fires now, not at the first one\'s end', () => {
    let s = lv5();
    s.bag.push({ id: 'fish_crucian', qty: 1 }, { id: 'crop_carrot', qty: 2 });
    s = step(s, { type: 'cook', items: ['fish_crucian'] }).s;
    const r = step(s, { type: 'cook', items: ['crop_carrot', 'crop_carrot'] }, T0 + 8 * S);
    expect(r.ev.map(e => e.kind)).toEqual(expect.arrayContaining(['pot', 'dish', 'queue']));
    expect(r.ev.find(e => e.kind === 'queue')).toMatchObject({ started_at: T0 + 8 * S });
    expect(r.s.stove).toMatchObject({ dish: 'dish_carrot_cake', started_at: T0 + 8 * S });
    expect(r.s.queue).toBeNull();
  });

  it('a done pot with no room waits; once a command makes room the waiting pot fires then, not at the first one\'s end', () => {
    let { s, two } = twoPots();
    while (s.bag.length < s.bag_cap) s.bag.push({ id: 'seed_radish', qty: 1 });
    expect(viewOf(c, s, T0 + 9 * S).cooking.queued).toMatchObject({ starts_in: null });
    s = step(s, { type: 'read_inbox', keys: [] }, T0 + 10 * S).s;
    expect(s.stove).toMatchObject({ dish: 'dish_grilled_crucian', no_room: true });
    s.bag.pop();   // room made (as a sell would)
    expect(viewOf(c, s, T0 + 11 * S).cooking.stove).toMatchObject({ id: two, ready_in: 5000 });
    const r = step(s, { type: 'read_inbox', keys: [] }, T0 + 12 * S);
    expect(r.ev.find(e => e.kind === 'dish')).toMatchObject({ auto: true });
    expect(r.s.stove).toMatchObject({ dish: 'dish_carrot_cake', started_at: T0 + 12 * S });
  });

  it('is refused below Cooking Lv5, with a pot already waiting, and while plates are left on the stove', () => {
    const s = veteran(); s.fires = 1;
    s.bag.push({ id: 'fish_crucian', qty: 3 });
    const busy = step(s, { type: 'cook', items: ['fish_crucian'] }).s;
    expect(applyP0(c, busy, { type: 'cook', items: ['fish_crucian'] }, T0 + S)).toMatchObject({ ok: false, code: 'stove_busy', detail: { queued: false } });
    const five = lv5(); five.bag.push({ id: 'fish_crucian', qty: 3 });
    let q = step(five, { type: 'cook', items: ['fish_crucian'] }).s;
    q = step(q, { type: 'cook', items: ['fish_crucian'] }, T0 + S).s;
    expect(applyP0(c, q, { type: 'cook', items: ['fish_crucian'] }, T0 + 2 * S)).toMatchObject({ ok: false, code: 'stove_busy', detail: { queued: true } });
    const plated = lv5(); plated.bag.push({ id: 'fish_crucian', qty: 1 });
    plated.stove = { dish: 'dish_grilled_fish', rarity: 1, started_at: T0, ms: 0, heats: [], xp_pct: 100, mystery: false, left: ['dish_grilled_fish'] };
    expect(applyP0(c, plated, { type: 'cook', items: ['fish_crucian'] }, T0)).toMatchObject({ ok: false, code: 'stove_busy', detail: { left: true } });
  });
});

describe('Cooking a chosen page (q(67): Cookbook Cook and Cook Again cook that page)', () => {
  const knowing = (...bag: { id: string; qty: number }[]) => {
    const s = veteran(); s.fires = 1; s.cookbook.push('dish_grilled_fish'); s.bag.push(...bag); return s;
  };
  const cookPage = (s: P0State, recipe: string, at = T0) => {
    const started = step(s, { type: 'cook', recipe }, at);
    const pot = started.ev.find(e => e.kind === 'pot')!;
    const done = step(started.s, { type: 'collect' }, at + started.s.stove!.ms + S);
    return { s: done.s, pot, items: started.s.stove!.items, dish: done.ev.find(e => e.kind === 'dish')! };
  };

  it('Grilled Fish with only crucians is still Grilled Fish, and its counts go to Grilled Fish', () => {
    let s = knowing({ id: 'fish_crucian', qty: 2 });
    expect(page(s, 'dish_grilled_fish').can_cook).toBe(true);
    const first = cookPage(s, 'dish_grilled_fish');
    expect(first.items).toEqual(['fish_crucian']);
    expect(first.pot).toMatchObject({ dish: 'dish_grilled_fish' });
    expect(first.dish).toMatchObject({ dish: 'dish_grilled_fish' });
    s = first.s;
    expect(s.book.cooked).toMatchObject({ dish_grilled_fish: 1 });
    expect(s.book.cooked.dish_grilled_crucian ?? 0).toBe(0);
    expect(s.day.cooked).toMatchObject({ dish_grilled_fish: 1 });
    const again = cookPage(s, 'dish_grilled_fish', T0 + 60 * S);   // the same page again today: its own diminishing
    expect(again.dish).toMatchObject({ dish: 'dish_grilled_fish' });
    expect(again.s.day.cooked).toMatchObject({ dish_grilled_fish: 2 });
    expect(again.s.day.cooked.dish_grilled_crucian ?? 0).toBe(0);
  });

  it('prefers fish that make the chosen page if laid out freely: a carp before the cheaper crucian', () => {
    const r = cookPage(knowing({ id: 'fish_crucian', qty: 1 }, { id: 'fish_carp', qty: 1 }), 'dish_grilled_fish');
    expect(r.items).toEqual(['fish_carp']);
    expect(count(r.s.bag, 'fish_crucian')).toBe(1);
    expect(count(r.s.bag, 'fish_carp')).toBe(0);
  });

  it('free slots still match by priority: a crucian laid in alone is Grilled Crucian', () => {
    const r = cookOnce(knowing({ id: 'fish_crucian', qty: 1 }), ['fish_crucian']);
    expect(r.pot).toMatchObject({ dish: 'dish_grilled_crucian' });
  });

  it('a chosen page without fitting items is refused, never cooked as another page', () => {
    const s = knowing({ id: 'fish_perch', qty: 1 });   // a Fine fish is not "Any Common fish"
    expect(page(s, 'dish_grilled_fish').can_cook).toBe(false);
    const r = applyP0(c, s, { type: 'cook', recipe: 'dish_grilled_fish' }, T0);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r).toMatchObject({ code: 'missing_ingredients', detail: { recipe: 'dish_grilled_fish' } });
  });
});

describe('A chosen page leaves what else is spoken for (q(99), 李元芳 int12-pre)', () => {
  const herbFish = (bag: [string, number][]) => {
    const s = veteran();
    s.cookbook.push('dish_herb_grilled_fish');
    s.bag = bag.map(([id, qty]) => ({ id, qty }));
    return s;
  };
  it("Herb Grilled Fish's any-fish slot takes the carp, not the only crucian Grilled Crucian names", () => {
    const r = step(herbFish([['fish_crucian', 1], ['fish_carp', 1], ['fish_perch', 1], ['wild_herb', 1]]), { type: 'cook', recipe: 'dish_herb_grilled_fish' });
    expect(r.s.stove!.dish).toBe('dish_herb_grilled_fish');
    expect(r.s.stove!.items).toEqual(expect.arrayContaining(['fish_carp']));
    expect(count(r.s.bag, 'fish_crucian')).toBe(1);   // Today's Cook it: Grilled Crucian can still cook
  });
  it("an accepted request's fish is picked last too (the Stall Board's tutorial included)", () => {
    const s = herbFish([['fish_carp', 1], ['fish_mullet', 1], ['wild_herb', 1]]);
    s.boards.stall[0].req = { ...s.boards.stall[0].req!, items: ['fish_carp'], status: 'accepted' };
    const r = step(s, { type: 'cook', recipe: 'dish_herb_grilled_fish' });
    expect(r.s.stove!.items).toEqual(expect.arrayContaining(['fish_mullet']));
    expect(count(r.s.bag, 'fish_carp')).toBe(1);
  });
  it('with only spoken-for fish left it still cooks the chosen page (q(67))', () => {
    const r = step(herbFish([['fish_crucian', 1], ['wild_herb', 1]]), { type: 'cook', recipe: 'dish_herb_grilled_fish' });
    expect(r.s.stove!.dish).toBe('dish_herb_grilled_fish');
    expect(count(r.s.bag, 'fish_crucian')).toBe(0);
  });
});
