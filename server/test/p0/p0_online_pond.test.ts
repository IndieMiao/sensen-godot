import Fastify, { type FastifyInstance } from 'fastify';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it } from 'vitest';
import { WebSocket } from 'ws';
import { LIMITS, PATH, registerP0Online } from '../../src/p0/online/hub.js';
import { loadOutposts, POND_BOUNDS, POND_CAPACITY, pondOfRoom, pondRoomSpec } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';

// Pond multiplayer (the user, 11-02 via 奕星): a pond is a room of 8, `pond:<id>`, made on first join; its lines go to the
// others in the room as `fishing`, and its people count under presence's `ponds`, apart from the outposts.

const PONDS = new Set(['pond_san_francisco_03', 'gn-5355933~pond1']);
let app: FastifyInstance | undefined;
const sockets: WebSocket[] = [];
afterEach(async () => {
  for (const ws of sockets.splice(0)) ws.terminate();
  await app?.close();
  app = undefined;
});

async function server(pass?: (player: string, room: string) => string | null) {
  app = Fastify({ logger: false });
  const rooms = new OutpostRooms(loadOutposts(), Date.now, pondRoomSpec(id => PONDS.has(id)));
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

describe('P0 pond rooms (pond multiplayer, 11-02)', () => {
  it('a pond the content knows is a room of 8 on its meadow, with no seats; any other pond: id is unknown', () => {
    const spec = pondRoomSpec(id => PONDS.has(id));
    expect(spec('pond:pond_san_francisco_03')).toEqual({ id: 'pond:pond_san_francisco_03', role: 'pond', capacity: POND_CAPACITY,
      bounds: POND_BOUNDS, seats: [] });
    expect(spec('pond:gn-5355933~pond1')?.capacity).toBe(8);
    expect(spec('pond:nowhere')).toBeUndefined();
    expect(spec('pond_san_francisco_03')).toBeUndefined();   // a pond room says it is one
    expect(pondOfRoom('pond:gn-5355933~pond1')).toBe('gn-5355933~pond1');
    expect(pondOfRoom('sh_tea_1')).toBe('');
  });

  it('every template\'s water lies inside the room\'s walls, so a landing kept in them is never moved off the water (周瑜 on #646)', () => {
    const file = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../assets/p0/p0_pond_templates.json');
    const templates = JSON.parse(readFileSync(file, 'utf8')).templates as Record<string, { polygon: [number, number][] }>;
    const [x0, x1, z0, z1] = POND_BOUNDS;
    expect(Object.keys(templates).length).toBeGreaterThan(0);
    for (const [id, t] of Object.entries(templates))
      for (const [x, z] of t.polygon) expect([id, x >= x0 && x <= x1 && z >= z0 && z <= z1]).toEqual([id, true]);
  });

  it('the 9th player of a pond lands in Room 2; presence counts ponds under `ponds`, by pond id', async () => {
    const { port } = await server();
    const players = await Promise.all(Array.from({ length: 9 }, (_, i) => connect(port, `pond-player-${i}`)));
    const rooms = [];
    for (const p of players) rooms.push((await join(p, 'pond:pond_san_francisco_03', [6, -2])).room);
    expect(rooms).toEqual([1, 1, 1, 1, 1, 1, 1, 1, 2]);
    const presence = (await app!.inject({ method: 'GET', url: '/v1/p0/presence' })).json();
    expect(presence.ponds).toEqual({ pond_san_francisco_03: { online: 9, rooms: 2 } });
    expect(Object.keys(presence.outposts).some(id => id.startsWith('pond:'))).toBe(false);
    const unknown = await connect(port, 'pond-player-x');
    expect(await join(unknown, 'pond:nowhere')).toMatchObject({ t: 'error', code: 'UNKNOWN_OUTPOST' });
  });

  it('a pond room asks the pass with the room id, and a refusal is the joiner\'s error', async () => {
    const asked: string[] = [];
    const { port } = await server((_player, room) => { asked.push(room); return room === 'pond:gn-5355933~pond1' ? 'TRAVEL_REQUIRED' : null; });
    const a = await connect(port, 'pond-player-a');
    expect(await join(a, 'pond:gn-5355933~pond1')).toMatchObject({ t: 'error', code: 'TRAVEL_REQUIRED' });
    expect(await join(a, 'pond:pond_san_francisco_03')).toMatchObject({ t: 'joined', capacity: 8 });
    expect(asked).toEqual(['pond:gn-5355933~pond1', 'pond:pond_san_francisco_03']);
  });

  it('a line goes to the others in the pond room — cast, bite, reel and the fish landed — never to the caster or another room', async () => {
    const { port } = await server();
    const [a, b, c] = await Promise.all(['pond-player-a', 'pond-player-b', 'pond-player-c'].map(p => connect(port, p)));
    const ja = await join(a, 'pond:pond_san_francisco_03', [6, -2]);
    await join(b, 'pond:pond_san_francisco_03', [7, -2]);
    await join(c, 'sh_tea_1');
    send(a, { t: 'fish', epoch: ja.epoch, phase: 'casting', target: [6, -40] });   // landing clamped into the meadow
    const cast = await until(msg(b, 'fishing', 0, m => m.members.length === 1));
    expect(cast.members[0]).toMatchObject({ id: ja.self, sequence: 1, phase: 'casting', target: [6, POND_BOUNDS[2]], held: false, fish: 0.5 });
    let from = b.json.length;
    send(a, { t: 'fish', epoch: ja.epoch, phase: 'playing', held: true, fish: 2 });
    expect((await until(msg(b, 'fishing', from, m => m.members[0]?.phase === 'playing'))).members[0]).toMatchObject({ held: true, fish: 1, sequence: 1 });
    from = b.json.length;
    send(a, { t: 'fish', epoch: ja.epoch, phase: 'result', outcome: 'caught', fish_id: 'fish_crucian' });
    expect((await until(msg(b, 'fishing', from, m => m.members[0]?.phase === 'result'))).members[0])
      .toMatchObject({ outcome: 'caught', fish_id: 'fish_crucian', held: false });
    expect(a.json.filter(m => m.t === 'fishing').every(m => m.members.length === 0)).toBe(true);   // never its own line
    expect(c.json.some(m => m.t === 'fishing')).toBe(false);   // nor an outpost's room
    // the next cast is a new line
    from = b.json.length;
    send(a, { t: 'fish', epoch: ja.epoch, phase: 'casting', target: [5, -3] });
    expect((await until(msg(b, 'fishing', from, m => m.members[0]?.sequence === 2))).members[0].phase).toBe('casting');
    // the line taken in: nothing more goes out
    send(a, { t: 'fish', epoch: ja.epoch, phase: 'none' });
    await new Promise(r => setTimeout(r, LIMITS.snapshot_ms * LIMITS.fishing_ticks * 2 + 50));
    from = b.json.length;
    await new Promise(r => setTimeout(r, LIMITS.snapshot_ms * LIMITS.fishing_ticks * 2 + 50));
    expect(b.json.slice(from).some(m => m.t === 'fishing')).toBe(false);
  });

  it('a line outside a pond room, for a stale epoch, or a cast without its landing is not one', async () => {
    const { port } = await server();
    const [a, b] = await Promise.all(['pond-player-a', 'pond-player-b'].map(p => connect(port, p)));
    const ja = await join(a, 'sh_tea_1');
    await join(b, 'sh_tea_1');
    send(a, { t: 'fish', epoch: ja.epoch, phase: 'casting', target: [1, 1] });   // an outpost room: ignored
    const jp = await join(a, 'pond:pond_san_francisco_03');
    await join(b, 'pond:pond_san_francisco_03');
    send(a, { t: 'fish', epoch: jp.epoch + 5, phase: 'casting', target: [1, 1] });   // stale epoch: ignored
    await new Promise(r => setTimeout(r, LIMITS.snapshot_ms * LIMITS.fishing_ticks * 2 + 50));
    expect(b.json.some(m => m.t === 'fishing' && m.members.length)).toBe(false);
    send(a, { t: 'fish', epoch: jp.epoch, phase: 'casting' });   // no landing: a schema error closes the socket
    await until(() => a.ws.readyState === WebSocket.CLOSED ? true : undefined);
  });
});
