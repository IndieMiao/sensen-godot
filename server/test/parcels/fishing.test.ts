/** Aquatic Park 码头钓鱼（C-232）：投竿扣体力、服务端按种子重放收线记录判定、同一竿只能领一次、渔具限量。 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { applyFarmCommands, emptyFarm, parseFarmCommands, welcome, withEconomy, type FarmCommand, type ParcelFarmState } from '../../src/parcels/farm.js';
import { castDeadline, castSeed, castView, initialReel, pickFish, reelTier, replayReel, rollRarity, stepReel, REPLAY_SLACK_MS,
  type FishingRules, type ReelTier } from '../../src/parcels/fishing.js';
import { hash32 as hash } from '../../src/parcels/requests.js';
import { loadParcelRules, parseParcelRules } from '../../src/parcels/rules.js';

const rules = loadParcelRules(DEFAULT_CONTENT_DIR);
const f = rules.fishing as FishingRules;
const T0 = Date.UTC(2026, 10, 28, 4);
const PARCEL = 'p-3512001';
const welcomed = (): ParcelFarmState => welcome(rules, emptyFarm(), T0)!;

function apply(state: ParcelFarmState, commands: FarmCommand[], now = T0) {
  return applyFarmCommands(rules, state, commands, now, { parcel_id: PARCEL });
}
function run(state: ParcelFarmState, commands: FarmCommand[], now = T0): ParcelFarmState {
  const out = apply(state, commands, now);
  if (!out.ok) throw new Error(`${out.code} @${out.index}`);
  return out.state;
}
/** 首次进入、到过码头（拿了新手竿）的农场。 */
const atPier = (): ParcelFarmState => run(welcomed(), [{ type: 'visit_pier' }]);

/** 玩家照 P0 自动收线（P0FishingPanel.auto_play）：鱼在条上面就按住。 */
function goodInputs(seed: number, tier: ReelTier): string {
  const s = initialReel(f, seed);
  let out = '';
  while (s.outcome === 'playing') {
    const held = s.fish > s.bar;
    out += held ? '1' : '0';
    stepReel(f, s, held, tier);
  }
  return out;
}
/** 一直不按：条沉到底，鱼游走，脱钩。 */
function idleInputs(seed: number, tier: ReelTier): string {
  const s = initialReel(f, seed);
  let out = '';
  while (s.outcome === 'playing') { out += '0'; stepReel(f, s, false, tier); }
  return out;
}
const rodOf = (id: string) => f.rods.find(r => r.id === id)!;
/** 投一竿，返回投完的农场和这一竿。 */
function cast(state: ParcelFarmState, now = T0, bait: string | null = null) {
  const s = run(state, [{ type: 'cast_line', bait }], now);
  return { s, c: s.fishing!.cast! };
}
/** 咬钩后 hook 毫秒提竿、记录交完时的服务端时间。 */
const doneAt = (c: { bite_at: number }, hook: number, inputs: string) => c.bite_at + hook + inputs.length * f.reel.step_ms;

