/**
 * C-232: writes tests/dynamic_farm/fixtures/fishing_cases.json, the fishing cases both sides run (server
 * test/parcels/fishing.test.ts, client tests/dynamic_farm/test_parcel_fishing.gd). Each `expect` is what the server
 * rules (assets/farm/data/dynamic_farm.json `fishing`) give; `reels` are reel replays step for step. Rerun after
 * changing the fishing numbers and review the diff.
 *
 *   cd server && npx tsx ../tools/dev/dynamic_farm/fishing_cases.ts
 */
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { DEFAULT_CONTENT_DIR } from '../../../server/src/domain/content.js';
import { applyFarmCommands, type FarmCommand } from '../../../server/src/parcels/farm.js';
import { castDeadline, castSeed, initialReel, reelTier, replayReel, rollRarity, stepReel, type FishingRules, type ReelTier }
  from '../../../server/src/parcels/fishing.js';
import { hash32 } from '../../../server/src/parcels/requests.js';
import { loadParcelRules } from '../../../server/src/parcels/rules.js';

const rules = loadParcelRules(DEFAULT_CONTENT_DIR);
const f = rules.fishing as FishingRules;
const OUT = path.join(DEFAULT_CONTENT_DIR, '..', '..', '..', 'tests', 'dynamic_farm', 'fixtures', 'fishing_cases.json');
const T0 = 1795406400000;
const PARCEL = 'p-3512001';
type Farm = Record<string, unknown>;

/** A welcomed farm at full Energy (210 at Lv2), a Starter Rod in the bag after its first pier visit. */
const base = (change: Farm = {}): Farm => ({
  v: 1, buildings: [], house: null, cleared: [], tilled: [], crops: {}, bag: { hoe_starter: 1, rod_starter: 1 },
  welcomed_at: T0 - 86_400_000 * 30, coins: 700, sales: 0, gathered: {}, blueprints_claimed: {},
  energy: { value: 210, at: T0, rested_on: null }, drops: [], drop_seq: 0, pail_water: 0, grants: {}, level: 2, requests_done: 0,
  fishing: { cast: null, casts: 3, caught: { fish_carp: 2 }, gifted_at: T0 - 86_400_000, bought: { day: null, counts: {} }, last: null },
  ...change,
});
/** The cast the server makes for `farm` at `now` (no bait, its best rod). */
function castOf(farm: Farm, now: number, bait: string | null = null) {
  const r = applyFarmCommands(rules, structuredClone(farm) as never, [{ type: 'cast_line', bait }], now, { parcel_id: PARCEL });
  if (!r.ok) throw new Error(r.code);
  return r.state.fishing!.cast!;
}
const tierOf = (c: { rarity: number; rod: string }) => reelTier(f, c.rarity, f.rods.find(r => r.id === c.rod)!);
function played(seed: number, tier: ReelTier, hold: (s: ReturnType<typeof initialReel>, i: number) => boolean): string {
  const s = initialReel(f, seed);
  let out = '';
  for (let i = 0; s.outcome === 'playing'; i++) { const h = hold(s, i); out += h ? '1' : '0'; stepReel(f, s, h, tier); }
  return out;
}
const good = (seed: number, tier: ReelTier) => played(seed, tier, s => s.fish > s.bar);
const idle = (seed: number, tier: ReelTier) => played(seed, tier, () => false);
/** A line in the water: cast at T0, its seed for the 4th cast of this parcel. */
const inWater = (change: Farm = {}, bait: string | null = null) => {
  const before = base(change);
  const c = castOf(before, T0, bait);
  return { farm: base({ ...change, energy: { value: 205, at: T0, rested_on: null },
    fishing: { ...(before.fishing as Farm), casts: 4, cast: c } }), c };
};

const cast = (bait: string | null = null): FarmCommand => ({ type: 'cast_line', bait });
const reel = (hook_ms: number, inputs: string): FarmCommand => ({ type: 'reel_line', hook_ms, inputs });
const buy = (item: string, count = 1): FarmCommand => ({ type: 'buy', item, count });

const w = inWater();
const wGood = good(w.c.seed, tierOf(w.c));
const wIdle = idle(w.c.seed, tierOf(w.c));
const done = (hook: number, inputs: string) => w.c.bite_at + hook + inputs.length * f.reel.step_ms;
const carbon = inWater({ bag: { rod_starter: 1, rod_reed: 1, rod_carbon: 1 }, level: 4 });
const cGood = good(carbon.c.seed, tierOf(carbon.c));
const worm = inWater({ bag: { rod_starter: 1, bait_worm: 3 } }, 'bait_worm');
const wormGood = good(worm.c.seed, tierOf(worm.c));

