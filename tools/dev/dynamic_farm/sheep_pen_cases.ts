/**
 * C-182: writes tests/dynamic_farm/fixtures/sheep_pen_cases.json, the sheep pen cases both sides run (server
 * test/parcels/farm.test.ts, client tests/dynamic_farm/test_sheep_pen.gd). Each `expect` is what the server rules
 * (assets/farm/data/dynamic_farm.json) give; rerun after changing the pen's numbers and review the diff.
 *
 *   cd server && npx tsx ../tools/dev/dynamic_farm/sheep_pen_cases.ts
 */
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { DEFAULT_CONTENT_DIR } from '../../../server/src/domain/content.js';
import { applyFarmCommands, type FarmCommand } from '../../../server/src/parcels/farm.js';
import { loadParcelRules } from '../../../server/src/parcels/rules.js';

const rules = loadParcelRules(DEFAULT_CONTENT_DIR);
const OUT = path.join(DEFAULT_CONTENT_DIR, '..', '..', '..', 'tests', 'dynamic_farm', 'fixtures', 'sheep_pen_cases.json');
const T0 = 1795406400000;
const MIN = 60_000;
const LAY = 30 * MIN;
type Farm = Record<string, unknown>;

/** A level-3 farm that has delivered 15 requests, with the coins for the blueprint. */
const base = (change: Farm = {}): Farm => ({
  v: 1, buildings: [], house: null, cleared: [], tilled: [], crops: {}, bag: { hoe_starter: 1, crop_carrot: 2 },
  welcomed_at: T0 - 86_400_000, coins: 1210, sales: 0, gathered: {}, blueprints_claimed: {},
  energy: { value: 220, at: T0, rested_on: null }, drops: [], drop_seq: 0, pail_water: 0, grants: {}, level: 3, requests_done: 15,
  ...change,
});
/** The blueprint bought, materials in the bag. */
const owner = (change: Farm = {}): Farm => base({ coins: 10, blueprints_claimed: { sheep_pen: T0 - 1000 },
  bag: { hoe_starter: 1, blueprint_sheep_pen: 1, wood: 18, stone: 16, wild_herb: 9 }, ...change });
const PEN = { id: 1, type: 'sheep_pen', model: 'sheep_pen', x: 20, y: 20, width: 6, depth: 6, rotation: 0, built_at: T0,
  animals: ['sheep', 'sheep', 'sheep', 'sheep'] };
/** The pen standing at 20,20, Wild Herbs in the bag. */
const keeper = (change: Farm = {}): Farm => base({ coins: 10, blueprints_claimed: { sheep_pen: T0 - 1000 }, buildings: [PEN],
  bag: { hoe_starter: 1, wood: 3, stone: 1, wild_herb: 9 }, ...change });
const wool = (id: number, animal: number, spot: number, ready_at: number) => ({ id, item: 'wool', amount: 1, building: 1, animal, spot, ready_at });
const COOP = { id: 2, type: 'coop', model: 'chicken_yard', x: 10, y: 10, width: 7, depth: 5, rotation: 0, built_at: T0,
  animals: ['hen_white', 'hen_brown', 'hen_white'] };

const buy: FarmCommand = { type: 'claim_blueprint', blueprint: 'sheep_pen' };
const place = (x: number, y: number, rotation = 0): FarmCommand => ({ type: 'place_building', building: 'sheep_pen', x, y, rotation });
const feed: FarmCommand = { type: 'feed', building: 1 };
const pick = (drop: number): FarmCommand => ({ type: 'pick_up', drop });

