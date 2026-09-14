import path from 'node:path';
import { readFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import pg from 'pg';
import { buildApp, blueprintSets, loadBlueprint } from '../src/http/app.js';
import { PgStore } from '../src/db/pg_store.js';
import { migrate } from '../src/db/migrate.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../src/domain/content.js';
import { PRESET_SPECS, buildPresetFarm, presetHmac } from '../src/domain/presets.js';

const env = parseEnv(readFileSync(new URL('../.env', import.meta.url), 'utf8'));
const database = process.env.JOURNEY_DATABASE ?? 'sensen_farm_journey_playtest';
if (!/^sensen_farm_journey_[a-z0-9_]+$/.test(database)) throw new Error('Use an isolated journey playtest database');
const address = new URL(env.TEST_DATABASE_URL);
const admin = new pg.Pool({ connectionString: address.toString(), max: 1 });
try {
  if (!(await admin.query('SELECT 1 FROM pg_database WHERE datname = $1', [database])).rowCount)
    await admin.query(`CREATE DATABASE "${database}"`);
} finally { await admin.end(); }
address.pathname = '/' + database;
const pool = new pg.Pool({ connectionString: address.toString(), max: 5 });
await migrate(pool);
const content = loadContent(DEFAULT_CONTENT_DIR);
const cv = contentVersion(DEFAULT_CONTENT_DIR);
const blueprintDir = path.resolve(DEFAULT_CONTENT_DIR, '../../blueprints');
const regionsFile = path.join(DEFAULT_CONTENT_DIR, 'regions.json');
const regions = JSON.parse(readFileSync(regionsFile, 'utf8')).regions;
const blueprint = (id: string, revision: number) => blueprintSets(loadBlueprint(blueprintDir, id, revision)!);
const timezone = (id: string) => regions.find((r: { id: string }) => r.id === id).timezone as string;
const now = () => Date.now();
const store = new PgStore({ pool, content, contentVersion: cv, timezone, blueprint, now });
for (const spec of PRESET_SPECS) {
  await store.ensureSystemFarm(presetHmac(spec.id ?? spec.layout),
    buildPresetFarm(spec, blueprint(spec.layout, spec.revision), content, timezone(spec.region), now()));
}
const app = await buildApp({ store, content, contentVersion: cv, blueprintDir, regionsFile,
  pepper: env.TOKEN_PEPPER, now, blueprint });
// Device inspection is opt-in and confined to this loopback playtest service.
if (process.env.JOURNEY_DEVICE_INSPECT === '1') {
  let snapshot: unknown = null;
  app.post('/v1/qa/journey/scene', async request => { snapshot = request.body; return { ok: true }; });
  app.get('/v1/qa/journey/scene', async () => snapshot ?? { pending: true });
}
const listening = await app.listen({ host: '127.0.0.1', port: Number(process.env.JOURNEY_PORT ?? 0) });
console.log(JSON.stringify({ listening, database, rules: 'journey-1', natural_clock: true }));
let stopping = false;
async function stop() {
  if (stopping) return;
  stopping = true;
  await app.close();
  await pool.end();
}
process.once('SIGTERM', () => { void stop(); });
process.once('SIGINT', () => { void stop(); });
