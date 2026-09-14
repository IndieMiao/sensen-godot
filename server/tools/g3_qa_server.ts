/** Loopback-only UI acceptance server. Only the dedicated disposable G3 database is accepted. */
import path from 'node:path';
import { readFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import pg from 'pg';
import { buildApp, blueprintSets, loadBlueprint } from '../src/http/app.js';
import { PgStore } from '../src/db/pg_store.js';
import { migrate } from '../src/db/migrate.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../src/domain/content.js';
import { PRESET_SPECS, buildPresetFarm, presetHmac } from '../src/domain/presets.js';
import { ledgerScript, type Path, type Style } from '../test/fixtures/build_ledger.js';
import { BEDS, RESERVED } from '../test/domain/helpers.js';
import { registerG3TouchQueue } from './g3_touch_queue.js';

const env = parseEnv(readFileSync(new URL('../.env', import.meta.url), 'utf8'));
const dsn = new URL(env.TEST_DATABASE_URL);
dsn.pathname = '/sensen_farm_g3_ui_qa';
const pool = new pg.Pool({ connectionString: dsn.toString(), max: 5 });
await migrate(pool);
const content = loadContent(DEFAULT_CONTENT_DIR);
const cv = contentVersion(DEFAULT_CONTENT_DIR);
const blueprintDir = path.resolve(DEFAULT_CONTENT_DIR, '../../blueprints');
const regions = JSON.parse(readFileSync(path.join(DEFAULT_CONTENT_DIR, 'regions.json'), 'utf8')).regions;
const setsFor = (id: string, revision: number) => blueprintSets(loadBlueprint(blueprintDir, id, revision)!);
const zone = (id: string) => regions.find((r: {id: string}) => r.id === id).timezone as string;
const now = () => Date.now();
const store = new PgStore({ pool, content, contentVersion: cv, timezone: zone, blueprint: setsFor, now });
for (const spec of PRESET_SPECS) {
  await store.ensureSystemFarm(presetHmac(spec.id ?? spec.layout),
    buildPresetFarm(spec, setsFor(spec.layout, spec.revision), content, zone(spec.region), now()));
}
const qaPlayerIds = new Set<string>();
const app = await buildApp({ store, content, contentVersion: cv, blueprintDir,
  regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: env.TOKEN_PEPPER,
  now, blueprint: setsFor, qaPlayerIds });
app.addHook('onSend', async (request, _reply, payload) => {
  if (request.url === '/v1/auth/anonymous' && typeof payload === 'string') {
    const body = JSON.parse(payload);
    if (typeof body.player_id === 'string') qaPlayerIds.add(body.player_id);
  }
  return payload;
});
app.get('/v1/qa/ledger', async request => {
  const query = request.query as {path?: string; style?: string};
  const route: Path = query.path === 'field' ? 'field' : 'tool';
  const style: Style = query.style === 'sell' ? 'sell' : 'life';
  return { path: route, style, beds: BEDS, reserved: RESERVED, steps: ledgerScript(route, style) };
});
await registerG3TouchQueue(app);
const port = Number(process.env.G3_QA_PORT ?? 3103);
await app.listen({ host: '127.0.0.1', port });
console.log(JSON.stringify({ listening: `http://127.0.0.1:${port}`, database: 'sensen_farm_g3_ui_qa', content: cv }));
async function stop() { await app.close(); await pool.end(); }
process.once('SIGTERM', () => { void stop(); });
process.once('SIGINT', () => { void stop(); });