const cases: [string, Farm, FarmCommand[], number][] = [
  ['the first pier visit gives a Starter Rod', base({ bag: { hoe_starter: 1 }, fishing: undefined }), [{ type: 'visit_pier' }], T0],
  ['the second visit gives nothing', base(), [{ type: 'visit_pier' }], T0],
  ['no rod: no cast', base({ bag: { hoe_starter: 1 } }), [cast()], T0],
  ['4 Energy: no cast, nothing changes', base({ energy: { value: 4, at: T0, rested_on: null } }), [cast()], T0],
  ['a cast takes 5 Energy; the server picks the tier, seed and bite', base(), [cast()], T0],
  ['an older save casts its first line', base({ fishing: undefined }), [cast()], T0 + 7],
  ['the best rod in the bag goes in', base({ bag: { rod_starter: 1, rod_reed: 1 } }), [cast()], T0 + 11],
  ['a Worm needs one in the bag', base(), [cast('bait_worm')], T0],
  ['a Worm halves the wait', base({ bag: { rod_starter: 1, bait_worm: 1 } }), [cast('bait_worm')], T0 + 13],
  ['a Spinner shifts the tiers', base({ bag: { rod_starter: 1, bait_lure: 2 } }), [cast('bait_lure')], T0 + 17],
  ['not a bait', base(), [cast('rod_starter')], T0],
  ['one line at a time', w.farm, [cast()], w.c.bite_at],
  ['a line past its deadline gets away as the next goes in', w.farm, [cast()], castDeadline(f, w.c) + 1],
  ['before the bite there is nothing to reel', w.farm, [reel(0, '1')], w.c.bite_at - 1],
  ['line in before the bite: all 5 back', w.farm, [{ type: 'cancel_line' }], w.c.bite_at - 1],
  ['line in after the bite: got away, 3 back', w.farm, [{ type: 'cancel_line' }], w.c.bite_at],
  ['a played reel lands the fish', w.farm, [reel(400, wGood)], done(400, wGood)],
  ['the same reel twice in a batch: refused whole', w.farm, [reel(400, wGood), reel(400, wGood)], done(400, wGood)],
  ['a lost reel gets away: 3 back', w.farm, [reel(250, wIdle)], done(250, wIdle)],
  ['sent too soon after the bite: refused', w.farm, [reel(0, wGood)], w.c.bite_at + 1000],
  ['just inside the slack it counts', w.farm, [reel(0, wGood)], done(0, wGood) - 250],
  ['cut short: refused', w.farm, [reel(0, wGood.slice(0, -1))], done(0, wGood)],
  ['padded past the result: refused', w.farm, [reel(0, wGood + '0')], done(0, wGood) + 50],
  ['hooked after the window: got away', w.farm, [reel(w.c.hook_ms + 1, wGood)], done(w.c.hook_ms + 1, wGood)],
  ['past the deadline: got away', w.farm, [reel(0, wGood)], castDeadline(f, w.c) + 1],
  ['nothing in the water', base(), [reel(0, wGood)], done(0, wGood)],
  ['the Carbon Rod reel lands', carbon.farm, [reel(2900, cGood)], carbon.c.bite_at + 2900 + cGood.length * f.reel.step_ms],
  ['a Worm is used once the fish has bitten', worm.farm, [reel(0, wormGood)], worm.c.bite_at + wormGood.length * f.reel.step_ms],
  ['a Worm stays on the hook when the line comes in before the bite', worm.farm, [{ type: 'cancel_line' }], worm.c.bite_at - 1],
  ['a Reed Rod for 80', base(), [buy('rod_reed')], T0],
  ['one Reed Rod is enough', base({ bag: { rod_starter: 1, rod_reed: 1 } }), [buy('rod_reed')], T0],
  ['the Carbon Rod needs farm level 4', base({ coins: 900 }), [buy('rod_carbon')], T0],
  ['the Carbon Rod at level 4 for 600', base({ level: 4 }), [buy('rod_carbon')], T0],
  ['599 coins: no Carbon Rod', base({ level: 4, coins: 599 }), [buy('rod_carbon')], T0],
  ['30 Worms a day', base(), [buy('bait_worm', 20), buy('bait_worm', 10)], T0],
  ['the 31st Worm waits for tomorrow', base(), [buy('bait_worm', 30), buy('bait_worm', 1)], T0],
  ['yesterday’s Worms do not count', base({ fishing: { cast: null, casts: 0, caught: {}, gifted_at: T0, bought: { day: '2026-11-26', counts: { bait_worm: 30 } }, last: null } }),
    [buy('bait_worm', 30)], T0],
  ['the Spinner needs level 4', base(), [buy('bait_lure')], T0],
  ['10 Spinners a day at level 4', base({ level: 4 }), [buy('bait_lure', 10), buy('bait_lure', 1)], T0],
  ['the Starter Rod is not sold', base(), [buy('rod_starter')], T0],
  ['fish sell at Jasmine’s', base({ bag: { rod_starter: 1, fish_seabass: 1, fish_mackerel: 2, fish_crucian: 3 } }),
    [{ type: 'sell', item: 'fish_seabass', count: 1 }, { type: 'sell', item: 'fish_mackerel', count: 2 }, { type: 'sell', item: 'fish_crucian', count: 3 }], T0],
];

