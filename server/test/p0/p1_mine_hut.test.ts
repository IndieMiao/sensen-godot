/**
 * q(204) (SGODOT-308): the Mine Hut goes live. One per highland city of tier M1 and up (only Denver today, `Golden
 * Mine Hut`, west toward the foothills via world.overrides), placed after every other place and named at its final
 * point; sent as detail.huts, never as an outpost. Ivo lives there alone, outside the outposts' slots and the
 * fixed-resident cap; his pin, ◆ and Today point there once Denver has been visited, whatever the home city, and a
 * home change keeps his request. The hut is entered like an outpost (fog, Day Pass) and gets an online room.
 */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { cityHuts, hutCities, residentPlace } from '../../src/p0/home_city.js';
import { mapMarkers } from '../../src/p0/markers.js';
import { generatedOutpostSpec, loadOutposts } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { viewOf } from '../../src/p0/view.js';
import { cityPlaces, generateCity, km, roomPlace, worldOf } from '../../src/p0/world.js';

const c: P0Content = loadP0Content();
const w = worldOf(c)!;
const DENVER = 'gn-5419384', HUT = `${DENVER}~hut0`, TOKYO = 'gn-1850147', SF = 'gn-5391959';
const H = 3_600_000, DAY = 24 * H;
const T = Date.UTC(2026, 9, 16, 18, 0);
const clusters = (c as P0Content & { clusters: { get(id: string): import('../../src/p0/clusters.js').CityCluster | undefined } }).clusters;
const run = (s: P0State, cmd: Record<string, unknown>, at = T) => applyP0(c, s, cmd as unknown as P0Command, at);
const visit = (s: P0State, city: string) => { s.travel.visits[city] = { n: 1, first_at: T - H, last_at: T - H, deliveries: 0, delivered_day: '' }; };
/** A save past the first session (the tutorial request only shows tracked markers). */
const save = (id: string) => { const s = freshState(c, id, T - DAY, 5); s.boards.stall = []; return s; };

