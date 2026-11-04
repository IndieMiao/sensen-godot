// q(288) (SGODOT-419; q row 1cea65e7, 不知火舞's spec 419 cd072712): every heat ring differs — its own width (the pot's ×
// 0.8–1.2, at most gold_cap + Chef's Sign), its own gold (≥ 0.4 s after the needle sets off, ending by 95% of the ring),
// its own start angle on screen, the ring drifting 12°/s against the needle; the window divides by heatK. The teaching
// pot, and content without heat_vary, stay as before.
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { goldCap } from '../../src/p0/cookbook.js';
import { heatHits, heatK, varyHeats } from '../../src/p0/cooking.js';
import { applyP0, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type Heat, type P0State } from '../../src/p0/state.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 10, 5, 12), S = 1000;
const vary = c.cooking.heat_vary!;
const fresh = (seed = 7) => freshState(c, 'heat-vary-player', T0, seed);

/** A gold centre's angle on screen when its needle sets off (the ring's drift is 0 then), 0–360. */
const centre = (h: Heat) => ((h.from! + (h.gold + h.width / 2) * 360) % 360 + 360) % 360;

function cook(s: P0State, content = c): P0State {
  s.bag.push({ id: 'fish_crucian', qty: 1 });
  const r = applyP0(content, s, { type: 'cook', items: ['fish_crucian'] }, T0);
  if (!r.ok) throw new Error(r.code);
  return r.state;
}

