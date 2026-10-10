/** SGODOT-282: Homestead Lv4–10 (§8.2–8.3) and the kitchen it grows (§7.7): stoves 2 and 3, Big Pot Double,
 * Warming Cabinet 12, Chef's Sign, Bag Upgrade II / III. */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, count, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { maxEnergy } from '../../src/p0/rules.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 10, 2);
const S = 1000, H = 3_600_000;
const veteran = (): P0State => ({ ...freshState(c, 'kitchen-p1', T0, 7), created_at: T0 - 8 * 24 * H, fires: 1 });
function step(s: P0State, cmd: P0Command, at = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, at);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const refusal = (s: P0State, cmd: P0Command, at = T0) => {
  const r = applyP0(c, s, cmd, at);
  return r.ok ? null : { code: r.code, detail: r.detail };
};
/** A dish kept the Keep way: the Warming Cabinet (Lv3+) first, then the bag. */
const kept = (s: P0State, id: string) => count(s.bag, id) + (s.cabinet.find(b => b.id === id)?.qty ?? 0);
const at = (level: number): P0State => { const s = veteran(); s.homestead.level = level; return s; };
/** Everything the next level asks for: skills, materials in storage, coins + the 40 floor. */
function readyFor(s: P0State): P0State {
  const next = c.homestead.levels.find(l => l.level === s.homestead.level + 1)!;
  s.skills = { farming: 99_999, fishing: 99_999, cooking: s.skills.cooking };
  for (const [id, n] of next.materials) s.storage[id] = (s.storage[id] ?? 0) + n;
  s.coins = next.coins + 40;
  return s;
}

