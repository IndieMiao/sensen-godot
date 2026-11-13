/**
 * P0 server (no Postgres; accounts in accounts.json beside the save, SGODOT-488): `node --import tsx tools/p0_server.ts`. Local playtests by default; the
 * deployed image (server/deploy/p0) runs the same file with P0_DEV=0 and P0_ACCESS_KEYS (SGODOT-232 D1).
 * Port P0_PORT (default 3110) on P0_HOST (default 0.0.0.0); state persisted to P0_STATE_FILE (default output/p0/p0-state.json);
 * observation log beside it in events/ (P0_EVENT_DIR, empty to turn it off).
 * Android emulator: `adb reverse tcp:3110 tcp:3110`, client base URL http://127.0.0.1:3110/v1.
 * Outpost rooms on the same port: ws://…/v1/p0/online (x-p0-player header), GET /v1/p0/presence.
 */
import { accountsConfig } from '../src/p0/accounts/config.js';
import { identify } from '../src/p0/accounts/identify.js';
import { registerAccountRoutes } from '../src/p0/accounts/routes.js';
import { P0Accounts } from '../src/p0/accounts/store.js';
import Fastify from 'fastify';
import { mkdirSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadP0Content } from '../src/p0/content.js';
import { registerP0Online } from '../src/p0/online/hub.js';
import { P0Voice, p0VoiceFromEnv, registerP0Voice } from '../src/p0/online/voice.js';
import { generatedOutpostSpec, landmarkOfRoom, landmarkRoomSpec, loadOutposts, pondOfRoom, pondRoomSpec } from '../src/p0/online/outposts.js';
import { placeOf, roomPlace } from '../src/p0/world.js';
import { OutpostRooms } from '../src/p0/online/rooms.js';
import { registerP0Routes } from '../src/p0/routes.js';
import { registerP0LineSwitch } from '../src/p0/line_switch.js';
import { P0Store } from '../src/p0/store.js';
import { SAVE_VERSION } from '../src/p0/state.js';
import { requirePass } from '../src/p0/travel.js';
import { AppearanceCatalog } from '../src/p0/online/appearance.js';
import { guardOptionsFromEnv, registerP0Guard, snapshotState, trustProxyFromEnv } from '../src/p0/guard.js';
import { openIpNear, type IpNear } from '../src/p0/ip_city.js';
import { registerP0Admin } from '../src/p0/admin.js';
import { P0Gate } from '../src/p0/gate.js';
import { devSitesFromEnv, setDevSites } from '../src/p0/mine.js';
import { P0EventLog } from '../src/p0/telemetry.js';
import { bjTableFromEnv, bjTableOn, setBlackjackSecret, setBlackjackTable } from '../src/p0/blackjack.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const stateFile = process.env.P0_STATE_FILE ?? path.join(root, 'output/p0/p0-state.json');
mkdirSync(path.dirname(stateFile), { recursive: true });   // only the save's own folder (the image's /repo is read-only to it)
const content = loadP0Content();
const store = new P0Store(content, stateFile);
if (store.migrated) console.log(JSON.stringify({ cleared: store.migrated, to: SAVE_VERSION, kept: `${stateFile}.v<old>.bak` }));   // v7 (355) clears older saves
// SGODOT-232 D1: a 32 KB body limit, the demo key and request limits (P0_ACCESS_KEYS, P0_RATE_PER_MINUTE, P0_RATE_PER_IP;
// P0_TRUST_PROXY=1 behind Caddy) and hourly save snapshots (P0_SNAPSHOT_DIR, 48 kept). A deployed server runs with
// P0_DEV=0 so no dev route is registered.
const app = Fastify({ logger: false, bodyLimit: 32 * 1024, ...trustProxyFromEnv() });
registerP0LineSwitch(app);   // 421: P0_LINE=close sends every client back to a request each (P0Line)
const guard = guardOptionsFromEnv();
// SYS-UPDATE / SYS-MAINT (gate.ts): P0_MIN_VERSION / P0_UPDATE_URL / P0_MAINT / P0_MAINT_UNTIL, changed at run time by
// the admin routes and kept in the save's folder (the data volume), so a restart keeps maintenance on.
const gate = new P0Gate(path.join(path.dirname(stateFile), 'gate.json'));
if (gate.loadError) console.log(JSON.stringify({ warn: 'gate_json_unreadable', error: gate.loadError }));
{
  const g = gate.state();
  // A minimum without a download url is not enforced (gate.ts): say so loudly at start rather than strand players.
  if (g.min_version > 0 && !g.update_on) console.log(JSON.stringify({ warn: 'min_version_without_update_url', min_version: g.min_version }));
  // 396 ①: the wipe's second guard likewise, not enforced without one
  if (g.features.length && !g.features_on) console.log(JSON.stringify({ warn: 'require_features_without_update_url', features: g.features }));
}
await registerP0Guard(app, guard, gate);
const dev = process.env.P0_DEV !== '0';
// The development mines (wd-dev-quarry / wd-dev-vein, no here check): only with P0_DEV_SITES=1, never on the live or preview server.
setDevSites(devSitesFromEnv(process.env));
// SGODOT-351: the blackjack shoe's key. A release server (P0_DEV=0) without one makes a random key for this process and
// warns (亚瑟 / 奕星 on #523: the card room stays open, a hand in play keeps its stored shoe); dev keeps a fixed key.
if (process.env.P0_BJ_SECRET) setBlackjackSecret(process.env.P0_BJ_SECRET);
else if (!dev) { setBlackjackSecret(randomBytes(32).toString('hex')); console.warn(JSON.stringify({ warn: 'P0_BJ_SECRET missing: a random key for this process' })); }
// The table itself (用户 via 奕星 on 351): open unless P0_BJ_TABLE is "0". The deploy script writes .env.p0 whole each
// time, so closing it goes through that script, never a hand edit (蒙恬).
setBlackjackTable(bjTableFromEnv(process.env.P0_BJ_TABLE));
// S7: observation log, one JSON line per command and reported UI moment (P0_EVENT_DIR; empty = off).
const eventDir = process.env.P0_EVENT_DIR ?? path.join(path.dirname(stateFile), 'events');
// P0_EVENT_KEEP_DAYS: how many days of day files to keep (the lines carry players' IPs since C25-4); unset = all, as before.
const keepRaw = Number(process.env.P0_EVENT_KEEP_DAYS ?? ''), eventKeepDays = Number.isInteger(keepRaw) && keepRaw >= 1 && keepRaw <= 3650 ? keepRaw : undefined;
if (process.env.P0_EVENT_KEEP_DAYS && !eventKeepDays) console.warn(JSON.stringify({ warn: 'P0_EVENT_KEEP_DAYS is not a whole number of days 1–3650: every file kept' }));
const log = new P0EventLog(eventDir === '' ? undefined : eventDir, undefined, undefined, eventKeepDays);
// Outpost rooms (SGODOT-227): WebSocket /v1/p0/online and GET /v1/p0/presence, in memory only. The same rooms
// give the Tea Host's "N online" in the state view (SGODOT-228).
// Generated outposts (SGODOT-280) get a room on first join, sized and walled like the room their art stands in for.
const outpostTable = loadOutposts();
const generatedRoom = generatedOutpostSpec(outpostTable, id => roomPlace(content, id));
// Ponds (11-02, pond multiplayer): `pond:<id>`, a room of 8 for a pond the content knows, made on first join.
const pondRoom = pondRoomSpec(id => !!placeOf(content, id));
// Landmarks (SGODOT-462): `landmark:<id>`, a room of 8 for a landmark whose scene the map opens.
const landmarkRoom = landmarkRoomSpec(id => content.landmark_scenes?.[id] === true);
const rooms = new OutpostRooms(outpostTable, Date.now, (id, layout) => layout ? generatedRoom(id, layout) : pondRoom(id) ?? landmarkRoom(id) ?? generatedRoom(id));
// q(188) ① `Near you`: the address table made from DB-IP City Lite at image build (tools/ip_near_table.ts); none, no guess.
let ipNear: IpNear | undefined;
if (process.env.P0_IP_NEAR_TABLE) {
  try { ipNear = openIpNear(process.env.P0_IP_NEAR_TABLE); }
  catch (e) { console.error(JSON.stringify({ ip_near: 'unavailable', error: String((e as Error).message ?? e).slice(0, 200) })); }
}
// SGODOT-488 accounts (contract-accounts.md): accounts.json beside the save, who a request is (identify) for the
// routes, the voice routes, the room's WebSocket and the request limits alike. P0_LEGACY_ID=1 takes an id alone
// (devserver, shots): the live server never has it — its healthz says legacy_id and the deploy's smoke checks false.
const accountsCfg = accountsConfig();
const accountsFile = path.join(path.dirname(stateFile), 'accounts.json');
const accounts = new P0Accounts(accountsFile, accountsCfg.refreshKey);
if (accountsCfg.legacyId) console.warn(JSON.stringify({ warn: 'P0_LEGACY_ID=1: an x-p0-player alone is taken for any player (never on the live server)' }));
const identifyDeps = { accounts, legacyId: accountsCfg.legacyId, updateUrl: () => gate.state().update_url || undefined };
const identifyReq = (h: Record<string, unknown>) => identify(h, identifyDeps);
registerP0Routes(app, { content, store, now: Date.now, dev, log, rooms, ipNear, identify: identifyDeps });
// The WebSocket upgrade checks the guard's demo keys itself: the guard's onRequest hook does not see it (SGODOT-232 D1).
// v5: joining an outpost room needs a pass for its city, as entering it does (requirePass; the entered outpost passes).
// A pond's room checks the pond's city as entering the pond does (its city from the pond, never `pond:…`; home's are free).
// A landmark's room asks nothing: the landmark itself is opened from the map with no pass and nothing sent (q(295) ④).
const pass = (player: string, room: string) => {
  if (landmarkOfRoom(room)) return null;
  const s = store.peek(player);
  if (!s) return null;
  const pond = pondOfRoom(room), place = pond || room;
  const r = requirePass(content, s, pond ? 'pond' : 'outpost', place, Date.now() + s.clock_ms, s.presence.entered === place ? 'rejoin' : undefined);
  return r ? r.code.toUpperCase() : null;
};
// Voice in the rooms (SGODOT-383): off unless P0_VOICE=on with the LiveKit keys; its blocks, 13+ answers and reports in
// their own files beside the save, never in it.
const voiceDir = path.dirname(stateFile);
const voice = new P0Voice(p0VoiceFromEnv(process.env), rooms, { blocks: path.join(voiceDir, 'voice_blocks.json'),
  ages: path.join(voiceDir, 'voice_ages.json'), reports: path.join(voiceDir, 'voice_reports.jsonl') });
