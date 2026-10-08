import { describe, expect, it } from 'vitest';
import { loadP0Content, recipeById } from '../../src/p0/content.js';
import { deriveRarity, heatHits, matchRecipe, recipeRarity } from '../../src/p0/cooking.js';
import { applyP0, count, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 5, 2, 0, 0); // 10:00 Shanghai
const S = 1000, H = 3_600_000;

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const REED = 'pond_shanghai_05', PEBBLE = 'pond_shanghai_04';   // q(36): Reed Pond = Pond template, Pebble Pond = River
// Standing at Reed Pond: casts take their template from the pond the player entered (SGODOT-232 S6).
const fresh = (): P0State => { const s = { ...freshState(c, 'player-test-02', T0, 7), created_at: T0 - 8 * 24 * H }; s.presence.place = REED; return s; };
const catchOf = (ev: P0Event[]) => ev.find(e => e.kind === 'catch') as Extract<P0Event, { kind: 'catch' }>;

/** Cast and wait out the bite, then report the outcome. */
function fishOnce(s: P0State, outcome: 'landed' | 'escaped', at = T0): { s: P0State; ev: P0Event[] } {
  const cast = step(s, { type: 'cast' }, at);
  const bite = cast.s.cast!.bite_ms;
  const reel = step(cast.s, { type: 'reel', outcome }, at + bite + 5 * S);
  return { s: reel.s, ev: [...cast.ev, ...reel.ev] };
}

