import Fastify, { type FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { WebSocket } from 'ws';
import { FRAME_HEADER, FRAME_MEMBER, P0_ACTIONS } from '../../src/p0/online/frame.js';
import { LIMITS, PATH, registerP0Online } from '../../src/p0/online/hub.js';
import { loadOutposts } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { loadP0Content } from '../../src/p0/content.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';

let app: FastifyInstance | undefined;
const sockets: WebSocket[] = [];
afterEach(async () => {
  for (const ws of sockets.splice(0)) ws.terminate();
  await app?.close();
  app = undefined;
});

async function server(keys?: string[]) {
  app = Fastify({ logger: false });
  const rooms = new OutpostRooms(loadOutposts());
  registerP0Online(app, { rooms, keys });
  await app.listen({ port: 0, host: '127.0.0.1' });
  const address = app.server.address();
  const port = typeof address === 'object' && address ? address.port : 0;
  return { port, rooms };
}

interface Client { ws: WebSocket; json: Record<string, any>[]; frames: Buffer[]; closed?: { code: number; reason: string } }
function connect(port: number, player: string, key?: string): Promise<Client> {
  const ws = new WebSocket(`ws://127.0.0.1:${port}${PATH}`, { headers: { 'x-p0-player': player, ...(key ? { 'x-p0-key': key } : {}) } });
  sockets.push(ws);
  const client: Client = { ws, json: [], frames: [] };
  ws.on('message', (data, binary) => binary ? client.frames.push(data as Buffer) : client.json.push(JSON.parse(String(data))));
  ws.on('close', (code, reason) => client.closed = { code, reason: String(reason) });
  return new Promise((resolve, reject) => { ws.once('open', () => resolve(client)); ws.once('error', reject); ws.once('unexpected-response', (_req, res) => reject(new Error('HTTP ' + res.statusCode))); });
}
async function until<T>(fn: () => T | undefined, ms = 2000): Promise<T> {
  const end = Date.now() + ms;
  for (;;) {
    const v = fn();
    if (v) return v;
    if (Date.now() > end) throw new Error('timeout');
    await new Promise(r => setTimeout(r, 10));
  }
}
const msg = (c: Client, t: string, from = 0) => () => c.json.slice(from).find(m => m.t === t);
const send = (c: Client, m: object) => c.ws.send(JSON.stringify(m));
async function join(c: Client, outpost: string, at?: [number, number]) {
  const from = c.json.length;
  send(c, { t: 'join', outpost, ...(at ? { at } : {}) });
  return until(msg(c, 'joined', from));
}
function decode(frame: Buffer) {
  const n = frame.readUInt16LE(10);
  return { version: frame.readUInt16LE(0), epoch: frame.readUInt32LE(6), members: Array.from({ length: n }, (_, i) => {
    const at = FRAME_HEADER + i * FRAME_MEMBER;
    return { id: frame.readUInt16LE(at), x: frame.readFloatLE(at + 2), z: frame.readFloatLE(at + 6), action: P0_ACTIONS[frame.readUInt8(at + 18)], seq: frame.readUInt32LE(at + 20) };
  }) };
}

describe('P0 online hub (/v1/p0/online, SGODOT-227)', () => {
  it('rejects a missing or malformed player id at the upgrade', async () => {
    const { port } = await server();
    await expect(connect(port, 'bad id!')).rejects.toThrow('HTTP 400');
  });

  it('join → joined + roster; others get peer and left; presence counts the instance', async () => {
    const { port } = await server();
    const a = await connect(port, 'player-aaaa');
    const b = await connect(port, 'player-bbbb');
    expect((await join(a, 'sh_tea_1', [1, 1])).room).toBe(1);
    const joined = await join(b, 'sh_tea_1');
    expect(joined).toMatchObject({ outpost: 'sh_tea_1', room: 1, capacity: 12, rejoined: false, self: 2, epoch: 1 });
    expect((await until(msg(b, 'roster'))).members.map((m: any) => m.player)).toEqual(['player-aaaa', 'player-bbbb']);
    expect(await until(msg(a, 'peer'))).toMatchObject({ count: 2, member: { id: 2, player: 'player-bbbb' } });
    const presence = await app!.inject({ method: 'GET', url: '/v1/p0/presence' });
    expect(presence.json().outposts.sh_tea_1).toEqual({ online: 2, rooms: 1 });
    send(b, { t: 'leave' });
    await until(msg(b, 'departed'));
    expect(await until(msg(a, 'left'))).toEqual({ t: 'left', id: 2, count: 1 });
  });

  it('the 13th player of an indoor outpost lands in Room 2; moving to another outpost frees the old instance', async () => {
    const { port } = await server();
    const clients = await Promise.all(Array.from({ length: 13 }, (_, i) => connect(port, `player-${String(i).padStart(4, '0')}`)));
    for (const c of clients.slice(0, 12)) expect((await join(c, 'sh_tackle_1')).room).toBe(1);
    expect((await join(clients[12], 'sh_tackle_1')).room).toBe(2);
    for (const c of clients.slice(0, 13)) await join(c, 'sh_market_1');
    const presence = (await app!.inject({ method: 'GET', url: '/v1/p0/presence' })).json().outposts;
    expect(presence.sh_tackle_1).toEqual({ online: 0, rooms: 0 });
    expect(presence.sh_market_1).toEqual({ online: 13, rooms: 1 });
  });

  it('streams frame v1 with the client positions, clamped to room bounds and walking speed', async () => {
    const { port } = await server();
    const a = await connect(port, 'player-aaaa');
    const { epoch } = await join(a, 'sh_post_1', [0, 0]);
    await new Promise(r => setTimeout(r, 250));
    send(a, { t: 'input', seq: 1, epoch, x: 0.4, z: -0.3, yaw: 1, action: 'walk' });
    const frame = await until(() => a.frames.map(decode).find(f => f.members[0]?.seq === 1));
    expect(frame.version).toBe(1);
    expect(frame.epoch).toBe(epoch);
    expect(frame.members[0]).toMatchObject({ id: 1, action: 'walk' });
    expect(frame.members[0].x).toBeCloseTo(0.4);
    send(a, { t: 'input', seq: 2, epoch, x: 999, z: 0, yaw: 0, action: 'run' });   // teleport: clamped, never past the wall
    const far = await until(() => a.frames.map(decode).find(f => f.members[0]?.seq === 2));
    expect(far.members[0].x).toBeLessThanOrEqual(3);
    expect(far.members[0].x).toBeLessThan(0.4 + 6 * 1 + 0.5);
  });

  it('one player per seat; standing up frees it for the next player', async () => {
    const { port } = await server();
    const a = await connect(port, 'player-aaaa');
    const b = await connect(port, 'player-bbbb');
    const ea = (await join(a, 'sh_tea_1')).epoch, eb = (await join(b, 'sh_tea_1')).epoch;
    send(a, { t: 'act', seq: 1, epoch: ea, action: 'sit', node: 'seat_table1_1' });
    expect(await until(msg(a, 'result'))).toEqual({ t: 'result', seq: 1, ok: true, code: '' });
    expect(await until(msg(b, 'seat'))).toEqual({ t: 'seat', id: 1, seat: 'seat_table1_1' });
    send(b, { t: 'act', seq: 1, epoch: eb, action: 'sit', node: 'seat_table1_1' });
    expect(await until(msg(b, 'result'))).toMatchObject({ ok: false, code: 'SEAT_TAKEN' });
    const from = b.json.length;
    send(a, { t: 'act', seq: 2, epoch: ea, action: 'stand' });
    expect(await until(msg(b, 'seat', from))).toEqual({ t: 'seat', id: 1, seat: '' });
    send(b, { t: 'act', seq: 2, epoch: eb, action: 'sit', node: 'seat_table1_1' });
    expect(await until(() => b.json.filter(m => m.t === 'result')[1])).toMatchObject({ ok: true });
  });

  it('a refused sit does not move the player', async () => {
    const { port, rooms } = await server();
    const a = await connect(port, 'player-aaaa');
    const b = await connect(port, 'player-bbbb');
    const ea = (await join(a, 'sh_tea_1', [1.15, 0])).epoch, eb = (await join(b, 'sh_tea_1', [-1, 1])).epoch;
    send(a, { t: 'act', seq: 1, epoch: ea, action: 'sit', node: 'seat_table1_1' });
    await until(msg(a, 'result'));
    await new Promise(r => setTimeout(r, 200));
    send(b, { t: 'act', seq: 1, epoch: eb, action: 'sit', node: 'seat_table1_1', at: [1.15, 0.62] });
    expect(await until(msg(b, 'result'))).toMatchObject({ ok: false, code: 'SEAT_TAKEN' });
    send(b, { t: 'act', seq: 2, epoch: eb, action: 'sit', node: 'seat_nowhere', at: [1.15, 0.62] });
    expect(await until(() => b.json.filter(m => m.t === 'result')[1])).toMatchObject({ ok: false, code: 'NO_SEAT' });
    expect(rooms.occupant('player-bbbb')).toMatchObject({ x: -1, z: 1, seat: '' });
  });

  it('a sit carries the seat position, so the next input at the seat keeps the player seated', async () => {
    const { port, rooms } = await server();
    const a = await connect(port, 'player-aaaa');
    const { epoch } = await join(a, 'sh_tea_1', [1.15, 0]);
    await new Promise(r => setTimeout(r, 200));
    send(a, { t: 'act', seq: 1, epoch, action: 'sit', node: 'seat_table1_1', at: [1.15, 0.62] });
    await until(msg(a, 'result'));
    send(a, { t: 'input', seq: 1, epoch, x: 1.15, z: 0.62, yaw: 1.57, action: 'idle' });
    await until(() => rooms.occupant('player-aaaa')!.seq === 1);
    expect(rooms.occupant('player-aaaa')).toMatchObject({ seat: 'seat_table1_1', action: 'sit' });
    expect(rooms.occupant('player-aaaa')!.z).toBeCloseTo(0.62);
  });

  it('a dropped connection that comes back within a minute returns to its room, flagged rejoined', async () => {
    const { port, rooms } = await server();
    const clients = await Promise.all(Array.from({ length: 13 }, (_, i) => connect(port, `player-${String(i).padStart(4, '0')}`)));
    for (const c of clients) await join(c, 'sh_tea_1');
    clients[12].ws.terminate();
    await until(() => !rooms.occupant('player-0012'));
    send(clients[0], { t: 'leave' });                      // a place frees up in Room 1 …
    await until(msg(clients[0], 'departed'));
    const back = await connect(port, 'player-0012');
    expect(await join(back, 'sh_tea_1')).toMatchObject({ room: 2, rejoined: true });   // … but the returning player keeps Room 2
  });

  it('a second connection for the same player replaces the first', async () => {
    const { port } = await server();
    const first = await connect(port, 'player-aaaa');
    await join(first, 'sh_tea_1');
    const second = await connect(port, 'player-aaaa');
    await until(() => first.closed);
    expect(first.closed).toEqual({ code: 4001, reason: 'SESSION_REPLACED' });
    expect(await join(second, 'sh_tea_1')).toMatchObject({ room: 1, rejoined: true, self: 1 });
  });

  it('closes on malformed, binary, oversized or flooding input; unknown outposts get an error', async () => {
    const { port } = await server();
    const a = await connect(port, 'player-aaaa');
    send(a, { t: 'join', outpost: 'nowhere' });
    expect(await until(msg(a, 'error'))).toEqual({ t: 'error', code: 'UNKNOWN_OUTPOST' });
    a.ws.send('not json');
    expect((await until(() => a.closed)).code).toBe(4002);
    const b = await connect(port, 'player-bbbb');
    b.ws.send(Buffer.from([1, 2, 3]), { binary: true });
    expect((await until(() => b.closed)).code).toBe(4002);
    const c = await connect(port, 'player-cccc');
    c.ws.send(JSON.stringify({ t: 'ping', at: 'x'.repeat(LIMITS.payload) }));
    expect((await until(() => c.closed)).code).toBe(1009);
    const d = await connect(port, 'player-dddd');
    for (let i = 0; i < LIMITS.burst + 5; i++) send(d, { t: 'ping', at: i });
    expect(await until(() => d.closed)).toEqual({ code: 4002, reason: 'RATE_OR_SCHEMA' });
  });
  it('the rooms that seat players also give the Tea Host her online count (p0_server wiring)', async () => {
    app = Fastify({ logger: false });
    const rooms = new OutpostRooms(loadOutposts());
    const content = loadP0Content();
    registerP0Routes(app, { content, store: new P0Store(content), now: Date.now, dev: true, presence: () => rooms.total() });
    registerP0Online(app, { rooms });
    await app.listen({ port: 0, host: '127.0.0.1' });
    const address = app.server.address();
    const port = typeof address === 'object' && address ? address.port : 0;
    const online = async () => (await app!.inject({ method: 'GET', url: '/v1/p0/state', headers: { 'x-p0-player': 'tea-reader-01' } })).json().state.keepers.tea.online;
    expect(await online()).toBe(0);
    const a = await connect(port, 'tea-guest-001');
    await join(a, 'sh_tea_1');
    const b = await connect(port, 'tackle-guest-02');
    await join(b, 'sh_tackle_1');
    expect(await online()).toBe(2);   // every outpost room, like GET /v1/p0/presence
  });
  it('with demo keys set the upgrade needs x-p0-key, which the HTTP guard hook never sees (SGODOT-232 D1)', async () => {
    const { port } = await server(['demo-key-1']);
    await expect(connect(port, 'keyless-player-1')).rejects.toThrow('HTTP 401');
    await expect(connect(port, 'wrong-key-player', 'nope')).rejects.toThrow('HTTP 401');
    const c = await connect(port, 'keyed-player-001', 'demo-key-1');
    expect((await join(c, 'sh_tea_1')).room).toBe(1);
  });
});
