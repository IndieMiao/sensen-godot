/**
 * q(206): the Tea Host's `N people around <town> right now` counts the people in the outpost rooms of the town the
 * player is in — the town's pins' counts summed, not every room in the world — and the player once they have walked
 * into one of its outposts, though the room has not seen them yet (the state read comes before the WebSocket join).
 */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { generatedOutpostSpec, loadOutposts } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';
import { cityPlaces } from '../../src/p0/world.js';

const c = loadP0Content();
const TOKYO = 'gn-1850147';

describe("the Tea Host's count by town (q(206))", () => {
  it('counts the town the player is in, and the player who has walked in before the room has them', async () => {
    const table = loadOutposts();
    const rooms = new OutpostRooms(table, Date.now, generatedOutpostSpec(table, id => cityPlaces(c, id.slice(0, id.indexOf('~')))?.detail.outposts.find(o => o.id === id)));
    const tokyoTea = cityPlaces(c, TOKYO)!.detail.outposts.find(o => o.role === 'tea')!.id;
    rooms.join('player-other-a', 'sh_tea_1');
    rooms.join('player-other-b', 'sh_market_1');
    rooms.join('player-other-c', tokyoTea);
    const app = Fastify();
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => Date.now(), dev: false, rooms });
    const hd = { 'x-p0-player': 'player-tea-01' };
    const online = async (url: string) => (await app.inject({ method: 'GET', url, headers: hd })).json().state.keepers.tea.online;

    expect(await online('/v1/p0/state')).toBe(2);   // San Francisco's two, not Tokyo's
    const pond = Object.keys(c.fishing.places)[0];
    expect(await online(`/v1/p0/state?space=pond&place=${pond}`)).toBe(2);   // at one of its ponds: not in an outpost
    expect(await online('/v1/p0/state?space=outpost&place=sh_tea_1')).toBe(3);   // walked in: counted before the join
    rooms.join('player-tea-01', 'sh_tea_1');
    expect(await online('/v1/p0/state?space=outpost&place=sh_tea_1')).toBe(3);   // in the room: still once
    rooms.leave('player-tea-01');

    await app.inject({ method: 'POST', url: '/v1/p0/commands', headers: hd, payload: { type: 'travel', to: TOKYO } });
    expect(await online(`/v1/p0/state?space=outpost&place=${encodeURIComponent(tokyoTea)}`)).toBe(2);   // Tokyo's one and the player
    await app.close();
  });

  it('is not known without the rooms', async () => {
    const app = Fastify();
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => Date.now(), dev: false });
    const r = (await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { 'x-p0-player': 'player-tea-02' } })).json();
    expect(r.state.keepers.tea.online).toBeNull();
    await app.close();
  });
});