describe('P0 fishing (§6.1–6.7)', () => {
  it('pre-pays 5 Energy, first bite is a crucian, landing pays catch + first-species + first-cast/landed XP', () => {
    const { s, ev } = fishOnce(fresh(), 'landed');
    expect(s.energy.value).toBe(195);
    expect(catchOf(ev)).toMatchObject({ fish: 'fish_crucian', result: 'landed', refund: 0 });
    expect(count(s.bag, 'fish_crucian')).toBe(1);
    // 10 (first cast) + 5 (catch) + 15 (first crucian) + 10 (first landed) + 10 (first in the city), q(37)
    expect(s.skills.fishing).toBe(50);
  });
  it('line in before the bite refunds all 5 and keeps the novice draw', () => {
    let s = fresh();
    s = step(s, { type: 'cast' }).s;
    const r = step(s, { type: 'reel', outcome: 'cancel' }, T0 + 500);
    expect(r.s.energy.value).toBe(200);
    expect(catchOf(r.ev).result).toBe('cancelled');
    expect(r.s.fishing.bites).toBe(0);
    expect(r.s.cast).toBeNull();
  });
  it('bites 1–3 are Pond Crucian, bite 4 at Lv1 is a Fine fish that breaks free with the level needed', () => {
    let s = fresh();
    for (let i = 0; i < 3; i++) {
      const r = fishOnce(s, 'landed', T0 + i * 60 * S);
      expect(catchOf(r.ev).fish).toBe('fish_crucian');
      s = r.s;
    }
    s.skills.fishing = 10; // keep Lv1 for the teaching bite
    const r = fishOnce(s, 'landed', T0 + 300 * S);
    expect(catchOf(r.ev)).toMatchObject({ fish: 'fish_perch', result: 'broke_free', need_level: 2, refund: 5 });
    expect(r.s.fishing.seen).toContain('fish_perch');
  });
  it('catch protection: Lv1–3 first 10 failures a day refund 5, then 3; Lv4+ always 3', () => {
    let s = fresh();
    s.fishing.bites = 10;
    const refunds: number[] = [];
    for (let i = 0; i < 11; i++) { const r = fishOnce(s, 'escaped', T0 + i * 60 * S); refunds.push(catchOf(r.ev).refund); s = r.s; }
    expect(refunds.slice(0, 10).every(x => x === 5)).toBe(true);
    expect(refunds[10]).toBe(3);
    const pro = fresh();
    pro.fishing.bites = 10; pro.skills.fishing = 480;
    expect(catchOf(fishOnce(pro, 'escaped').ev).refund).toBe(3);
  });
  it('refuses a full creel, short energy, and landing before the bite', () => {
    const full = fresh();
    while (full.bag.length < c.bag.capacity) full.bag.push({ id: 'crop_radish', qty: 1 });
    expect(applyP0(c, full, { type: 'cast' }, T0)).toMatchObject({ ok: false, code: 'creel_full' });
    const tired = fresh(); tired.energy = { value: 4, tick_ms: T0 };
    expect(applyP0(c, tired, { type: 'cast' }, T0)).toMatchObject({ ok: false, code: 'need_energy', detail: { need: 5, have: 4 } });
    const s = step(fresh(), { type: 'cast' }).s;
    expect(applyP0(c, s, { type: 'reel', outcome: 'landed' }, T0 + 100)).toMatchObject({ ok: false, code: 'too_early' });
  });
  it('a River-template pond draws mullet and trout; a Pond-template one never does; mackerel stays Coast-only', () => {
    let s = fresh();
    s.fishing.bites = 10; s.skills.fishing = 480;
    const seen = { pond: new Set<string>(), river: new Set<string>() };
    for (const site of ['pond', 'river'] as const) {
      for (let i = 0; i < 120; i++) {
        const r = applyP0(c, s, { type: 'cast', space: 'pond', place: site === 'pond' ? REED : PEBBLE }, T0 + i * 60 * S);
        if (!r.ok) throw new Error(r.code);
        seen[site].add(r.state.cast!.fish);
        s = { ...r.state, cast: null };
        s.energy.value = 200;
      }
    }
    expect(seen.river.has('fish_trout') && seen.river.has('fish_mullet')).toBe(true);
    expect(seen.pond.has('fish_trout') || seen.pond.has('fish_mullet')).toBe(false);
    expect(seen.pond.has('fish_mackerel') || seen.river.has('fish_mackerel')).toBe(false);
    const away = fresh(); away.presence.place = null;
    expect(applyP0(c, away, { type: 'cast' }, T0)).toMatchObject({ ok: false, code: 'not_at_pond' });
  });
  it('the Starter Rod cannot hold Rare fish even at a high level (rod gate after level gate)', () => {
    const s = fresh();
    s.fishing.bites = 50; s.skills.fishing = 1300; // Lv6
    let rodBreaks = 0;
    let cur = s;
    for (let i = 0; i < 80; i++) {
      const r = fishOnce(cur, 'landed', T0 + i * 60 * S);
      const ev = catchOf(r.ev);
      if (ev.rarity >= 3) { expect(ev.result).toBe('broke_free'); rodBreaks++; }
      cur = r.s;
      cur.energy.value = 200;
      cur.bag = cur.bag.filter(b => !b.id.startsWith('fish_'));
    }
    expect(rodBreaks).toBeGreaterThan(0);
  });
  it('Fishing Lv2 gift: 3 worms, 3 herbs and the Herb Grilled Fish page; worms are consumed at the bite', () => {
    let s = fresh();
    s.skills.fishing = 60;
    s.fishing.bites = 5;
    s = fishOnce(s, 'landed').s;
    expect(count(s.bag, 'bait_worm')).toBe(3);
    expect(count(s.bag, 'wild_herb')).toBe(3);   // q(40): the gift is Wild Herb, a seasoning material
    expect(s.cookbook).toContain('dish_herb_grilled_fish');
    const cast = step(s, { type: 'cast', bait: 'bait_worm' }, T0 + 60 * S);
    expect(cast.s.cast!.bite_ms).toBeLessThanOrEqual(2100);
    expect(cast.s.cast!.fish).toBe('fish_perch'); // pin 3: the first baited bite after Lv2 is a Fine fish
    const done = step(cast.s, { type: 'reel', outcome: 'escaped' }, T0 + 70 * S);
    expect(count(done.s.bag, 'bait_worm')).toBe(2);
  });
});

