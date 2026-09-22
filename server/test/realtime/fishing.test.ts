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
beforeAll(async () => {
  if (!process.env.TEST_DATABASE_URL) return;
  pool = new pg.Pool({ connectionString: process.env.TEST_DATABASE_URL, max: 5 });
  await migrate(pool);
});
afterAll(async () => { await pool?.end(); });

for (const backend of ['memory', 'postgres']) describe.skipIf(backend === 'postgres' && !process.env.TEST_DATABASE_URL)(`${backend} fishing HTTP/WebSocket settlement`, () => {
  it('checks real presence, saves a catch once, recovers its response after leaving, and sells without duplication', async () => {
    let now = Date.now();
    const store = backend === 'memory'
      ? new MemoryStore({ content, contentVersion: cv, plot: sets, timezone: 'Asia/Shanghai', now: () => now })
      : new PgStore({ pool: pool!, content, contentVersion: cv, plot: sets, timezone: () => 'Asia/Shanghai', now: () => now });
    const app = await buildApp({ store, content, contentVersion: cv, blueprintDir,
      regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'fishing-test', now: () => now });
    const address = await app.listen({ port: 0, host: '127.0.0.1' });
    const account = await seed(store);
    const client = new Client(address.replace('http:', 'ws:') + '/v1/online');
    const post = async (body: object) => {
      const r = await fetch(address + '/v1/farms/me/commands', { method: 'POST', headers: {
        authorization: `Bearer ${account.token}`, 'content-type': 'application/json' }, body: JSON.stringify(body) });
      return { status: r.status, body: await r.json() as any };
    };
    const command = async (type: string, payload: object) => post({ type, payload, idempotency_key: randomUUID(), base_version: (await store.farmByOwner(account.player))!.version });
    try {
      await client.connect(account.token);
      const missing = await command('cast_fishing', { site_id: 'farm_pond', sequence: 0,
        fishingPresence: { space: 'farm', home: account.farm.id, x: 9.375, z: -27.375 } });
      expect(missing.body.code).toBe('FISHING_LOCATION');
      const joined = await client.join('farm', { farm_id: account.farm.id });
      const member = onlineGateways.get(app)!.rooms.get(joined.room)!.members.get(account.player)!;
      member.x = 9.375; member.z = -27.375; member.target = [member.x, member.z];
      const cast = await command('cast_fishing', { site_id: 'farm_pond', sequence: 0 });
      expect(cast.status).toBe(200);
      const active = cast.body.state.fishing.active;
      now = active.bite_at;
      expect((await command('hook_fishing', { sequence: 1 })).status).toBe(200);
      const game = initialFishingSimulation(active.seed, content.fishing);
      let inputs = '';
      while (game.outcome === 'playing') {
        const held = game.fish > game.bar + game.velocity * .15;
        inputs += held ? '1' : '0';
        stepFishing(game, held, content.fishing.tiers[String(content.fishing.fish[active.fish_id].tier)], content.fishing);
      }
      expect(game.outcome).toBe('caught');
      now += inputs.length * content.fishing.step_ms;
      const envelope = { type: 'finish_fishing', payload: { sequence: 1, inputs }, idempotency_key: randomUUID(),
        base_version: (await store.farmByOwner(account.player))!.version };
      const caught = await post(envelope);
      expect(caught.body.state.fishing.last.outcome).toBe('caught');
      client.send({ t: 'leave' }); await client.next('departed');
      const replayed = await post(envelope);
      expect(replayed.body.outcome).toBe('replayed');
      expect(replayed.body.state.bag).toEqual(caught.body.state.bag);
      const stack = caught.body.state.bag.slots.find((s: any) => s.item_id === active.fish_id);
      const sale = { type: 'sell_fish', payload: { sequence: caught.body.state.bag.sequence, stack_id: stack.id, quantity: 1 },
        idempotency_key: randomUUID(), base_version: caught.body.version };
      const sold = await post(sale);
      expect(sold.status).toBe(200);
      expect(sold.body.state.wallet - caught.body.state.wallet).toBe(content.fishing.fish[active.fish_id].price);
      expect((await post(sale)).body.state.wallet).toBe(sold.body.state.wallet);
      expect((await store.farmByOwner(account.player))!.state.bag!.slots.some(s => s.item_id === active.fish_id)).toBe(false);
    } finally { client.close(); await app.close(); }
  });
});