describe('dynamic_farm.json fishing (SEN-C-223 §6, SEN-Q-342)', () => {
  it('ships seven fish at 60 : 30 : 10, cast 5 Energy and 3 back when a fish gets away', () => {
    expect(f.fish).toEqual({ fish_crucian: 1, fish_carp: 1, fish_mullet: 1, fish_perch: 2, fish_bass: 2, fish_mackerel: 2, fish_seabass: 3 });
    expect(f.weights).toEqual([60, 30, 10]);
    expect([f.cast_energy, f.refund_fail]).toEqual([5, 3]);
    for (const [id, price] of Object.entries({ fish_crucian: 3, fish_carp: 4, fish_mullet: 4, fish_perch: 7, fish_bass: 7, fish_mackerel: 8, fish_seabass: 14 }))
      expect(rules.economy.sell_prices[id]).toBe(price);
  });

  it('ships the three rods and two baits: Reed 80, Carbon 600 from Lv4; Worm 2 (30 a day), Spinner 6 (10 a day, Lv4)', () => {
    expect(f.starter_rod).toBe('rod_starter');
    expect(f.rods.map(r => [r.id, r.hook_bonus_ms, r.band_bonus, r.loss_mult]))
      .toEqual([['rod_starter', 0, 0, 1], ['rod_reed', 400, 0.03, 1], ['rod_carbon', 800, 0.05, 0.9]]);
    expect(Object.fromEntries(['rod_reed', 'rod_carbon', 'bait_worm', 'bait_lure'].map(id => [id, rules.economy.buy_prices[id]])))
      .toEqual({ rod_reed: 80, rod_carbon: 600, bait_worm: 2, bait_lure: 6 });
    expect(rules.economy.buy_prices.rod_starter).toBeUndefined();
    expect(f.goods).toEqual({ rod_reed: { max_owned: 1 }, rod_carbon: { max_owned: 1, min_level: 4 }, bait_worm: { daily: 30 },
      bait_lure: { daily: 10, min_level: 4 } });
    // Worm: bites twice as fast, Fine +10 (60/30/10 → 50/40/10); Spinner: Rare +20 (→ 45/25/30).
    expect(f.baits).toEqual({ bait_worm: { shift: [-10, 10, 0], wait: 0.5 }, bait_lure: { shift: [-15, -5, 20], wait: 1 } });
  });

  it('keeps the P0 reel: 50 ms steps, 30 s at most, the Common / Fine / Rare tiers of fishing.json', () => {
    expect(f.reel).toMatchObject({ step_ms: 50, max_steps: 600, bar_acceleration: 2.8, bar_max_speed: 0.75, initial_progress: 0.3 });
    expect(f.reel.tiers['1']).toEqual({ bar_size: 0.34, fish_speed: 0.2, turn_steps: 40, gain: 0.16, loss: 0.08 });
    expect(f.reel.tiers['3']).toEqual({ bar_size: 0.24, fish_speed: 0.44, turn_steps: 22, gain: 0.13, loss: 0.12 });
  });

  it('refuses malformed fishing rules at load time; rules without fishing cannot fish', () => {
    const bad = (patch: Record<string, unknown>) => () => parseParcelRules(structuredClone({ ...rules, fishing: { ...f, ...patch } }));
    expect(bad({ weights: [60, 30] })).toThrow();   // the Sea Bass's tier 3 would have no weight
    expect(bad({ weights: [] })).toThrow();
    expect(bad({ fish: { fish_unknown: 1 } })).toThrow();   // no sell price
    expect(bad({ starter_rod: 'rod_gold' })).toThrow();
    expect(bad({ refund_fail: 6 })).toThrow();   // more back than the cast cost
    expect(bad({ baits: { bait_worm: { shift: [1, 2], wait: 0.5 } } })).toThrow();
    const { fishing: _, ...without } = rules;
    const none = parseParcelRules(structuredClone(without));
    expect(applyFarmCommands(none, welcomed(), [{ type: 'visit_pier' }], T0)).toMatchObject({ ok: false, code: 'NO_FISHING' });
  });
});