describe('P0 recipes (§7.2.3 / §7.4.1)', () => {
  it('derives page rarity from ingredient rarity × families', () => {
    // §7.14.0 (q(39)): the 14 P0 pages, Common 5 / Fine 6 / Rare 3, in Cookbook order.
    expect(c.cooking.recipes.map(r => [r.n, r.id, recipeRarity(c, r)])).toEqual([
      [1, 'dish_grilled_crucian', 1], [2, 'dish_grilled_fish', 1], [5, 'dish_radish_salad', 1], [6, 'dish_veggie_plate', 1],
      [7, 'dish_carrot_cake', 1], [10, 'dish_herb_grilled_fish', 2], [11, 'dish_salt_grilled_fish', 2], [12, 'dish_fish_soup', 2],
      [15, 'dish_pan_fried_fish', 2], [17, 'dish_salted_potatoes', 2], [19, 'dish_fruit_tea', 2], [27, 'dish_bass_tomato_stew', 3],
      [28, 'dish_smoked_trout', 3], [37, 'dish_fisher_stew', 3]]);
    expect(c.cooking.recipes.filter(r => r.in.length === 3).every(r => r.in.includes('rock_salt'))).toBe(true);
    expect([...c.cooking.recipes.map(r => r.n), ...c.cooking.pages.map(p => p.n)].sort((a, b) => a! - b!)).toEqual(
      Array.from({ length: 48 }, (_, i) => i + 1));
    expect(deriveRarity(c, [{ family: 'W', rarity: 1 }, { family: 'F', rarity: 1 }, { family: 'S', rarity: 1 }])).toBe(3);
  });
  it('specific pages beat tag pages, fewest wildcards win, otherwise a Mystery Dish', () => {
    expect(matchRecipe(c, ['fish_crucian'])?.id).toBe('dish_grilled_crucian');
    expect(matchRecipe(c, ['fish_carp'])?.id).toBe('dish_grilled_fish');
    expect(matchRecipe(c, ['crop_lettuce', 'crop_radish'])?.id).toBe('dish_radish_salad');
    expect(matchRecipe(c, ['fish_crucian', 'crop_chili'])?.id).toBe('dish_herb_grilled_fish');
    expect(matchRecipe(c, ['fish_crucian', 'rock_salt'])?.id).toBe('dish_salt_grilled_fish');      // a named slot beats "any seasoning"
    expect(matchRecipe(c, ['fish_trout', 'crop_potato', 'rock_salt'])?.id).toBe('dish_fisher_stew');
    expect(matchRecipe(c, ['fish_trout', 'wild_herb', 'rock_salt'])?.id).toBe('dish_smoked_trout');
    expect(matchRecipe(c, ['fish_trout', 'crop_herb', 'rock_salt'])).toBeNull();                   // Smoked Trout takes Wild Herb only
    expect(matchRecipe(c, ['fish_carp', 'fish_carp'])).toBeNull();                                  // Carp Fish Cakes is P1
    expect(matchRecipe(c, ['crop_tomato'])).toBeNull();                                             // so is Roast Veggies
    expect(matchRecipe(c, ['crop_radish', 'crop_carrot'])).toBeNull();
  });
});

