import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { parseArgs, parseEnv } from 'node:util';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import pg from 'pg';
import { projectBagAggregates } from '../src/domain/bag.js';
import { contentVersion, DEFAULT_CONTENT_DIR, loadContent, type Content } from '../src/domain/content.js';
import { projectFarmState } from '../src/domain/progress.js';
import { DOMAIN_VERSION, STATE_SCHEMA_VERSION } from '../src/domain/version.js';
import type { FarmState } from '../src/domain/state.js';
import { plotFor, loadBlueprint } from '../src/http/app.js';
import { inventoryFixture } from './prepare_inventory_qa.js';

type Scenario = 'materials' | 'full';

/** Artificial developer fixtures, never normal progression rewards. The CLI backs up the complete row. */
export function characterFixture(original: FarmState, content: Content, scenario: Scenario): FarmState {
  const state = inventoryFixture(original, content, scenario);
  const bag = state.bag!;
  bag.equipped.gloves = null;
  state.character = { version: 1, buffs: [] };
  if (scenario === 'materials') {
    const quantities: Record<string, number> = { R: 10, L: 10, C: 6, H: 6,
      wood: 30, stone: 30, fiber: 30, copper_ore: 20, rock_salt: 10, salad: 5, tea: 5, vegetable_soup: 5 };
    for (const stack of bag.slots) if (quantities[stack.item_id]) stack.quantity = quantities[stack.item_id];
  } else {
    const hand = bag.equipped.main_hand!;
    const row = bag.slots.findIndex(stack => stack.item_id === 'row_tool');
    bag.slots[row] = hand;
    const id = bag.next_id++;
    bag.equipped.main_hand = { id: `bag_${id}`, item_id: 'copper_pickaxe', instance_id: `item_${id}`, quantity: 1, quality: 'normal' };
    const soup = content.character.consumables.vegetable_soup;
    state.character.buffs.push({ id: soup.buff_id, source_item_id: 'vegetable_soup', remaining_uses: soup.uses });
  }
  projectBagAggregates(state, content);
  return state;
}

async function main() {
  const { values, positionals } = parseArgs({ options: { device: { type: 'boolean', default: false } }, allowPositionals: true });
  const scenario = positionals[0];
  const database = values.device ? 'sensen_farm_journey_character_device_20260914'
    : 'sensen_farm_journey_character_emulator_20260914';
  const farmId = process.env.FARM_ID;
  if (positionals.length !== 1 || scenario !== 'materials' && scenario !== 'full')
    throw new Error('Usage: FARM_ID=<existing-test-farm-uuid> pnpm exec tsx tools/prepare_character_qa.ts materials|full [--device]');
  if (!farmId || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(farmId))
    throw new Error('FARM_ID must identify an existing ordinary test farm');
  const env = parseEnv(readFileSync(new URL('../.env', import.meta.url), 'utf8'));
  if (!env.TEST_DATABASE_URL) throw new Error('TEST_DATABASE_URL is required in server/.env');
  const address = new URL(env.TEST_DATABASE_URL);
  address.pathname = '/' + database;
  const pool = new pg.Pool({ connectionString: address.toString(), max: 1 });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const found = await client.query('SELECT * FROM farms WHERE id = $1 FOR UPDATE', [farmId]);
    if (!found.rowCount) throw new Error('The specified farm does not exist in the selected isolated character QA database');
    const row = found.rows[0];
    const owner = await client.query('SELECT install_key_hmac FROM players WHERE id = $1', [row.owner_id]);
    if (!owner.rowCount || String(owner.rows[0].install_key_hmac).startsWith('preset:'))
      throw new Error('QA fixtures require an ordinary player farm, not a system visitor');
    if (row.state_schema_version !== STATE_SCHEMA_VERSION || row.domain_version !== DOMAIN_VERSION)
      throw new Error('Create or explicitly migrate the isolated farm under the current domain first');
    const stamp = new Date().toISOString().replaceAll(':', '-');
    const evidence = new URL(values.device ? '../../output/character-device-2026-09-14/fixtures/'
      : '../../output/character-emulator-2026-09-14/fixtures/', import.meta.url);
    mkdirSync(evidence, { recursive: true });
    const backup = new URL(`${stamp}-${scenario}-${farmId}-before.json`, evidence);
    writeFileSync(backup, JSON.stringify({ fixture: scenario, artificial_qa: true, database, before: row }, null, 2),
      { flag: 'wx', mode: 0o600 });
    const content = loadContent(DEFAULT_CONTENT_DIR);
    const state = characterFixture(row.state as FarmState, content, scenario);
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
    const report = { fixture: scenario, artificial_qa: true, database, farm_id: farmId,
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
