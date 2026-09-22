import { afterEach, describe, expect, it } from 'vitest';
import { onlineGateways } from '../../src/realtime/gateway.js';
import { Client, appFor, memory, seed, content } from './helpers.js';
import type { FastifyInstance } from 'fastify';

const clients: Client[] = [];
let app: FastifyInstance | undefined;
afterEach(async () => { clients.splice(0).forEach(c => c.close()); await app?.close(); app = undefined; });
async function connect(url: string, token: string) {
  const client = new Client(url); clients.push(client); await client.connect(token); return client;
}
async function harness() {
  const store = memory(); app = await appFor(store);
  const url = (await app.listen({ port: 0, host: '127.0.0.1' })).replace('http:', 'ws:') + '/v1/online';
  return { store, url, gateway: onlineGateways.get(app)! };
}

describe('live WebSocket instances and party binding', () => {
  it('isolates solo mines, never teleports on grouping, and inherits only after re-entry while the leader is inside', async () => {
    const { store, url, gateway } = await harness();
    const a = await seed(store), b = await seed(store);
    const ca = await connect(url, a.token), cb = await connect(url, b.token);
    const ra = await ca.join('mine'), rb = await cb.join('mine');
    expect(ra.room).not.toBe(rb.room);
    const leaderRoom = gateway.rooms.get(ra.room)!;
    leaderRoom.mine.floors['3'].cleared = true;
    const originalB = gateway.rooms.get(rb.room)!;
    leaderRoom.members.get(a.player)!.floor = 3; originalB.members.get(b.player)!.floor = 3;
    const party = await gateway.party(a.player, 'create');
    await gateway.party(b.player, 'join', party.party!.code);
    expect(originalB.members.has(b.player)).toBe(true);
    expect(leaderRoom.members.has(b.player)).toBe(false);
    expect((await store.realtimeDirectory(b.player)).instance).toBe(rb.room.slice(5));
    cb.send({ t: 'leave' }); await cb.next('departed');
    const joined = await cb.join('mine');
    expect(joined.room).toBe(ra.room);
    const world = await cb.next('world', m => m.instance === ra.room.slice(5));
    expect(world.cleared).toContain(3);
    expect(joined.floor).toBe(3);
    expect((await store.realtimeDirectory(b.player)).instance).toBe(ra.room.slice(5));
    expect(originalB.members.size).toBe(0);
  });
  it('does not copy an outside leader\'s historical progress into a new member instance', async () => {
    const { store, url, gateway } = await harness();
    const a = await seed(store), b = await seed(store), c = await seed(store);
    const ca = await connect(url, a.token), cb = await connect(url, b.token);
    const ra = await ca.join('mine');
    const party = await gateway.party(a.player, 'create');
    await gateway.party(b.player, 'join', party.party!.code);
    ca.send({ t: 'leave' }); await ca.next('departed');
    const rb = await cb.join('mine');
    expect(rb.room).not.toBe(ra.room);
    const cbWorld = await cb.next('world');
    expect(cbWorld.cleared).toEqual([]);
    // A non-leader in a mine is never the source for a third member's binding.
    await gateway.party(c.player, 'join', party.party!.code);
    const cc = await connect(url, c.token);
    expect((await cc.join('mine')).room).not.toBe(rb.room);
  });
  it('does not accept a client supplied instance ID or enter a private farm', async () => {
    const { store, url } = await harness();
    const a = await seed(store), b = await seed(store);
    const ca = await connect(url, a.token), cb = await connect(url, b.token);
    const leader = await ca.join('mine');
    const intruder = await cb.join('mine', { instance: leader.room.slice(5) });
    expect(intruder.room).not.toBe(leader.room);
    cb.send({ t: 'leave' }); await cb.next('departed');
    (await store.farmByOwner(a.player))!.visit_access = 'only_me';
    cb.send({ t: 'join', kind: 'farm', farm_id: a.farm.id });
    expect((await cb.next('error')).code).toBe('NOT_FOUND');
  });
  it('sends real binary motion/health snapshots and removes a disconnected remote avatar', async () => {
    const { store, url } = await harness();
    const a = await seed(store), b = await seed(store);
    const ca = await connect(url, a.token), cb = await connect(url, b.token);
    await ca.join('farm', { farm_id: a.farm.id }); await cb.join('farm', { farm_id: a.farm.id });
    const peer = await ca.next('peer', m => m.member?.player === b.player);
    expect(peer.count).toBe(2);
    cb.send({ t: 'input', seq: 1, epoch: 1, x: 5.8, z: -.975, yaw: 1.5, action: 'run', hp: 99999 });
    await new Promise(resolve => setTimeout(resolve, 220));
    const frame = ca.frames.at(-1)!;
    expect(frame.readUInt16LE(0)).toBe(1);
    expect(frame.readUInt16LE(10)).toBe(2);
    expect(frame.readUInt16LE(12 + 26 + 14)).toBe(content.character.base.max_hp);
    cb.close();
    expect((await ca.next('left')).id).toBe(peer.member.id);
  });
  it('transfers leadership, rejects non-leader kicks, and keeps existing bindings when the group changes', async () => {
    const { store, gateway } = await harness();
    const a = await seed(store), b = await seed(store);
    const party = await gateway.party(a.player, 'create');
    await gateway.party(b.player, 'join', party.party!.code);
    await expect(gateway.party(b.player, 'kick', a.player)).rejects.toThrow('NOT_LEADER');
    await gateway.party(a.player, 'leader', b.player);
    expect((await store.realtimeDirectory(a.player)).party!.leader).toBe(b.player);
    await gateway.party(b.player, 'kick', a.player);
    expect((await store.realtimeDirectory(a.player)).party).toBeNull();
  });

  it('only resets empty instances and prevents members from reopening retired progress while the leader is outside', async () => {
    const { store, url, gateway } = await harness();
    const a = await seed(store), b = await seed(store);
    const party = await gateway.party(a.player, 'create');
    await gateway.party(b.player, 'join', party.party!.code);
    const ca = await connect(url, a.token), cb = await connect(url, b.token);
    const old = await ca.join('mine'); await cb.join('mine');
    await expect(gateway.reset(a.player)).rejects.toThrow('INSTANCE_OCCUPIED');
    await expect(gateway.reset(b.player)).rejects.toThrow('NOT_LEADER');
    ca.send({ t: 'leave' }); cb.send({ t: 'leave' });
    await ca.next('departed'); await cb.next('departed');
    const reset = await gateway.reset(a.player);
    expect(reset.instance).not.toBe(old.room.slice(5));
    expect((await store.realtimeLoad(old.room))!.mine.retired).toBe(true);
    const entered = await cb.join('mine');
    expect(entered.room).not.toBe(old.room);
    expect(entered.room).not.toBe('mine:' + reset.instance);
  });

  it('an ex-member re-entering solo cannot rejoin the former party instance', async () => {
    const { store, url, gateway } = await harness();
    const a = await seed(store), b = await seed(store);
    const party = await gateway.party(a.player, 'create'); await gateway.party(b.player, 'join', party.party!.code);
    const ca = await connect(url, a.token), cb = await connect(url, b.token);
    const leader = await ca.join('mine'); await cb.join('mine');
    await gateway.party(b.player, 'leave');
    expect(gateway.rooms.get(leader.room)!.members.has(b.player)).toBe(true);
    cb.send({ t: 'leave' }); await cb.next('departed');
    expect((await cb.join('mine')).room).not.toBe(leader.room);
  });

  it('revoking an authenticated token immediately removes its spatial presence', async () => {
    const { store, url, gateway } = await harness();
    const a = await seed(store), client = await connect(url, a.token);
    const joined = await client.join('street');
    const closed = new Promise<number>(resolve => client.ws.once('close', resolve));
    const response = await app!.inject({ method: 'DELETE', url: '/v1/auth/token', headers: { authorization: 'Bearer ' + a.token } });
    expect(response.statusCode).toBe(200);
    expect(await closed).toBe(4003);
    expect(gateway.rooms.get(joined.room)!.members.size).toBe(0);
  });

  it('transport reconnect restores the member\'s current instance and floor even after joining an inside leader', async () => {
    const { store, url, gateway } = await harness();
    const a = await seed(store), b = await seed(store);
    const ca = await connect(url, a.token), cb = await connect(url, b.token);
    const leader = await ca.join('mine'), member = await cb.join('mine');
    gateway.rooms.get(member.room)!.members.get(b.player)!.floor = 3;
    cb.send({ t: 'ping' });
    const ticket = (await cb.next('pong')).resume;
    const party = await gateway.party(a.player, 'create'); await gateway.party(b.player, 'join', party.party!.code);
    cb.close();
    const restored = await connect(url, b.token);
    const joined = await restored.join('mine', { resume: ticket });
    expect(joined.room).toBe(member.room);
    expect(joined.room).not.toBe(leader.room);
    expect(joined.floor).toBe(3);
    restored.send({ t: 'leave' }); await restored.next('departed');
    expect((await restored.join('mine')).room).toBe(leader.room);
  });

  it('rejects forged and explicitly departed resume tickets', async () => {
    const { store, url } = await harness();
    const a = await seed(store), client = await connect(url, a.token);
    const joined = await client.join('mine');
    client.send({ t: 'leave' }); await client.next('departed');
    client.send({ t: 'join', kind: 'mine', resume: joined.resume });
    expect((await client.next('error')).code).toBe('RESUME_EXPIRED');
    client.send({ t: 'join', kind: 'mine', resume: joined.resume + '0' });
    expect((await client.next('error')).code).toBe('RESUME_EXPIRED');
  });
});
