import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import pg from 'pg';
import { ensureBag, projectBagAggregates } from '../src/domain/bag.js';
import { contentVersion, DEFAULT_CONTENT_DIR, loadContent, type Content } from '../src/domain/content.js';
import { reconcileJourney, startJourney } from '../src/domain/journey.js';
import { projectFarmState } from '../src/domain/progress.js';
import { DOMAIN_VERSION, STATE_SCHEMA_VERSION } from '../src/domain/version.js';
import type { BagStack, FarmState } from '../src/domain/state.js';
import { plotFor, loadBlueprint } from '../src/http/app.js';

type Scenario = 'materials' | 'full';
const DATABASE = 'sensen_farm_journey_inventory_emulator_20260914';

/** Deliberately artificial QA inventory; the CLI backs up the old row before replacing it. */
export function inventoryFixture(original: FarmState, content: Content, scenario: Scenario): FarmState {
  let next = startJourney(structuredClone(original), content);
  ensureBag(next, content);
  next.journey!.facts = [...new Set([...next.journey!.facts, 'workbench', 'met_bistro', 'planter_crafted',
    'shared_meal', 'crafted_lantern', 'project_waystation_0', 'project_waystation_1'])];
  next.journey!.unlocks = [...new Set([...next.journey!.unlocks, 'bistro', 'kitchen', 'crop_C', 'crop_H',
    'crafting', 'tea', 'growth', 'decorations'])];
  next = reconcileJourney(next, content);
  const bag = next.bag!;
  bag.sequence += 1;
  bag.capacity = content.items.capacity;
  bag.slots = [];
  bag.overflow = [];
  bag.equipped.main_hand = null;
  const create = (item_id: string, quantity: number, seed_lot?: 'bound' | 'bought'): BagStack => {
    const id = bag.next_id++;
    return { id: `bag_${id}`, item_id, quantity, quality: 'normal', ...(seed_lot ? { seed_lot } : {}),
      ...(content.items.items[item_id].max_stack === 1 ? { instance_id: `item_${id}` } : {}) };
  };
  bag.equipped.main_hand = create('hand_tools', 1);
  const add = (item_id: string, quantity: number, seed_lot?: 'bound' | 'bought') => {
    if (quantity < 1 || quantity > content.items.items[item_id].max_stack) throw new Error('Invalid QA fixture stack');
    bag.slots.push(create(item_id, quantity, seed_lot));
  };
  if (scenario === 'materials') {
    add('seed_R', 6, 'bound');
    add('seed_L', 3, 'bound');
    add('seed_C', 2, 'bought');
    add('seed_H', 2, 'bought');
    for (const [id, quantity] of Object.entries({ R: 3, L: 3, C: 2, H: 1, wood: 8, stone: 8, fiber: 4,
      copper_ore: 6, rock_salt: 3, salad: 1, tea: 1, vegetable_soup: 1, planter: 1, crate: 1, row_tool: 1 }))
      add(id, quantity);
  } else {
    // Stone has no room, so every rock fails. After discarding the first copper stack, the stone
    // fits the free slot and either bonus mineral fits an existing stack, independent of the drop roll.
    add('copper_ore', 99);
    add('copper_ore', 95);
    add('rock_salt', 95);
    for (let i = 0; i < content.items.capacity - 4; i++) add('stone', 99);
    add('row_tool', 1);
  }
  if (bag.slots.length > bag.capacity) throw new Error('QA fixture exceeds bag capacity');
  next.engineering.reserved = {};
  next.mine = { version: 1, run: (next.mine?.run ?? -1) + 1, floor: 0, deepest_floor: 1,
    broken: {}, cleared_floors: [], elevator_unlocked: next.mine?.elevator_unlocked ?? false };
  projectBagAggregates(next, content);
  return next;
}