describe('P0 cooking (§7.2.4–7.2.5 / §7.6.2)', () => {
  const withFish = () => { const s = fresh(); s.bag.push({ id: 'fish_crucian', qty: 5 }); return s; };
  it('a known page cooks in one tap; collect before 5 s is refused; a gold tap makes it Good', () => {
    let s = withFish();
    const pot = step(s, { type: 'cook', recipe: 'dish_grilled_crucian' });
    s = pot.s;
    expect(count(s.bag, 'fish_crucian')).toBe(4);
    expect(s.stove!.heats[0]).toMatchObject({ at: 2500, spin: 2000, width: 0.5 }); // first fire teaches with a wide arc
    expect(applyP0(c, s, { type: 'collect' }, T0 + 4 * S)).toMatchObject({ ok: false, code: 'not_ready' });
    const h = s.stove!.heats[0];
    const tap = h.at + (h.gold + h.width / 2) * h.spin;
    const done = step(s, { type: 'collect', taps: [tap] }, T0 + 6 * S);
    expect(count(done.s.bag, 'dish_grilled_crucian@good')).toBe(1);
    expect(done.s.skills.cooking).toBe(15); // 10 first-cook + floor(4 × 1.25) Good base XP (§14.2.2)
    expect(done.s.energy.value).toBe(200);  // cooking costs no energy
  });
  it('judges only the first tap per ring; misses stay Plain', () => {
    const heat = { at: 2500, spin: 1600, gold: 0.5, width: 0.35 };
    const goldMid = 2500 + 0.675 * 1600;
    expect(heatHits(c, [heat], [goldMid])).toBe(1);
    expect(heatHits(c, [heat], [2600, goldMid])).toBe(0);
    expect(heatHits(c, [heat], [2500 + 0.5 * 1600 - 140])).toBe(1); // inside the 150 ms tolerance
    expect(heatHits(c, [heat], [])).toBe(0);
  });
  it('repeat cooking XP: level difference, then same-page decay 100/50/0, then quality', () => {
    let s = withFish();
    s.firsts.push('cook:dish_grilled_crucian');
    s.fires = 3;
    const xp: number[] = [];
    for (let i = 0; i < 3; i++) {
      s = step(s, { type: 'cook', recipe: 'dish_grilled_crucian' }, T0 + i * 10 * S).s;
      const before = s.skills.cooking;
      s = step(s, { type: 'collect', taps: [] }, T0 + i * 10 * S + 6 * S).s;
      xp.push(s.skills.cooking - before);
    }
    expect(xp).toEqual([4, 2, 0]);
  });
  it('experiment discovers a page; unmatched sets become a Mystery Dish with no XP', () => {
    let s = fresh();
    s.bag.push({ id: 'crop_carrot', qty: 2 });
    s = step(s, { type: 'cook', items: ['crop_carrot', 'crop_carrot'] }).s;
    s = step(s, { type: 'collect' }, T0 + 6 * S).s;
    expect(s.cookbook).toContain('dish_carrot_cake');
    s.bag.push({ id: 'crop_radish', qty: 1 }, { id: 'crop_carrot', qty: 1 });
    s = step(s, { type: 'cook', items: ['crop_radish', 'crop_carrot'] }, T0 + 10 * S).s;
    const before = s.skills.cooking;
    s = step(s, { type: 'collect' }, T0 + 30 * S).s;
    expect(count(s.bag, 'dish_mystery')).toBe(1);
    expect(s.skills.cooking).toBe(before);
  });
  it('refuses seasoning-only pots, ornamental fish, a third slot before Cooking Lv4, and a busy stove', () => {
    const s = fresh();
    s.bag.push({ id: 'crop_herb', qty: 3 }, { id: 'fish_koi', qty: 1 }, { id: 'fish_crucian', qty: 3 }, { id: 'crop_radish', qty: 1 });
    expect(applyP0(c, s, { type: 'cook', items: ['crop_herb'] }, T0)).toMatchObject({ ok: false, code: 'needs_main' });
    expect(applyP0(c, s, { type: 'cook', items: ['fish_koi'] }, T0)).toMatchObject({ ok: false, code: 'not_for_cooking' });
    expect(applyP0(c, s, { type: 'cook', items: ['fish_crucian', 'crop_herb', 'crop_radish'] }, T0)).toMatchObject({ ok: false, code: 'bad_slots', detail: { slots: 2 } });
    const busy = step(s, { type: 'cook', items: ['fish_crucian'] }).s;
    expect(applyP0(c, busy, { type: 'cook', items: ['fish_crucian'] }, T0 + S)).toMatchObject({ ok: false, code: 'stove_busy' });
    s.skills.cooking = 220;
    expect(applyP0(c, s, { type: 'cook', items: ['fish_crucian', 'crop_herb', 'crop_radish'] }, T0).ok).toBe(true);
  });
  it('Perfect on a two-heat Rare page gives a second Plain portion', () => {
    let s = fresh();
    s.bag.push({ id: 'fish_bass', qty: 1 }, { id: 'crop_tomato', qty: 1 });
    s.fires = 1;
    s = step(s, { type: 'cook', items: ['fish_bass', 'crop_tomato'] }).s;
    const taps = s.stove!.heats.map(h => h.at + (h.gold + h.width / 2) * h.spin);
    s = step(s, { type: 'collect', taps }, T0 + 31 * S).s;
    expect(count(s.bag, 'dish_bass_tomato_stew@perfect')).toBe(1);
    expect(count(s.bag, 'dish_bass_tomato_stew')).toBe(1);
    expect(s.skills.cooking).toBe(64); // first Rare 40 + Perfect base 16 × 1.5
  });
});

