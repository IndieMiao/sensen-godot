import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import type { FarmRow } from '../../src/http/dto.js';
import { onlineGateways } from '../../src/realtime/gateway.js';
import { generateFarmTerrain, terrainNavigation } from '../../src/geography/farm_terrain.js';
import { CENTER, fixtureGeography } from '../geography/fixtures.js';
import { Client, appFor, memory, seed, content } from './helpers.js';

let app: FastifyInstance;
const clients: Client[] = [];
afterEach(async () => { clients.splice(0).forEach(c => c.close()); await app?.close(); });
const deferred = () => { let resolve!: () => void; const promise = new Promise<void>(r => resolve = r); return { promise, resolve }; };
async function harness() {
  const store = memory(), owner = await seed(store), visitor = await seed(store), third = await seed(store);
  app = await appFor(store);
  const address = await app.listen({ host: '127.0.0.1', port: 0 }), gateway = onlineGateways.get(app)!;
  const connect = async (account: typeof owner) => {
    const client = new Client(address.replace('http:', 'ws:') + '/v1/online'); clients.push(client);
    await client.connect(account.token); return client;
  };
  const read = (account: typeof owner, farmId?: string) => app.inject({ method: 'GET',
    url: farmId ? '/v1/farms/' + farmId + '/snapshot' : '/v1/farms/me', headers: { authorization: 'Bearer ' + account.token } });
  const relocate = async () => {
    const farm = (await store.farmByOwner(owner.player))!;
    const terrain = generateFarmTerrain(CENTER, fixtureGeography(), content.farm_plot.layouts[content.farm_plot.default_layout]);
    farm.farm_terrain = terrain; farm.layout_patch_id = terrain.layout_id; farm.blueprint_revision = 1; farm.version++;
    farm.relocation_used = true; farm.relocation_available = false;
    return { kind: 'applied' as const, farm };
  };
  return { store, owner, visitor, third, gateway, connect, read, relocate };
}
const activeCast = (farm: FarmRow, home = farm.id) => {
  farm.state.fishing = { version: 1, sequence: 1, active: { site: 'farm_pond', fish_id: 'fish_crucian', seed: 1,
    nonce: 'fixture', bite_at: Date.now() + 1000, hook_until: Date.now() + 3000, home } };
};