const out = cases.map(([name, farm, commands, now]) => {
  const clean = JSON.parse(JSON.stringify(farm));
  const r = applyFarmCommands(rules, structuredClone(clean), commands, now, { parcel_id: PARCEL });
  const expect = r.ok ? { ok: true, bag: r.state.bag, energy: r.state.energy, coins: r.state.coins, fishing: r.state.fishing ?? null }
    : { ok: false, index: r.index, code: r.code, detail: r.detail ?? {} };
  return { name, farm: clean, commands, now, expect };
});

/** Reel replays: each tier on each rod, a played, an idle and a jittery trace, the outcome after every 40th step. */
const reels = [];
for (let i = 0; i < 6; i++) {
  const seed = castSeed(PARCEL, T0 + i * 997, i);
  for (const rarity of [1, 2, 3]) for (const rod of f.rods) {
    const tier = reelTier(f, rarity, rod);
    for (const [kind, inputs] of [['played', good(seed, tier)], ['idle', idle(seed, tier)],
      ['jitter', played(seed, tier, (s, n) => (hash32(`${seed}:${n}`) % 100) < (s.fish > s.bar ? 80 : 30))]] as const) {
      const marks: [number, number, number, number][] = [];
      const s = initialReel(f, seed);
      for (let n = 0; n < inputs.length; n++) {
        stepReel(f, s, inputs[n] === '1', tier);
        if (s.step % 40 === 0 || s.outcome !== 'playing') marks.push([s.step, s.bar, s.fish, s.progress]);
      }
      reels.push({ seed, rarity, rod: rod.id, kind, inputs, outcome: replayReel(f, seed, tier, inputs)!.outcome, marks });
    }
  }
}
const rolls = Array.from({ length: 64 }, (_, i) => {
  const seed = castSeed(PARCEL, T0 + i, i);
  return { seed, none: rollRarity(f, seed, null), bait_worm: rollRarity(f, seed, 'bait_worm'), bait_lure: rollRarity(f, seed, 'bait_lure') };
});

const note = 'C-232 fishing at the Aquatic Park pier (SEN-C-223 §6, SEN-Q-342): the Starter Rod on the first visit, casting (5 Energy, the server '
  + 'picks the tier, seed and bite), the reel replayed by the server (landed, got away 3 back, refused traces), the line in before the bite (5 back), '
  + 'the tackle limits at Jasmine\'s and fish sales. Each case runs through server/src/parcels/farm.ts (server/test/parcels/fishing.test.ts) and '
  + 'modules/dynamic_farm/parcel_farm.gd (tests/dynamic_farm/test_parcel_fishing.gd); both must give `expect`. `reels` are reel replays with the '
  + 'state every 40th step, `rolls` the tier rolls. Generated by the server rules: tools/dev/dynamic_farm/fishing_cases.ts.';
writeFileSync(OUT, JSON.stringify({ _note: note, parcel_id: PARCEL, cases: out, reels, rolls }, null, 1) + '\n');
console.log(`${out.length} cases, ${reels.length} reels → ${OUT}`);
for (const c of out) console.log(c.expect.ok ? 'ok  ' : `${String(c.expect.code).padEnd(18)}`, c.name);
const tally: Record<string, number> = {};
for (const r of reels) tally[`${r.kind}:${r.outcome}`] = (tally[`${r.kind}:${r.outcome}`] ?? 0) + 1;
console.log(tally);
