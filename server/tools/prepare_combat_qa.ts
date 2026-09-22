import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import pg from 'pg';
import { addBagItem, projectBagAggregates } from '../src/domain/bag.js';
import { contentVersion, DEFAULT_CONTENT_DIR, loadContent } from '../src/domain/content.js';
import type { FarmState } from '../src/domain/state.js';
import { DOMAIN_VERSION } from '../src/domain/version.js';

const database = 'sensen_farm_journey_combat_emulator_20260915';
const scenario = process.argv[2];
if (!['materials', 'full', 'restore'].includes(scenario)) throw new Error('Use materials, full or restore');
const env = parseEnv(readFileSync(new URL('../.env', import.meta.url), 'utf8'));
const address = new URL(env.TEST_DATABASE_URL);
address.pathname = '/' + database;
const pool = new pg.Pool({ connectionString: address.toString(), max: 1 });
const client = await pool.connect();
const directory = new URL('../../output/combat-emulator-2026-09-15/fixtures/', import.meta.url);
mkdirSync(directory, { recursive: true });
try {
  await client.query('BEGIN');
  const rows = await client.query(`SELECT f.* FROM farms f JOIN players p ON p.id = f.owner_id
    WHERE p.install_key_hmac NOT LIKE 'preset:%' FOR UPDATE OF f`);
  if (rows.rowCount !== 1) throw new Error('This fixture requires exactly one ordinary farm in the isolated combat database');
  const row = rows.rows[0];
  const content = loadContent(DEFAULT_CONTENT_DIR);
  if (row.domain_version !== DOMAIN_VERSION || row.content_version !== contentVersion(DEFAULT_CONTENT_DIR))
    throw new Error('The isolated farm must use current combat content');
  const stamp = new Date().toISOString().replaceAll(':', '-');
  writeFileSync(new URL(`${stamp}-${scenario}-before.json`, directory), JSON.stringify({ database, artificial_qa: true, before: row }, null, 2), { flag: 'wx', mode: 0o600 });
  const state = structuredClone(row.state) as FarmState;
  const bag = state.bag!;
  if (scenario === 'materials') {
    if (!state.journey!.facts.includes('workbench')) state.journey!.facts.push('workbench');
    for (const [id, quantity] of Object.entries({ wood: 12, fiber: 12, copper_ore: 12, salad: 3, tea: 3, vegetable_soup: 3 }))
      addBagItem(bag, { item_id: id, quantity }, content, true);
  } else if (scenario === 'full') {
    for (const stack of bag.slots) {
      const item = content.items.items[stack.item_id];
      if (item.source.kind === 'material') stack.quantity = item.max_stack;
    }
    while (bag.slots.length < bag.capacity) {
      const id = bag.next_id++;
      bag.slots.push({ id: `bag_${id}`, item_id: 'seed_R', quality: 'normal', quantity: 99, seed_lot: 'bound' });
    }
  } else {
    const backup = readdirSync(directory).filter(name => name.endsWith('-full-before.json')).sort().at(-1);
    if (!backup) throw new Error('No full-bag fixture backup exists');
    const saved = JSON.parse(readFileSync(new URL(backup, directory), 'utf8'));
    if (saved.before.id !== row.id) throw new Error('Backup belongs to another farm');
    state.bag = structuredClone(saved.before.state.bag);
    state.bag!.next_id = Math.max(bag.next_id, state.bag!.next_id);
    state.bag!.sequence = bag.sequence;
    for (const [id, quantity] of Object.entries(state.mine?.combat?.last_result?.materials ?? {}))
      addBagItem(state.bag!, { item_id: id, quantity: quantity! }, content, true);
  }
  state.bag!.sequence += 1;
  projectBagAggregates(state, content);
  const updated = await client.query('UPDATE farms SET state = $1, version = version + 1 WHERE id = $2 RETURNING version', [state, row.id]);
  await client.query('COMMIT');
  const result = { scenario, artificial_qa: true, farm_id: row.id, version: updated.rows[0].version, state };
  writeFileSync(new URL(`${stamp}-${scenario}-after.json`, directory), JSON.stringify(result, null, 2), { mode: 0o600 });
  console.log(JSON.stringify({ scenario, artificial_qa: true, farm_id: row.id, version: result.version }));
} catch (error) {
  await client.query('ROLLBACK');
  throw error;
} finally {
  client.release();
  await pool.end();
}