describe('one-time farm relocation realtime boundary', () => {
  it('evicts every old channel, invalidates the connection generation, and requires a fresh DTO before rejoining new navigation', async () => {
    const { owner, visitor, third, gateway, connect, read, relocate, store } = await harness();
    const oldView = (await read(owner)).json();
    const a = await connect(owner), b = await connect(visitor), c = await connect(third);
    const own = await a.join('farm'), remote = await b.join('farm', { farm_id: owner.farm.id, channel: 2 });
    const idle = await c.join('farm', { farm_id: owner.farm.id, channel: 3 }); c.send({ t: 'leave' }); await c.next('departed');
    const oldRooms = [own.room, remote.room, idle.room].map(k => gateway.rooms.get(k)!);
    const oldMember = oldRooms[0].members.get(owner.player)!, oldEpoch = oldMember.epoch, oldTarget = [...oldMember.target];
    const oldNonce = gateway.fishingPresence(owner.player)!.nonce;
    const closedA = new Promise<number>(resolve => a.ws.once('close', resolve)), closedB = new Promise<number>(resolve => b.ws.once('close', resolve));
    await gateway.withFarmRelocation(owner.player, owner.farm.id, relocate);
    expect((await a.next('error')).code).toBe('FARM_RELOCATED'); expect((await b.next('error')).code).toBe('FARM_RELOCATED');
    expect(await closedA).toBe(4005); expect(await closedB).toBe(4005);
    expect(oldRooms.every(room => room.failed && room.members.size === 0)).toBe(true);
    expect([own.room, remote.room, idle.room].every(k => !gateway.rooms.has(k))).toBe(true);
    expect(gateway.fishingPresence(owner.player)).toBeNull();
    expect(oldMember.epoch).toBeGreaterThan(oldEpoch);
    oldRooms[0].input(oldMember, { t: 'input', epoch: oldEpoch, seq: 999, x: 1, z: -1, yaw: 0 });
    expect(oldMember.target).toEqual(oldTarget);
    const staleCommand = await app.inject({ method: 'POST', url: '/v1/farms/me/commands', headers: { authorization: 'Bearer ' + owner.token },
      payload: { type: 'cast_fishing', payload: { site_id: 'farm_pond', sequence: 0 }, idempotency_key: 'stale-cast-version', base_version: oldView.version } });
    expect(staleCommand.statusCode).toBe(409); expect(staleCommand.json().code).toBe('VERSION_CONFLICT');
    const noPresence = await app.inject({ method: 'POST', url: '/v1/farms/me/commands', headers: { authorization: 'Bearer ' + owner.token },
      payload: { type: 'cast_fishing', payload: { site_id: 'farm_pond', sequence: 0 }, idempotency_key: 'stale-cast-generation', base_version: (await store.farmByOwner(owner.player))!.version } });
    expect(noPresence.statusCode).toBe(422); expect(noPresence.json().code).toBe('FISHING_LOCATION');
    const reconnected = await connect(owner);
    reconnected.send({ t: 'join', kind: 'farm' }); expect((await reconnected.next('error')).code).toBe('FARM_RELOCATED');
    await gateway.acknowledgeFarmRead(owner.player, oldView);
    reconnected.send({ t: 'join', kind: 'farm' }); expect((await reconnected.next('error')).code).toBe('FARM_RELOCATED');
    const refreshedOwner = await read(owner); expect(refreshedOwner.statusCode).toBe(200);
    const checksum = refreshedOwner.json().farm_terrain.plot.checksum;
    for (const binding of [{}, { terrain_checksum: 'stale-rendered-map' }]) {
      reconnected.send({ t: 'join', kind: 'farm', ...binding });
      expect((await reconnected.next('error')).code).toBe('FARM_RELOCATED');
      expect(gateway.fishingPresence(owner.player)).toBeNull();
    }
    const joined = await reconnected.join('farm', { terrain_checksum: checksum }); expect(joined.room).toBe(own.room);
    const world = await reconnected.next('world');
    expect(world.navigation).toEqual(terrainNavigation((await store.farmByOwner(owner.player))!.farm_terrain!));
    expect(gateway.rooms.get(joined.room)).not.toBe(oldRooms[0]);
    expect(gateway.fishingPresence(owner.player)!.nonce).not.toBe(oldNonce);
    const returningVisitor = await connect(visitor);
    returningVisitor.send({ t: 'join', kind: 'farm', farm_id: owner.farm.id });
    expect((await returningVisitor.next('error')).code).toBe('FARM_RELOCATED');
    expect((await read(visitor, owner.farm.id)).statusCode).toBe(200);
    returningVisitor.send({ t: 'join', kind: 'farm', farm_id: owner.farm.id, terrain_checksum: 'old-visitor-scene' });
    expect((await returningVisitor.next('error')).code).toBe('FARM_RELOCATED');
    expect((await returningVisitor.join('farm', { farm_id: owner.farm.id, terrain_checksum: checksum })).room).toBe(own.room);
  });

  it('rejects authoritative owner or visitor fishing and an active owner mine without committing', async () => {
    const { owner, visitor, gateway, connect, store, relocate } = await harness();
    let commits = 0; const commit = async () => { commits++; return relocate(); };
    const farm = (await store.farmByOwner(owner.player))!;
    activeCast(farm);
    await expect(gateway.withFarmRelocation(owner.player, farm.id, commit)).rejects.toThrow('RELOCATION_BUSY');
    farm.state.fishing!.active = null;
    const b = await connect(visitor); await b.join('farm', { farm_id: farm.id });
    const other = (await store.farmByOwner(visitor.player))!; activeCast(other, farm.id);
    // No visual sync is needed: the committed owner state, not a stale animation, controls safety.
    await expect(gateway.withFarmRelocation(owner.player, farm.id, commit)).rejects.toThrow('RELOCATION_BUSY');
    other.state.fishing!.active = null;
    const a = await connect(owner); await a.join('mine');
    await expect(gateway.withFarmRelocation(owner.player, farm.id, commit)).rejects.toThrow('RELOCATION_BUSY');
    expect(commits).toBe(0); expect(farm.farm_terrain).toBeUndefined();
    a.send({ t: 'leave' }); await a.next('departed');
    activeCast(farm); farm.state.fishing!.active!.hook_until = Date.now() - 100000;
    await gateway.withFarmRelocation(owner.player, farm.id, commit); expect(commits).toBe(1);
  });

  it('serializes an in-flight visitor fishing write before relocation and observes its committed cast', async () => {
    const { owner, visitor, gateway, connect, store, relocate } = await harness();
    const b = await connect(visitor), joined = await b.join('farm', { farm_id: owner.farm.id });
    const member = gateway.rooms.get(joined.room)!.members.get(visitor.player)!;
    member.x = 9.375; member.z = -27.375; member.target = [member.x, member.z];
    const entered = deferred(), release = deferred();
    const apply = store.applyCommand.bind(store);
    store.applyCommand = async (...args) => { entered.resolve(); await release.promise; return apply(...args); };
    const fishing = Promise.resolve(app.inject({ method: 'POST', url: '/v1/farms/me/commands', headers: { authorization: 'Bearer ' + visitor.token },
      payload: { type: 'cast_fishing', payload: { site_id: 'farm_pond', sequence: 0 }, idempotency_key: 'concurrent-visitor-cast', base_version: visitor.farm.version } }));
    await entered.promise; let called = false;
    const relocating = gateway.withFarmRelocation(owner.player, owner.farm.id, async () => { called = true; return relocate(); });
    const rejected = expect(relocating).rejects.toThrow('RELOCATION_BUSY');
    release.resolve(); expect((await fishing).statusCode).toBe(200); await rejected; expect(called).toBe(false);
  });

  it('holds new joins and casts behind the commit, then rejects the evicted generation', async () => {
    const { owner, visitor, gateway, connect, relocate, read } = await harness();
    const a = await connect(owner); await a.join('farm');
    const b = await connect(visitor);
    const entered = deferred(), release = deferred();
    const relocating = gateway.withFarmRelocation(owner.player, owner.farm.id, async () => {
      entered.resolve(); await release.promise; return relocate();
    });
    await entered.promise;
    const connection = [...gateway.connections].find(c => c.player === visitor.player)!;
    // Observe actual receipt after the gateway's handler, without a CPU-load-sensitive
    // count of one-millisecond timers. Admission itself is still held by the commit.
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => { connection.ws.off('message', received); release.resolve(); reject(new Error('Server did not receive queued join')); }, 5000);
      const received = (raw: Buffer, binary: boolean) => {
        if (binary) return;
        const message = JSON.parse(raw.toString());
        if (message.t !== 'join' || message.farm_id !== owner.farm.id) return;
        clearTimeout(timer); connection.ws.off('message', received); resolve();
      };
      connection.ws.on('message', received);
      b.send({ t: 'join', kind: 'farm', farm_id: owner.farm.id });
    });
    expect(connection.pendingFarm).toBe(owner.farm.id);
    const fishing = gateway.withFishingCommand(async () => gateway.fishingPresence(owner.player));
    release.resolve(); await relocating; expect(await fishing).toBeNull();
    expect((await b.next('error')).code).toBe('FARM_RELOCATED');
    const refreshed = await connect(visitor), refreshedView = (await read(visitor, owner.farm.id)).json();
    const joined = await refreshed.join('farm', { farm_id: owner.farm.id, terrain_checksum: refreshedView.farm_terrain.plot.checksum }), world = await refreshed.next('world');
    expect(world.navigation).toEqual(terrainNavigation((await gateway.deps.store.farmByOwner(owner.player))!.farm_terrain!));
    expect(gateway.rooms.get(joined.room)!.members.has(owner.player)).toBe(false);
  });

  it('invalidates old party farm tickets and clears the refresh fence with a newly prepared visitor snapshot', async () => {
    const { owner, visitor, gateway, connect, relocate } = await harness();
    const party = await gateway.party(owner.player, 'create'); await gateway.party(visitor.player, 'join', party.party!.code);
    const a = await connect(owner), b = await connect(visitor); await a.join('farm'); await b.join('farm', { farm_id: owner.farm.id });
    const prior = await gateway.prepareTravel(visitor.player, owner.player, 'farm');
    await gateway.withFarmRelocation(owner.player, owner.farm.id, relocate);
    await expect(gateway.travel.validate(gateway.travel.read(prior.ticket, visitor.player), visitor.player)).rejects.toThrow('DESTINATION_CHANGED');
    const fresh = await app.inject({ method: 'POST', url: '/v1/online/travel', headers: { authorization: 'Bearer ' + visitor.token }, payload: { mode: 'farm', target: owner.player } });
    expect(fresh.statusCode).toBe(200);
    const returning = await connect(visitor);
    expect((await returning.join('farm', { travel_ticket: fresh.json().ticket, terrain_checksum: fresh.json().snapshot.farm_terrain.plot.checksum })).kind).toBe('farm');
  });

  it('does not evict occupants or consume navigation when a confirm is rejected or replayed unchanged', async () => {
    const { owner, gateway, connect } = await harness();
    const a = await connect(owner), joined = await a.join('farm'), room = gateway.rooms.get(joined.room)!;
    expect(await gateway.withFarmRelocation(owner.player, owner.farm.id, async () => ({ kind: 'rejected', code: 'VERSION_CONFLICT' }))).toEqual({ kind: 'rejected', code: 'VERSION_CONFLICT' });
    expect(await gateway.withFarmRelocation(owner.player, owner.farm.id, async () => ({ kind: 'replayed' }))).toEqual({ kind: 'replayed' });
    expect(gateway.rooms.get(joined.room)).toBe(room); expect(room.members.has(owner.player)).toBe(true); expect(gateway.fishingPresence(owner.player)).not.toBeNull();
  });

  it('permits committed confirmation recovery after entering a mine and fences a commit whose response was lost', async () => {
    const { owner, gateway, connect, relocate, read } = await harness();
    const a = await connect(owner); await a.join('farm');
    await expect(gateway.withFarmRelocation(owner.player, owner.farm.id, async () => {
      await relocate(); throw new Error('CONNECTION_LOST_AFTER_COMMIT');
    })).rejects.toThrow('CONNECTION_LOST_AFTER_COMMIT');
    expect((await a.next('error')).code).toBe('FARM_RELOCATED');
    const recovered = await connect(owner); await read(owner); await recovered.join('mine');
    expect(await gateway.withFarmRelocation(owner.player, owner.farm.id, async () => ({ kind: 'replayed' }))).toEqual({ kind: 'replayed' });
    expect(gateway.fishingPresence(owner.player)?.space).toBe('mine');
  });

  it('acknowledges the successful confirm DTO so adopting it permits immediate fresh-room admission', async () => {
    const { owner, gateway, connect, store } = await harness();
    const farm = (await store.farmByOwner(owner.player))!; farm.relocation_available = true;
    const terrain = generateFarmTerrain(CENTER, fixtureGeography(), content.farm_plot.layouts[content.farm_plot.default_layout]);
    expect(await store.saveRelocationPreview(owner.player, { preview_id: 'realtime-confirm', base_version: farm.version,
      expires_at: Date.now() + 10000, region_id: farm.region_id, location: CENTER, farm_terrain: terrain, moved_cells: 0, moved_decorations: 0 })).toEqual({});
    const a = await connect(owner); const previous = await a.join('farm');
    const confirmation = await app.inject({ method: 'POST', url: '/v1/farms/me/relocation/confirm', headers: { authorization: 'Bearer ' + owner.token },
      payload: { preview_id: 'realtime-confirm', base_version: farm.version, idempotency_key: 'realtime-confirm-once' } });
    expect(confirmation.statusCode).toBe(200); expect(confirmation.json().farm_terrain).toEqual(terrain);
    expect((await a.next('error')).code).toBe('FARM_RELOCATED'); expect(gateway.rooms.has(previous.room)).toBe(false);
    const returning = await connect(owner); expect((await returning.join('farm', { terrain_checksum: terrain.plot.checksum })).kind).toBe('farm');
    expect((await returning.next('world')).navigation).toEqual(terrainNavigation(terrain));
  });
});
