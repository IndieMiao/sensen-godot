/** SGODOT-280: a generated outpost's realtime room is made on first join from the generator's detail, walled like the
 * hand-written room its art stands in for, and let go once it empties; the WS join still needs a pass (requirePass). */
import Fastify from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { WebSocket } from 'ws';
import { loadP0Content } from '../../src/p0/content.js';
import { PATH, registerP0Online } from '../../src/p0/online/hub.js';
import { generatedOutpostSpec, loadOutposts } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';
import { requirePass } from '../../src/p0/travel.js';
import { cityPlaces } from '../../src/p0/world.js';

const c = loadP0Content();
const table = loadOutposts();
const TOKYO = 'gn-1850147';
const detailOf = (id: string) => cityPlaces(c, id.slice(0, id.indexOf('~')))?.detail.outposts.find(o => o.id === id);
const resolve = generatedOutpostSpec(table, detailOf);

describe('generated outpost rooms (SGODOT-280)', () => {
  it('a Tokyo square gets its room on first join, sized by the generator, walled like the placeholder room', () => {
    const market = cityPlaces(c, TOKYO)!.detail.outposts.find(o => o.role === 'market')!;
    const placeholder = table.find(o => o.art === market.art)!;
    const rooms = new OutpostRooms(table, Date.now, resolve);
    expect(rooms.spec(market.id)).toBeUndefined();
    const placed = rooms.join('player-gen-01', market.id);
    expect(placed).toMatchObject({ outpost: market.id, room: 1, capacity: market.capacity });
    expect(rooms.spec(market.id)).toMatchObject({ role: 'market', bounds: placeholder.bounds, seats: placeholder.seats });
    expect(rooms.presence()[market.id]).toEqual({ online: 1, rooms: 1 });
    rooms.join('player-gen-02', market.id);
    rooms.leave('player-gen-01');
    expect(rooms.spec(market.id)).toBeDefined();   // someone is still there
    rooms.leave('player-gen-02');
    expect(rooms.spec(market.id)).toBeUndefined();   // empty: let go, made again on the next join
    expect(rooms.presence()[market.id]).toBeUndefined();
    expect(rooms.presence().sh_market_1).toEqual({ online: 0, rooms: 0 });   // hand-written ones stay listed
    expect(rooms.join('player-gen-01', market.id).room).toBe(1);
  });

  it('ids the generator does not know stay unknown; the hand-written table is untouched', () => {
    const rooms = new OutpostRooms(table, Date.now, resolve);
    expect(() => rooms.join('player-gen-03', `${TOKYO}~market99`)).toThrow('UNKNOWN_OUTPOST');
    expect(() => rooms.join('player-gen-03', 'gn-1~market0')).toThrow('UNKNOWN_OUTPOST');
    expect(() => rooms.join('player-gen-03', 'nowhere')).toThrow('UNKNOWN_OUTPOST');
    expect(rooms.join('player-gen-03', 'sh_tea_1').outpost).toBe('sh_tea_1');
    rooms.leave('player-gen-03');
    expect(rooms.spec('sh_tea_1')).toBeDefined();
  });

  it('over WebSocket: no pass is refused (PASS_REQUIRED); after travel the generated room joins', async () => {
    const store = new P0Store(c);
    const rooms = new OutpostRooms(table, Date.now, resolve);
    const app = Fastify();
    registerP0Routes(app, { content: c, store, now: () => Date.now(), dev: false });
    const pass = (player: string, outpost: string) => {
      const s = store.peek(player);
      const r = s ? requirePass(c, s, 'outpost', outpost, Date.now() + s.clock_ms, s.presence.entered === outpost ? 'rejoin' : undefined) : null;
      return r ? r.code.toUpperCase() : null;
    };
    registerP0Online(app, { rooms, pass });
    await app.listen({ port: 0, host: '127.0.0.1' });
    const port = (app.server.address() as { port: number }).port;
    const player = 'player-gen-ws1';
    const H = { 'x-p0-player': player };
    await app.inject({ method: 'GET', url: '/v1/p0/state', headers: H });
    const outpost = cityPlaces(c, TOKYO)!.detail.outposts.find(o => o.role === 'tea')!.id;
    const ws = new WebSocket(`ws://127.0.0.1:${port}${PATH}`, { headers: H });
    const got: Record<string, any>[] = [];
    ws.on('message', (d, binary) => { if (!binary) got.push(JSON.parse(String(d))); });
    await new Promise(r => ws.once('open', r));
    const wait = async (pred: (m: Record<string, any>) => boolean) => {
      for (let i = 0; i < 100; i++) { const m = got.find(pred); if (m) return m; await new Promise(r => setTimeout(r, 20)); }
      throw new Error('no message');
    };
    ws.send(JSON.stringify({ t: 'join', outpost }));
    expect(await wait(m => m.t === 'error')).toMatchObject({ code: 'PASS_REQUIRED' });
    await app.inject({ method: 'POST', url: '/v1/p0/commands', headers: H, payload: { type: 'travel', to: TOKYO } });
    ws.send(JSON.stringify({ t: 'join', outpost }));
    expect(await wait(m => m.t === 'joined')).toMatchObject({ outpost, room: 1, capacity: 12 });
    ws.terminate();
    await app.close();
  });
});
