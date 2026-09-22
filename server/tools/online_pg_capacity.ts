import { readFileSync } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import { parseEnv } from 'node:util';
import { isDeepStrictEqual } from 'node:util';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { PgStore } from '../src/db/pg_store.js';
import { migrate } from '../src/db/migrate.js';
import { initialExpedition } from '../src/realtime/model.js';
import { content, cv, seed, sets } from '../test/realtime/helpers.js';

const settings = parseEnv(readFileSync(new URL('../.env', import.meta.url), 'utf8'));
const address = new URL(settings.TEST_DATABASE_URL);
address.pathname = '/sensen_farm_online_test_20260916';
const pool = new pg.Pool({ connectionString: address.toString(), max: 8 });
try {
  await migrate(pool);
  const store = new PgStore({ pool, content, contentVersion: cv, timezone: () => 'Asia/Shanghai', blueprint: () => sets, now: Date.now });
  const accounts: Awaited<ReturnType<typeof seed>>[] = [];
  for (let start = 0; start < 300; start += 6) accounts.push(...await Promise.all(Array.from({ length: 6 }, () => seed(store))));
  const effects = accounts.map(a => ({ player: a.player, loot: { stone: 1, seed_R: 2 } }));
  const mine = initialExpedition(content), key = 'mine:' + randomUUID(), id = randomUUID();
  mine.floors['1'].rocks[0].broken = true;
  const start = performance.now();
  const committed = await store.realtimeCommit(key, 0, id, mine, effects);
  const commitMs = performance.now() - start;
  const repeated = await store.realtimeCommit(key, 0, id, mine, effects);
  if (!isDeepStrictEqual(committed, repeated)) throw new Error('Retry changed the settlement');
  if (committed.farms.length !== 300 || committed.farms.some(f => f.state.journey?.materials?.stone !== 1)) throw new Error('Missing independent loot');
  const report = { recipients: 300, database: 'isolated PostgreSQL on LAN', transaction_ms: commitMs, atomic_replay_equal: true };
  await mkdir('../output/online-2026-09-16', { recursive: true });
  await writeFile('../output/online-2026-09-16/postgres-capacity.json', JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report));
} finally { await pool.end(); }
