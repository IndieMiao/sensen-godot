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
const fresh = () => freshState(c, 'player-test-02', T0, 7);
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
    // 5 (first cast) + 5 (catch) + 15 (first crucian) + 5 (first landed)
    expect(s.skills.fishing).toBe(30);
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
  it('bites 2–3 are Common, bite 4 at Lv1 is a Fine fish that breaks free with the level needed', () => {
    let s = fresh();
    for (let i = 0; i < 3; i++) {
      const r = fishOnce(s, 'landed', T0 + i * 60 * S);
      expect(c.fish.find(f => f.id === catchOf(r.ev).fish)!.rarity).toBe(1);
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
  it('Willow Creek (River template) draws mullet and trout; the pond never does; mackerel stays Coast-only', () => {
    let s = fresh();
    s.fishing.bites = 10; s.skills.fishing = 480;
    const seen = { pond: new Set<string>(), river: new Set<string>() };
    for (const site of ['pond', 'river'] as const) {
      for (let i = 0; i < 120; i++) {
        const r = applyP0(c, s, { type: 'cast', site }, T0 + i * 60 * S);
        if (!r.ok) throw new Error(r.code);
        seen[site].add(r.state.cast!.fish);
        s = { ...r.state, cast: null };
        s.energy.value = 200;
      }
    }
    expect(seen.river.has('fish_trout') && seen.river.has('fish_mullet')).toBe(true);
    expect(seen.pond.has('fish_trout') || seen.pond.has('fish_mullet')).toBe(false);
    expect(seen.pond.has('fish_mackerel') || seen.river.has('fish_mackerel')).toBe(false);
    expect(applyP0(c, fresh(), { type: 'cast', site: 'sea' }, T0)).toMatchObject({ ok: false, code: 'bad_site' });
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
    expect(count(s.bag, 'crop_herb')).toBe(3);
    expect(s.cookbook).toContain('dish_herb_grilled_fish');
    const cast = step(s, { type: 'cast', bait: 'bait_worm' }, T0 + 60 * S);
    expect(cast.s.cast!.bite_ms).toBeLessThanOrEqual(2100);
    const done = step(cast.s, { type: 'reel', outcome: 'escaped' }, T0 + 70 * S);
    expect(count(done.s.bag, 'bait_worm')).toBe(2);
  });
});

describe('P0 recipes (§7.2.3 / §7.4.1)', () => {
  it('derives page rarity from ingredient rarity × families', () => {
    expect(c.cooking.recipes.map(r => [r.id, recipeRarity(c, r)])).toEqual([
      ['dish_grilled_crucian', 1], ['dish_herb_grilled_fish', 2], ['dish_grilled_fish', 1], ['dish_carp_cakes', 1],
      ['dish_mullet_skewers', 1], ['dish_radish_salad', 1], ['dish_veggie_plate', 1], ['dish_carrot_cake', 1],
      ['dish_fish_soup', 2], ['dish_pan_fried_fish', 2], ['dish_fruit_tea', 2], ['dish_roast_veggies', 2],
      ['dish_herb_baked_perch', 3], ['dish_bass_tomato_stew', 3]]);
    expect(deriveRarity(c, [{ family: 'W', rarity: 1 }, { family: 'F', rarity: 1 }, { family: 'S', rarity: 1 }])).toBe(3);
  });
  it('specific pages beat tag pages, fewest wildcards win, otherwise a Mystery Dish', () => {
    expect(matchRecipe(c, ['fish_crucian'])?.id).toBe('dish_grilled_crucian');
    expect(matchRecipe(c, ['fish_carp'])?.id).toBe('dish_grilled_fish');
    expect(matchRecipe(c, ['fish_carp', 'fish_carp'])?.id).toBe('dish_carp_cakes');
    expect(matchRecipe(c, ['crop_lettuce', 'crop_radish'])?.id).toBe('dish_radish_salad');
    expect(matchRecipe(c, ['crop_herb', 'fish_perch'])?.id).toBe('dish_herb_baked_perch');
    expect(matchRecipe(c, ['fish_crucian', 'crop_chili'])?.id).toBe('dish_herb_grilled_fish');
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
    expect(done.s.skills.cooking).toBe(10); // first cook, no level difference
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
    s.bag.push({ id: 'fish_carp', qty: 2 });
    s = step(s, { type: 'cook', items: ['fish_carp', 'fish_carp'] }).s;
    s = step(s, { type: 'collect' }, T0 + 6 * S).s;
    expect(s.cookbook).toContain('dish_carp_cakes');
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
    s.bag.push({ id: 'fish_perch', qty: 1 }, { id: 'crop_herb', qty: 1 });
    s.fires = 1;
    s = step(s, { type: 'cook', items: ['fish_perch', 'crop_herb'] }).s;
    const taps = s.stove!.heats.map(h => h.at + (h.gold + h.width / 2) * h.spin);
    s = step(s, { type: 'collect', taps }, T0 + 31 * S).s;
    expect(count(s.bag, 'dish_herb_baked_perch@perfect')).toBe(1);
    expect(count(s.bag, 'dish_herb_baked_perch')).toBe(1);
    expect(s.skills.cooking).toBe(40);
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
