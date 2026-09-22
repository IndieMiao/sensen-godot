import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { PgStore } from '../../src/db/pg_store.js';
import { migrate } from '../../src/db/migrate.js';
import { initialExpedition, type Effect } from '../../src/realtime/model.js';
import { content, cv, memory, seed, sets } from './helpers.js';
import type { Store } from '../../src/http/store.js';

let pool: pg.Pool | undefined;
beforeAll(async () => {
  if (!process.env.TEST_DATABASE_URL) return;
  pool = new pg.Pool({ connectionString: process.env.TEST_DATABASE_URL, max: 5 });
  await migrate(pool);
});
afterAll(async () => { await pool?.end(); });

for (const backend of ['memory', 'postgres']) describe.skipIf(backend === 'postgres' && !process.env.TEST_DATABASE_URL)(backend + ' room transactions', () => {
  const store = (): Store => backend === 'memory' ? memory() : new PgStore({ pool: pool!, content, contentVersion: cv,
    timezone: () => 'Asia/Shanghai', plot: sets, now: Date.now });
  it('atomically checkpoints a kill with personal bound loot and replays a lost acknowledgement once', async () => {
    const s = store(), a = await seed(s), b = await seed(s), key = 'mine:' + randomUUID(), commit = randomUUID();
    const mine = initialExpedition(content); mine.floors['3'].monsters[0].hp = 0; mine.floors['3'].cleared = true;
    const effects: Effect[] = [{ player: a.player, loot: { seed_R: 2, copper_ore: 1 } }, { player: b.player, loot: { seed_R: 3 } }];
    const before = (await s.farmByOwner(a.player))!;
    const first = await s.realtimeCommit(key, 0, commit, mine, effects);
    const retry = await s.realtimeCommit(key, 0, commit, mine, effects);
    expect(retry).toEqual(first);
    const farm = (await s.farmByOwner(a.player))!;
    expect(farm.version).toBe(before.version + 1);
    expect(farm.state.inventory.seeds.R.bound).toBe(before.state.inventory.seeds.R.bound + 2);
    expect((await s.realtimeLoad(key))!.mine.floors['3'].monsters[0].hp).toBe(0);
    await expect(s.realtimeCommit(key, 0, randomUUID(), mine, effects)).rejects.toThrow('ROOM_CONFLICT');
  });
  it('rolls back all recipients and the world when any recipient is missing', async () => {
    const s = store(), a = await seed(s), key = 'mine:' + randomUUID();
    const before = structuredClone(await s.farmByOwner(a.player));
    await expect(s.realtimeCommit(key, 0, randomUUID(), initialExpedition(content),
      [{ player: a.player, loot: { stone: 2 } }, { player: randomUUID(), loot: { stone: 2 } }])).rejects.toThrow('NO_FARM');
    expect(await s.farmByOwner(a.player)).toEqual(before);
    expect(await s.realtimeLoad(key)).toBeNull();
  });
  it('serializes two room settlements into the same farm without losing either reward', async () => {
    const s = store(), a = await seed(s);
    const before = (await s.farmByOwner(a.player))!.state.journey!.materials?.stone ?? 0;
    await Promise.all([1, 2].map(quantity => s.realtimeCommit('mine:' + randomUUID(), 0, randomUUID(), initialExpedition(content),
      [{ player: a.player, loot: { stone: quantity } }])));
    expect((await s.farmByOwner(a.player))!.state.journey!.materials!.stone).toBe(before + 3);
  });
  it('uses current persisted health for rescue and preserves existing personal mine progress', async () => {
    const s = store(), a = await seed(s), key = 'mine:' + randomUUID();
    const before = structuredClone((await s.farmByOwner(a.player))!.state.mine);
    const result = await s.realtimeCommit(key, 0, randomUUID(), initialExpedition(content),
      [{ player: a.player, raw_damage: 10000, elevator: true }]);
    expect(result.checkpoint.rescued).toEqual([a.player]);
    const farm = (await s.farmByOwner(a.player))!;
    expect(farm.state.character!.hp).toBe(1);
    expect(farm.state.mine!.elevator_unlocked).toBe(true);
    if (before) expect({ ...farm.state.mine, elevator_unlocked: before.elevator_unlocked }).toEqual(before);
  });
  it('persists party membership independently of mine bindings, then dissolves it atomically', async () => {
    const s = store(), a = await seed(s), b = await seed(s);
    const own = randomUUID(); await s.realtimeDirectory(b.player, 'bind', own);
    const party = await s.realtimeDirectory(a.player, 'create');
    await s.realtimeDirectory(b.player, 'join', party.party!.code);
    expect((await s.realtimeDirectory(a.player)).farm_access).toBe(false);
    await s.realtimeDirectory(a.player, 'farm_access', 'allow');
    expect((await s.realtimeDirectory(a.player)).farm_access).toBe(true);
    expect((await s.realtimeHomes([a.player]))[0].party_farm_access).toBe(party.party!.id);
    expect((await s.realtimeDirectory(b.player)).instance).toBe(own);
    await s.realtimeDirectory(a.player, 'disband');
    expect(await s.realtimeDirectory(b.player)).toEqual({ instance: own, party: null, farm_access: false });
    expect((await s.realtimeDirectory(a.player)).farm_access).toBe(false);
  });
});
