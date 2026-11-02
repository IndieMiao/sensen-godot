import Fastify, { type FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { WebSocket } from 'ws';
import { FRAME_HEADER, FRAME_MEMBER } from '../../src/p0/online/frame.js';
import { LIMITS, PATH, P0OnlineHub, publicPlayer, registerP0Online } from '../../src/p0/online/hub.js';
import { loadOutposts, pondRoomSpec } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';

// A Block either way keeps two players out of each other's sight in a room (q(28), 383 V3; 奕星 11-02): no roster line,
// peer, left, seat, frame member or fishing line of the other; at a Block they leave each other's view at once and come
// back at an Unblock. Everyone else sees both as ever.

let app: FastifyInstance | undefined;
const sockets: WebSocket[] = [];
afterEach(async () => {
  for (const ws of sockets.splice(0)) ws.terminate();
  await app?.close();
  app = undefined;
});

const hidden = new Set<string>();   // "a b": a blocks b
const hides = (a: string, b: string) => hidden.has(`${a} ${b}`) || hidden.has(`${b} ${a}`);

async function server() {
  hidden.clear();
  app = Fastify({ logger: false });
  const rooms = new OutpostRooms(loadOutposts(), Date.now, pondRoomSpec(id => id === 'pond_san_francisco_03'));
  const hub = registerP0Online(app, { rooms, hides });
  await app.listen({ port: 0, host: '127.0.0.1' });
  const address = app.server.address();
  return { port: typeof address === 'object' && address ? address.port : 0, hub };
}
interface Client { ws: WebSocket; json: Record<string, any>[]; frames: Buffer[] }
function connect(port: number, player: string): Promise<Client> {
  const ws = new WebSocket(`ws://127.0.0.1:${port}${PATH}`, { headers: { 'x-p0-player': player } });
  sockets.push(ws);
  const client: Client = { ws, json: [], frames: [] };
  ws.on('message', (data, binary) => binary ? client.frames.push(data as Buffer) : client.json.push(JSON.parse(String(data))));
  return new Promise((resolve, reject) => { ws.once('open', () => resolve(client)); ws.once('error', reject); });
}
async function until<T>(fn: () => T | undefined, ms = 3000): Promise<T> {
  const end = Date.now() + ms;
  for (;;) { const v = fn(); if (v) return v; if (Date.now() > end) throw new Error('timeout'); await new Promise(r => setTimeout(r, 10)); }
}
const send = (c: Client, m: object) => c.ws.send(JSON.stringify(m));
async function join(c: Client, room: string, at?: [number, number]) {
  const from = c.json.length;
  send(c, { t: 'join', outpost: room, ...(at ? { at } : {}) });
  return until(() => c.json.slice(from).find(m => m.t === 'joined'));
}
const frameIds = (f: Buffer) => Array.from({ length: f.readUInt16LE(10) }, (_, i) => f.readUInt16LE(FRAME_HEADER + i * FRAME_MEMBER));
const wait = (ms: number) => new Promise(r => setTimeout(r, ms));

describe('a Block hides two players from each other in a room (q(28), 383 V3)', () => {
  it('coming into a room: no roster line nor peer of the other; the frames leave them out; a third sees both', async () => {
    const { port } = await server();
    hidden.add('player-aaaa player-bbbb');
    const [a, b, c] = await Promise.all(['player-aaaa', 'player-bbbb', 'player-cccc'].map(p => connect(port, p)));
    const ja = await join(a, 'sh_tea_1');
    const jb = await join(b, 'sh_tea_1');
    const jc = await join(c, 'sh_tea_1');
    const rosterB = b.json.find(m => m.t === 'roster')!;
    expect(rosterB.members.map((m: any) => m.player)).toEqual([publicPlayer('player-bbbb')]);   // not A
    expect(rosterB.count).toBe(1);
    expect(a.json.filter(m => m.t === 'peer').map(m => m.member.id)).toEqual([jc.self]);   // C, never B
    const rosterC = c.json.find(m => m.t === 'roster')!;
    expect(rosterC.members.map((m: any) => m.id).sort()).toEqual([ja.self, jb.self, jc.self].sort());
    send(a, { t: 'input', seq: 1, epoch: ja.epoch, x: 1, z: 1, yaw: 0, action: 'idle' });
    send(b, { t: 'input', seq: 1, epoch: jb.epoch, x: 2, z: 2, yaw: 0, action: 'idle' });
    await wait(LIMITS.snapshot_ms * 3);
    expect(a.frames.slice(-1).flatMap(frameIds)).not.toContain(jb.self);
    expect(b.frames.slice(-1).flatMap(frameIds)).not.toContain(ja.self);
    expect(c.frames.slice(-1).flatMap(frameIds).sort()).toEqual([ja.self, jb.self, jc.self].sort());
    // B leaving: A is not told (A never saw B); C is
    const fromA = a.json.length, fromC = c.json.length;
    send(b, { t: 'leave' });
    await until(() => c.json.slice(fromC).find(m => m.t === 'left' && m.id === jb.self));
    await wait(50);
    expect(a.json.slice(fromA).some(m => m.t === 'left')).toBe(false);
  });

  it('a Block in the room takes each out of the other\'s view at once (left); an Unblock brings them back (peer)', async () => {
    const { port, hub } = await server();
    const [a, b] = await Promise.all(['player-aaaa', 'player-bbbb'].map(p => connect(port, p)));
    const ja = await join(a, 'sh_tea_1');
    const jb = await join(b, 'sh_tea_1');
    await until(() => a.json.find(m => m.t === 'peer' && m.member.id === jb.self));
    hidden.add('player-aaaa player-bbbb');
    hub.seenChanged('player-aaaa', 'player-bbbb');
    expect(await until(() => a.json.find(m => m.t === 'left' && m.id === jb.self))).toMatchObject({ count: 1 });
    expect(await until(() => b.json.find(m => m.t === 'left' && m.id === ja.self))).toMatchObject({ count: 1 });
    hidden.clear();
    const fromA = a.json.length, fromB = b.json.length;
    hub.seenChanged('player-aaaa', 'player-bbbb');
    expect(await until(() => a.json.slice(fromA).find(m => m.t === 'peer'))).toMatchObject({ count: 2, member: { id: jb.self } });
    expect(await until(() => b.json.slice(fromB).find(m => m.t === 'peer'))).toMatchObject({ count: 2, member: { id: ja.self } });
    expect(hub).toBeInstanceOf(P0OnlineHub);
  });

  it('in a pond the other\'s line is never shown', async () => {
    const { port } = await server();
    hidden.add('player-aaaa player-bbbb');
    const [a, b, c] = await Promise.all(['player-aaaa', 'player-bbbb', 'player-cccc'].map(p => connect(port, p)));
    const ja = await join(a, 'pond:pond_san_francisco_03');
    await join(b, 'pond:pond_san_francisco_03');
    await join(c, 'pond:pond_san_francisco_03');
    send(a, { t: 'fish', epoch: ja.epoch, phase: 'casting', target: [6, -5] });
    await until(() => c.json.find(m => m.t === 'fishing' && m.members.some((l: any) => l.id === ja.self)));
    await wait(LIMITS.snapshot_ms * LIMITS.fishing_ticks + 50);
    expect(b.json.filter(m => m.t === 'fishing').every(m => !m.members.some((l: any) => l.id === ja.self))).toBe(true);
  });
});
