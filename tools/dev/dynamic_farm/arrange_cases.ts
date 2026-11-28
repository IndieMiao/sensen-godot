/**
 * C-229: writes tests/dynamic_farm/fixtures/arrange_cases.json, the move and store cases both sides run (server
 * test/parcels/farm.test.ts, client tests/dynamic_farm/test_building_arrange.gd). Each `expect` is what the server rules
 * (assets/farm/data/dynamic_farm.json) give; rerun after changing a building's numbers and review the diff.
 *
 *   cd server && npx tsx ../tools/dev/dynamic_farm/arrange_cases.ts
 */
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { DEFAULT_CONTENT_DIR } from '../../../server/src/domain/content.js';
import { applyFarmCommands, type FarmCommand } from '../../../server/src/parcels/farm.js';
import { loadParcelRules } from '../../../server/src/parcels/rules.js';

const rules = loadParcelRules(DEFAULT_CONTENT_DIR);
const OUT = path.join(DEFAULT_CONTENT_DIR, '..', '..', '..', 'tests', 'dynamic_farm', 'fixtures', 'arrange_cases.json');
const T0 = 1795406400000;
const MIN = 60_000;
type Farm = Record<string, unknown>;

const COTTAGE = { id: 1, type: 'cottage', model: 'cottage', x: 40, y: 40, width: 3, depth: 3, rotation: 0, built_at: T0 - 9000 };
const COOP = { id: 2, type: 'coop', model: 'chicken_yard', x: 20, y: 40, width: 7, depth: 5, rotation: 0, built_at: T0 - 8000,
  animals: ['hen_white', 'hen_brown', 'hen_white'] };
const BARN = { id: 3, type: 'barn', model: 'cow_barn', x: 20, y: 20, width: 11, depth: 6, rotation: 0, built_at: T0 - 7000,
  animals: ['cow', 'cow'], cutouts: [[0, 0, 2, 2]] };
const PEN = { id: 4, type: 'sheep_pen', model: 'sheep_pen', x: 40, y: 20, width: 6, depth: 6, rotation: 0, built_at: T0 - 6000,
  animals: ['sheep', 'sheep', 'sheep', 'sheep'] };
const WELL = { id: 5, type: 'well', model: 'well', x: 50, y: 50, width: 1, depth: 1, rotation: 0, built_at: T0 - 5000 };
const house = { model: 'cottage', x: 40, y: 40, width: 3, depth: 3, rotation: 0, built_at: T0 - 9000 };
const drop = (id: number, item: string, building: number, animal: number, spot: number, ready_at: number) =>
  ({ id, item, amount: 1, building, animal, spot, ready_at });

/** A level-3 yard with all five buildings standing. */
const yard = (change: Farm = {}): Farm => ({
  v: 1, buildings: [COTTAGE, COOP, BARN, PEN, WELL], house, cleared: [], tilled: ['60,60'], crops: { '60,60': { crop: 'crop_carrot',
    planted_at: T0 - 1000, ripe_at: T0 + 59_000, watered_at: T0 - 1000 } }, bag: { hoe_starter: 1, crop_carrot: 4, wood: 2 },
  welcomed_at: T0 - 86_400_000, coins: 50, sales: 1, gathered: {}, blueprints_claimed: {},
  energy: { value: 30, at: T0, rested_on: null }, drops: [], drop_seq: 0, pail_water: 1, grants: {}, level: 3, requests_done: 0,
  ...change,
});
const move = (building: number, x: number, y: number, rotation = 0): FarmCommand => ({ type: 'move_building', building, x, y, rotation });
const store = (building: number): FarmCommand => ({ type: 'store_building', building });
const place = (building: string, x: number, y: number, rotation = 0): FarmCommand => ({ type: 'place_building', building, x, y, rotation });

const eggs = { drops: [drop(1, 'egg', 2, 0, 3, T0 - MIN), drop(2, 'egg', 2, 1, 6, T0 + MIN)], drop_seq: 2 };
const laid = { drops: [drop(1, 'egg', 2, 0, 3, T0 - MIN), drop(2, 'milk', 3, 0, 2, T0 - 2 * MIN), drop(3, 'wool', 4, 1, 5, T0 - 3 * MIN)], drop_seq: 3 };