describe('fishing commands (C-232)', () => {
  it('parses the four commands; malformed reels are refused before they reach the farm', () => {
    expect(parseFarmCommands([{ type: 'visit_pier' }, { type: 'cast_line' }, { type: 'cast_line', bait: 'bait_worm' },
      { type: 'reel_line', hook_ms: 300, inputs: '0101' }, { type: 'cancel_line' }])).toEqual([{ type: 'visit_pier' },
      { type: 'cast_line', bait: null }, { type: 'cast_line', bait: 'bait_worm' }, { type: 'reel_line', hook_ms: 300, inputs: '0101' }, { type: 'cancel_line' }]);
    for (const bad of [{ type: 'reel_line', hook_ms: 300, inputs: '' }, { type: 'reel_line', hook_ms: 300, inputs: '012' },
      { type: 'reel_line', hook_ms: -1, inputs: '1' }, { type: 'reel_line', hook_ms: 1.5, inputs: '1' }, { type: 'reel_line', inputs: '1' },
      { type: 'cast_line', bait: 3 }, { type: 'reel_line', hook_ms: 0, inputs: '1'.repeat(10_001) }])
      expect(parseFarmCommands([bad])).toBeNull();
    // The outcome is never the client's: a `landed` field is simply not read.
    expect(parseFarmCommands([{ type: 'reel_line', hook_ms: 0, inputs: '1', outcome: 'landed', fish: 'fish_seabass' }]))
      .toEqual([{ type: 'reel_line', hook_ms: 0, inputs: '1' }]);
  });

  it('the first visit to the pier gives one Starter Rod, once', () => {
    const s = atPier();
    expect(s.bag.rod_starter).toBe(1);
    expect(s.fishing).toMatchObject({ gifted_at: T0, cast: null, casts: 0 });
    expect(apply(s, [{ type: 'visit_pier' }], T0 + 1000)).toMatchObject({ ok: false, code: 'PIER_GIFTED' });
  });

  it('a cast needs a rod and 5 Energy: without enough it is refused and nothing changes', () => {
    expect(apply(welcomed(), [{ type: 'cast_line', bait: null }])).toMatchObject({ ok: false, code: 'NO_ROD', detail: { item: 'rod_starter' } });
    const low = atPier();
    low.energy = { value: 4, at: T0, rested_on: null };
    const out = apply(low, [{ type: 'cast_line', bait: null }]);
    expect(out).toMatchObject({ ok: false, code: 'NO_ENERGY', detail: { need: 5, have: 4 } });
    expect(low.fishing!.cast).toBeNull();
    // With 5 it casts: Energy −5, the server picks the tier, seed and bite time.
    low.energy = { value: 5, at: T0, rested_on: null };
    const { s, c } = cast(low);
    expect(s.energy!.value).toBe(0);
    expect(c).toMatchObject({ at: T0, rarity: rollRarity(f, castSeed(PARCEL, T0, 0), null), seed: castSeed(PARCEL, T0, 0), bait: null,
      rod: 'rod_starter', hook_ms: 2200 });
    expect(c.bite_at - T0).toBeGreaterThanOrEqual(f.bite_min_ms);
    expect(c.bite_at - T0).toBeLessThan(f.bite_min_ms + f.bite_spread_ms);
    expect(s.fishing!.casts).toBe(1);
    // One line at a time.
    expect(apply(s, [{ type: 'cast_line', bait: null }], T0 + 1000)).toMatchObject({ ok: false, code: 'ALREADY_CASTING' });
  });

  it('the server replays the reel: a played-out trace lands the fish of the cast’s tier; the same cast cannot be claimed twice', () => {
    const { s, c } = cast(atPier());
    const tier = reelTier(f, c.rarity, rodOf('rod_starter'));
    const inputs = goodInputs(c.seed, tier);
    expect(replayReel(f, c.seed, tier, inputs)!.outcome).toBe('caught');
    const at = doneAt(c, 400, inputs);
    const out = run(s, [{ type: 'reel_line', hook_ms: 400, inputs }], at);
    const fish = pickFish(f, c.seed, c.rarity);
    expect(f.fish[fish]).toBe(c.rarity);
    expect(out.bag[fish]).toBe(1);
    expect(out.fishing).toMatchObject({ cast: null, caught: { [fish]: 1 }, last: { result: 'landed', fish, at, refund: 0 } });
    expect(out.energy!.value).toBe(195);
    // The same reel again: nothing in the water, nothing more in the bag.
    expect(apply(out, [{ type: 'reel_line', hook_ms: 400, inputs }], at + 10)).toMatchObject({ ok: false, code: 'NO_CAST' });
    // Twice in one batch: refused as a whole, so not even the first lands.
    expect(apply(s, [{ type: 'reel_line', hook_ms: 400, inputs }, { type: 'reel_line', hook_ms: 400, inputs }], at))
      .toMatchObject({ ok: false, index: 1, code: 'NO_CAST' });
  });

  it('a lost reel gets away: 3 Energy back, no fish', () => {
    const { s, c } = cast(atPier());
    const inputs = idleInputs(c.seed, reelTier(f, c.rarity, rodOf('rod_starter')));
    const out = run(s, [{ type: 'reel_line', hook_ms: 100, inputs }], doneAt(c, 100, inputs));
    expect(out.fishing).toMatchObject({ cast: null, caught: {}, last: { result: 'escaped', fish: null, refund: 3 } });
    expect(out.energy!.value).toBe(198);
    expect(Object.keys(out.bag).filter(k => k.startsWith('fish_'))).toEqual([]);
  });

  it('refuses a forged trace: cut short, padded past the end, or longer than the time since the bite', () => {
    const { s, c } = cast(atPier());
    const tier = reelTier(f, c.rarity, rodOf('rod_starter'));
    const inputs = goodInputs(c.seed, tier);
    const at = doneAt(c, 0, inputs);
    expect(apply(s, [{ type: 'reel_line', hook_ms: 0, inputs: inputs.slice(0, -1) }], at))
      .toMatchObject({ ok: false, code: 'REEL_INPUT', detail: { reason: 'unfinished' } });
    expect(apply(s, [{ type: 'reel_line', hook_ms: 0, inputs: inputs + '1' }], at + 50))
      .toMatchObject({ ok: false, code: 'REEL_INPUT', detail: { reason: 'unfinished' } });
    // Sent the moment the fish bit: a 10 s reel cannot be over yet.
    expect(apply(s, [{ type: 'reel_line', hook_ms: 0, inputs }], c.bite_at)).toMatchObject({ ok: false, code: 'REEL_INPUT', detail: { reason: 'too_fast' } });
    expect(apply(s, [{ type: 'reel_line', hook_ms: 0, inputs }], at - REPLAY_SLACK_MS - 1)).toMatchObject({ ok: false, code: 'REEL_INPUT' });
    expect(apply(s, [{ type: 'reel_line', hook_ms: 0, inputs }], at - REPLAY_SLACK_MS)).toMatchObject({ ok: true });
    // Before the bite there is nothing to reel.
    expect(apply(s, [{ type: 'reel_line', hook_ms: 0, inputs: '1' }], c.bite_at - 1)).toMatchObject({ ok: false, code: 'TOO_EARLY' });
  });

  it('a hook after the window, or a result past the deadline, gets away whatever the trace says', () => {
    const { s, c } = cast(atPier());
    const inputs = goodInputs(c.seed, reelTier(f, c.rarity, rodOf('rod_starter')));
    const late = run(s, [{ type: 'reel_line', hook_ms: c.hook_ms + 1, inputs }], doneAt(c, c.hook_ms + 1, inputs));
    expect(late.fishing!.last).toMatchObject({ result: 'escaped', refund: 3 });
    const stale = run(s, [{ type: 'reel_line', hook_ms: 0, inputs }], castDeadline(f, c) + 1);
    expect(stale.fishing!.last).toMatchObject({ result: 'escaped' });
  });

  it('line in before the bite gives all 5 back and keeps the bait; after the bite it counts as got away and uses the bait', () => {
    const baited = atPier();
    baited.bag.bait_worm = 2;
    const { s, c } = cast(baited, T0, 'bait_worm');
    const before = run(s, [{ type: 'cancel_line' }], c.bite_at - 1);
    expect(before.fishing!.last).toMatchObject({ result: 'cancelled', refund: 5 });
    expect(before.energy!.value).toBe(200);
    expect(before.bag.bait_worm).toBe(2);
    const after = run(s, [{ type: 'cancel_line' }], c.bite_at);
    expect(after.fishing!.last).toMatchObject({ result: 'escaped', refund: 3 });
    expect(after.bag.bait_worm).toBe(1);
    expect(apply(after, [{ type: 'cancel_line' }], c.bite_at + 1)).toMatchObject({ ok: false, code: 'NO_CAST' });
  });

  it('a line left past its deadline gets away when the next cast goes in', () => {
    const { s, c } = cast(atPier());
    expect(apply(s, [{ type: 'cast_line', bait: null }], castDeadline(f, c))).toMatchObject({ ok: false, code: 'ALREADY_CASTING' });
    const next = run(s, [{ type: 'cast_line', bait: null }], castDeadline(f, c) + 1);
    expect(next.fishing!.last).toMatchObject({ result: 'escaped', refund: 3 });
    expect(next.fishing!.casts).toBe(2);
    expect(next.fishing!.cast!.at).toBe(castDeadline(f, c) + 1);
  });

  it('baits: one is needed in the bag; a worm halves the wait and is used once the fish has bitten', () => {
    expect(apply(atPier(), [{ type: 'cast_line', bait: 'bait_worm' }])).toMatchObject({ ok: false, code: 'NO_BAIT', detail: { item: 'bait_worm' } });
    expect(apply(atPier(), [{ type: 'cast_line', bait: 'rod_reed' }])).toMatchObject({ ok: false, code: 'NO_BAIT' });
    const baited = atPier();
    baited.bag.bait_worm = 1;
    const { s, c } = cast(baited, T0, 'bait_worm');
    expect(c.bait).toBe('bait_worm');
    expect(c.bite_at - T0).toBe(Math.round((f.bite_min_ms + (castWait(c.seed))) * 0.5));
    const inputs = goodInputs(c.seed, reelTier(f, c.rarity, rodOf('rod_starter')));
    const out = run(s, [{ type: 'reel_line', hook_ms: 0, inputs }], doneAt(c, 0, inputs));
    expect(out.bag.bait_worm).toBeUndefined();
  });

  it('rolls 60 : 30 : 10 by seed; the Worm shifts it to 50 : 40 : 10 and the Spinner to 45 : 25 : 30', () => {
    const share = (bait: string | null) => {
      const n = [0, 0, 0];
      for (let i = 0; i < 20_000; i++) n[rollRarity(f, castSeed(PARCEL, T0 + i, i), bait) - 1]++;
      return n.map(x => Math.round(x / 200));
    };
    const near = (got: number[], want: number[]) => got.forEach((g, i) => expect(Math.abs(g - want[i])).toBeLessThanOrEqual(2));
    near(share(null), [60, 30, 10]);
    near(share('bait_worm'), [50, 40, 10]);
    near(share('bait_lure'), [45, 25, 30]);
    // Every fish of a tier can come up.
    const seen = new Set<string>();
    for (let i = 0; i < 300; i++) for (const t of [1, 2, 3]) seen.add(pickFish(f, castSeed(PARCEL, T0, i), t));
    expect([...seen].sort()).toEqual(Object.keys(f.fish).sort());
  });

  it('casts with the best rod in the bag: the Carbon Rod widens the band 5 points, loses 10 % less and hooks 0.8 s longer', () => {
    const s = atPier();
    s.bag.rod_reed = 1;
    expect(cast(s).c).toMatchObject({ rod: 'rod_reed', hook_ms: 2600 });
    s.bag.rod_carbon = 1;
    const { c } = cast(s);
    expect(c).toMatchObject({ rod: 'rod_carbon', hook_ms: 3000 });
    const t = reelTier(f, 1, rodOf('rod_carbon'));
    expect(t.bar_size).toBeCloseTo(0.39, 10);
    expect(t.loss).toBeCloseTo(0.072, 10);
    expect(reelTier(f, 3, rodOf('rod_reed')).bar_size).toBeCloseTo(0.27, 10);
  });

  it('sells fish at Jasmine’s prices', () => {
    const s = atPier();
    s.bag.fish_seabass = 2;
    s.bag.fish_crucian = 1;
    const out = run(s, [{ type: 'sell', item: 'fish_seabass', count: 2 }, { type: 'sell', item: 'fish_crucian', count: 1 }]);
    expect(out.coins).toBe(31);
    expect(apply(out, [{ type: 'sell', item: 'rod_starter', count: 1 }])).toMatchObject({ ok: false, code: 'NOT_SELLABLE' });
  });

  it('a save from before C-232 reads and writes without a fishing field', () => {
    const old = welcomed();
    expect(withEconomy(old).fishing).toBeUndefined();
    expect(run(old, [{ type: 'till', cell: '1,1' }]).fishing).toBeUndefined();
  });
});