describe('the Mine Hut (q(204))', () => {
  it('Denver has one, Golden Mine Hut, west toward Golden; Ivo lives there; it is no outpost', () => {
    const city = cityPlaces(c, DENVER)!;
    expect(city.tier).toBe('M1');
    expect(city.detail.huts).toEqual([{ id: HUT, role: 'mine_hut', name: 'Golden Mine Hut', lat: 39.7512, lng: -105.1592,
      category: 'Mine hut · Old miner', keeper: null, residents: ['res_ivo'], art: 'mine_hut',
      anchors: 'res://assets/p0/outposts/mine_hut.anchors.json', capacity: w.rooms.indoor_cap }]);
    expect(city.outposts).not.toContain(HUT);
    expect(city.outposts).toHaveLength(6);
    expect(city.detail.outposts.some(o => o.residents.includes('res_ivo'))).toBe(false);
    expect(city.residents).toBe(6);   // the city card: Pip, Sam, Nadia, Theo, Hana and Ivo
    expect(hutCities(c)).toEqual([DENVER]);
    expect(cityHuts(c, TOKYO)).toEqual([]);
    expect(cityPlaces(c, TOKYO)!.detail.huts).toEqual([]);
  });

  it('by rule: a highland city of M1 and up gets one on the 8 km ring, 300 m clear, named `<place> Mine Hut`; not S tier, not without the room', () => {
    const cl = clusters.get(TOKYO)!;
    w.coastal[TOKYO] = [...(w.coastal[TOKYO] ?? []), 'highland'];
    try {
      const city = generateCity(c, cl);
      expect(city.detail.huts).toHaveLength(1);
      const hut = city.detail.huts[0];
      expect(hut.id).toBe(`${TOKYO}~hut0`);
      expect(km(cl, hut)).toBeGreaterThanOrEqual(w.placement.hut!.ring_km - 0.05);   // the ring is laid flat (world.ts offset)
      for (const p of [...city.detail.ponds, ...city.detail.outposts]) expect(km(p, hut)).toBeGreaterThanOrEqual(0.3);
      expect(hut.name).toMatch(/^[^0-9]+ Mine Hut$/);
      expect(hut.name.length).toBeLessThanOrEqual(24);
      expect(city.detail.outposts.map(o => o.name)).not.toContain(hut.name);
      expect(hut.residents).toEqual(['res_ivo']);
      // nowhere that fits (every ring point within 300 m of a place): no hut rather than one breaking the rules
      const placement = w.placement;
      w.placement = { ...placement, other_kind_min_m: 50_000 };
      try { expect(generateCity(c, cl).detail.huts).toEqual([]); } finally { w.placement = placement; }
      const room = w.room.mine_hut;
      delete w.room.mine_hut;
      try {
        expect(generateCity(c, cl).detail.huts).toEqual([]);   // not live: no hut, and Ivo nowhere
        expect(generateCity(c, cl).detail.outposts.some(o => o.residents.includes('res_ivo'))).toBe(false);
      } finally { w.room.mine_hut = room; }
    } finally { w.coastal[TOKYO] = w.coastal[TOKYO].filter(t => t !== 'highland'); }
    const small = [...(c as P0Content & { clusters: { byId: Map<string, import('../../src/p0/clusters.js').CityCluster> } }).clusters.byId.values()]
      .find(x => x.id !== SF && generateCity(c, x).tier === 'S')!;
    w.coastal[small.id] = ['highland'];
    try { expect(generateCity(c, small).detail.huts).toEqual([]); }
    finally { delete w.coastal[small.id]; }
  });

  it('Ivo is found at the hut, whatever the home city (view.residents[id].place)', () => {
    const s = save('player-hut-01');
    expect(residentPlace(c, s, 'res_ivo')).toBe(HUT);
    expect(residentPlace(c, s, 'res_pip')).toBe(viewOf(c, s, T).home.set?.post);
    const v = viewOf(c, s, T) as unknown as { residents: Record<string, { place: string | null }> };
    expect(v.residents.res_ivo.place).toBe(HUT);
    expect(v.residents.res_pip.place).toBe(residentPlace(c, s, 'res_pip'));
  });

  it('his marker and ◆ go on the hut only once Denver has been visited (§9.5.1)', () => {
    const s = save('player-hut-02');
    expect(mapMarkers(c, s, T).filter(m => m.place === HUT)).toEqual([]);
    visit(s, DENVER);
    expect(mapMarkers(c, s, T).find(m => m.place === HUT)).toMatchObject({ kind: 'request', why: { resident: 'res_ivo' } });
    s.residents.res_ivo = { affinity: 30, chat_day: '', gift_day: '', next: 99, req: null, done_day: '' };   // Acquainted, no request left
    expect(mapMarkers(c, s, T).find(m => m.place === HUT)).toMatchObject({ kind: 'new', why: { resident: 'res_ivo' } });
  });

  it('a home change keeps his accepted request', () => {
    const s = save('player-hut-03');
    s.residents.res_ivo = { affinity: 0, chat_day: '', gift_day: '', next: 0, req: { id: 'req_res_ivo_1', at: T - H, progress: 0 }, done_day: '' };
    const r = run(s, { type: 'change_home', city: TOKYO, spot: 0 });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.residents.res_ivo.req?.id).toBe('req_res_ivo_1');
    expect(residentPlace(c, r.state, 'res_ivo')).toBe(HUT);
  });

  it('is entered like an outpost: a pass for Denver; the city read sends it as detail.huts', async () => {
    const store = new P0Store(c);
    const app = Fastify();
    registerP0Routes(app, { content: c, store, now: () => T, dev: false });
    const hd = { 'x-p0-player': 'player-hut-04' };
    const city = (await app.inject({ method: 'GET', url: `/v1/p0/city/${DENVER}`, headers: hd })).json();
    expect(city.city.detail.huts.map((h: { id: string }) => h.id)).toEqual([HUT]);
    expect(city.city.detail.outposts.map((o: { id: string }) => o.id)).not.toContain(HUT);
    expect(city.city.preview.counts).toMatchObject({ outposts: 6, residents: 6 });
    const enter = () => app.inject({ method: 'GET', url: `/v1/p0/state?space=outpost&place=${encodeURIComponent(HUT)}`, headers: hd });
    expect((await enter()).json()).toMatchObject({ ok: false, code: 'pass_required' });
    await app.inject({ method: 'POST', url: '/v1/p0/commands', headers: hd, payload: { type: 'travel', to: DENVER } });
    expect((await enter()).json()).toMatchObject({ ok: true });
    await app.close();
  });

  it('gets an online room with its own walls (no hand-written room stands in for it)', () => {
    const table = loadOutposts();
    const rooms = new OutpostRooms(table, Date.now, generatedOutpostSpec(table, id => roomPlace(c, id)));
    expect(rooms.join('player-hut-05', HUT)).toMatchObject({ outpost: HUT, room: 1, capacity: w.rooms.indoor_cap });
    expect(rooms.spec(HUT)).toMatchObject({ role: 'mine_hut', bounds: w.room.mine_hut!.bounds, seats: [] });
    expect(rooms.presence()[HUT]).toEqual({ online: 1, rooms: 1 });
    expect(() => rooms.join('player-hut-06', `${DENVER}~hut1`)).toThrow('UNKNOWN_OUTPOST');
  });

  it("is counted in its town: its pin's online count and the Tea Host's people around Denver (q(206)), gone when empty", async () => {
    const table = loadOutposts();
    const rooms = new OutpostRooms(table, Date.now, generatedOutpostSpec(table, id => roomPlace(c, id)));
    rooms.join('player-hut-07', HUT);
    const app = Fastify({ logger: false });
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => Date.now(), dev: false, rooms });
    expect(rooms.presence()[HUT]).toEqual({ online: 1, rooms: 1 });
    const hd = { 'x-p0-player': 'player-hut-08' };
    const online = async () => (await app.inject({ method: 'GET', url: '/v1/p0/state', headers: hd })).json().state.keepers.tea.online;
    expect(await online()).toBe(0);   // in San Francisco: Denver's hut is not counted there
    await app.inject({ method: 'POST', url: '/v1/p0/commands', headers: hd, payload: { type: 'travel', to: DENVER } });
    expect(await online()).toBe(1);   // in Denver: the one in the hut
    rooms.leave('player-hut-07');
    expect(rooms.presence()[HUT]).toBeUndefined();   // a generated room is let go when empty
    expect(await online()).toBe(0);
    await app.close();
  });
});
