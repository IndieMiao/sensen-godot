import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { Client, appFor, memory, seed } from './helpers.js';
import { onlineGateways } from '../../src/realtime/gateway.js';

let app: FastifyInstance;
const peers: Client[] = [];
afterEach(async () => { peers.splice(0).forEach(p => p.close()); await app?.close(); });
async function harness() {
  const store = memory();
  const a = await seed(store, { layout: 'sh_b' }), b = await seed(store, { region: 'los_angeles', layout: 'la_a' }), outsider = await seed(store);
  for (const account of [a, b]) (await store.farmByOwner(account.player))!.visit_access = 'only_me';
  app = await appFor(store);
  const base = await app.listen({ host: '127.0.0.1', port: 0 });
  const gateway = onlineGateways.get(app)!;
  const group = await gateway.party(a.player, 'create'); await gateway.party(b.player, 'join', group.party!.code);
  const connect = async (who: typeof a) => {
    const peer = new Client(base.replace('http:', 'ws:') + '/v1/online'); peers.push(peer);
    await peer.connect(who.token); return peer;
  };
  const request = (who: typeof a, method: 'GET' | 'POST', url: string, payload?: object) => app.inject({
    method, url, headers: { authorization: 'Bearer ' + who.token }, ...(payload ? { payload } : {}) });
  return { store, a, b, outsider, gateway, connect, request };
}

