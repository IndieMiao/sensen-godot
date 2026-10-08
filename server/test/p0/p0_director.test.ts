/**
 * SGODOT-232 V2: the first-session director table (plan §14.2) replayed minute by minute against the P0 reducer.
 * It checks the Energy ledger (§14.2.1), the XP ledger and the three teaching pins (§14.2.2) and the three hard targets
 * (loop closed by minute 20, Fishing Lv2 and Cooking Lv2 by minute 30, ending Energy ≥ 180). Natural recovery depends
 * on when each command lands, so those rows allow a few points either way; every spend, refund and reward is exact.
 * A change that moves a number here moves the first session: update the table in §14.2 with it, or fix the code.
 */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, count, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { skillLevel } from '../../src/p0/rules.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 8, 2, 0, 0);   // 10:00 Shanghai, a brand-new account (Newcomer Blessing)
const MIN = 60_000, SEC = 1000;
const REED = 'pond_shanghai_05';   // Reed Pond, the beginner pond 0.8 km from the P0 farm (q(32))
const at = (m: number, s = 0) => T0 + m * MIN + s * SEC;

/** One player playing the table: every command at its minute, from where the director puts them. */
class Director {
  s: P0State;
  ledger: { at: number; what: string; energy: number; fishing: number; cooking: number }[] = [];
  firsts: Record<string, number> = {};
  constructor(player: string) { this.s = freshState(c, player, T0); }
  do(cmd: P0Command, t: number, what = cmd.type): P0Event[] {
    const r = applyP0(c, this.s, cmd, t);
    if (!r.ok) throw new Error(`${what} at ${((t - T0) / MIN).toFixed(1)} min: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
    this.s = r.state;
    for (const e of r.events) {
      const key = e.kind === 'level' ? `${e.skill}_lv${e.level}` : e.kind === 'meal' ? 'first_meal' : null;
      if (key && this.firsts[key] === undefined) this.firsts[key] = (t - T0) / MIN;
    }
    this.ledger.push({ at: (t - T0) / MIN, what, energy: this.s.energy.value, fishing: this.s.skills.fishing, cooking: this.s.skills.cooking });
    return r.events;
  }
  /** Energy at t with natural recovery, as the HUD shows it. */
  energyAt(t: number): number { return viewOf(c, this.s, t).energy.value; }
  fish(t: number, bait?: string): Extract<P0Event, { kind: 'catch' }> & { events: P0Event[] } {
    const cast = this.do({ type: 'cast', space: 'pond', place: REED, ...(bait ? { bait } : {}) }, t, 'cast');
    const bite = this.s.cast!.bite_ms;
    const ev = [...cast, ...this.do({ type: 'reel', outcome: 'landed', space: 'pond', place: REED }, t + bite + 4 * SEC, 'reel')];
    return { ...(ev.find(e => e.kind === 'catch') as Extract<P0Event, { kind: 'catch' }>), events: ev };
  }
  /** Cook a known page, tap the middle of every gold arc (Good on one ring), and take it out at the end. */
  cook(recipe: string, t: number, eat: boolean): P0Event[] {
    this.do({ type: 'cook', recipe, space: 'home' }, t, `cook ${recipe}`);
    const pot = this.s.stove!;
    const taps = pot.heats.map(h => h.at + (h.gold + h.width / 2) * h.spin);
    return this.do({ type: 'collect', taps, eat, space: 'home' }, t + pot.ms + SEC, eat ? 'collect + eat' : 'collect (keep)');
  }
}

describe('first session director table (§14.2; SGODOT-232 V2)', () => {
  it('replays the 30 minutes: Energy and XP ledgers, the three pins and the three hard targets', () => {
    const d = new Director('director-first-session-01');
    expect(d.s.energy.value).toBe(200);
    expect(d.s.coins).toBe(180);

    // 0–3 min: sow the first bed's 20 radishes (2 Energy each), then water them for free
    for (let i = 0; i < 20; i++) d.do({ type: 'sow', plot: i, seed: 'seed_radish', space: 'home' }, at(0, 20 + i * 6), 'sow radish');
    for (let i = 0; i < 20; i++) d.do({ type: 'water', plot: i, space: 'home' }, at(2, 30 + i), 'water');
    expect(d.energyAt(at(3))).toBe(160);

    // 3–5 min: take the tutorial request at the stall
    d.do({ type: 'accept', request: 'req_pond_catch', space: 'home' }, at(4));

    // 5–9 min: Go to Reed Pond (Trip 1 within the city is free)
    expect(d.energyAt(at(9))).toBeGreaterThanOrEqual(160);

    // 9–14 min, pin 1: the first three bites are Pond Crucian
    const first = d.fish(at(9, 30));
    expect(first).toMatchObject({ fish: 'fish_crucian', result: 'landed' });
    expect(d.s.skills.fishing).toBe(50);   // first cast 10 + first landed 10 + new city 10 + first species 15 + catch 5 (q(37))
    expect(d.fish(at(11)).fish).toBe('fish_crucian');
    expect(d.fish(at(12, 30)).fish).toBe('fish_crucian');
    expect(d.s.skills.fishing).toBe(60);
    const afterThree = d.energyAt(at(14));

    // 14–16 min: go home (free), deliver 2 crucian, grill the third and eat it (Good: 20 + 5, the Blessing does not
    // multiply meals)
    const deliver = d.do({ type: 'deliver', request: 'req_pond_catch', space: 'home' }, at(14, 20));
    expect(deliver).toContainEqual({ kind: 'coins', delta: 14 });
    expect(d.s.coins).toBe(194);
    const grill = d.cook('dish_grilled_crucian', at(15), true);
    expect(grill.find(e => e.kind === 'dish')).toMatchObject({ dish: 'dish_grilled_crucian', quality: 1, first: true });
    expect(grill.find(e => e.kind === 'meal')).toMatchObject({ gain: 25 });
    expect(d.s.skills.cooking).toBe(15);   // first cook 10 + 4 × Good 1.25
    const afterMeal = d.energyAt(at(16));
    expect(afterMeal - afterThree).toBeGreaterThanOrEqual(25);   // the meal, plus recovery since minute 14
    expect(afterMeal).toBeGreaterThanOrEqual(176 - 3);
    expect(afterMeal).toBeLessThanOrEqual(176 + 3);

    // 16–18 min: sow 10 lettuce on the rest of the farm (till the wild plots first, free)
    for (let i = 20; i < 30; i++) d.do({ type: 'till', plot: i, space: 'home' }, at(16, 20 + (i - 20) * 3), 'till');
    const beforeLettuce = d.energyAt(at(17));
    for (let i = 20; i < 30; i++) d.do({ type: 'sow', plot: i, seed: 'seed_lettuce', space: 'home' }, at(17, (i - 20) * 6), 'sow lettuce');
    expect(beforeLettuce - d.energyAt(at(17, 55))).toBeLessThanOrEqual(20);
    expect(count(d.s.bag, 'seed_lettuce')).toBe(0);

    // 18–22 min, pin 2: the fourth bite is a Fine fish that breaks free at Fishing Lv1, Energy refunded
    const fourth = d.fish(at(18, 30));
    expect(fourth).toMatchObject({ fish: 'fish_perch', result: 'broke_free', need_level: 2, refund: 5 });
    expect(d.s.skills.fishing).toBe(60);
    // casts 5 and 6 on the normal weights; 70 XP reaches Fishing Lv2 (+50 Energy, the first level-up)
    const fifth = d.fish(at(19, 30));
    const sixth = d.fish(at(20, 30));
    expect([fifth.result, sixth.result]).toEqual(['landed', 'landed']);
    expect(d.s.skills.fishing).toBeGreaterThanOrEqual(70);
    expect(d.s.skills.fishing).toBeLessThanOrEqual(85 + 15);
    const lv2 = [...fifth.events, ...sixth.events].find(e => e.kind === 'level');
    expect(lv2).toMatchObject({ skill: 'fishing', level: 2, energy: 50 });
    expect(count(d.s.bag, 'bait_worm')).toBe(3);
    expect(count(d.s.bag, 'wild_herb')).toBe(3);
    expect(d.s.cookbook).toContain('dish_herb_grilled_fish');

    // 22–25 min, pin 3: the first baited bite after Lv2 is a Fine global fish; the first Fine fish pays +20 Energy
    const seventh = d.fish(at(22, 30), 'bait_worm');
    expect(seventh).toMatchObject({ fish: 'fish_perch', result: 'landed' });
    expect(seventh.events).toContainEqual({ kind: 'reward', id: 'first_fish_2', energy: 20 });
    const fishingEnd = d.s.skills.fishing;
    expect(fishingEnd).toBeGreaterThanOrEqual(110);
    expect(fishingEnd).toBeLessThanOrEqual(125 + 15);
    const bonus = d.energyAt(at(25));
    expect(bonus).toBeGreaterThan(200);   // in the bonus zone: recovery holds

    // 25–28 min: Herb Grilled Fish (a Common fish + Wild Herb, Fine page) — Energy is above max, so Keep
    expect(applyP0(c, d.s, { type: 'cook', recipe: 'dish_herb_grilled_fish', space: 'home' }, at(25, 30)).ok).toBe(true);
    const herb = d.cook('dish_herb_grilled_fish', at(25, 30), false);
    expect(herb.find(e => e.kind === 'dish')).toMatchObject({ dish: 'dish_herb_grilled_fish', quality: 1, first: true });
    expect(count(d.s.bag, 'dish_herb_grilled_fish@good')).toBe(1);
    expect(d.s.skills.cooking).toBe(45);   // + first Fine 20 + 8 × 1.25
    expect(herb.find(e => e.kind === 'level')).toMatchObject({ skill: 'cooking', level: 2, energy: 0 });   // Cooking levels give no Energy (q(37))
    expect(d.s.cookbook).toContain('dish_fish_soup');   // Cooking Lv2 card: Fresh Fish Soup
    expect(applyP0(c, d.s, { type: 'eat', item: 'dish_herb_grilled_fish@good' }, at(27))).toMatchObject({ ok: false, code: 'energy_full' });

    // 28–30 min: the end state the player looks at
    const end = d.energyAt(at(30));
    const v = viewOf(c, d.s, at(30));
    expect(skillLevel(c, d.s, 'fishing')).toBe(2);
    expect(skillLevel(c, d.s, 'cooking')).toBe(2);
    expect(skillLevel(c, d.s, 'farming')).toBe(1);
    expect(d.s.skills.farming).toBe(0);   // the 60 sowing XP waits in the field for the harvest
    expect(v.cooking.discovered).toBe(2);
    expect(Object.keys(d.s.fishing.caught).length).toBeGreaterThanOrEqual(2);

    // The three hard targets (§14.8.1): loop by minute 20, both Lv2 by minute 30, ending Energy ≥ 180
    expect(d.firsts.first_meal).toBeLessThanOrEqual(20);
    expect(d.firsts.fishing_lv2).toBeLessThanOrEqual(30);
    expect(d.firsts.cooking_lv2).toBeLessThanOrEqual(30);
    expect(end).toBeGreaterThanOrEqual(180);
    // §14.2.1 ends at 213/200 · bonus; recovery timing may move it a few points
    expect(end).toBeGreaterThanOrEqual(213 - 5);
    expect(end).toBeLessThanOrEqual(213 + 5);
    expect(d.s.coins).toBe(194);
  });
});
