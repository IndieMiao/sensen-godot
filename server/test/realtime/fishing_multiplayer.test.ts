import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import pg from 'pg';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { PgStore } from '../../src/db/pg_store.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { migrate } from '../../src/db/migrate.js';
import { buildApp } from '../../src/http/app.js';
import { DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { onlineGateways } from '../../src/realtime/gateway.js';
import { initialFishingSimulation, stepFishing } from '../../src/domain/fishing.js';
import { Client, seed, content, cv, sets, blueprintDir } from './helpers.js';
let pool: pg.Pool | undefined;
beforeAll(async () => { if (process.env.TEST_DATABASE_URL) { pool = new pg.Pool({ connectionString: process.env.TEST_DATABASE_URL, max: 5 }); await migrate(pool); } });
afterAll(async () => { await pool?.end(); });
for (const backend of ['memory', 'postgres']) describe.skipIf(backend === 'postgres' && !process.env.TEST_DATABASE_URL)(`${backend} shared shoreline`, () => {
  it('simultaneous casts, late join, bounded/private poses, visitor loot, cancellation and leave cleanup', async () => {
    let now = Date.now();
    const store = backend === 'memory' ? new MemoryStore({ content, contentVersion: cv, plot: sets, timezone: 'Asia/Shanghai', now: () => now })
      : new PgStore({ pool: pool!, content, contentVersion: cv, plot: sets, timezone: () => 'Asia/Shanghai', now: () => now });
    const app = await buildApp({ store, content, contentVersion: cv, blueprintDir, regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'shared-fishing', now: () => now });
    const address = await app.listen({ port: 0, host: '127.0.0.1' });
    const accounts = await Promise.all([seed(store), seed(store), seed(store)]);
    const clients: Client[] = [];
    const command = async (i: number, type: string, payload: object) => {
      const r = await fetch(address + '/v1/farms/me/commands', { method: 'POST', headers: { authorization: `Bearer ${accounts[i].token}`, 'content-type': 'application/json' },
        body: JSON.stringify({ type, payload, idempotency_key: randomUUID(), base_version: (await store.farmByOwner(accounts[i].player))!.version }) });
      const b = await r.json() as any;
      return { status: r.status, ...b };
    };
    try {
      for (const i of [0, 1]) {
        const client = new Client(address.replace('http:', 'ws:') + '/v1/online'); clients.push(client);
        await client.connect(accounts[i].token); await client.join('farm', { farm_id: accounts[0].farm.id });
      }
      const room = onlineGateways.get(app)!.rooms.get(clients[0].joined.room)!;
      const members = accounts.slice(0, 2).map(a => room.members.get(a.player)!);
      for (const [i, m] of members.entries()) { m.x = 9.15 + i * .25; m.z = -27.4; m.target = [m.x, m.z]; }
      const casts = await Promise.all([0, 1].map(i => command(i, 'cast_fishing', { sequence: 0, site_id: 'farm_pond', target: [9.2, -29.2] })));
      expect(casts.map(c => c.status)).toEqual([200, 200]);
      const hostAfterCast = structuredClone((await store.farmByOwner(accounts[0].player))!);
      const observer = new Client(address.replace('http:', 'ws:') + '/v1/online'); clients.push(observer);
      await observer.connect(accounts[2].token); await observer.join('farm', { farm_id: accounts[0].farm.id });
      const visible = await observer.next('fishing', m => m.members.length === 2);
      expect(visible.members.map((m: any) => m.id).sort()).toEqual(members.map(m => m.id).sort());
      expect(JSON.stringify(visible)).not.toMatch(/seed|nonce|wallet|bag|fish_id|hook_until/);
      expect(visible.members.length).toBeLessThanOrEqual(8);
      now = Math.max(...casts.map(c => c.state.fishing.active.bite_at));
      expect((await command(1, 'hook_fishing', { sequence: 1 })).status).toBe(200);
      clients[1].send({ t: 'input', epoch: members[1].epoch, seq: 1, x: members[1].x, z: members[1].z, yaw: 0, action: 'fishing_reel', fishing: { sequence: 1, held: true, fish: 99 } });
      const reel = await observer.next('fishing', m => m.members.some((p: any) => p.id === members[1].id && p.phase === 'playing' && p.held));
      expect(reel.members.find((p: any) => p.id === members[1].id).fish).toBe(1);
      const active = casts[1].state.fishing.active, simulation = initialFishingSimulation(active.seed, content.fishing);
      let inputs = '';
      while (simulation.outcome === 'playing') { const held = simulation.fish > simulation.bar + simulation.velocity * .15; inputs += held ? '1' : '0'; stepFishing(simulation, held, content.fishing.tiers[String(content.fishing.fish[active.fish_id].tier)], content.fishing); }
      now += inputs.length * content.fishing.step_ms;
      const caught = await command(1, 'finish_fishing', { sequence: 1, inputs });
      expect(caught.state.fishing.last.outcome).toBe('caught');
      expect(await store.farmByOwner(accounts[0].player)).toEqual(hostAfterCast);
      expect(caught.state.bag.slots.some((s: any) => s.item_id === active.fish_id && s.quantity === 1)).toBe(true);
      await observer.next('fishing', m => m.members.some((p: any) => p.id === members[1].id && p.outcome === 'caught' && p.fish_id === active.fish_id));
      await command(0, 'cancel_fishing', { sequence: 1 });
      now += 2000;
      await observer.next('fishing', m => m.members.length === 0);
      const next = await command(1, 'cast_fishing', { sequence: 1, site_id: 'farm_pond', target: [9, -29] });
      expect(next.status).toBe(200);
      members[1].x += 1; members[1].target = [members[1].x, members[1].z];
      await room.tick();
      members[1].x -= 1; members[1].target = [members[1].x, members[1].z];
      now = next.state.fishing.active.bite_at;
      expect((await command(1, 'hook_fishing', { sequence: 2 })).code).toBe('FISHING_LOCATION');
      await command(1, 'cancel_fishing', { sequence: 2 });
      expect((await command(1, 'cast_fishing', { sequence: 2, site_id: 'farm_pond' })).status).toBe(200);
      clients[1].send({ t: 'leave' }); await clients[1].next('departed');
      await observer.next('left', m => m.id === members[1].id);
      await observer.next('fishing', m => m.members.length === 0);
      // Client action names cannot create an authoritative fishing lifecycle.
      clients[0].send({ t: 'input', epoch: members[0].epoch, seq: 1, x: members[0].x, z: members[0].z, yaw: 0, action: 'fishing_reel', fishing: { sequence: 999, held: true, fish: .5 } });
      await observer.next('fishing', m => m.members.length === 0);
      expect(members[0].fishing).toBeUndefined();
    } finally { clients.forEach(c => c.close()); await app.close(); }
  });
});