describe('P0 eating (§7.17.1)', () => {
  const hungry = () => { const s = fresh(); s.energy = { value: 100, tick_ms: T0 }; return s; };
  it('same dish: full, half rounded up, then nothing; meals count the nominal value', () => {
    let s = hungry();
    s.bag.push({ id: 'dish_grilled_crucian@good', qty: 1 }, { id: 'dish_grilled_crucian', qty: 2 });
    const gains: number[] = [];
    for (const id of ['dish_grilled_crucian@good', 'dish_grilled_crucian', 'dish_grilled_crucian']) {
      const r = step(s, { type: 'eat', item: id });
      gains.push((r.ev.find(e => e.kind === 'meal') as Extract<P0Event, { kind: 'meal' }>).gain);
      s = r.s;
    }
    expect(gains).toEqual([25, 10, 0]);
    expect(s.day.meals).toBe(35);
    expect(viewOf(c, s, T0).meals).toMatchObject({ used: 35, cap: 200 });
  });
  it('refuses at full energy; near full the gain is clipped but the meal still counts in full', () => {
    const full = fresh(); full.bag.push({ id: 'dish_fish_soup', qty: 1 });
    expect(applyP0(c, full, { type: 'eat', item: 'dish_fish_soup' }, T0)).toMatchObject({ ok: false, code: 'energy_full' });
    const near = fresh(); near.energy = { value: 188, tick_ms: T0 }; near.bag.push({ id: 'dish_fish_soup', qty: 1 });
    const r = step(near, { type: 'eat', item: 'dish_fish_soup' });
    expect(r.s.energy.value).toBe(200);
    expect(r.s.day.meals).toBe(40);
  });
  it('stops restoring at the 200 daily cap and resets at 04:00', () => {
    let s = hungry();
    s.energy.value = 10;
    s.day.meals = 190; s.day.key = '2026-10-05';
    s.bag.push({ id: 'dish_pan_fried_fish', qty: 1 }, { id: 'dish_carrot_cake', qty: 1 });
    s = step(s, { type: 'eat', item: 'dish_pan_fried_fish' }).s;
    expect(s.energy.value).toBe(20);
    s.energy = { value: 10, tick_ms: T0 + 20 * H };
    s = step(s, { type: 'eat', item: 'dish_carrot_cake' }, T0 + 20 * H).s; // next player day
    expect(s.day.meals).toBe(20);
  });
});

describe('P0 stall M2 goods', () => {
  it('sells fish at full price and gates worms on Fishing Lv2 with a daily stock', () => {
    let s = fresh();
    s.bag.push({ id: 'fish_koi', qty: 1 });
    s = step(s, { type: 'sell', item: 'fish_koi', qty: 1 }).s;
    expect(s.coins).toBe(193);
    expect(applyP0(c, s, { type: 'buy', item: 'bait_worm', qty: 1 }, T0)).toMatchObject({ ok: false, code: 'locked', detail: { skill: 'fishing', level: 2 } });
    s.skills.fishing = 70;
    s = step(s, { type: 'buy', item: 'bait_worm', qty: 30 }).s;
    expect(applyP0(c, s, { type: 'buy', item: 'bait_worm', qty: 1 }, T0)).toMatchObject({ ok: false, code: 'sold_out' });
    expect(recipeById(c, 'dish_grilled_crucian')?.known).toBe(true);
  });
});

describe('P0 Newcomer Blessing (§3.4.6) and one-time rewards (§3.4.8)', () => {
  const newcomer = () => freshState(c, 'player-test-03', T0, 7);
  it('regenerates every 2:40 and allows 300 meals for the first 7 days, then back to 4:00 / 200', () => {
    const s = newcomer();
    s.energy = { value: 100, tick_ms: T0 };
    const v = viewOf(c, s, T0 + 160_000);
    expect(v.energy.value).toBe(101);
    expect(v.meals.cap).toBe(300);
    expect(v.blessing).not.toBeNull();
    const later = viewOf(c, { ...s, energy: { value: 100, tick_ms: T0 + 8 * 24 * H } }, T0 + 8 * 24 * H);
    expect(later.energy.regen_ms).toBe(240_000);
    expect(later.meals.cap).toBe(200);
    expect(later.blessing).toBeNull();
  });
  it('first Fine fish +20 Energy (may pass max by ≤ 50), once', () => {
    let s = fresh();
    s.fishing.bites = 10; s.skills.fishing = 70;
    let got = 0;
    for (let i = 0; i < 40 && !got; i++) {
      s.energy = { value: 200, tick_ms: T0 + i * 60 * S };
      const r = fishOnce(s, 'landed', T0 + i * 60 * S);
      const reward = r.ev.find(e => e.kind === 'reward') as Extract<P0Event, { kind: 'reward' }> | undefined;
      if (reward) { expect(reward).toMatchObject({ id: 'first_fish_2', energy: 20 }); got = r.s.energy.value; }
      s = r.s;
    }
    expect(got).toBe(215); // 200 − 5 cast + 20 into the bonus zone
    expect(s.rewards).toContain('first_fish_2');
  });
  it('first Rare dish +30 Energy; Common and Fine firsts give none', () => {
    let s = fresh();
    s.energy = { value: 150, tick_ms: T0 };
    s.bag.push({ id: 'fish_bass', qty: 1 }, { id: 'crop_tomato', qty: 1 }, { id: 'fish_crucian', qty: 1 });
    s = step(s, { type: 'cook', items: ['fish_crucian'] }).s;
    let r = step(s, { type: 'collect' }, T0 + 6 * S);
    expect(r.ev.some(e => e.kind === 'reward')).toBe(false);
    r = step(r.s, { type: 'cook', items: ['fish_bass', 'crop_tomato'] }, T0 + 10 * S);
    r = step(r.s, { type: 'collect' }, T0 + 41 * S);
    expect(r.ev.find(e => e.kind === 'reward')).toMatchObject({ id: 'first_dish_3', energy: 30 });
  });
});

