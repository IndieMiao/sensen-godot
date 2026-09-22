import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { Client, appFor, memory, seed } from './helpers.js';
import { onlineGateways } from '../../src/realtime/gateway.js';
import { defaultAppearance } from '../../src/realtime/appearance.js';

let app: FastifyInstance | undefined;
const clients: Client[] = [];
afterEach(async () => { clients.splice(0).forEach(c => c.close()); await app?.close(); app = undefined; });
const look = (cloth: string, extras = {}) => ({ version: 1, slots: { ...defaultAppearance().slots, cloth, ...extras } });
async function harness() {
  const store = memory(); app = await appFor(store);
  const url = (await app.listen({ port: 0, host: '127.0.0.1' })).replace('http:', 'ws:') + '/v1/online';
  const connect = async (token: string) => { const c = new Client(url); clients.push(c); await c.connect(token); return c; };
  return { store, connect, gateway: onlineGateways.get(app)! };
}
describe('cosmetic appearance over real WebSocket', () => {
  it.each(['street', 'farm', 'mine'])('sends actual clothes to existing and later peers in %s', async kind => {
    const { store, connect, gateway } = await harness();
    const a = await seed(store), b = await seed(store), c = await seed(store);
    const party = await gateway.party(a.player, 'create');
    for (const account of [b, c]) await gateway.party(account.player, 'join', party.party!.code);
    const ca = await connect(a.token), cb = await connect(b.token), cc = await connect(c.token);
    const options = kind !== 'mine' ? { farm_id: a.farm.id } : {}; // Legacy street joins use the selected private farm.
    const outfit = look('cloth1', { hairHat: 'hairhat20', shoes: 'shoes1' });
    await ca.join(kind, { ...options, appearance: outfit }); await cb.join(kind, options);
    expect((await cb.next('roster')).members.find((m: any) => m.player === a.player).appearance).toEqual(outfit);
    expect((await ca.next('peer', p => p.member?.player === b.player)).member.appearance).toEqual(defaultAppearance());
    const before = structuredClone((await store.farmByOwner(a.player))!.state);
    ca.send({ t: 'appearance', player: b.player, appearance: look('cloth11') });
    expect((await ca.next('appearance_result')).ok).toBe(true);
    expect((await cb.next('peer', p => p.member?.player === a.player)).member.appearance).toEqual(look('cloth11'));
    await cc.join(kind, options);
    const roster = (await cc.next('roster')).members;
    expect(roster.find((m: any) => m.player === a.player).appearance).toEqual(look('cloth11'));
    expect(roster.find((m: any) => m.player === b.player).appearance).toEqual(defaultAppearance());
    expect((await store.farmByOwner(a.player))!.state).toEqual(before);
  });
  it('rejects invalid/slot-mismatched/path appearances before creating a mine binding', async () => {
    const { store, connect } = await harness(); const a = await seed(store), ca = await connect(a.token);
    for (const appearance of [look('res://secret'), look('hairhat20'), look(''), { version: 2, slots: {} },
      { version: 1, slots: { ...defaultAppearance().slots, hp: 999 } }, { version: 1, slots: [] }]) {
      ca.send({ t: 'join', kind: 'mine', appearance });
      expect((await ca.next('error')).code).toBe('APPEARANCE_INVALID');
      expect((await store.realtimeDirectory(a.player)).instance).toBe('');
    }
    await ca.join('mine', { appearance: look('cloth1') });
    ca.send({ t: 'appearance', appearance: look('shoes1') });
    expect((await ca.next('appearance_result')).code).toBe('APPEARANCE_INVALID');
    ca.send({ t: 'ping' }); expect((await ca.next('pong')).time).toBeDefined();
  });
  it('restores the published outfit on reconnect and sends it with a floor roster', async () => {
    const { store, connect, gateway } = await harness(); const a = await seed(store);
    const ca = await connect(a.token), outfit = look('cloth11', { hairHat: 'hairhat41' });
    const joined = await ca.join('mine', { appearance: outfit });
    ca.close();
    const restored = await connect(a.token);
    const resumed = await restored.join('mine', { resume: joined.resume, appearance: outfit });
    expect(resumed.room).toBe(joined.room);
    const room = gateway.rooms.get(joined.room)!, m = room.members.get(a.player)!;
    m.floor = 3; room.roster(m);
    expect((await restored.next('roster', r => r.members[0]?.floor === 3)).members[0].appearance).toEqual(outfit);
  });
  it('bounds update floods without replacing the last accepted appearance', async () => {
    const { store, connect, gateway } = await harness(); const a = await seed(store), ca = await connect(a.token);
    const joined = await ca.join('street');
    ca.send({ t: 'appearance', appearance: look('cloth1') }); expect((await ca.next('appearance_result')).ok).toBe(true);
    ca.send({ t: 'appearance', appearance: look('cloth11') }); expect((await ca.next('appearance_result')).code).toBe('APPEARANCE_RATE_LIMIT');
    expect(gateway.rooms.get(joined.room)!.members.get(a.player)!.appearance).toEqual(look('cloth1'));
  });
});
