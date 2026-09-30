import { beforeAll, afterAll, describe, expect, it } from 'vitest';
import pg from 'pg';
import { PgStore } from '../../src/db/pg_store.js';
import { migrate } from '../../src/db/migrate.js';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { MemoryStore } from '../../src/http/memory_store.js';
import { buildApp } from '../../src/http/app.js';
import { DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { PondCatalog, pondCell } from '../../src/ponds/catalog.js';
import { waterContains, nearestWater, defaultFishingTarget, validFishingCast, initialFishingSimulation, stepFishing } from '../../src/domain/fishing.js';
import { walkable } from '../../src/realtime/model.js';
import { onlineGateways } from '../../src/realtime/gateway.js';
import { seed, Client, content, cv, sets, blueprintDir } from './helpers.js';

let pool: pg.Pool | undefined;
beforeAll(async () => {
  if (process.env.TEST_DATABASE_URL) { pool = new pg.Pool({ connectionString: process.env.TEST_DATABASE_URL, max: 5 }); await migrate(pool); }
});
afterAll(async () => { await pool?.end(); });

describe('published system ponds', () => {
  it('keeps stable city entries, all three shapes, immutable reads and existing farm content', () => {
    const a = new PondCatalog(), b = new PondCatalog();
    expect(a.revision).toBe(b.revision);
    for (const city of ['los_angeles', 'shanghai']) {
      const rows = a.list(city);
      expect(rows).toHaveLength(6);
      expect(new Set(rows.map(r => r.template_id)).size).toBe(3);
      expect(rows).toEqual(b.list(city));
      rows[0].lat = 0;
      expect(a.list(city)[0].lat).not.toBe(0);
    }
    expect(a.revision).toBe('2c6e2a2f5f6efa3742912257fa8a0b4844cbf89277e5867ac88157784770a187');
    expect(() => a.room('invented-pond', a.revision, content)).toThrow('POND_NOT_FOUND');
    expect(() => a.room(a.list('shanghai')[0].id, 'stale', content)).toThrow('POND_UPDATE_REQUIRED');
  });

  for (const shape of ['crescent', 'gourd', 'meander']) it(`${shape}: dry connected navigation, reachable shores and dry/wet cast bounds`, () => {
    const catalog = new PondCatalog();
    const entry = catalog.list('shanghai').find(p => p.template_id === shape)!;
    const { site, template } = catalog.room(entry.id, catalog.revision, content);
    const nav = template.navigation;
    const dry = new Set<string>(), shores: [number, number][] = [];
    for (let y = 0; y < nav.rows.length; y++) for (let x = 0; x < nav.rows[y].length; x++) {
      if (nav.rows[y][x] !== '1') continue;
      dry.add(`${x},${y}`);
      const p: [number, number] = [(x + .5) * nav.cell, -(y + .5) * nav.cell];
      expect(waterContains(site, p)).toBe(false);
      if (validFishingCast(site, p, defaultFishingTarget(site, p), content.fishing, p => walkable(nav, p))) shores.push(p);
    }
    const queue = [[Math.floor(nav.spawn[0] / nav.cell), Math.floor(-nav.spawn[1] / nav.cell)]];
    const visited = new Set(queue.map(p => p.join(',')));
    for (let i = 0; i < queue.length; i++) {
      const [x, y] = queue[i];
      for (const [dx, dy] of [[1,0],[-1,0],[0,1],[0,-1]]) {
        const next = `${x+dx},${y+dy}`;
        if (dry.has(next) && !visited.has(next)) { visited.add(next); queue.push([x+dx,y+dy]); }
      }
    }
    expect(visited.size).toBe(dry.size);
    expect(shores.length).toBeGreaterThan(50);
    const origin = shores[0], target = defaultFishingTarget(site, origin);
    expect(waterContains(site, target)).toBe(true);
    expect(validFishingCast(site, target, target, content.fishing)).toBe(false);
    expect(validFishingCast(site, nav.spawn, target, content.fishing)).toBe(false);
    expect(validFishingCast(site, origin, [NaN, 0], content.fishing)).toBe(false);
    expect(Math.hypot(...nearestWater(site, origin).map((v,i) => v-origin[i]))).toBeLessThanOrEqual(1.25);
  });

  for (const backend of ['memory', 'postgres']) it.skipIf(backend === 'postgres' && !process.env.TEST_DATABASE_URL)(`${backend}: serves registered entries, joins a shared room, fences site/geometry and settles a personal catch exactly once`, async () => {
    let now = Date.now();
    const store = backend === 'memory'
      ? new MemoryStore({ content, contentVersion: cv, plot: sets, timezone: 'Asia/Shanghai', now: () => now })
      : new PgStore({ pool: pool!, content, contentVersion: cv, plot: sets, timezone: () => 'Asia/Shanghai', now: () => now });
    const app = await buildApp({ guestWrites: true, store, content, contentVersion: cv, blueprintDir,
      regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'system-pond-test', now: () => now });
    const address = await app.listen({ port: 0, host: '127.0.0.1' });
    const accounts = await Promise.all([seed(store), seed(store)]);
    const clients: Client[] = [];
    const gateway = onlineGateways.get(app)!;
    // The real-time clock is a controlled dependency, never supplied over HTTP.
    const catalog = gateway.ponds;
    const entry = catalog.list('shanghai')[0];
    const command = async (type: string, payload: object, envelope?: object) => {
      const body = envelope ?? { type, payload, idempotency_key: randomUUID(), base_version: (await store.farmByOwner(accounts[0].player))!.version };
      const r = await fetch(address + '/v1/farms/me/commands', { method: 'POST', headers: { authorization: `Bearer ${accounts[0].token}`, 'content-type': 'application/json' }, body: JSON.stringify(body) });
      return { status: r.status, body: await r.json() as any, envelope: body };
    };
    try {
      for (const account of accounts) {
        const client = new Client(address.replace('http:', 'ws:') + '/v1/online');
        clients.push(client);
        await client.connect(account.token);
      }
      const directory = await (await fetch(address + '/v1/ponds?region_id=shanghai')).json() as any;
      expect(directory.catalog_revision).toBe(catalog.revision);
      expect(directory.locations).toEqual(catalog.list('shanghai'));
      expect((await fetch(address + '/v1/ponds?region_id=unknown')).status).toBe(400);
      clients[0].send({ t: 'join', kind: 'pond', pond_id: entry.id, catalog_revision: 'stale' });
      expect((await clients[0].next('error')).code).toBe('POND_UPDATE_REQUIRED');
      await clients[0].join('pond', { pond_id: entry.id, catalog_revision: catalog.revision });
      const joined = await clients[1].join('pond', { pond_id: entry.id, catalog_revision: catalog.revision });
      const room = gateway.rooms.get(joined.room)!;
      expect(room.kind).toBe('pond'); expect(joined.capacity).toBe(16);
      expect(room.members.size).toBe(2);
      const world = await clients[1].next('world');
      expect(world.template_id).toBe(entry.template_id);
      expect(world.catalog_revision).toBe(catalog.revision);
      const own = room.members.get(accounts[0].player)!;
      const spec = room.pond!.site, nav = room.navigation;
      const shore: [number, number][] = [];
      for (let y=0;y<nav.rows.length;y++) for(let x=0;x<nav.rows[y].length;x++) {
        const p: [number,number] = [(x+.5)*nav.cell,-(y+.5)*nav.cell];
        if (validFishingCast(spec,p,defaultFishingTarget(spec,p),content.fishing,p=>walkable(nav,p))) shore.push(p);
      }
      [own.x,own.z]=shore[0]; own.target=shore[0];
      expect((await command('cast_fishing',{site_id:catalog.list('shanghai')[1].id,sequence:0})).body.code).toBe('FISHING_LOCATION');
      expect((await command('cast_fishing',{site_id:'farm_pond',sequence:0})).body.code).toBe('FISHING_LOCATION');
      const before = await store.farmByOwner(accounts[0].player), other = await store.farmByOwner(accounts[1].player);
      const cast = await command('cast_fishing',{site_id:entry.id,sequence:0});
      expect(cast.status).toBe(200);
      const active = cast.body.state.fishing.active;
      now=active.bite_at;
      expect((await command('hook_fishing',{sequence:1})).status).toBe(200);
      const simulation=initialFishingSimulation(active.seed,content.fishing); let inputs='';
      while(simulation.outcome==='playing') { const held=simulation.fish>simulation.bar+simulation.velocity*.15;inputs+=held?'1':'0';stepFishing(simulation,held,content.fishing.tiers[String(content.fishing.fish[active.fish_id].tier)],content.fishing); }
      expect(simulation.outcome).toBe('caught'); now+=inputs.length*content.fishing.step_ms;
      const caught=await command('finish_fishing',{sequence:1,inputs});
      expect(caught.status).toBe(200); expect(caught.body.state.fishing.last.outcome).toBe('caught');
      expect(caught.body.state.cells).toEqual(before!.state.cells); expect(caught.body.state.wallet).toBe(before!.state.wallet);
      expect(await store.farmByOwner(accounts[1].player)).toEqual(other);
      clients[0].send({t:'leave'});await clients[0].next('departed');
      const replay=await command('',{},caught.envelope);
      expect(replay.body.outcome).toBe('replayed');expect(replay.body.state.bag).toEqual(caught.body.state.bag);
      expect((await command('cast_fishing',{site_id:entry.id,sequence:1})).body.code).toBe('FISHING_LOCATION');
      const party = await store.realtimeDirectory(accounts[1].player, 'create');
      await store.realtimeDirectory(accounts[0].player, 'join', party.party!.code);
      const grant = await gateway.prepareTravel(accounts[0].player, accounts[1].player, 'follow');
      expect(grant.kind).toBe('pond'); expect(grant.pond_id).toBe(entry.id);
      expect(grant.snapshot).toBeUndefined();
      const returned = await clients[0].join('pond', { travel_ticket: grant.ticket });
      expect(returned.room).toBe(joined.room);
    } finally { clients.forEach(c=>c.close());await app.close(); }
  });
});

describe('server-only pond locations and the cell directory', () => {
  it('adds San Francisco without touching the frozen bundled catalog revision', () => {
    const catalog = new PondCatalog();
    expect(catalog.revision).toBe('2c6e2a2f5f6efa3742912257fa8a0b4844cbf89277e5867ac88157784770a187');
    const sf = catalog.list('gn-5391959');
    expect(sf).toHaveLength(6);
    expect(new Set(sf.map(p => p.template_id)).size).toBe(3);
    for (const p of sf) {
      expect(pondCell(p.lat, p.lng)).toEqual([75, -245]);
      expect(catalog.room(p.id, catalog.revision, content).location.id).toBe(p.id);
    }
    expect(catalog.cell(75, -245).map(p => p.id).sort()).toEqual(sf.map(p => p.id).sort());
    expect(catalog.list('los_angeles')).toHaveLength(6);
    expect(new PondCatalog(undefined, null).list('gn-5391959')).toHaveLength(0);
    expect(catalog.location('pond_san_francisco_01')?.name).toBe('Willow Pond');
    expect(catalog.location('invented')).toBeUndefined();
  });

  it('serves whole cells, bounded and cacheable, next to the legacy region directory', async () => {
    let now = Date.now();
    const store = new MemoryStore({ content, contentVersion: cv, plot: sets, timezone: 'Asia/Shanghai', now: () => now });
    const app = await buildApp({ guestWrites: true, store, content, contentVersion: cv, blueprintDir,
      regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'pond-cells-test', now: () => now });
    const address = await app.listen({ port: 0, host: '127.0.0.1' });
    try {
      const catalog = onlineGateways.get(app)!.ponds;
      const la = catalog.list('los_angeles')[0], [ly, lx] = pondCell(la.lat, la.lng);
      const r = await fetch(`${address}/v1/ponds/cells?cells=75:-245,${ly}:${lx},0:0`);
      expect(r.status).toBe(200);
      expect(r.headers.get('cache-control')).toContain('max-age=300');
      const body = await r.json() as any;
      expect(body).toMatchObject({ version: 2, catalog_revision: catalog.revision, available: true, cell_deg: 0.5 });
      expect(body.cells['75:-245']).toHaveLength(6);
      expect(body.cells[`${ly}:${lx}`].map((p: any) => p.id)).toContain(la.id);
      expect(body.cells['0:0']).toEqual([]);
      for (const bad of ['', 'x', '1:2:3', '999:0', Array.from({ length: 26 }, (_, i) => `0:${i}`).join(',')])
        expect((await fetch(`${address}/v1/ponds/cells?cells=${bad}`)).status).toBe(400);
      const legacy = await (await fetch(address + '/v1/ponds?region_id=los_angeles')).json() as any;
      expect(legacy.catalog_revision).toBe(catalog.revision);
      expect(legacy.locations).toHaveLength(6);
    } finally { await app.close(); }
  });
});