describe('Homestead Lv4–10 (§8.2.1)', () => {
  it('nine upgrades cost 11,300 coins and the §8.2.1 materials; skills total 2N − 1', () => {
    expect(c.homestead.max_level).toBe(10);
    expect(c.homestead.levels.map(l => l.level)).toEqual([2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(c.homestead.levels.reduce((n, l) => n + l.coins, 0)).toBe(11_300);
    for (const l of c.homestead.levels) expect(l.skills).toBe(2 * l.level - 1);
    const total: Record<string, number> = {};
    for (const l of c.homestead.levels) for (const [id, n] of l.materials) total[id] = (total[id] ?? 0) + n;
    expect(total).toEqual({ wood: 150, stone: 140, fiber: 80, copper_ore: 75, clay: 50, quartz: 22, hardwood: 28, rock_salt: 15 });
  });

  it('climbs from Lv3 to Lv10 one level at a time, Energy refilled each time, then stops', () => {
    let s = at(3);
    for (let lv = 4; lv <= 10; lv++) {
      const r = step(readyFor(s), { type: 'homestead_upgrade' });
      s = r.s;
      expect(s.homestead.level).toBe(lv);
      expect(s.energy.value).toBe(maxEnergy(c, s));
    }
    expect(maxEnergy(c, s)).toBe(290);
    expect(viewOf(c, s, T0).homestead.next).toBeNull();
    expect(refusal(s, { type: 'homestead_upgrade' })?.code).toBe('max_level');
  });

  it('Lv4 needs skills total 7 before materials or coins', () => {
    const s = readyFor(at(3));
    s.skills = { farming: 0, fishing: 0, cooking: 0 };
    expect(refusal(s, { type: 'homestead_upgrade' })).toMatchObject({ code: 'skills_short', detail: { need: 7 } });
  });
});

describe('Kitchen facilities by Homestead level (§7.7 / §8.3.2)', () => {
  it('stoves 1 / 2 / 3 at Lv1 / Lv4 / Lv8; Warming Cabinet 6 then 12 at Lv8', () => {
    const facts = [1, 3, 4, 7, 8, 10].map(lv => {
      const v = viewOf(c, at(lv), T0);
      return [lv, v.cooking.stoves.length, v.cooking.cabinet?.cap ?? 0];
    });
    expect(facts).toEqual([[1, 1, 0], [3, 1, 6], [4, 2, 6], [7, 2, 6], [8, 3, 12], [10, 3, 12]]);
  });

  it('never more than three stoves, whatever the content says (亚瑟 on #209)', () => {
    const many = { ...c, homestead: { ...c.homestead, stoves: [[1, 1], [4, 9]] as [number, number][] } };
    expect(viewOf(many, at(10), T0).cooking.stoves).toHaveLength(3);
    expect(refusal(at(10), { type: 'cook', items: ['fish_crucian'], stove: 3 })).toMatchObject({ code: 'bad_stove', detail: { stoves: 3 } });
  });

  it('an old save with stove 1 only reads as empty stoves 2 and 3', () => {
    const { burners: _gone, ...old } = at(8);
    const up = upgradeState(c, { ...old, v: 4 } as unknown as P0State, T0);
    expect(up.burners).toEqual([]);
    expect(viewOf(c, up, T0).cooking.stoves).toEqual([null, null, null]);
  });

  it('Lv4: a second pot goes on the empty stove 2 and each stove is collected by its pot', () => {
    let s = at(4);
    s.bag.push({ id: 'fish_crucian', qty: 1 }, { id: 'crop_carrot', qty: 2 });
    const one = step(s, { type: 'cook', items: ['fish_crucian'] });
    expect(one.ev.find(e => e.kind === 'pot')).toMatchObject({ stove: 0 });
    const two = step(one.s, { type: 'cook', items: ['crop_carrot', 'crop_carrot'] }, T0 + S);
    expect(two.ev.find(e => e.kind === 'pot')).toMatchObject({ stove: 1 });
    s = two.s;
    const v = viewOf(c, s, T0 + 2 * S).cooking;
    expect(v.stoves.map(p => p?.dish ?? null)).toEqual(['dish_grilled_crucian', null]);   // Carrot Cake is still Hidden
    expect(v.stoves.map(p => p?.id)).toEqual([s.stove!.id, s.burners[0].stove!.id]);
    expect(v.stove).toMatchObject({ id: s.stove!.id });   // stove 1 stays where it was in the view
    // collect stove 2's pot by its id; stove 1 keeps cooking
    const carrot = s.burners[0].stove!;
    const got = step(s, { type: 'collect', pot: carrot.id }, T0 + S + carrot.ms + S);
    expect(got.s.burners[0].stove).toBeNull();
    expect(kept(got.s, 'dish_carrot_cake')).toBe(1);
    expect(got.s.stove).toMatchObject({ dish: 'dish_grilled_crucian' });
  });

  it('a stove can be asked for by number; one beyond the kitchen is refused; a busy one says which', () => {
    let s = at(4);
    s.bag.push({ id: 'fish_crucian', qty: 3 });
    expect(refusal(s, { type: 'cook', items: ['fish_crucian'], stove: 2 })).toMatchObject({ code: 'bad_stove', detail: { stoves: 2 } });
    s = step(s, { type: 'cook', items: ['fish_crucian'], stove: 1 }).s;
    expect(s.stove).toBeNull();
    expect(s.burners[0].stove).toMatchObject({ dish: 'dish_grilled_crucian' });
    expect(refusal(s, { type: 'cook', items: ['fish_crucian'], stove: 1 })).toMatchObject({ code: 'stove_busy', detail: { stove: 1 } });
    s = step(s, { type: 'cook', items: ['fish_crucian'] }).s;   // no number: the first empty one
    expect(s.stove).toMatchObject({ dish: 'dish_grilled_crucian' });
    expect(refusal(s, { type: 'cook', items: ['fish_crucian'] })).toMatchObject({ code: 'stove_busy' });
  });

  it('heat taps go to the pot they name, on whichever stove it is', () => {
    let s = at(4);
    s.bag.push({ id: 'fish_crucian', qty: 2 });
    s = step(s, { type: 'cook', items: ['fish_crucian'] }).s;
    s = step(s, { type: 'cook', items: ['fish_crucian'] }).s;
    const second = s.burners[0].stove!;
    const h = second.heats[0];
    s = step(s, { type: 'heat', pot: second.id, taps: [h.at + (h.gold + h.width / 2) * h.spin] }).s;
    expect(s.burners[0].stove!.taps).toHaveLength(1);
    expect(s.stove!.taps ?? []).toEqual([]);
  });

  it('Big Pot (Lv6): Double takes the ingredients twice for two portions and one round of heat', () => {
    const below = at(5);
    below.bag.push({ id: 'fish_crucian', qty: 2 });
    expect(refusal(below, { type: 'cook', items: ['fish_crucian'], double: true })).toMatchObject({ code: 'locked', detail: { unlock: 'big_pot' } });
    let s = at(6);
    s.bag.push({ id: 'fish_crucian', qty: 2 });
    expect(viewOf(c, s, T0).cooking.big_pot).toBe(true);
    const started = step(s, { type: 'cook', items: ['fish_crucian'], double: true });
    expect(count(started.s.bag, 'fish_crucian')).toBe(0);
    expect(started.s.stove).toMatchObject({ double: true });
    expect(started.s.stove!.heats).toHaveLength(c.cooking.tiers['1'].heats.length);
    s = step(started.s, { type: 'collect' }, T0 + started.s.stove!.ms + S).s;
    expect(kept(s, 'dish_grilled_crucian')).toBe(2);
  });

  it('Double needs the ingredients twice and a mix that makes a page', () => {
    const s = at(6);
    s.bag.push({ id: 'fish_crucian', qty: 1 }, { id: 'crop_radish', qty: 1 }, { id: 'crop_carrot', qty: 1 });
    expect(refusal(s, { type: 'cook', items: ['fish_crucian'], double: true })).toMatchObject({ code: 'not_enough', detail: { need: 2, have: 1 } });
    expect(refusal(s, { type: 'cook', items: ['crop_radish', 'crop_carrot'], double: true })?.code).toBe('no_double');
  });

  it("Chef's Sign (Lv10) widens every dish's gold zone by 5 points", () => {
    const width = (lv: number) => {
      const s = at(lv);
      s.bag.push({ id: 'fish_crucian', qty: 1 });
      return step(s, { type: 'cook', items: ['fish_crucian'] }).s.stove!.heats[0].width;
    };
    expect(Math.round((width(10) - width(9)) * 1000) / 1000).toBe(0.05);
    expect(viewOf(c, at(10), T0).homestead.unlocks).toMatchObject({ chefs_sign: true, stoves: 3, cabinet: 12, big_pot: true, notice_board: true });
  });
});

describe('Cooking Lv7–10 conveniences (§4.6.3)', () => {
  const XP = c.skills.cooking;   // cumulative XP per level
  const cook = (lv: number, home = 1): P0State => { const s = at(home); s.skills.cooking = XP[lv - 1]; return s; };
  const firstWidth = (s: P0State) => {
    s.bag.push({ id: 'fish_crucian', qty: 1 });
    return step(s, { type: 'cook', items: ['fish_crucian'] }).s.stove!.heats[0].width;
  };

  it('Steady Hand II (Lv7) adds another 5 points to the gold zone', () => {
    expect(Math.round((firstWidth(cook(7)) - firstWidth(cook(6))) * 1000) / 1000).toBe(0.05);
  });

  it('Fast Mastery (Lv7): a page is Mastered after 7 pots instead of 10', () => {
    const page = (s: P0State) => viewOf(c, s, T0).cooking.cookbook.find(p => p.id === 'dish_grilled_crucian')!;
    const s = cook(6);
    s.firsts.push('cook:dish_grilled_crucian');
    s.book.cooked.dish_grilled_crucian = 7;
    expect(page(s).state).toBe('discovered');
    s.skills.cooking = XP[6];
    expect(page(s).state).toBe('mastered');
  });

  it('Cook All (Lv8) fills every free stove with known pages, rarest first, at most 2 pots a page', () => {
    expect(refusal(cook(7, 8), { type: 'cook_all' })).toMatchObject({ code: 'locked' });
    const s = cook(8, 8);
    s.cookbook.push('dish_herb_grilled_fish');
    s.bag.push({ id: 'fish_crucian', qty: 5 }, { id: 'wild_herb', qty: 3 });
    const r = step(s, { type: 'cook_all' });
    const pots = r.ev.filter(e => e.kind === 'pot');
    expect(pots.map(e => [e.dish, (e as { stove?: number }).stove])).toEqual([
      ['dish_herb_grilled_fish', 0], ['dish_herb_grilled_fish', 1], ['dish_grilled_crucian', 2],
      ['dish_grilled_crucian', 0]]);   // Queue ×2 takes the fourth behind stove 1
    expect(r.s.queue).toMatchObject({ dish: 'dish_grilled_crucian' });
    const bare = cook(8, 8);
    bare.bag = [];
    expect(refusal(bare, { type: 'cook_all' })?.code).toBe('nothing_to_cook');
  });

  it('Lucky Double (Lv10): sometimes one more Plain portion; never with Double', () => {
    const lucky = { ...c, cooking: { ...c.cooking, lucky_double: 1 } };   // always, to see it
    const s = cook(10, 3);
    s.bag.push({ id: 'fish_crucian', qty: 1 });
    const started = applyP0(lucky, s, { type: 'cook', items: ['fish_crucian'] }, T0);
    if (!started.ok) throw new Error(started.code);
    const done = applyP0(lucky, started.state, { type: 'collect' }, T0 + started.state.stove!.ms + S);
    if (!done.ok) throw new Error(done.code);
    expect(done.events.find(e => e.kind === 'dish')).toMatchObject({ qty: 2, lucky: true });
    const never = { ...c, cooking: { ...c.cooking, lucky_double: 0 } };
    const plain = applyP0(never, started.state, { type: 'collect' }, T0 + started.state.stove!.ms + S);
    expect(plain.ok && plain.events.find(e => e.kind === 'dish')).toMatchObject({ qty: 1 });
  });

  it('the view lists the Lv7–10 conveniences once reached', () => {
    expect(viewOf(c, cook(10), T0).cooking.conveniences).toEqual(expect.arrayContaining(
      ['steady_hand_2', 'fast_mastery', 'cook_all', 'provisions_plus', 'chefs_touch', 'title_chef', 'lucky_double']));
    expect(viewOf(c, cook(6), T0).cooking.conveniences).not.toContain('steady_hand_2');
  });
});

describe('Cookbook milestones (§7.6.1)', () => {
  it('ships Line Cook 20 (100 coins + Recipe Stand), Head Chef 36 (+4 cabinet), Master Chef 48, Muscle Memory 10 Mastered', () => {
    expect(c.cooking.milestones).toEqual([
      { id: 'line_cook', title: 'Line Cook', discovered: 20, coins: 100, decor: 'recipe_stand' },
      { id: 'head_chef', title: 'Head Chef', discovered: 36, cabinet: 4 },
      { id: 'master_chef', title: 'Master Chef', discovered: 48 },
      { id: 'muscle_memory', title: 'Muscle Memory', mastered: 10 },
    ]);
  });

  // Thresholds scaled down so the 14 cookable pages reach them.
  const small = { ...c, cooking: { ...c.cooking, milestones: [
    { id: 'line_cook', title: 'Line Cook', discovered: 2, coins: 100, decor: 'recipe_stand' },
    { id: 'head_chef', title: 'Head Chef', discovered: 3, cabinet: 4 },
    { id: 'muscle_memory', title: 'Muscle Memory', mastered: 1 },
  ] } };
  const run = (s: P0State, cmd: P0Command, t: number) => {
    const r = applyP0(small, s, cmd, t);
    if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`);
    return { s: r.state, ev: r.events };
  };
  const cookIt = (s: P0State, items: string[], t: number) => {
    const started = run(s, { type: 'cook', items }, t);
    return run(started.s, { type: 'collect' }, t + started.s.stove!.ms + S);
  };

  it('pays each milestone once when the count is reached; Head Chef adds 4 cabinet portions', () => {
    let s = at(3);
    s.bag.push({ id: 'fish_crucian', qty: 11 }, { id: 'crop_radish', qty: 1 }, { id: 'crop_lettuce', qty: 1 });
    s = cookIt(s, ['fish_crucian'], T0).s;
    const second = cookIt(s, ['crop_radish', 'crop_lettuce'], T0 + 60 * S);
    expect(second.ev.find(e => e.kind === 'milestone')).toEqual({ kind: 'milestone', id: 'line_cook', title: 'Line Cook', coins: 100, cabinet: 0, decor: 'recipe_stand' });
    expect(second.s.coins).toBe(s.coins + 100);
    s = second.s;
    s.cabinet = [];
    for (let i = 0; i < 9; i++) s = cookIt(s, ['fish_crucian'], T0 + (120 + i * 20) * S).s;   // 10 crucian pots: Mastered
    expect(viewOf(small, s, T0 + 400 * S).cooking).toMatchObject({ mastered_count: 1,
      milestones: [{ id: 'line_cook', reached: true }, { id: 'head_chef', reached: false, need: 3 }, { id: 'muscle_memory', counts: 'mastered', reached: true }] });
    const again = cookIt(s, ['fish_crucian'], T0 + 500 * S);
    expect(again.ev.filter(e => e.kind === 'milestone')).toEqual([]);   // once each
    expect(viewOf(small, s, T0).cooking.cabinet!.cap).toBe(6);
    s.firsts.push('milestone:head_chef');
    expect(viewOf(small, s, T0).cooking.cabinet!.cap).toBe(10);
  });
});

describe('Bag Upgrade II / III (§9.11, §8.3.2)', () => {
  const stall = (id: string): P0Command => ({ type: 'buy', item: id, qty: 1, shop: 'homestead' });
  it('II goes on sale at Lv6 and needs Upgrade I first; III at Lv9 after II', () => {
    let s = at(6);
    s.coins = 5_000;
    s.storage = { hardwood: 20, clay: 20, copper_ore: 20, quartz: 10, fiber: 20, wood: 20 };
    expect(viewOf(c, s, T0).homestead.unlocks).toMatchObject({ bag_upgrade_1: 'for_sale', bag_upgrade_2: 'for_sale', bag_upgrade_3: 'locked' });
    expect(refusal(s, stall('bag_upgrade_2'))).toMatchObject({ code: 'needs_previous', detail: { item: 'bag_upgrade_1' } });
    s = step(s, stall('bag_upgrade_1')).s;
    s = step(s, stall('bag_upgrade_2')).s;
    expect(s.bag_cap).toBe(35);
    expect(s.storage).toMatchObject({ hardwood: 16, clay: 14, copper_ore: 16 });
    expect(refusal(s, stall('bag_upgrade_3'))).toMatchObject({ code: 'homestead_level', detail: { need: 9 } });
    s.homestead.level = 9;
    s = step(s, stall('bag_upgrade_3')).s;
    expect(s.bag_cap).toBe(40);
  });
});
