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
 */
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
const parcels = new MemoryParcelStore(id => store.displayNameOf(id));
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
console.log('QA_SERVER_READY');
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.on(signal, () => { void app.close().then(() => process.exit(0)); });
