/**
 * P0 server (no Postgres, no accounts): `node --import tsx tools/p0_server.ts`. Local playtests by default; the
 * deployed image (server/deploy/p0) runs the same file with P0_DEV=0 and P0_ACCESS_KEYS (SGODOT-232 D1).
 * Port P0_PORT (default 3110) on P0_HOST (default 0.0.0.0); state persisted to P0_STATE_FILE (default output/p0/p0-state.json);
 * observation log beside it in events/ (P0_EVENT_DIR, empty to turn it off).
 * Android emulator: `adb reverse tcp:3110 tcp:3110`, client base URL http://127.0.0.1:3110/v1.
 * Outpost rooms on the same port: ws://…/v1/p0/online (x-p0-player header), GET /v1/p0/presence.
 */
import Fastify from 'fastify';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadP0Content } from '../src/p0/content.js';
import { registerP0Online } from '../src/p0/online/hub.js';
import { generatedOutpostSpec, loadOutposts } from '../src/p0/online/outposts.js';
import { roomPlace } from '../src/p0/world.js';
import { OutpostRooms } from '../src/p0/online/rooms.js';
import { registerP0Routes } from '../src/p0/routes.js';
import { P0Store } from '../src/p0/store.js';
import { SAVE_VERSION } from '../src/p0/state.js';
import { requirePass } from '../src/p0/travel.js';
import { AppearanceCatalog } from '../src/p0/online/appearance.js';
import { guardOptionsFromEnv, registerP0Guard, snapshotState, trustProxyFromEnv } from '../src/p0/guard.js';
import { openIpNear, type IpNear } from '../src/p0/ip_city.js';
import { registerP0Admin } from '../src/p0/admin.js';
import { P0Gate } from '../src/p0/gate.js';
import { P0EventLog } from '../src/p0/telemetry.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const stateFile = process.env.P0_STATE_FILE ?? path.join(root, 'output/p0/p0-state.json');
mkdirSync(path.dirname(stateFile), { recursive: true });   // only the save's own folder (the image's /repo is read-only to it)
const content = loadP0Content();
const store = new P0Store(content, stateFile);
if (store.migrated) console.log(JSON.stringify({ migrated: store.migrated, to: SAVE_VERSION, kept: `${stateFile}.v<old>.bak` }));
// SGODOT-232 D1: a 32 KB body limit, the demo key and request limits (P0_ACCESS_KEYS, P0_RATE_PER_MINUTE, P0_RATE_PER_IP;
// P0_TRUST_PROXY=1 behind Caddy) and hourly save snapshots (P0_SNAPSHOT_DIR, 48 kept). A deployed server runs with
// P0_DEV=0 so no dev route is registered.
const app = Fastify({ logger: false, bodyLimit: 32 * 1024, ...trustProxyFromEnv() });
const guard = guardOptionsFromEnv();
// SYS-UPDATE / SYS-MAINT (gate.ts): P0_MIN_VERSION / P0_UPDATE_URL / P0_MAINT / P0_MAINT_UNTIL, changed at run time by
// the admin routes and kept in the save's folder (the data volume), so a restart keeps maintenance on.
const gate = new P0Gate(path.join(path.dirname(stateFile), 'gate.json'));
if (gate.loadError) console.log(JSON.stringify({ warn: 'gate_json_unreadable', error: gate.loadError }));
{
  const g = gate.state();
  // A minimum without a download url is not enforced (gate.ts): say so loudly at start rather than strand players.
  if (g.min_version > 0 && !g.update_on) console.log(JSON.stringify({ warn: 'min_version_without_update_url', min_version: g.min_version }));
}
await registerP0Guard(app, guard, gate);
const dev = process.env.P0_DEV !== '0';
// S7: observation log, one JSON line per command and reported UI moment (P0_EVENT_DIR; empty = off).
const eventDir = process.env.P0_EVENT_DIR ?? path.join(path.dirname(stateFile), 'events');
const log = new P0EventLog(eventDir === '' ? undefined : eventDir);
// Outpost rooms (SGODOT-227): WebSocket /v1/p0/online and GET /v1/p0/presence, in memory only. The same rooms
// give the Tea Host's "N online" in the state view (SGODOT-228).
// Generated outposts (SGODOT-280) get a room on first join, sized and walled like the room their art stands in for.
const outpostTable = loadOutposts();
const generatedRoom = generatedOutpostSpec(outpostTable, id => roomPlace(content, id));
const rooms = new OutpostRooms(outpostTable, Date.now, generatedRoom);
// q(188) ① `Near you`: the address table made from DB-IP City Lite at image build (tools/ip_near_table.ts); none, no guess.
let ipNear: IpNear | undefined;
if (process.env.P0_IP_NEAR_TABLE) {
  try { ipNear = openIpNear(process.env.P0_IP_NEAR_TABLE); }
  catch (e) { console.error(JSON.stringify({ ip_near: 'unavailable', error: String((e as Error).message ?? e).slice(0, 200) })); }
}
registerP0Routes(app, { content, store, now: Date.now, dev, log, rooms, ipNear });
// The WebSocket upgrade checks the guard's demo keys itself: the guard's onRequest hook does not see it (SGODOT-232 D1).
// v5: joining an outpost room needs a pass for its city, as entering it does (requirePass; the entered outpost passes).
const pass = (player: string, outpost: string) => {
  const s = store.peek(player);
  if (!s) return null;
  const r = requirePass(content, s, 'outpost', outpost, Date.now() + s.clock_ms, s.presence.entered === outpost ? 'rejoin' : undefined);
  return r ? r.code.toUpperCase() : null;
};
registerP0Online(app, { rooms, keys: guard.keys, gate, pass, appearances: new AppearanceCatalog(path.join(root, 'assets/avatar')) });
const startedAt = Date.now();
app.get('/v1/healthz', async () => {
  const g = gate.state();
  return { ok: true, p0: content.version, players: store.size(), up_s: Math.round((Date.now() - startedAt) / 1000),
    maintenance: g.maintenance, min_version: g.update_on ? g.min_version : 0 };
});
const snapshots = process.env.P0_SNAPSHOT_DIR ?? path.join(path.dirname(stateFile), 'snapshots');
setInterval(() => snapshotState(stateFile, snapshots, 48), 3_600_000).unref();
const port = Number(process.env.P0_PORT ?? 3110);
await app.listen({ port, host: process.env.P0_HOST ?? '0.0.0.0' });
console.log(JSON.stringify({ ready: true, port, content: content.version, dev, key: guard.keys.length > 0, admin: !!process.env.P0_ADMIN_KEY && Number(process.env.P0_ADMIN_PORT ?? 0) > 0, ip_near: !!ipNear }));
// SGODOT-150 observer tools (q(53)): admin routes on 127.0.0.1 inside the container only, with their own key.
const adminPort = Number(process.env.P0_ADMIN_PORT ?? 0);
const admin = adminPort && process.env.P0_ADMIN_KEY ? Fastify({ logger: false, bodyLimit: 4 * 1024 }) : null;
if (admin) {
  registerP0Admin(admin, { content, store, now: Date.now, key: process.env.P0_ADMIN_KEY!, gate });
  await admin.listen({ port: adminPort, host: '127.0.0.1' });
}
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.on(signal, () => { void Promise.all([app.close(), admin?.close()]).then(() => process.exit(0)); });