async function main() {
  const scenario = process.argv[2];
  const farmId = process.env.FARM_ID;
  if (process.argv.length !== 3 || scenario !== 'materials' && scenario !== 'full')
    throw new Error('Usage: FARM_ID=<existing-test-farm-uuid> pnpm exec tsx tools/prepare_inventory_qa.ts materials|full');
  if (!farmId || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(farmId))
    throw new Error('FARM_ID must identify an existing ordinary test farm');
  const env = parseEnv(readFileSync(new URL('../.env', import.meta.url), 'utf8'));
  if (!env.TEST_DATABASE_URL) throw new Error('TEST_DATABASE_URL is required in server/.env');
  const address = new URL(env.TEST_DATABASE_URL);
  address.pathname = '/' + DATABASE;
  const pool = new pg.Pool({ connectionString: address.toString(), max: 1 });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const found = await client.query('SELECT * FROM farms WHERE id = $1 FOR UPDATE', [farmId]);
    if (!found.rowCount) throw new Error('The specified farm does not exist in the isolated emulator database');
    const row = found.rows[0];
    const owner = await client.query('SELECT install_key_hmac FROM players WHERE id = $1', [row.owner_id]);
    if (!owner.rowCount || String(owner.rows[0].install_key_hmac).startsWith('preset:'))
      throw new Error('QA fixtures require an ordinary player farm, not a system visitor');
    if (row.state_schema_version !== STATE_SCHEMA_VERSION || row.domain_version !== DOMAIN_VERSION)
      throw new Error('Start with an ordinary farm created or explicitly migrated under the current domain');
    const stamp = new Date().toISOString().replaceAll(':', '-');
    const evidence = new URL('../../output/inventory-emulator-2026-09-14/fixtures/', import.meta.url);
    mkdirSync(evidence, { recursive: true });
    const backup = new URL(`${stamp}-${scenario}-${farmId}-before.json`, evidence);
    writeFileSync(backup, JSON.stringify({ fixture: scenario, artificial_qa: true, database: DATABASE, before: row }, null, 2),
      { flag: 'wx', mode: 0o600 });
    const content = loadContent(DEFAULT_CONTENT_DIR);
    const state = inventoryFixture(row.state as FarmState, content, scenario);
    const regions = JSON.parse(readFileSync(path.join(DEFAULT_CONTENT_DIR, 'regions.json'), 'utf8')).regions;
    const region = regions.find((region: { id: string }) => region.id === row.region_id);
    if (!region) throw new Error('Unknown QA farm region');
    const layout = loadBlueprint(path.resolve(DEFAULT_CONTENT_DIR, '../../blueprints'), row.layout_patch_id, row.blueprint_revision);
    if (!layout) throw new Error('Unknown QA farm blueprint');
    const now = Math.max(Date.now(), state.clock.last_effective_now);
    const projected = projectFarmState(state, now, region.timezone, content, plotFor(content));
    projected.clock.last_effective_now = now;
    const updated = await client.query(`UPDATE farms SET state = $2, version = version + 1,
      content_version = $3, updated_at = $4 WHERE id = $1 RETURNING version`,
    [farmId, JSON.stringify(projected), contentVersion(DEFAULT_CONTENT_DIR), now]);
    await client.query('COMMIT');
    const report = { fixture: scenario, artificial_qa: true, database: DATABASE, farm_id: farmId,
      version: updated.rows[0].version, bag_slots: projected.bag!.slots.length, bag_capacity: projected.bag!.capacity,
      bag_overflow: projected.bag!.overflow.length, mine_run: projected.mine!.run,
      discard_stack_id: scenario === 'full' ? projected.bag!.slots[0].id : null, backup: fileURLToPath(backup) };
    writeFileSync(new URL(`${stamp}-${scenario}-${farmId}-after.json`, evidence), JSON.stringify({ ...report, state: projected }, null, 2),
      { flag: 'wx', mode: 0o600 });
    console.log(JSON.stringify(report));
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error instanceof Error ? error.message : String(error)); process.exitCode = 1; });
}