describe('party travel across regions', () => {
  it('normalizes legacy street joins to private farms and requires owner opt-in before travel', async () => {
    const { a, b, store, gateway, connect, request } = await harness();
    const ca = await connect(a), cb = await connect(b);
    const leader = await ca.join('street', { channel: 7 });
    const own = await cb.join('street'); expect(own.room).not.toBe(leader.room);
    expect((await request(b, 'POST', '/v1/online/travel', { mode: 'leader' })).json().code).toBe('PARTY_ACCESS_REQUIRED');
    await gateway.party(a.player, 'farm_access', 'allow');
    const prepared = await request(b, 'POST', '/v1/online/travel', { mode: 'leader' });
    expect(prepared.statusCode).toBe(200);
    const destination = prepared.json();
    expect(destination).toMatchObject({ kind: 'farm', channel: 7, layout_patch_id: 'sh_b', blueprint_revision: 2 });
    expect(destination.snapshot.cells).toBeDefined();
    cb.send({ t: 'leave' }); await cb.next('departed');
    expect((await cb.join('street', { travel_ticket: destination.ticket })).room).toBe(leader.room);
    expect((await store.farmByOwner(b.player))!.region_id).toBe('los_angeles');
    expect((await store.farmByOwner(b.player))!.layout_patch_id).toBe('la_a');
  });

  it('requires owner opt-in for a private farm and grants a visitor DTO rather than owner state', async () => {
    const { a, b, outsider, store, gateway, connect, request } = await harness();
    const ca = await connect(a), cb = await connect(b);
    const leader = await ca.join('farm', { channel: 4 });
    expect((await request(b, 'POST', '/v1/online/travel', { mode: 'leader' })).json().code).toBe('PARTY_ACCESS_REQUIRED');
    await gateway.party(a.player, 'farm_access', 'allow');
    const prepared = (await request(b, 'POST', '/v1/online/travel', { mode: 'farm', target: a.player })).json();
    expect(prepared).toMatchObject({ farm_id: a.farm.id, channel: 4, layout_patch_id: 'sh_b' });
    expect(prepared.snapshot.cells).toBeDefined();
    for (const secret of ['state', 'inventory', 'wallet', 'character', 'owner_id']) expect(prepared.snapshot[secret]).toBeUndefined();
    expect((await cb.join('farm', { travel_ticket: prepared.ticket })).room).toBe(leader.room);
    expect((await request(b, 'GET', '/v1/farms/' + a.farm.id + '/snapshot')).statusCode).toBe(200);
    expect((await request(outsider, 'GET', '/v1/farms/' + a.farm.id + '/snapshot')).statusCode).toBe(404);
    expect((await store.farmByOwner(a.player))!.visit_access).toBe('only_me');
  });

  it('revokes an admitted private-farm visitor when the owner disables sharing', async () => {
    const { a, b, gateway, connect, request } = await harness();
    await gateway.party(a.player, 'farm_access', 'allow');
    const cb = await connect(b);
    await cb.join('farm', { farm_id: a.farm.id });
    const closed = new Promise<number>(resolve => cb.ws.once('close', resolve));
    await gateway.party(a.player, 'farm_access', 'deny');
    expect(await closed).toBe(4004);
    expect((await request(b, 'GET', '/v1/farms/' + a.farm.id + '/snapshot')).statusCode).toBe(404);
  });

  it('leaving the party invalidates travel tickets and private farm permission', async () => {
    const { a, b, gateway, connect, request } = await harness();
    await gateway.party(a.player, 'farm_access', 'allow');
    const destination = (await request(b, 'POST', '/v1/online/travel', { mode: 'farm', target: a.player })).json();
    await gateway.party(b.player, 'leave');
    const cb = await connect(b); cb.send({ t: 'join', kind: 'farm', travel_ticket: destination.ticket });
    expect((await cb.next('error')).code).toBe('PARTY_CHANGED');
    expect((await request(b, 'GET', '/v1/farms/' + a.farm.id + '/snapshot')).statusCode).toBe(404);
  });

  it('admits the member to the inside leader current mine floor only after an explicit re-entry', async () => {
    const { a, b, connect, gateway, store, request } = await harness();
    const ca = await connect(a), cb = await connect(b);
    const leader = await ca.join('mine');
    gateway.rooms.get(leader.room)!.members.get(a.player)!.floor = 3;
    const oldBinding = (await store.realtimeDirectory(b.player)).instance;
    const destination = (await request(b, 'POST', '/v1/online/travel', { mode: 'leader' })).json();
    expect(destination.floor).toBe(3);
    expect((await store.realtimeDirectory(b.player)).instance).toBe(oldBinding);
    const entered = await cb.join('mine', { travel_ticket: destination.ticket });
    expect(entered.room).toBe(leader.room); expect(entered.floor).toBe(3);
  });

  it('rejects a stale destination after the leader changes floor without changing the member binding', async () => {
    const { a, b, connect, gateway, store, request } = await harness();
    const ca = await connect(a), cb = await connect(b);
    const joined = await ca.join('mine');
    const destination = (await request(b, 'POST', '/v1/online/travel', { mode: 'leader' })).json();
    const m = gateway.rooms.get(joined.room)!.members.get(a.player)!;
    m.floor = 3; m.epoch++;
    cb.send({ t: 'join', kind: 'mine', travel_ticket: destination.ticket });
    expect((await cb.next('error')).code).toBe('DESTINATION_CHANGED');
    expect((await store.realtimeDirectory(b.player)).instance).toBe('');
  });

  it('does not inherit an outside leader historical mine and cannot follow another member into a mine', async () => {
    const { a, b, gateway, connect, request } = await harness();
    const ca = await connect(a), cb = await connect(b);
    await ca.join('mine'); ca.send({ t: 'leave' }); await ca.next('departed');
    expect((await request(b, 'POST', '/v1/online/travel', { mode: 'leader' })).json().code).toBe('TARGET_OFFLINE');
    await ca.join('street'); await cb.join('mine');
    await gateway.party(a.player, 'farm_access', 'allow');
    expect((await request(a, 'POST', '/v1/online/travel', { mode: 'follow', target: b.player })).json().code).toBe('FOLLOW_LEADER_MINE');
    expect((await request(b, 'POST', '/v1/online/travel', { mode: 'leader' })).json().kind).toBe('farm');
    await gateway.party(a.player, 'leader', b.player);
    expect((await request(a, 'POST', '/v1/online/travel', { mode: 'leader' })).json().kind).toBe('mine');
  });

  it('rejects a ticket used by another account and reports only current group positions', async () => {
    const { a, b, outsider, gateway, connect, request } = await harness();
    const ca = await connect(a); await ca.join('street', { channel: 9 });
    const status = (await request(b, 'GET', '/v1/online/status')).json();
    expect(status.roster.find((row: { player: string }) => row.player === a.player)).toMatchObject({ online: true, scene: { kind: 'farm', channel: 9, layout_patch_id: 'sh_b' } });
    expect(status.roster).toHaveLength(2);
    await gateway.party(a.player, 'farm_access', 'allow');
    const destination = (await request(b, 'POST', '/v1/online/travel', { mode: 'leader' })).json();
    const wrong = await connect(outsider); wrong.send({ t: 'join', kind: 'street', travel_ticket: destination.ticket });
    expect((await wrong.next('error')).code).toBe('TRAVEL_EXPIRED');
    expect((await request(outsider, 'GET', '/v1/online/status')).json().roster).toEqual([]);
  });
});