const cases: [string, Farm, FarmCommand[], number][] = [
  ['Scott sells the sheep pen blueprint for 1,200 coins after 15 requests at farm level 3', base(), [buy], T0],
  ['exactly 1,200 coins is enough', base({ coins: 1200 }), [buy], T0],
  ['1,199 coins: refused, nothing changes', base({ coins: 1199 }), [buy], T0],
  ['14 requests: refused at farm level 3 with the coins, nothing changes', base({ requests_done: 14 }), [buy], T0],
  ['no request delivered yet (an older save without the count): refused', base({ requests_done: undefined }), [buy], T0],
  ['farm level 2: refused after 15 requests with the coins, nothing changes', base({ level: 2 }), [buy], T0],
  ['neither 15 requests nor level 3: the requests are named first', base({ requests_done: 3, level: 1 }), [buy], T0],
  ['more requests and a higher level buy it too', base({ requests_done: 40, level: 5 }), [buy], T0],
  ['bought once only', base({ blueprints_claimed: { sheep_pen: T0 - 1000 }, coins: 5000 }), [buy], T0],
  ['the barn blueprint asks for no requests', base({ requests_done: 0, coins: 600 }), [{ type: 'claim_blueprint', blueprint: 'barn' }], T0],
  ...[0, 1, 2, 3].map(r => [`the pen goes down turned ${r * 90}° with its four sheep for the blueprint, 15 Timber and 15 Stone`, owner(), [place(10, 10, r)], T0] as [string, Farm, FarmCommand[], number]),
  ['14 Timber: refused, nothing changes', owner({ bag: { blueprint_sheep_pen: 1, wood: 14, stone: 16 } }), [place(10, 10)], T0],
  ['14 Stone: refused, nothing changes', owner({ bag: { blueprint_sheep_pen: 1, wood: 18, stone: 14 } }), [place(10, 10)], T0],
  ['no blueprint: refused', owner({ bag: { wood: 18, stone: 16 } }), [place(10, 10)], T0],
  ['not over the coop', owner({ buildings: [COOP] }), [place(14, 12)], T0],
  ['not over the coop when turned', owner({ buildings: [COOP] }), [place(5, 6, 3)], T0],
  ['beside the coop it fits', owner({ buildings: [COOP] }), [place(17, 10)], T0],
  ['not over tilled ground', owner({ tilled: ['12,15'] }), [place(10, 10)], T0],
  ['not over a crop (turned)', owner({ tilled: ['15,13'], crops: { '15,13': { crop: 'crop_carrot', planted_at: T0, ripe_at: T0 + MIN, watered_at: T0 } } }), [place(10, 10, 1)], T0],
  ['one sheep pen per parcel', keeper({ bag: { blueprint_sheep_pen: 1, wood: 15, stone: 15 } }), [place(1, 1)], T0],
  ['two Wild Herbs are not enough: nothing changes', keeper({ bag: { wild_herb: 2 } }), [feed], T0],
  ['no Wild Herb: nothing changes', keeper({ bag: { crop_carrot: 9 } }), [feed], T0],
  ['no Energy: nothing changes', keeper({ energy: { value: 0, at: T0, rested_on: null } }), [feed], T0],
  ['feeding takes three Wild Herbs and 1 Energy; the wool is due in 30 minutes', keeper(), [feed], T0 + 1000],
  ['four sheep, four wools on four spots', keeper({ bag: { wild_herb: 12 } }), [feed, feed, feed, feed], T0],
  ['all four fed: four on the ground, no fifth feeding', keeper({ bag: { wild_herb: 15 } }), [feed, feed, feed, feed, feed], T0],
  ['given and one picked up: a sheep eats again', keeper({ energy: { value: 216, at: T0, rested_on: null }, drop_seq: 4,
    drops: [wool(1, 0, 1, T0 + LAY), wool(3, 2, 4, T0 + LAY), wool(4, 3, 0, T0 + LAY)] }), [feed], T0 + LAY],
  ['four given on the ground: pick them up first', keeper({ energy: { value: 216, at: T0 + LAY, rested_on: null }, drop_seq: 4,
    drops: [wool(1, 0, 1, T0 + LAY), wool(2, 1, 5, T0 + LAY), wool(3, 2, 4, T0 + LAY), wool(4, 3, 0, T0 + LAY)] }), [feed], T0 + 2 * LAY],
  ['not before it is given', keeper({ drop_seq: 1, drops: [wool(1, 0, 1, T0 + LAY)] }), [pick(1)], T0 + LAY - 1],
  ['picked: into the bag, off the ground', keeper({ drop_seq: 1, drops: [wool(1, 0, 1, T0 + LAY)] }), [pick(1)], T0 + LAY],
  ['the same wool twice: once only', keeper({ drop_seq: 1, drops: [wool(1, 0, 1, T0 + LAY)] }), [pick(1), pick(1)], T0 + LAY],
  ['picked wool is gone for good', keeper({ drop_seq: 1, bag: { wool: 1 } }), [pick(1)], T0 + LAY],
  ['wool sells at Jasmine\'s for 30', keeper({ bag: { wool: 2 } }), [{ type: 'sell', item: 'wool', count: 2 }], T0],
];

const out = cases.map(([name, farm, commands, now]) => {
  const clean = JSON.parse(JSON.stringify(farm));
  const r = applyFarmCommands(rules, structuredClone(clean), commands, now);
  const expect = r.ok ? { ok: true, buildings: r.state.buildings, drops: r.state.drops, drop_seq: r.state.drop_seq, bag: r.state.bag, energy: r.state.energy,
    coins: r.state.coins, blueprints_claimed: r.state.blueprints_claimed, requests_done: r.state.requests_done }
    : { ok: false, index: r.index, code: r.code, detail: r.detail ?? {} };
  return { name, farm: clean, commands, now, expect };
});
const note = 'C-182 sheep pen: buying its blueprint (15 delivered requests and farm level 3, 1,200 coins; SEN-Q-282), building (15 Timber + 15 Stone), '
  + 'feeding (3 Wild Herbs, 1 Energy), wool on the ground (30 min, at most 4) and selling it (30). Each case runs through server/src/parcels/farm.ts '
  + '(server/test/parcels/farm.test.ts) and modules/dynamic_farm/parcel_farm.gd (tests/dynamic_farm/test_sheep_pen.gd); both must give `expect`. '
  + 'Generated by the server rules: tools/dev/dynamic_farm/sheep_pen_cases.ts.';
writeFileSync(OUT, JSON.stringify({ _note: note, cases: out }, null, 1) + '\n');
console.log(`${out.length} cases → ${OUT}`);
for (const c of out) console.log(c.expect.ok ? 'ok  ' : `${String(c.expect.code).padEnd(18)}`, c.name);
