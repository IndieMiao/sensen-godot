/** SGODOT-232: map pin markers (§9.5.2 as settled in q(48)) — what each pin shows and when it goes. */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { mapMarkers, pondFor } from '../../src/p0/markers.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type BoardRequest, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 8, 2);
const at = (s: P0State) => mapMarkers(c, s).map(m => `${m.kind}:${m.place}${m.why.tracked ? ':tracked' : ''}`);
function step(s: P0State, cmd: P0Command, now = T0): P0State {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`);
  return r.state;
}
// a first command rolls the player day in, as any real save has (resident requests wait on it)
const fresh = () => step(freshState(c, 'markers-player-01', T0), { type: 'read_inbox', keys: [] });
/** Pond Catch handed in: the first session is over. */
function afterTutorial(): P0State {
  const s = step(fresh(), { type: 'accept', request: 'req_pond_catch' });
  s.bag.push({ id: 'fish_crucian', qty: 2 });
  return step(s, { type: 'deliver', request: 'req_pond_catch' });
}

describe('map pin markers (§9.5.2, q(48); SGODOT-232)', () => {
  it('loads the outposts and pond points the markers need', () => {
    expect(c.outposts?.map(o => o.id)).toEqual(expect.arrayContaining(['sh_tackle_1', 'sh_tea_1', 'sh_post_1', 'sh_market_1']));
    expect(c.outposts?.find(o => o.id === 'sh_post_1')?.residents).toContain('res_pip');
    expect(c.fishing.places.pond_shanghai_05.at).toHaveLength(2);
  });

  it('a tracked fish request points to the beginner pond until the bag holds it, then the hand-in point shows ✓', () => {
    let s = fresh();
    expect(at(s)).not.toContain('request:pond_shanghai_05:tracked');   // Pond Catch not taken yet: the ! is on the farm's stall
    s = step(s, { type: 'accept', request: 'req_pond_catch' });
    expect(at(s)[0]).toBe('request:pond_shanghai_05:tracked');   // §14.2 minute 3–5: Reed Pond's gold !
    s.bag.push({ id: 'fish_crucian', qty: 2 });
    expect(at(s)[0]).toBe('deliver:home:tracked');
    expect(at(s)).not.toContain('request:pond_shanghai_05:tracked');
    expect(viewOf(c, s, T0).map_markers[0]).toEqual({ place: 'home', kind: 'deliver', why: { request: 'req_pond_catch', tracked: true } });
  });

  it('first session: until Pond Catch is handed in only the tracked marker shows (q(48))', () => {
    let s = fresh();
    expect(at(s)).toEqual([]);   // Pip's and Old Kai's requests are open, but minutes 5–9 have one goal
    s = step(s, { type: 'accept', request: 'req_pond_catch' });
    expect(at(s)).toEqual(['request:pond_shanghai_05:tracked']);
    s.bag.push({ id: 'fish_crucian', qty: 3 });
    expect(at(s)).toEqual(['deliver:home:tracked']);   // Pip could take a crucian too: not yet
    s = step(s, { type: 'deliver', request: 'req_pond_catch' });
    expect(at(s)).toContain('deliver:sh_post_1');      // handed in: Pip's request shows, and the bag holds his fish
  });

  it('residents with an open request light their outpost; ready without taking it shows ✓ there', () => {
    const s = afterTutorial();
    expect(at(s)).toContain('request:sh_post_1');
    s.bag.push({ id: 'fish_crucian', qty: 1 });   // Pip ①: a Common fish
    expect(at(s)).toContain('deliver:sh_post_1');
  });

  it('Old Kai\'s Rare fish request lights the tackle shop only from Fishing Lv4 (Golden Koi)', () => {
    const s = afterTutorial();
    s.residents.res_pip = { affinity: 0, chat_day: '', gift_day: '', next: 99, req: null, done_day: '' };
    s.skills.fishing = 220;   // Lv3: no Rare fish yet; the Reed Rod's ◆ shows instead
    expect(mapMarkers(c, s).find(m => m.place === 'sh_tackle_1')?.kind).toBe('new');
    s.seen = ['item:rod_reed', 'item:bait_worm'];
    expect(mapMarkers(c, s).find(m => m.place === 'sh_tackle_1')).toBeUndefined();
    s.skills.fishing = 480;   // Lv4
    expect(mapMarkers(c, s).find(m => m.place === 'sh_tackle_1')).toMatchObject({ kind: 'request', why: { resident: 'res_old_kai' } });
  });

  it('a new level-gated good lights its outpost once; walking in marks it seen', () => {
    let s = afterTutorial();
    s.residents.res_old_kai = { ...(s.residents.res_old_kai ?? {}), next: 99 } as never;   // Old Kai out of requests: only ◆ can show there
    s.skills.fishing = 70;   // Fishing Lv2: Worm Bait on the tackle counter
    expect(mapMarkers(c, s).find(m => m.place === 'sh_tackle_1')).toEqual({ place: 'sh_tackle_1', kind: 'new', why: { item: 'bait_worm' } });
    s = step(s, { type: 'read_inbox', keys: [], space: 'outpost', place: 'sh_tackle_1' }, T0 + 60_000);
    expect(mapMarkers(c, s).some(m => m.place === 'sh_tackle_1')).toBe(false);
    s.skills.fishing = 220;   // Lv3: the Reed Rod is new again
    expect(mapMarkers(c, s).find(m => m.place === 'sh_tackle_1')?.why).toEqual({ item: 'rod_reed' });
    s.skills.farming = 300;   // Farming Lv4: the Row Hoe at the market square
    expect(mapMarkers(c, s).find(m => m.place === 'sh_market_1')?.why).toEqual({ item: 'tool_row_hoe' });
  });

  it('the entry read of an outpost also marks it seen', async () => {
    const { default: Fastify } = await import('fastify');
    const { registerP0Routes } = await import('../../src/p0/routes.js');
    const { P0Store } = await import('../../src/p0/store.js');
    const store = new P0Store(c);
    const app = Fastify();
    registerP0Routes(app, { content: c, store, now: () => T0, dev: false });
    try {
      const s = store.get('markers-player-02', T0);
      s.boards.stall = [];   // past the first session (Pond Catch gone from the board)
      s.skills.fishing = 70;
      s.residents.res_old_kai = { ...(s.residents.res_old_kai ?? {}), next: 99 } as never;
      store.put(s);
      const before = (await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { 'x-p0-player': 'markers-player-02' } })).json();
      expect(before.state.map_markers.some((m: { place: string }) => m.place === 'sh_tackle_1')).toBe(true);
      const inside = (await app.inject({ method: 'GET', url: '/v1/p0/state?space=outpost&place=sh_tackle_1', headers: { 'x-p0-player': 'markers-player-02' } })).json();
      expect(inside.state.map_markers.some((m: { place: string }) => m.place === 'sh_tackle_1')).toBe(false);
    } finally { await app.close(); }
  });

  it('a resident at Acquainted opens a second page of talk: ◆ at their outpost', () => {
    const s = afterTutorial();
    s.residents.res_pip = { ...(s.residents.res_pip ?? {}), affinity: 15, next: 99 } as never;
    expect(mapMarkers(c, s).find(m => m.place === 'sh_post_1')).toEqual({ place: 'sh_post_1', kind: 'new', why: { resident: 'res_pip' } });
  });

  it('picks the beginner pond when its template has the fish, else the pond nearest the farm', () => {
    expect(pondFor(c, ['fish_crucian'])).toBe('pond_shanghai_05');   // Reed Pond (beginner, Pond template)
    expect(pondFor(c, ['fish_koi'])).toBe('pond_shanghai_05');       // Golden Koi lives in Pond only
    expect(pondFor(c, ['fish_trout'])).toBe('pond_shanghai_04');     // River only: Pebble Pond is the nearest River pond
    expect(pondFor(c, ['fish_mackerel'])).toBeNull();                // Coast: no such pond in P0
  });

  it('one marker per place, deliver before request before new; old saves get an empty seen list', () => {
    let s = fresh();
    s = step(s, { type: 'accept', request: 'req_pond_catch' });
    const kinds = mapMarkers(c, s).map(m => m.kind);
    expect([...kinds].sort((a, b) => ['deliver', 'request', 'new'].indexOf(a) - ['deliver', 'request', 'new'].indexOf(b))).toEqual(kinds);
    expect(new Set(mapMarkers(c, s).map(m => m.place)).size).toBe(mapMarkers(c, s).length);
    const old = structuredClone(fresh());
    delete old.seen;
    expect(upgradeState(c, old, T0).seen).toEqual([]);
  });

  it('more counts the other reasons behind the one shown at a place; the Market Board\'s open slots are one (q(103))', () => {
    const s = afterTutorial();
    // Pip at Acquainted (a second page of talk, ◆) with his first request still open (!): two reasons at the post
    s.residents.res_pip = { affinity: 15, chat_day: '', gift_day: '', next: 0, req: null, done_day: '' };
    expect(mapMarkers(c, s).find(m => m.place === 'sh_post_1')).toMatchObject({ kind: 'request', why: { resident: 'res_pip' }, more: 1 });
    const open = (id: string): BoardRequest => ({ id, template: 'req_sys_fish_fine', items: ['fish_trout'], rarity: 2, kind: 'fish', qty: 2, bonus: 20, drawn_at: T0, status: 'open' });
    s.boards.market = [{ req: open('m1'), refill_at: 0 }, { req: open('m2'), refill_at: 0 }];
    const market = () => mapMarkers(c, s).find(m => m.place === 'sh_market_1');
    expect(market()).toMatchObject({ kind: 'request', why: { request: 'm1' } });
    expect(market()?.more).toBeUndefined();   // two open slots: one reason, the card writes `Market Board · 2 requests`
    s.skills.farming = 300;   // Farming Lv4: the Row Hoe is new at the market square
    expect(market()).toMatchObject({ kind: 'request', more: 1 });
    expect(viewOf(c, s, T0).map_markers.find(m => m.place === 'sh_post_1')?.more).toBe(1);
    expect(mapMarkers(c, afterTutorial()).every(m => m.more === undefined || m.more > 0)).toBe(true);   // never 0
  });

  it('first session: other reasons at the tracked place do not count toward more', () => {
    let s = step(fresh(), { type: 'accept', request: 'req_pond_catch' });
    s.bag.push({ id: 'fish_crucian', qty: 2 });
    expect(mapMarkers(c, s)).toEqual([{ place: 'home', kind: 'deliver', why: { request: 'req_pond_catch', tracked: true } }]);
  });
});
