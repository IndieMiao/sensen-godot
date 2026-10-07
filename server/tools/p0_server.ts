/**
 * P0 local playtest server (no Postgres, no accounts): `node --import tsx tools/p0_server.ts`.
 * Port P0_PORT (default 3110) on 0.0.0.0; state persisted to output/p0/p0-state.json; observation log in
 * output/p0/events/ (P0_EVENT_DIR, empty to turn it off).
 * Android emulator: `adb reverse tcp:3110 tcp:3110`, client base URL http://127.0.0.1:3110/v1.
 */
import Fastify from 'fastify';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadP0Content } from '../src/p0/content.js';
import { registerP0Routes } from '../src/p0/routes.js';
import { P0Store } from '../src/p0/store.js';
import { P0EventLog } from '../src/p0/telemetry.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const dir = path.join(root, 'output/p0');
mkdirSync(dir, { recursive: true });
const content = loadP0Content();
const store = new P0Store(content, process.env.P0_STATE_FILE ?? path.join(dir, 'p0-state.json'));
const app = Fastify({ logger: false });
// S7: observation log, one JSON line per command and reported UI moment (P0_EVENT_DIR; empty = off).
const eventDir = process.env.P0_EVENT_DIR ?? path.join(dir, 'events');
const log = new P0EventLog(eventDir === '' ? undefined : eventDir);
registerP0Routes(app, { content, store, now: Date.now, dev: process.env.P0_DEV !== '0', log });
app.get('/v1/healthz', async () => ({ ok: true, p0: content.version }));
const port = Number(process.env.P0_PORT ?? 3110);
await app.listen({ port, host: process.env.P0_HOST ?? '0.0.0.0' });
console.log(JSON.stringify({ ready: true, port, content: content.version }));
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.on(signal, () => { void app.close().then(() => process.exit(0)); });
