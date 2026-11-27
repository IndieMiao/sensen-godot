/**
 * C-175 (0.4.5 run-through): this checkout's dynamic-farm server on memory stores, for an emulator walkthrough on one
 * machine. Nothing is written to disk or sent anywhere: email codes are printed (`QA_MAIL <purpose> <email> <code>`),
 * the stores vanish with the process. Guests are closed and email sign-up is open, as 0.4.5's client expects.
 *
 *   cd server && PORT=3975 GIT_SHA=$(git rev-parse HEAD) pnpm exec tsx tools/dynamicfarm_qa_server.ts
 *
 * Env: PORT (default 3975, on 127.0.0.1 only); GIT_SHA (shown by /v1/healthz); GOOGLE_CLIENT_IDS as in src/index.ts
 * (the OAuth Web client ids Android asks ID tokens for; unset: the same default as the real server, empty: Google
 * sign-in off). Google sign-in also needs this machine to reach Google's public keys. Prints QA_SERVER_READY once
 * listening; stop it with `kill <its PID>`.
 *
 * C-190 (0.4.6 run-through): a test save skips the waits for the requests count and the upgrades' coins. With
 * QA_CONTROL_PORT set, a second listener on 127.0.0.1 takes `POST /qa/test-save` with `{"set": {"<path>": value, …}}`
 * and writes those fields into the farm of the last parcel claimed (`coins`, `level`, `requests_done`, `bag.wood`,
 * `board.done_today`, `board.slots.0.req`, …; null deletes). It bumps the farm version like a command, so close the
 * app first and reopen it to read the new save. Each write prints `QA_TEST_SAVE <path>=<value>` for the record.
 */
import { createServer } from 'node:http';
import path from 'node:path';
import { buildApp, plotFor } from '../src/http/app.js';
import { MemoryStore } from '../src/http/memory_store.js';
import { MemoryParcelStore } from '../src/parcels/store.js';
import { contentVersion, DEFAULT_CONTENT_DIR, loadContent } from '../src/domain/content.js';
import { CityCatalog } from '../src/geography/cities.js';
import { loadParcelRules } from '../src/parcels/rules.js';
import { loadStarterZones } from '../src/parcels/starter_zone.js';
import { googleIdJwksFetcher } from '../src/accounts/google_token.js';
import { CachedJwks } from '../src/accounts/firebase_token.js';
import type { Mailer } from '../src/accounts/mailer.js';

const CONTENT_DIR = DEFAULT_CONTENT_DIR;
const content = loadContent(CONTENT_DIR);
const cv = contentVersion(CONTENT_DIR);
const plot = plotFor(content);
const now = () => Date.now();
const store = new MemoryStore({ content, timezone: 'America/Los_Angeles', plot, now, contentVersion: cv });
/** Remembers who claimed last, for the test save. */
class QaParcelStore extends MemoryParcelStore {
  lastPlayer: string | null = null;
  override async claim(...args: Parameters<MemoryParcelStore['claim']>) {
    const out = await super.claim(...args);
    if (out.kind === 'claimed') this.lastPlayer = args[0];
    return out;
  }
}
const parcels = new QaParcelStore(id => store.displayNameOf(id));
const regionsFile = path.join(CONTENT_DIR, 'regions.json');
const mailer: Mailer = { async sendCode(email, code, purpose) { console.log(`QA_MAIL ${purpose} ${email} ${code}`); } };

function googleConfig() {
  const audiences = (process.env.GOOGLE_CLIENT_IDS ?? '105022638066-s710gs2tsaikbkhbtvstdino7cq661go.apps.googleusercontent.com')
    .split(',').map(v => v.trim()).filter(Boolean);
  if (!audiences.length) return undefined;
  const jwks = new CachedJwks(googleIdJwksFetcher(), now);
  return { audiences, keys: jwks.keys, refreshKeys: jwks.refresh };
}

const app = await buildApp({
  store, content, contentVersion: cv, blueprintDir: path.resolve(CONTENT_DIR, '../../blueprints'), regionsFile,
  pepper: 'dynamicfarm-qa-local', now, plot, gitSha: process.env.GIT_SHA, realtimeEnabled: false,
  cities: CityCatalog.fromRegionsFile(regionsFile), mailer, guestAccountsClosed: true, google: googleConfig(),
  parcels: { store: parcels, rules: loadParcelRules(CONTENT_DIR), reselect: false, starterZones: loadStarterZones(CONTENT_DIR, 'file') },
});
app.addHook('onResponse', async (req, reply) => { console.log(`QA_REQ ${req.method} ${req.url.split('?')[0]} ${reply.statusCode}`); });
await app.listen({ port: Number(process.env.PORT ?? 3975), host: '127.0.0.1' });

async function testSave(set: Record<string, unknown>): Promise<Record<string, unknown>> {
  const player = parcels.lastPlayer;
  const row = player ? await parcels.mine(player) : null;
  if (!player || !row) return { error: 'no parcel claimed yet' };
  const out = await parcels.updateFarm(player, row.farm_version, farm => {
    for (const [key, value] of Object.entries(set)) {
      const keys = key.split('.');
      let at: Record<string, unknown> = farm as unknown as Record<string, unknown>;
      for (const k of keys.slice(0, -1)) at = at[k] as Record<string, unknown>;
      if (value === null) delete at[keys[keys.length - 1]]; else at[keys[keys.length - 1]] = value;
      console.log(`QA_TEST_SAVE ${key}=${JSON.stringify(value)}`);
    }
    return { ok: true, state: farm };
  }, now());
  return out.kind === 'applied' ? { farm_version: out.parcel.farm_version, farm: out.parcel.farm } : { error: out.kind };
}
if (process.env.QA_CONTROL_PORT) {
  createServer((req, res) => {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      const reply = (status: number, value: unknown) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(value)); };
      if (req.method === 'GET' && req.url === '/qa/farm') {
        const player = parcels.lastPlayer;
        void (player ? parcels.mine(player) : Promise.resolve(null)).then(row => reply(row ? 200 : 404, row ?? { error: 'no parcel claimed yet' }));
        return;
      }
      if (req.method !== 'POST' || req.url !== '/qa/test-save') { reply(404, { error: 'not found' }); return; }
      let set: unknown;
      try { set = (JSON.parse(body) as { set?: unknown }).set; } catch { reply(400, { error: 'bad json' }); return; }
      if (!set || typeof set !== 'object') { reply(400, { error: 'set required' }); return; }
      testSave(set as Record<string, unknown>).then(v => reply('error' in v ? 409 : 200, v), (e: unknown) => reply(500, { error: String(e) }));
    });
  }).listen(Number(process.env.QA_CONTROL_PORT), '127.0.0.1');
}
console.log('QA_SERVER_READY');
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.on(signal, () => { void app.close().then(() => process.exit(0)); });