describe('q(288) heat rings (SGODOT-419)', () => {
  it('the content carries the approved numbers', () => {
    expect(vary).toEqual({ width_mul: [0.8, 1.2], drift: 12, lead_ms: 400, end: 0.95, pair_min_deg: 45, pair_opposite_deg: 20 });
    expect(c.cooking.tolerance_ms).toBe(150);
  });

  it('a ring drifting against the needle brings its gold sooner: the window divides by 1 + drift ÷ the needle speed', () => {
    expect(heatK(1600)).toBe(1);
    expect(heatK(1600, 12)).toBeCloseTo(1 + 12 / 225, 9);   // Common: the needle 225°/s
    expect(heatK(1200, 12)).toBeCloseTo(1.04, 9);            // Legendary: 300°/s
    const h: Heat = { at: 0, spin: 1200, gold: 0.4, width: 0.2, from: 90, drift: 12 };
    const from = 0.4 * 1200 / 1.04 - 150, to = 0.6 * 1200 / 1.04 + 150;
    expect([heatHits(c, [h], [from - 1]), heatHits(c, [h], [from + 1]), heatHits(c, [h], [to - 1]), heatHits(c, [h], [to + 1])])
      .toEqual([0, 1, 1, 0]);
    // no drift (an older pot, the teaching one): the window as before, and `from` never counts
    const still: Heat = { at: 0, spin: 1200, gold: 0.4, width: 0.2 };
    expect([heatHits(c, [still], [to + 1]), heatHits(c, [still], [0.6 * 1200 + 150 + 1])]).toEqual([1, 0]);
    expect(heatHits(c, [{ ...h, from: 300 }], [to - 1])).toBe(1);
  });

  it('every ring: its own width ×0.8–1.2, gold from 0.4 s in to 95% of the ring, a whole-degree start; two rings apart', () => {
    for (const [tier, spin] of [['1', 1600], ['2', 1600], ['3', 1400], ['4', 1200]] as const) {
      const base = c.cooking.tiers[tier].gold, s = fresh(11), k = heatK(spin, 12);
      const widths: number[] = [], golds: number[] = [], froms: number[] = [];
      for (let i = 0; i < 3000; i++) {
        const heats = varyHeats(c, s, vary, [10_000, 22_000], spin, base);
        for (const h of heats) {
          expect(h.width).toBeGreaterThanOrEqual(Math.round(base * 0.8 * 1000) / 1000 - 1e-9);
          expect(h.width).toBeLessThanOrEqual(Math.round(base * 1.2 * 1000) / 1000 + 1e-9);
          expect(h.gold * h.spin / k).toBeGreaterThanOrEqual(400 - 0.5 * h.spin / 1000);   // gold in thousandths
          expect(h.gold + h.width).toBeLessThanOrEqual(0.95 + 0.0005);
          expect(Number.isInteger(h.from) && h.from! >= 0 && h.from! < 360).toBe(true);
          expect([h.spin, h.drift]).toEqual([spin, 12]);
          widths.push(h.width); golds.push(h.gold); froms.push(h.from!);
        }
        const d = Math.abs(centre(heats[1]) - centre(heats[0])), apart = Math.min(d, 360 - d);
        expect(apart).toBeGreaterThanOrEqual(45);
        expect(Math.abs(apart - 180)).toBeGreaterThanOrEqual(20);
        expect(heats[0].width === heats[1].width && heats[0].gold === heats[1].gold).toBe(false);   // each ring its own
      }
      // the draws spread over their ranges, not stuck at one end
      expect(Math.min(...widths)).toBeLessThan(base * 0.84);
      expect(Math.max(...widths)).toBeGreaterThan(base * 1.16);
      expect(Math.max(...golds) - Math.min(...golds)).toBeGreaterThan(0.95 - base * 1.2 - 400 * k / spin - 0.05);
      expect(Math.max(...froms) - Math.min(...froms)).toBeGreaterThan(340);
    }
  });

  it("a ring's width stops at gold_cap, Chef's Sign above it", () => {
    const s = fresh(5);
    expect(goldCap(c, s)).toBe(c.cooking.gold_cap);
    for (let i = 0; i < 500; i++) for (const h of varyHeats(c, s, vary, [2500], 1600, 0.6)) expect(h.width).toBeLessThanOrEqual(0.6);
    const sign = structuredClone(c);
    sign.cooking.gold_cap = 0.6;
    const signed = fresh(5);
    // Chef's Sign comes at Homestead Lv10 (§7.7): the cap is gold_cap + its points
    signed.homestead.level = 10;
    const cap = goldCap(sign, signed);
    expect(cap).toBeCloseTo(0.6 + (c.homestead.chefs_sign_gold ?? 0), 9);
    let wider = false;
    for (let i = 0; i < 500; i++) for (const h of varyHeats(sign, signed, vary, [2500], 1600, cap)) {
      expect(h.width).toBeLessThanOrEqual(cap + 1e-9);
      if (h.width > 0.6) wider = true;
    }
    expect(wider).toBe(true);
  });

  it('the teaching pot stays as it was; the next pot has q(288) rings', () => {
    const s = fresh();
    const first = cook(s);
    expect(first.stove!.heats).toEqual([expect.objectContaining({ width: c.cooking.first_fire.gold, spin: c.cooking.first_fire.spin_ms })]);
    expect(first.stove!.heats[0]).not.toHaveProperty('from');
    expect(first.stove!.heats[0]).not.toHaveProperty('drift');
    const later = fresh();
    later.fires = 1;
    const h = cook(later).stove!.heats[0];
    expect(h).toMatchObject({ drift: 12, spin: c.cooking.tiers['1'].spin_ms });
    expect(h.from).toBeGreaterThanOrEqual(0);
  });

  it('content without heat_vary makes rings as before (gold in [0.1, 0.95 − width), no start angle, no drift)', () => {
    const plain = structuredClone(c);
    delete plain.cooking.heat_vary;
    for (let seed = 1; seed < 200; seed++) {
      const s = fresh(seed);
      s.fires = 1;
      const h = cook(s, plain).stove!.heats[0];
      expect(h.width).toBe(c.cooking.tiers['1'].gold);
      expect(h.gold).toBeGreaterThanOrEqual(0.1);
      expect(h.gold).toBeLessThan(0.95 - h.width + 0.0005);
      expect(h).not.toHaveProperty('from');
      expect(h).not.toHaveProperty('drift');
    }
  });

  it("the dish event says the pot's rarity and how many rings it had (the week after 11-13 reads rates by tier)", () => {
    const s = fresh();
    s.fires = 1;
    const cooking = cook(s);
    const h = cooking.stove!.heats[0];
    const tap = h.at + (h.gold + h.width / 2) * h.spin / heatK(h.spin, h.drift);
    const done = applyP0(c, cooking, { type: 'collect', taps: [tap] }, T0 + cooking.stove!.ms + S);
    if (!done.ok) throw new Error(done.code);
    expect(done.events.find((e: P0Event) => e.kind === 'dish')).toMatchObject({ hits: 1, quality: 1, rarity: 1, heats: 1 });
  });
});
