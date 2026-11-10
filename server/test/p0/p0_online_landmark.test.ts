import Fastify, { type FastifyInstance } from 'fastify';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it } from 'vitest';
import { WebSocket } from 'ws';
import { LIMITS, PATH, registerP0Online } from '../../src/p0/online/hub.js';
import { LANDMARK_BOUNDS, LANDMARK_CAPACITY, landmarkOfRoom, landmarkRoomSpec, loadOutposts, pondRoomSpec } from '../../src/p0/online/outposts.js';
import { P0Voice } from '../../src/p0/online/voice.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';

// Landmark multiplayer (SGODOT-462; the user, 11-10: 「恶魔岛无法多人,无法语音」, 「都是现成代码的复用」): a landmark whose
// scene the map opens is a room of 8, `landmark:<id>`, made on first join as a pond's is; its people count under presence's
// `landmarks`, apart from the outposts and the ponds; its room has voice.

const LANDMARKS_FILE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../assets/p0/content/landmarks.json');
const SCENES = JSON.parse(readFileSync(LANDMARKS_FILE, 'utf8')).landmark_scenes as Record<string, boolean>;
const known = (id: string) => SCENES[id] === true;   // as tools/p0_server.ts asks content.landmark_scenes
const PONDS = new Set(['pond_san_francisco_03']);
let app: FastifyInstance | undefined;
const sockets: WebSocket[] = [];
afterEach(async () => {
  for (const ws of sockets.splice(0)) ws.terminate();
  await app?.close();
  app = undefined;
});

async function server(pass?: (player: string, room: string) => string | null) {
  app = Fastify({ logger: false });
  const pond = pondRoomSpec(id => PONDS.has(id)), landmark = landmarkRoomSpec(known);
  const rooms = new OutpostRooms(loadOutposts(), Date.now, id => pond(id) ?? landmark(id));
  registerP0Online(app, { rooms, pass });
  await app.listen({ port: 0, host: '127.0.0.1' });
  const address = app.server.address();
  return { port: typeof address === 'object' && address ? address.port : 0, rooms };
}

interface Client { ws: WebSocket; json: Record<string, any>[] }
function connect(port: number, player: string): Promise<Client> {
  const ws = new WebSocket(`ws://127.0.0.1:${port}${PATH}`, { headers: { 'x-p0-player': player } });
  sockets.push(ws);
  const client: Client = { ws, json: [] };
  ws.on('message', (data, binary) => { if (!binary) client.json.push(JSON.parse(String(data))); });
  return new Promise((resolve, reject) => { ws.once('open', () => resolve(client)); ws.once('error', reject); });
}
async function until<T>(fn: () => T | undefined, ms = 3000): Promise<T> {
  const end = Date.now() + ms;
  for (;;) {
    const v = fn();
    if (v) return v;
    if (Date.now() > end) throw new Error('timeout');
    await new Promise(r => setTimeout(r, 10));
  }
}
const msg = (c: Client, t: string, from = 0, ok: (m: any) => boolean = () => true) => () => c.json.slice(from).find(m => m.t === t && ok(m));
const send = (c: Client, m: object) => c.ws.send(JSON.stringify(m));
async function join(c: Client, room: string, at?: [number, number]) {
  const from = c.json.length;
  send(c, { t: 'join', outpost: room, ...(at ? { at } : {}) });
  return until(() => c.json.slice(from).find(m => m.t === 'joined' || m.t === 'error'));
}

describe('P0 landmark rooms (SGODOT-462)', () => {
  it('Alcatraz and Griffith, the landmarks the map opens, are rooms of 8 with no seats; any other id is no landmark room', () => {
    expect(SCENES).toMatchObject({ alcatraz_island: true, griffith_observatory: true });
    const spec = landmarkRoomSpec(known);
    for (const id of ['alcatraz_island', 'griffith_observatory'])
      expect(spec(`landmark:${id}`)).toEqual({ id: `landmark:${id}`, role: 'landmark', capacity: LANDMARK_CAPACITY, bounds: LANDMARK_BOUNDS, seats: [] });
    expect(LANDMARK_CAPACITY).toBe(8);
    expect(spec('landmark:golden_gate')).toBeUndefined();   // no scene: no room
    expect(spec('alcatraz_island')).toBeUndefined();         // a landmark room says it is one
    expect(spec('pond:pond_san_francisco_03')).toBeUndefined();
    expect(landmarkOfRoom('landmark:alcatraz_island')).toBe('alcatraz_island');
    expect(landmarkOfRoom('pond:pond_san_francisco_03')).toBe('');
  });

  it('the walls hold Alcatraz\'s whole walkable ground (its camera keeps to ±50 / ±40 m)', () => {
    const [x0, x1, z0, z1] = LANDMARK_BOUNDS;
    expect([x0 <= -50, x1 >= 50, z0 <= -40, z1 >= 40]).toEqual([true, true, true, true]);
  });

  it('two on Alcatraz see each other; the 9th lands in Room 2; presence counts landmarks under `landmarks`, never as outposts', async () => {
    const { port } = await server();
    const players = await Promise.all(Array.from({ length: 9 }, (_, i) => connect(port, `isle-player-${i}`)));
    const rooms = [];
    for (const p of players) rooms.push((await join(p, 'landmark:alcatraz_island', [2, 30])).room);
    expect(rooms).toEqual([1, 1, 1, 1, 1, 1, 1, 1, 2]);
    // the second on the island had the first in its welcome; the first was told of the second
    expect(players[0].json.some(m => m.t === 'peer')).toBe(true);
    const presence = (await app!.inject({ method: 'GET', url: '/v1/p0/presence' })).json();
    expect(presence.landmarks).toEqual({ alcatraz_island: { online: 9, rooms: 2 } });
    expect(Object.keys(presence.outposts).some(id => id.startsWith('landmark:'))).toBe(false);
    expect(presence.ponds).toEqual({});
    const griffith = await connect(port, 'hill-player');
    expect(await join(griffith, 'landmark:griffith_observatory', [0, 0])).toMatchObject({ t: 'joined', room: 1, capacity: 8 });
    const nowhere = await connect(port, 'isle-player-x');
    expect(await join(nowhere, 'landmark:golden_gate')).toMatchObject({ t: 'error', code: 'UNKNOWN_OUTPOST' });
  });

  it('a landmark room has voice, as a pond\'s (not in NO_VOICE_ROLES)', async () => {
    const pond = pondRoomSpec(id => PONDS.has(id)), landmark = landmarkRoomSpec(known);
    const rooms = new OutpostRooms(loadOutposts(), Date.now, id => pond(id) ?? landmark(id));
    const voice = new P0Voice({ url: 'ws://livekit.test:7880', apiKey: 'devkey', apiSecret: 'a-secret-of-at-least-32-characters-long', namespace: 'p0-test' },
      rooms, null, Date.now, { getParticipant: async () => ({}), removeParticipant: async () => {} });
    for (const p of ['isle-a', 'isle-b']) { voice.setAge(p, true); rooms.join(p, 'landmark:alcatraz_island'); voice.joined(rooms.occupant(p)!); }
    const a = await voice.join('isle-a') as Record<string, any>, b = await voice.join('isle-b') as Record<string, any>;
    expect(a).toMatchObject({ ok: true, capacity: 8 });
    expect(b.room).toBe(a.room);   // one voice for the island's room
  });
});
