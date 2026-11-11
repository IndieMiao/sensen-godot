import Fastify, { type FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { WebSocket } from 'ws';
import { FRAME_HEADER, FRAME_MEMBER } from '../../src/p0/online/frame.js';
import { PATH, registerP0Online } from '../../src/p0/online/hub.js';
import { loadOutposts, pondRoomSpec } from '../../src/p0/online/outposts.js';
import { OutpostRooms, SPAWN_FREE_M } from '../../src/p0/online/rooms.js';

// q(311) (SGODOT-470) on the wire: a newer client's first join of a visit carries its places in order (`spawns`, the spawn
// first); the server stands it on the first free one and says where in `joined.spawn` — what every other player in the
// room is told too. Those who block each other take places from each other all the same (周瑜's notes, ②).

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
async function join(c: Client, room: string, at: [number, number], spawns?: unknown) {
  const from = c.json.length;
  send(c, { t: 'join', outpost: room, at, ...(spawns !== undefined ? { spawns } : {}) });
  return until(() => c.json.slice(from).find(m => m.t === 'joined'));
}

/** A member's x, z in a snapshot frame (frame.ts: u16 id · f32 x · f32 z …), undefined when it is not in it. */
function framePos(f: Buffer, id: number): [number, number] | undefined {
  for (let i = 0; i < f.readUInt16LE(10); i++) {
    const at = FRAME_HEADER + i * FRAME_MEMBER;
    if (f.readUInt16LE(at) === id) return [f.readFloatLE(at + 2), f.readFloatLE(at + 6)];
  }
  return undefined;
}
const SPAWN: [number, number] = [0.5, 1.5];
const RING: [number, number][] = [SPAWN, [1.25, 1.5], [-0.25, 1.5], [1.0, 2.15], [0.0, 2.15]];

describe('newcomers stand apart (q(311), SGODOT-470)', () => {
  it('each newer client on the first free place, told in joined.spawn; the others\' frames have it there', async () => {
    const { port } = await server();
    const [a, b, c] = await Promise.all(['player-aaaa', 'player-bbbb', 'player-cccc'].map(p => connect(port, p)));
    expect((await join(a, 'sh_tea_1', SPAWN, RING)).spawn).toEqual(SPAWN);
    const jb = await join(b, 'sh_tea_1', SPAWN, RING);
    expect(jb.spawn).toEqual(RING[1]);
    expect((await join(c, 'sh_tea_1', SPAWN, RING)).spawn).toEqual(RING[2]);
    // positions travel in the frames: A's next one has B on its place (B has sent no input yet)
    const from = a.frames.length;
    const where = await until(() => a.frames.slice(from).map(f => framePos(f, jb.self)).find(p => p));
    expect(where[0]).toBeCloseTo(RING[1][0]);
    expect(where[1]).toBeCloseTo(RING[1][1]);
  });

  it('those who block each other take places from each other all the same', async () => {
    const { port } = await server();
    hidden.add('player-aaaa player-bbbb');
    const [a, b] = await Promise.all(['player-aaaa', 'player-bbbb'].map(p => connect(port, p)));
    expect((await join(a, 'sh_tea_1', SPAWN, RING)).spawn).toEqual(SPAWN);
    const jb = await join(b, 'sh_tea_1', SPAWN, RING);
    expect(jb.spawn).toEqual(RING[1]);   // not on A, whom B does not see
    expect(Math.hypot(jb.spawn[0] - SPAWN[0], jb.spawn[1] - SPAWN[1])).toBeGreaterThanOrEqual(SPAWN_FREE_M);
  });

  it('an older client (no spawns) stands where it says; pairs that are not two numbers are dropped', async () => {
    const { port } = await server();
    const [a, b, c] = await Promise.all(['player-aaaa', 'player-bbbb', 'player-cccc'].map(p => connect(port, p)));
    await join(a, 'sh_tea_1', SPAWN, RING);
    expect((await join(b, 'sh_tea_1', SPAWN)).spawn).toEqual(SPAWN);   // on A, as before q(311)
    const junk = [SPAWN, 'x', [1], [NaN, 1], [1, 'y'], null, [1.25, 1.5]];
    const jc = await join(c, 'sh_tea_1', SPAWN, junk);
    expect(jc.spawn).toEqual([1.25, 1.5]);
  });
});
