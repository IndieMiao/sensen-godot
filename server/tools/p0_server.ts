/**
 * P0 server (no Postgres, no accounts): `node --import tsx tools/p0_server.ts`. Local playtests by default; the
 * deployed image (server/deploy/p0) runs the same file with P0_DEV=0 and P0_ACCESS_KEYS (SGODOT-232 D1).
 * Port P0_PORT (default 3110) on P0_HOST (default 0.0.0.0); state persisted to P0_STATE_FILE (default output/p0/p0-state.json).
 * Android emulator: `adb reverse tcp:3110 tcp:3110`, client base URL http://127.0.0.1:3110/v1.
 */
import Fastify from 'fastify';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadP0Content } from '../src/p0/content.js';
import { registerP0Routes } from '../src/p0/routes.js';
import { P0Store } from '../src/p0/store.js';
import { guardOptionsFromEnv, registerP0Guard, snapshotState } from '../src/p0/guard.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const stateFile = process.env.P0_STATE_FILE ?? path.join(root, 'output/p0/p0-state.json');
mkdirSync(path.dirname(stateFile), { recursive: true });   // only the save's own folder (the image's /repo is read-only to it)
const content = loadP0Content();
const store = new P0Store(content, stateFile);
// SGODOT-232 D1: a 32 KB body limit, the demo key and request limits (P0_ACCESS_KEYS, P0_RATE_PER_MINUTE) and hourly
// save snapshots (P0_SNAPSHOT_DIR, 48 kept). A deployed server runs with P0_DEV=0 so no dev route is registered.
const app = Fastify({ logger: false, bodyLimit: 32 * 1024 });
const guard = guardOptionsFromEnv();
await registerP0Guard(app, guard);
const dev = process.env.P0_DEV !== '0';
registerP0Routes(app, { content, store, now: Date.now, dev });
const startedAt = Date.now();
app.get('/v1/healthz', async () => ({ ok: true, p0: content.version, players: store.size(), up_s: Math.round((Date.now() - startedAt) / 1000) }));
const snapshots = process.env.P0_SNAPSHOT_DIR ?? path.join(path.dirname(stateFile), 'snapshots');
setInterval(() => snapshotState(stateFile, snapshots, 48), 3_600_000).unref();
const port = Number(process.env.P0_PORT ?? 3110);
await app.listen({ port, host: process.env.P0_HOST ?? '0.0.0.0' });
console.log(JSON.stringify({ ready: true, port, content: content.version, dev, key: guard.keys.length > 0 }));
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.on(signal, () => { void app.close().then(() => process.exit(0)); });