describe('P0 stall board (§14.1.2 tutorial request)', () => {
  it('Pond Catch: accept, refuse short delivery, deliver 2 crucian for 14 coins once, no XP', () => {
    let s = fresh();
    expect(viewOf(c, s, T0).stall.board.requests[0]).toMatchObject({ id: 'req_pond_catch', status: 'open', qty: 2, coins: 14, have: 0 });
    s = step(s, { type: 'accept', request: 'req_pond_catch' }).s;
    expect(applyP0(c, s, { type: 'deliver', request: 'req_pond_catch' }, T0)).toMatchObject({ ok: false, code: 'not_enough', detail: { need: 2, have: 0 } });
    s.bag.push({ id: 'fish_crucian', qty: 3 });
    const xp = { ...s.skills };
    const r = step(s, { type: 'deliver', request: 'req_pond_catch' });
    expect(r.s.coins).toBe(194);
    expect(count(r.s.bag, 'fish_crucian')).toBe(1);
    expect(r.s.skills).toEqual(xp);
    expect(applyP0(c, r.s, { type: 'deliver', request: 'req_pond_catch' }, T0)).toMatchObject({ ok: false, code: 'request_done' });
    // q(58): the view lists requests handed in, so the first session's Deliver row can tick
    expect(viewOf(c, r.s, T0).req_done).toContain('req_pond_catch');
  });
});

describe('P0 Reed Rod and Tools & Gear (§6.4.1)', () => {
  it('Old Kai sells the Reed Rod from Fishing Lv3; it equips, lands Rare fish the Starter Rod could not, and can be switched back', () => {
    let s = fresh();
    expect(applyP0(c, s, { type: 'buy', item: 'rod_reed', qty: 1, shop: 'tackle' }, T0)).toMatchObject({ ok: false, code: 'locked', detail: { skill: 'fishing', level: 3 } });
    expect(applyP0(c, s, { type: 'buy', item: 'rod_reed', qty: 1 }, T0)).toMatchObject({ ok: false, code: 'bad_item' }); // not at Bao's
    s.skills.fishing = 480; s.fishing.bites = 10; // Lv4: koi's level gate is open
    s = step(s, { type: 'buy', item: 'rod_reed', qty: 1, shop: 'tackle' }).s;
    expect(s.coins).toBe(100);
    expect(s.gear).toMatchObject({ rods: ['rod_starter', 'rod_reed'], rod: 'rod_reed' });
    expect(count(s.bag, 'rod_reed')).toBe(0);
    expect(applyP0(c, s, { type: 'buy', item: 'rod_reed', qty: 1, shop: 'tackle' }, T0)).toMatchObject({ ok: false, code: 'owned' });
    let koi = null as null | string;
    for (let i = 0; i < 200 && !koi; i++) {
      s.energy = { value: 200, tick_ms: T0 + i * 60 * S };
      const r = fishOnce(s, 'landed', T0 + i * 60 * S);
      if (catchOf(r.ev).fish === 'fish_koi') koi = catchOf(r.ev).result;
      s = r.s;
      s.bag = s.bag.filter(b => !b.id.startsWith('fish_'));
    }
    expect(koi).toBe('landed');
    s = step(s, { type: 'equip', item: 'rod_starter' }).s;
    expect(viewOf(c, s, T0).fishing.rod).toBe('Starter Rod');
    expect(applyP0(c, s, { type: 'equip', item: 'rod_carbon' }, T0)).toMatchObject({ ok: false, code: 'not_owned' });
  });
});