/**
 * C-241 防刷：咬钩前收线全退体力、不扣鱼饵（C-223 的规则不变），所以咬钩前客户端拿到的东西里不能有能推出这一竿档次或鱼种的信息。
 * 正式服的种子是服务端随机数（FarmContext.cast_seed），回给客户端的存档到咬钩时刻之前去掉 rarity 和 seed（castView）。
 */
describe('C-241 nothing before the bite tells the client what the cast holds', () => {
  /** 按服务端随机来源投一竿（routes.ts 传的是 node:crypto randomInt，这里换成给定的种子）。 */
  function castWith(state: ParcelFarmState, seed: number, now = T0, bait: string | null = null) {
    const out = applyFarmCommands(rules, state, [{ type: 'cast_line', bait }], now, { parcel_id: PARCEL, cast_seed: () => seed });
    if (!out.ok) throw new Error(out.code);
    return { s: out.state, c: out.state.fishing!.cast! };
  }

  it('with a server random source the seed is that number, not one the parcel, the time and the cast count give', () => {
    const { c } = castWith(atPier(), 0xDEADBEEF);
    expect(c.seed).toBe(0xDEADBEEF);
    expect(c.seed).not.toBe(castSeed(PARCEL, T0, 0));
    expect(c.rarity).toBe(rollRarity(f, 0xDEADBEEF, null));
    expect(c.bite_at - T0).toBe(f.bite_min_ms + castWait(0xDEADBEEF));
    // Out-of-range sources are folded into 0 … 2^32−1 like the client's own seed.
    expect(castWith(atPier(), 2 ** 32 + 5).c.seed).toBe(5);
  });

  it('the client view hides the tier and the seed until the server time reaches the bite, then shows the cast as saved', () => {
    const { s, c } = castWith(atPier(), 123_456_789);
    for (const at of [T0, c.bite_at - 1]) {
      const v = castView(s.fishing, at)!;
      expect(v.cast).toEqual({ at: T0, bite_at: c.bite_at, hook_ms: c.hook_ms, bait: null, rod: 'rod_starter' });
      expect(JSON.stringify(v)).not.toMatch(/rarity|seed/);
      // Nothing else of the save changes, and the saved cast keeps both.
      expect({ ...v, cast: null }).toEqual({ ...s.fishing, cast: null });
      expect(s.fishing!.cast).toMatchObject({ rarity: c.rarity, seed: 123_456_789 });
    }
    expect(castView(s.fishing, c.bite_at)).toEqual(s.fishing);
    expect(castView(s.fishing, c.bite_at + 5000)).toEqual(s.fishing);
    expect(castView(undefined, T0)).toBeUndefined();
    const idle = atPier().fishing!;
    expect(castView(idle, T0)).toBe(idle);
  });

  it('seeds that share a bite time still roll 60 : 30 : 10: the bite time tells nothing of the tier', () => {
    // The bite time is all the client sees of a seed before the bite. Group many random seeds by their bite time: within a
    // group the tiers are still spread as the weights say.
    const byWait = new Map<number, number[]>();
    let x = 7;
    for (let i = 0; i < 60_000; i++) {
      x = (Math.imul(x, 1664525) + 1013904223) >>> 0;
      const w = castWait(x) % 10;   // ten bands of bite times
      const n = byWait.get(w) ?? [0, 0, 0];
      n[rollRarity(f, x, null) - 1]++;
      byWait.set(w, n);
    }
    for (const n of byWait.values()) {
      const total = n[0] + n[1] + n[2];
      expect(Math.abs(n[2] / total - 0.1)).toBeLessThan(0.02);
      expect(Math.abs(n[0] / total - 0.6)).toBeLessThan(0.03);
    }
  });

  it('line in before the bite still gives all 5 back and keeps the bait; the server still replays the reel on the saved seed', () => {
    const baited = atPier();
    baited.bag.bait_worm = 2;
    const { s, c } = castWith(baited, 987_654_321, T0, 'bait_worm');
    expect(s.energy!.value).toBe(195);
    const before = run(s, [{ type: 'cancel_line' }], c.bite_at - 1);
    expect(before.fishing!.last).toMatchObject({ result: 'cancelled', refund: 5 });
    expect(before).toMatchObject({ energy: { value: 200 }, bag: { bait_worm: 2 } });
    // After the bite the client reads the seed and the tier and reels on them; the server replays the same seed.
    const shown = castView(s.fishing, c.bite_at)!.cast!;
    const tier = reelTier(f, shown.rarity, rodOf('rod_starter'));
    const inputs = goodInputs(shown.seed, tier);
    const out = run(s, [{ type: 'reel_line', hook_ms: 200, inputs }], doneAt(c, 200, inputs));
    const fish = pickFish(f, 987_654_321, c.rarity);
    expect(out.fishing!.last).toMatchObject({ result: 'landed', fish });
    expect(out.bag).toMatchObject({ [fish]: 1 });
    expect(out.bag.bait_worm).toBe(1);
    expect(apply(out, [{ type: 'reel_line', hook_ms: 200, inputs }], doneAt(c, 200, inputs) + 1)).toMatchObject({ ok: false, code: 'NO_CAST' });
  });
});

