/** Isolated local PostgreSQL and normal HTTP/WebSocket APIs for device fishing verification. */
import { readFileSync } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import { parseEnv } from 'node:util';
import pg from 'pg';
import { addBagItem, projectBagAggregates } from '../src/domain/bag.js';
import { PgStore } from '../src/db/pg_store.js';
import { migrate } from '../src/db/migrate.js';
import { appFor, seed, content, cv, sets } from '../test/realtime/helpers.js';

const settings = parseEnv(readFileSync(new URL('../.env', import.meta.url), 'utf8'));
if (!settings.TEST_DATABASE_URL) throw new Error('TEST_DATABASE_URL is required');
const address = new URL(settings.TEST_DATABASE_URL);
const database = 'sensen_equipment_playtest_20260919';
const admin = new pg.Pool({ connectionString: address.toString(), max: 1 });
try {
  if (!(await admin.query('SELECT 1 FROM pg_database WHERE datname=$1', [database])).rowCount)
    await admin.query('CREATE DATABASE "sensen_equipment_playtest_20260919"');
} finally { await admin.end(); }
address.pathname = '/' + database;
const pool = new pg.Pool({ connectionString: address.toString(), max: 5 });
await migrate(pool);
const store = new PgStore({ pool, content, contentVersion: cv, timezone: () => 'Asia/Shanghai', plot: sets, now: Date.now });
const account = await seed(store);
const peer = await seed(store);
const state = account.farm.state;
for (const item_id of ['row_tool', 'rusty_sword', 'copper_pickaxe', 'copper_axe', 'copper_knife', 'copper_ring', 'wooden_ring', 'copper_necklace', 'foraging_gloves', 'artisan_apron'])
  addBagItem(state.bag!, { item_id, quantity: 1 }, content, true);
state.journey!.facts.push('workbench');
projectBagAggregates(state, content);
await pool.query('UPDATE farms SET state=$1 WHERE owner_id=$2', [JSON.stringify(state), account.player]);
const directory = new URL(process.env.EQUIPMENT_QA_OUTPUT ?? '../../output/equipment-2026-09-19/private/', import.meta.url);
await mkdir(directory, { recursive: true });
await writeFile(new URL('account.json', directory), JSON.stringify(account), { mode: 0o600 });
await writeFile(new URL('peer.json', directory), JSON.stringify(peer), { mode: 0o600 });
const app = await appFor(store);
await app.listen({ port: 3181, host: '127.0.0.1' });
console.log('EQUIPMENT_QA_READY port=3181 database=' + database);
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.on(signal, () => {
  void app.close().then(() => pool.end()).then(() => process.exit(0));
});
