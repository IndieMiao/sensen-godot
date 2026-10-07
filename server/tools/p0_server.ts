/**
 * P0 local playtest server (no Postgres, no accounts): `node --import tsx tools/p0_server.ts`.
 * Port P0_PORT (default 3110) on 0.0.0.0; state persisted to output/p0/p0-state.json.
 * Android emulator: `adb reverse tcp:3110 tcp:3110`, client base URL http://127.0.0.1:3110/v1.
 * Outpost rooms on the same port: ws://…/v1/p0/online (x-p0-player header), GET /v1/p0/presence.
 */
import Fastify from 'fastify';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadP0Content } from '../src/p0/content.js';
import { registerP0Online } from '../src/p0/online/hub.js';
import { loadOutposts } from '../src/p0/online/outposts.js';
import { OutpostRooms } from '../src/p0/online/rooms.js';
import { registerP0Routes } from '../src/p0/routes.js';
import { P0Store } from '../src/p0/store.js';
import { AppearanceCatalog } from '../src/realtime/appearance.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const dir = path.join(root, 'output/p0');
mkdirSync(dir, { recursive: true });
const content = loadP0Content();
const store = new P0Store(content, process.env.P0_STATE_FILE ?? path.join(dir, 'p0-state.json'));
const app = Fastify({ logger: false });
// Outpost rooms (SGODOT-227): WebSocket /v1/p0/online and GET /v1/p0/presence, in memory only. The same rooms
// give the Tea Host's "N online" in the state view (SGODOT-228).
const rooms = new OutpostRooms(loadOutposts());
registerP0Routes(app, { content, store, now: Date.now, dev: process.env.P0_DEV !== '0', presence: () => rooms.total() });
registerP0Online(app, { rooms, appearances: new AppearanceCatalog(path.join(root, 'assets/farm/data/regions.json')) });
app.get('/v1/healthz', async () => ({ ok: true, p0: content.version }));
const port = Number(process.env.P0_PORT ?? 3110);
await app.listen({ port, host: process.env.P0_HOST ?? '0.0.0.0' });
console.log(JSON.stringify({ ready: true, port, content: content.version }));
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.on(signal, () => { void app.close().then(() => process.exit(0)); });