/** 不挂饵时的咬钩随机部分（cast_line 同一个算法）。 */
function castWait(seed: number): number {
  return hash(`${seed}:b`) % f.bite_spread_ms;
}
describe('tackle at Jasmine’s counter (C-232)', () => {
  const rich = (level = 1): ParcelFarmState => ({ ...atPier(), coins: 5000, level });

  it('one Reed Rod and one Carbon Rod at most; the Carbon Rod needs farm level 4', () => {
    const s = run(rich(), [{ type: 'buy', item: 'rod_reed', count: 1 }]);
    expect(s).toMatchObject({ coins: 4920, bag: { rod_reed: 1 } });
    expect(apply(s, [{ type: 'buy', item: 'rod_reed', count: 1 }])).toMatchObject({ ok: false, code: 'ALREADY_OWNED', detail: { item: 'rod_reed', max: 1 } });
    expect(apply(rich(3), [{ type: 'buy', item: 'rod_carbon', count: 1 }])).toMatchObject({ ok: false, code: 'CONDITION_NOT_MET', detail: { level: 3, min_level: 4 } });
    expect(run(rich(4), [{ type: 'buy', item: 'rod_carbon', count: 1 }])).toMatchObject({ coins: 4400, bag: { rod_carbon: 1 } });
    expect(apply(rich(4), [{ type: 'buy', item: 'rod_carbon', count: 2 }])).toMatchObject({ ok: false, code: 'ALREADY_OWNED' });
    // Conditions before coins: a poor Lv3 farm hears about the level.
    expect(apply({ ...atPier(), level: 3 }, [{ type: 'buy', item: 'rod_carbon', count: 1 }])).toMatchObject({ code: 'CONDITION_NOT_MET' });
    expect(apply(atPier(), [{ type: 'buy', item: 'rod_reed', count: 1 }])).toMatchObject({ code: 'NOT_ENOUGH_COINS', detail: { need: 80 } });
    expect(apply(rich(), [{ type: 'buy', item: 'rod_starter', count: 1 }])).toMatchObject({ code: 'NOT_FOR_SALE' });
  });

  it('30 Worms and 10 Spinners a player day; the count starts again after 04:00', () => {
    let s = run(rich(4), [{ type: 'buy', item: 'bait_worm', count: 25 }, { type: 'buy', item: 'bait_worm', count: 5 }, { type: 'buy', item: 'bait_lure', count: 10 }]);
    expect(s.bag).toMatchObject({ bait_worm: 30, bait_lure: 10 });
    expect(s.coins).toBe(5000 - 60 - 60);
    expect(apply(s, [{ type: 'buy', item: 'bait_worm', count: 1 }])).toMatchObject({ ok: false, code: 'DAILY_LIMIT', detail: { item: 'bait_worm', limit: 30, bought: 30 } });
    expect(apply(s, [{ type: 'buy', item: 'bait_lure', count: 1 }])).toMatchObject({ ok: false, code: 'DAILY_LIMIT' });
    // Using them does not give more today.
    s.bag.bait_worm = 0;
    expect(apply(s, [{ type: 'buy', item: 'bait_worm', count: 1 }])).toMatchObject({ ok: false, code: 'DAILY_LIMIT' });
    s = run(s, [{ type: 'buy', item: 'bait_worm', count: 30 }], T0 + 24 * 3_600_000);
    expect(s.fishing!.bought.counts).toEqual({ bait_worm: 30 });
    expect(apply(rich(3), [{ type: 'buy', item: 'bait_lure', count: 1 }])).toMatchObject({ code: 'CONDITION_NOT_MET', detail: { min_level: 4 } });
    // A refused batch keeps no count: 31 at once is refused and 30 still go through.
    expect(apply(rich(), [{ type: 'buy', item: 'bait_worm', count: 31 }])).toMatchObject({ ok: false, code: 'DAILY_LIMIT', detail: { bought: 0 } });
  });
});