const cases: [string, Farm, FarmCommand[], number][] = [
  ...[0, 1, 2, 3].map(r => [`the coop moves and turns ${r * 90}°, its hens, eggs and timers with it, nothing spent`, yard(eggs),
    [move(2, 60, 30, r)], T0] as [string, Farm, FarmCommand[], number]),
  ['the cottage moves (D3: it moves, never stores); the house mirror follows', yard(), [move(1, 41, 41, 1)], T0],
  ['its own old cells do not count: the barn shifts one cell over itself', yard(), [move(3, 21, 20, 0)], T0],
  ['the barn turned keeps its cutout; the well then stands in the freed corner', yard(), [move(3, 20, 20, 2), move(5, 30, 21)], T0],
  ['onto another building: refused, nothing changes', yard(), [move(5, 41, 41)], T0],
  ['onto tilled soil and a crop: refused, nothing changes', yard(), [move(1, 58, 58)], T0],
  ['off the grid: refused', yard(), [move(2, 1020, 10)], T0],
  ['no such building: refused', yard(), [move(9, 70, 70)], T0],
  ['moves with 0 Energy', yard({ energy: { value: 0, at: T0, rested_on: null } }), [move(5, 70, 70), move(1, 70, 60, 3)], T0],
  ['storing the sheep pen gives back its blueprint, 15 Timber and 15 Stone; its sheep go with it (D1)', yard(), [store(4)], T0],
  ['storing the barn gives back its blueprint, 20 Timber and 10 Stone (D1)', yard(), [store(3)], T0],
  ['storing the coop and the well gives back their blueprints', yard(), [store(2), store(5)], T0],
  ['laid egg, milk and wool go into the bag when their buildings are stored', yard(laid), [store(2), store(3), store(4)], T0],
  ['an egg on its way: the coop cannot be stored yet (D2), nothing changes', yard(eggs), [store(2)], T0],
  ['the egg laid: stored, both eggs in the bag', yard(eggs), [store(2)], T0 + MIN],
  ['the cottage is never stored (D3)', yard(), [store(1)], T0],
  ['the same building twice in a batch: refused, nothing changes', yard(), [store(5), store(5)], T0],
  ['stored and placed again: the rules\' animals, the materials taken again', yard(), [store(4), place('sheep_pen', 70, 20, 1)], T0],
  ['stored then moved: refused, nothing changes', yard(), [store(2), move(2, 70, 70)], T0],
];

const out = cases.map(([name, farm, commands, now]) => {
  const clean = JSON.parse(JSON.stringify(farm));
  const r = applyFarmCommands(rules, structuredClone(clean), commands, now);
  const expect = r.ok ? { ok: true, buildings: r.state.buildings, house: r.state.house, drops: r.state.drops, drop_seq: r.state.drop_seq, bag: r.state.bag,
    energy: r.state.energy } : { ok: false, index: r.index, code: r.code, detail: r.detail ?? {} };
  return { name, farm: clean, commands, now, expect };
});
const note = 'C-229 moving and storing built buildings (design SEN-C-227 D-555 README §5, owner SEN-Q-344 D1–D3): move_building checks the new spot '
  + 'as place_building does, its own old cells not counting, and keeps animals, drops and timers; store_building gives back the blueprint and the '
  + 'rules\' materials, laid drops into the bag, never the cottage, never while a drop is on its way. Each case runs through server/src/parcels/farm.ts '
  + '(server/test/parcels/farm.test.ts) and modules/dynamic_farm/parcel_farm.gd (tests/dynamic_farm/test_building_arrange.gd); both must give `expect`. '
  + 'Generated by the server rules: tools/dev/dynamic_farm/arrange_cases.ts.';
writeFileSync(OUT, JSON.stringify({ _note: note, cases: out }, null, 1) + '\n');
console.log(`${out.length} cases → ${OUT}`);
for (const c of out) console.log(c.expect.ok ? 'ok  ' : `${String(c.expect.code).padEnd(18)}`, c.name);
