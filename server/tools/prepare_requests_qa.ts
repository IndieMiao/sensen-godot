import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import pg from 'pg';
import { projectBagAggregates } from '../src/domain/bag.js';
import { contentVersion, DEFAULT_CONTENT_DIR, loadContent, type Content } from '../src/domain/content.js';
import { projectFarmState } from '../src/domain/progress.js';
import { DOMAIN_VERSION, STATE_SCHEMA_VERSION } from '../src/domain/version.js';
import type { FarmState } from '../src/domain/state.js';
import { plotFor, loadBlueprint } from '../src/http/app.js';
import { characterFixture } from './prepare_character_qa.js';

type Scenario = 'materials' | 'shortage';
const DATABASE = 'sensen_farm_journey_requests_emulator_20260914';

/** Artificial developer supplies; ownership and prior receipts remain explicit in the backup. */
export function requestsFixture(original: FarmState, content: Content, scenario: Scenario): FarmState {
  const state = characterFixture(original, content, 'materials');
  const journey = state.journey!;
  const variants: Record<string, number> = { nursery: 0, bistro: 2, restorer: scenario === 'shortage' ? 3 : 2 };
  for (const [slot, progress] of Object.entries(journey.opportunities)) {
    progress.sequence += 1;
    progress.variant = variants[slot];
    progress.accepted = false;
  }
  delete journey.tracked_opportunity;
  delete journey.tracked_project;
  delete journey.tracked_discovery;
  if (journey.gathering) delete journey.gathering.planned;
  if (journey.workshop?.planned) {
    delete journey.workshop.planned;
    journey.workshop.sequence += 1;
  }
  if (scenario === 'shortage') state.bag!.slots = state.bag!.slots.filter(stack =>
    !['crate', 'vegetable_soup', 'copper_ore', 'rock_salt'].includes(stack.item_id));
  projectBagAggregates(state, content);
  return state;
}

async function main() {
  const scenario = process.argv[2];
  const farmId = process.env.FARM_ID;
  if (process.argv.length !== 3 || scenario !== 'materials' && scenario !== 'shortage')
    throw new Error('Usage: FARM_ID=<existing-test-farm-uuid> pnpm exec tsx tools/prepare_requests_qa.ts materials|shortage');
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
    if (!found.rowCount) throw new Error('The specified farm does not exist in the isolated requests emulator database');
    const row = found.rows[0];
    const owner = await client.query('SELECT install_key_hmac FROM players WHERE id = $1', [row.owner_id]);
    if (!owner.rowCount || String(owner.rows[0].install_key_hmac).startsWith('preset:'))
      throw new Error('QA fixtures require an ordinary player farm, not a system visitor');
    if (row.state_schema_version !== STATE_SCHEMA_VERSION || row.domain_version !== DOMAIN_VERSION)
      throw new Error('Create or explicitly migrate the isolated farm under the current domain first');
    const stamp = new Date().toISOString().replaceAll(':', '-');
    const evidence = new URL('../../output/requests-emulator-2026-09-14/fixtures/', import.meta.url);
    mkdirSync(evidence, { recursive: true });
    const backup = new URL(`${stamp}-${scenario}-${farmId}-before.json`, evidence);
    writeFileSync(backup, JSON.stringify({ fixture: scenario, artificial_qa: true, database: DATABASE, before: row }, null, 2),
      { flag: 'wx', mode: 0o600 });
    const content = loadContent(DEFAULT_CONTENT_DIR);
    const state = requestsFixture(row.state as FarmState, content, scenario);
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
      version: updated.rows[0].version, bag_slots: projected.bag!.slots.length,
      requests: Object.fromEntries(Object.entries(projected.journey!.opportunities).map(([slot, request]) => [slot,
        { sequence: request.sequence, accepted: request.accepted,
          offer_id: content.journey.opportunities[slot][request.variant].id }])), backup: fileURLToPath(backup) };
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