registerP0Voice(app, voice, identifyReq);
const hub = registerP0Online(app, { rooms, keys: guard.keys, gate, pass, appearances: new AppearanceCatalog(path.join(root, 'assets/avatar')),
  joined: o => voice.joined(o), departed: o => voice.departed(o), hides: (a, b) => voice.hides(a, b), identify: identifyReq });
registerAccountRoutes(app, { store, accounts, identify: identifyDeps, now: Date.now,
  voiceAge: p => { const a = voice.status(p).age; return a === 'ok' ? true : a === 'no' ? false : null; },
  newSave: h => { const f = String(h['x-p0-features'] ?? '').split(',').map(x => x.trim()); return { pending: f.includes('choose_home'), guide: f.includes('guide_v3') }; } });
voice.tell = (player, payload) => hub.tell(player, payload);
voice.seen = (a, b) => hub.seenChanged(a, b);
const startedAt = Date.now();
app.get('/v1/healthz', async () => {
  const g = gate.state();
  return { ok: true, p0: content.version, players: store.size(), up_s: Math.round((Date.now() - startedAt) / 1000), legacy_id: accountsCfg.legacyId,
    maintenance: g.maintenance, min_version: g.update_on ? g.min_version : 0, require_features: g.features_on ? g.features : [] };
});
const snapshots = process.env.P0_SNAPSHOT_DIR ?? path.join(path.dirname(stateFile), 'snapshots');
setInterval(() => snapshotState(stateFile, snapshots, 48, Date.now(), accountsFile), 3_600_000).unref();
const port = Number(process.env.P0_PORT ?? 3110);
await app.listen({ port, host: process.env.P0_HOST ?? '0.0.0.0' });
console.log(JSON.stringify({ ready: true, port, content: content.version, dev, blackjack_table: bjTableOn(), key: guard.keys.length > 0, admin: !!process.env.P0_ADMIN_KEY && Number(process.env.P0_ADMIN_PORT ?? 0) > 0, ip_near: !!ipNear, event_keep_days: eventKeepDays ?? null, voice: !!voice.config, dev_sites: devSitesFromEnv(process.env) }));
// SGODOT-150 observer tools (q(53)): admin routes on 127.0.0.1 inside the container only, with their own key.
const adminPort = Number(process.env.P0_ADMIN_PORT ?? 0);
const admin = adminPort && process.env.P0_ADMIN_KEY ? Fastify({ logger: false, bodyLimit: 4 * 1024 }) : null;
if (admin) {
  registerP0Admin(admin, { content, store, now: Date.now, key: process.env.P0_ADMIN_KEY!, gate });
  await admin.listen({ port: adminPort, host: '127.0.0.1' });
}
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.on(signal, () => { void Promise.all([app.close(), admin?.close()]).then(() => process.exit(0)); });