/**
 * 客户端和服务端同一套钓鱼规则：tests/dynamic_farm/fixtures/fishing_cases.json 的每个用例在这里按服务端跑，
 * 在 tests/dynamic_farm/test_parcel_fishing.gd 里按客户端 parcel_fishing.gd 跑，两边结果都要等于文件里记的结果。
 */
describe('C-232 the client runs the same fishing cases (shared fixture)', () => {
  const shared = JSON.parse(readFileSync(path.join(DEFAULT_CONTENT_DIR, '..', '..', '..', 'tests', 'dynamic_farm', 'fixtures', 'fishing_cases.json'), 'utf8'));
  it('has the cases', () => {
    expect(shared.cases.length).toBeGreaterThanOrEqual(40);
    expect(shared.reels.length).toBeGreaterThanOrEqual(150);
  });
  for (const c of shared.cases) {
    it(c.name, () => {
      const frozen = structuredClone(c.farm);
      const r = applyFarmCommands(rules, c.farm, c.commands, c.now, { parcel_id: shared.parcel_id });
      expect(r.ok ? { ok: true, bag: r.state.bag, energy: r.state.energy, coins: r.state.coins, fishing: r.state.fishing ?? null }
        : { ok: false, index: r.index, code: r.code, detail: r.detail ?? {} }).toEqual(c.expect);
      expect(c.farm).toEqual(frozen);
    });
  }
  it('replays every reel to the recorded outcome, step for step', () => {
    for (const r of shared.reels) {
      const tier = reelTier(f, r.rarity, f.rods.find(x => x.id === r.rod)!);
      expect(replayReel(f, r.seed, tier, r.inputs)!.outcome).toBe(r.outcome);
      const s = initialReel(f, r.seed);
      const marks: number[][] = [];
      for (const bit of r.inputs) {
        stepReel(f, s, bit === '1', tier);
        if (s.step % 40 === 0 || s.outcome !== 'playing') marks.push([s.step, s.bar, s.fish, s.progress]);
      }
      expect(marks).toEqual(r.marks);
    }
    for (const x of shared.rolls) for (const bait of ['bait_worm', 'bait_lure'])
      expect([rollRarity(f, x.seed, null), rollRarity(f, x.seed, bait)]).toEqual([x.none, x[bait]]);
  });
});
