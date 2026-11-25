/**
 * C-100 装上即建号与闲置地块回收。同一组 HTTP 场景跑内存与 PostgreSQL 两套存储；并发与锁只在真库上有意义。
 * - PARCEL_GUEST_WRITES 打开时游客只多了三条写接口：认领、进入（发赠品）、地块内命令（存档、市场、木匠）；
 *   放弃重选和 Journey 其它写接口仍要账号。默认关。
 * - 游客 30 天（可调）没有登录或使用，地块收回、整行存档，之后能被重新认领；有账号的玩家的地块不收。
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import pg from 'pg';
import { buildApp, plotFor } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { PgStore } from '../../src/db/pg_store.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import type { Store } from '../../src/http/store.js';
import { newInstallKey } from '../../src/http/auth.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { loadParcelRules } from '../../src/parcels/rules.js';
import { MemoryParcelStore, type ParcelStore } from '../../src/parcels/store.js';
import { PgParcelStore } from '../../src/parcels/pg_store.js';
import { parcelGuestWritesFromEnv } from '../../src/parcels/routes.js';
import { DAY_MS, DEFAULT_IDLE_RECLAIM_DAYS, parcelIdleDaysFromEnv, reclaimIdleParcels, scheduleIdleReclaim } from '../../src/parcels/reclaim.js';
import { emptyFarm } from '../../src/parcels/farm.js';

const DSN = process.env.TEST_DATABASE_URL;
if (process.env.CI === '1' && !DSN) throw new Error('CI 下必须设置 TEST_DATABASE_URL');

const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const rules = loadParcelRules(DEFAULT_CONTENT_DIR);
const DATASET = 'sf-dynamic-farm-20261118-r4';
const T0 = Date.UTC(2026, 10, 25, 4);
const A = { parcel_id: 'p-3512001', center: [-122.4194, 37.7749] };
const B = { parcel_id: 'p-3512002', center: [-122.4180, 37.7752] };
const C = { parcel_id: 'p-3512003', center: [-122.4170, 37.7755] };
const IDLE = DEFAULT_IDLE_RECLAIM_DAYS * DAY_MS;

let pool: pg.Pool | undefined;
beforeAll(async () => { if (DSN) { pool = new pg.Pool({ connectionString: DSN, max: 20 }); await migrate(pool); } });
afterAll(async () => { await pool?.end(); });

type Stores = { store: Store; parcels: ParcelStore; archived: () => Promise<Record<string, unknown>[]> };
const makers: [string, boolean, (now: () => number) => Stores][] = [
  ['MemoryStore', true, now => {
    const store = new MemoryStore({ content, timezone: 'America/Los_Angeles', plot: plotFor(content), now, contentVersion: CV });
    const parcels = new MemoryParcelStore(id => store.displayNameOf(id), id => store.playerActivity(id));
    return { store, parcels, archived: async () => structuredClone(parcels.reclaimed) as unknown as Record<string, unknown>[] };
  }],
  ['PgStore', Boolean(DSN), now => ({
    store: new PgStore({ pool: pool!, content, contentVersion: CV, timezone: () => 'America/Los_Angeles', plot: plotFor(content), now }),
    parcels: new PgParcelStore(pool!),
    archived: async () => (await pool!.query('SELECT * FROM parcel_reclaims ORDER BY id')).rows.map(r => ({
      ...r, farm: r.farm_state, claimed_at: Number(r.claimed_at), updated_at: Number(r.updated_at),
      last_active_at: Number(r.last_active_at), reclaimed_at: Number(r.reclaimed_at) })),
  })],
];

const bearer = (token: string) => ({ authorization: `Bearer ${token}` });
let clock = T0;
const appFor = (stores: Stores, opts: { parcelGuestWrites?: boolean; reselect?: boolean } = {}) => buildApp({
  store: stores.store, content, contentVersion: CV, blueprintDir: path.join(ROOT, 'assets', 'blueprints'),
  regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'test-pepper', now: () => clock, realtimeEnabled: false,
  parcels: { store: stores.parcels, rules, reselect: opts.reselect ?? false, guestWrites: opts.parcelGuestWrites },
});

async function account(app: FastifyInstance, name: string): Promise<string> {
  const res = await app.inject({ method: 'POST', url: '/v1/auth/email/register',
    payload: { email: `${name.toLowerCase()}@example.com`, password: 'correct horse', display_name: name } });
  expect(res.statusCode).toBe(201);
  return res.json().token;
}
/** 一次安装：同一个 install_key 再登录就是同一个玩家；卸载重装是新 key。 */
async function install(app: FastifyInstance, key = newInstallKey()): Promise<{ key: string; token: string; player: string }> {
  const res = await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_key: key } });
  expect(res.statusCode).toBe(200);
  return { key, token: res.json().token, player: res.json().player_id };
}
const claim = (app: FastifyInstance, token: string, parcel: { parcel_id: string; center: number[] }) =>
  app.inject({ method: 'POST', url: '/v1/parcels/claim', headers: bearer(token), payload: { dataset_version: DATASET, ...parcel } });
const mine = async (app: FastifyInstance, token: string) =>
  (await app.inject({ method: 'GET', url: '/v1/parcels/mine', headers: bearer(token) })).json().parcel;
const enter = (app: FastifyInstance, token: string) => app.inject({ method: 'POST', url: '/v1/parcels/mine/enter', headers: bearer(token) });
const command = (app: FastifyInstance, token: string, base_version: number, commands: object[]) =>
  app.inject({ method: 'POST', url: '/v1/parcels/mine/commands', headers: bearer(token), payload: { base_version, commands } });
const ownerOf = async (app: FastifyInstance, token: string, id: string) =>
  (await app.inject({ method: 'GET', url: `/v1/parcels?dataset_version=${DATASET}&ids=${id}`, headers: bearer(token) })).json().parcels[0].owner;

for (const [name, enabled, makeStores] of makers) {
  describe.skipIf(!enabled)(`${name}: install-and-play guests`, () => {
    let stores: Stores;
    let app: FastifyInstance;
    beforeEach(async () => {
      if (pool) await truncateAll(pool);
      clock = T0;
      stores = makeStores(() => clock);
      app = await appFor(stores, { parcelGuestWrites: true });
    });
    afterEach(async () => { await app.close(); });

    it('a fresh install plays the whole loop without an account: claim, gift, house, farm, market and carpenter', async () => {
      const g = await install(app);
      expect(await mine(app, g.token)).toBeNull();
      expect((await claim(app, g.token, A)).statusCode).toBe(201);
      expect((await enter(app, g.token)).json()).toMatchObject({ granted: true, parcel: { farm_version: 1 } });
      expect((await command(app, g.token, 1, [{ type: 'place_house', x: 9, y: 9 }, { type: 'clear_obstacle', cell: '2,2' },
        { type: 'till', cell: '1,1' }, { type: 'till', cell: '2,1' },
        { type: 'sow', cell: '1,1', crop: 'crop_carrot' }, { type: 'sow', cell: '2,1', crop: 'crop_carrot' },
        // C-151: the well from the entry's grant, a pail drawn, both cells watered.
        { type: 'place_building', building: 'well', x: 20, y: 20, rotation: 0 }, { type: 'draw_water', building: 2 },
        { type: 'water', cell: '1,1' }, { type: 'water', cell: '2,1' }])).statusCode).toBe(200);
      clock = T0 + 60_000;
      expect((await command(app, g.token, 2, [{ type: 'harvest', cell: '1,1' }, { type: 'harvest', cell: '2,1' }])).statusCode).toBe(200);
      // Market (sell) and carpenter (claim_blueprint) go through the same parcel save.
      expect((await command(app, g.token, 3, [{ type: 'sell', item: 'crop_carrot', count: 2 }])).statusCode).toBe(200);
      expect((await command(app, g.token, 4, [{ type: 'claim_blueprint', blueprint: 'coop' }])).statusCode).toBe(200);
      expect(await mine(app, g.token)).toMatchObject({ parcel_id: A.parcel_id, farm_version: 5, farm: {
        house: { model: 'cottage' }, cleared: ['2,2'], tilled: ['1,1', '2,1'], coins: 24, sales: 1,
        bag: { hoe_starter: 1, seed_carrot: 1, blueprint_coop: 1, pail: 1 } } });
      // The same installation signing in again is the same player with the same parcel.
      const again = await install(app, g.key);
      expect(again.player).toBe(g.player);
      expect((await mine(app, again.token)).farm_version).toBe(5);
    });

    it('uninstall and reinstall is a new player: no home, the old parcel shows as someone else’s', async () => {
      const first = await install(app);
      await claim(app, first.token, A);
      const second = await install(app);
      expect(second.player).not.toBe(first.player);
      expect(await mine(app, second.token)).toBeNull();
      expect(await ownerOf(app, second.token, A.parcel_id)).toBe('other');
      expect((await claim(app, second.token, A)).json().code).toBe('PARCEL_TAKEN');
      expect((await claim(app, second.token, B)).statusCode).toBe(201);
    });

    it('a guest still cannot use any other write: abandon, Journey farms, profile, account', async () => {
      const g = await install(app);
      await claim(app, g.token, A);
      const reselect = await appFor(stores, { parcelGuestWrites: true, reselect: true });
      try {
        const writes: [FastifyInstance, string, string, object?][] = [
          [reselect, 'POST', '/v1/parcels/mine/abandon', {}],
          [app, 'POST', '/v1/farms', { idempotency_key: 'k1', region_id: 'shanghai', layout_patch_id: 'x', blueprint_revision: 1 }],
          [app, 'POST', '/v1/farms/me/commands', { idempotency_key: 'k2', type: 'till', base_version: 0, payload: {} }],
          [app, 'PUT', '/v1/users/me/profile', { display_name: 'Guest' }],
          [app, 'POST', '/v1/auth/email/password', { current_password: 'x', new_password: 'correct horse battery' }],
          [app, 'DELETE', '/v1/users/me', { password: 'x' }],
        ];
        for (const [target, method, url, payload] of writes) {
          const res = await target.inject({ method: method as 'POST' | 'PUT' | 'DELETE', url, headers: bearer(g.token), payload });
          expect.soft(res.statusCode, `${method} ${url}`).toBeGreaterThanOrEqual(400);
          expect.soft([401, 403], `${method} ${url}`).toContain(res.statusCode);
        }
        expect((await mine(app, g.token)).parcel_id).toBe(A.parcel_id);
      } finally { await reselect.close(); }
    });

    it('a guest reads and writes only their own parcel', async () => {
      const ada = await install(app), bob = await install(app);
      await claim(app, ada.token, A); await enter(app, ada.token);
      await command(app, ada.token, 1, [{ type: 'till', cell: '1,1' }]);
      const before = await mine(app, ada.token);
      expect((await command(app, bob.token, before.farm_version, [{ type: 'till', cell: '2,2' }])).json().code).toBe('NO_PARCEL');
      expect((await enter(app, bob.token)).json().code).toBe('NO_PARCEL');
      expect((await claim(app, bob.token, A)).json().code).toBe('PARCEL_TAKEN');
      await claim(app, bob.token, B); await enter(app, bob.token);
      await command(app, bob.token, 1, [{ type: 'till', cell: '3,3' }]);
      expect(await mine(app, ada.token)).toEqual(before);
      // One home per guest, as for accounts.
      expect((await claim(app, ada.token, C)).json().code).toBe('ALREADY_CLAIMED');
    });

    it('with the switch off (the default) guests stay read-only', async () => {
      const closed = await appFor(stores);
      try {
        const g = await install(closed);
        expect(await mine(closed, g.token)).toBeNull();
        for (const res of [await claim(closed, g.token, A), await enter(closed, g.token), await command(closed, g.token, 0, [{ type: 'till', cell: '1,1' }])]) {
          expect(res.statusCode).toBe(401);
          expect(res.json().code).toBe('LOGIN_REQUIRED');
        }
        expect(await ownerOf(closed, g.token, A.parcel_id)).toBe('none');
      } finally { await closed.close(); }
    });

    it('reclaims a guest’s parcel only once it has been idle for more than 30 days; it can then be claimed again', async () => {
      const g = await install(app);
      await claim(app, g.token, A); await enter(app, g.token);
      await command(app, g.token, 1, [{ type: 'till', cell: '1,1' }]);
      const saved = await mine(app, g.token); // last activity: T0
      expect(await reclaimIdleParcels(stores.parcels, 30, T0 + IDLE - 1)).toBe(0);
      expect(await reclaimIdleParcels(stores.parcels, 30, T0 + IDLE)).toBe(0); // exactly 30 days: kept
      expect(await reclaimIdleParcels(stores.parcels, 30, T0 + IDLE + 1)).toBe(1);
      expect(await reclaimIdleParcels(stores.parcels, 30, T0 + IDLE + 2)).toBe(0);
      const [archived] = await stores.archived();
      expect(archived).toMatchObject({ parcel_id: A.parcel_id, player_id: g.player, farm_version: saved.farm_version,
        farm: saved.farm, claimed_at: T0, last_active_at: T0, reclaimed_at: T0 + IDLE + 1 });
      clock = T0 + IDLE + 10;
      const newcomer = await install(app);
      expect(await ownerOf(app, newcomer.token, A.parcel_id)).toBe('none');
      const res = await claim(app, newcomer.token, A);
      expect(res.statusCode).toBe(201);
      expect(res.json().parcel).toMatchObject({ farm_version: 0, farm: emptyFarm() }); // starts fresh
      // The guest who came back has no home now and may claim another.
      expect(await mine(app, g.token)).toBeNull();
      expect((await claim(app, g.token, B)).statusCode).toBe(201);
    });

    it('any sign-in or use of the token counts as activity', async () => {
      const reader = await install(app), returner = await install(app), idle = await install(app);
      await claim(app, reader.token, A); await claim(app, returner.token, B); await claim(app, idle.token, C);
      clock = T0 + 20 * DAY_MS;
      await mine(app, reader.token);          // the app reads its parcel with the saved token
      await install(app, returner.key);       // the app starts and signs in again
      expect(await reclaimIdleParcels(stores.parcels, 30, T0 + IDLE + 1)).toBe(1);
      expect((await stores.archived()).map(r => r.parcel_id)).toEqual([C.parcel_id]);
      expect(await reclaimIdleParcels(stores.parcels, 30, T0 + 20 * DAY_MS + IDLE)).toBe(0);
      expect(await reclaimIdleParcels(stores.parcels, 30, T0 + 20 * DAY_MS + IDLE + 1)).toBe(2);
    });

    it('signing out or revoking every token keeps the real last activity (C-120)', async () => {
      const one = await install(app), all = await install(app), rotated = await install(app);
      await claim(app, one.token, A); await claim(app, all.token, B); await claim(app, rotated.token, C);
      clock = T0 + 20 * DAY_MS; // each guest plays with the token they signed in with at T0
      for (const g of [one, all, rotated]) await mine(app, g.token);
      clock = T0 + 25 * DAY_MS; // then the token goes: sign out of this phone, of every phone, or a new install key
      expect((await app.inject({ method: 'DELETE', url: '/v1/auth/token', headers: bearer(one.token) })).statusCode).toBe(200);
      expect((await app.inject({ method: 'DELETE', url: '/v1/auth/tokens', headers: bearer(all.token) })).statusCode).toBe(200);
      expect((await app.inject({ method: 'POST', url: '/v1/auth/rotate-install-key', headers: bearer(rotated.token),
        payload: { current_install_key: rotated.key, new_install_key: newInstallKey() } })).statusCode).toBe(200);
      for (const g of [one, all, rotated]) expect(await mine(app, g.token)).toBeUndefined(); // 401: no token left
      expect(await reclaimIdleParcels(stores.parcels, 30, T0 + IDLE + 1)).toBe(0); // the sign-in at T0 alone would be idle
      // DELETE /v1/auth/token does not use the token, so its last use stays T0 + 20 days; the other two used it at T0 + 25 days.
      expect(await reclaimIdleParcels(stores.parcels, 30, T0 + 20 * DAY_MS + IDLE)).toBe(0);
      expect(await reclaimIdleParcels(stores.parcels, 30, T0 + 20 * DAY_MS + IDLE + 1)).toBe(1);
      expect(await reclaimIdleParcels(stores.parcels, 30, T0 + 25 * DAY_MS + IDLE)).toBe(0);
      expect(await reclaimIdleParcels(stores.parcels, 30, T0 + 25 * DAY_MS + IDLE + 1)).toBe(2);
      expect((await stores.archived()).map(r => [r.parcel_id, r.last_active_at])).toEqual([
        [A.parcel_id, T0 + 20 * DAY_MS], [B.parcel_id, T0 + 25 * DAY_MS], [C.parcel_id, T0 + 25 * DAY_MS]]);
    });

    it('an expired token keeps its last use as activity', async () => {
      const g = await install(app);
      await claim(app, g.token, A);
      clock = T0 + 20 * DAY_MS;
      await mine(app, g.token);
      clock = T0 + 20 * DAY_MS + 91 * DAY_MS; // past the 90-day token idle limit: the token is dropped on use
      expect(await mine(app, g.token)).toBeUndefined();
      expect(await reclaimIdleParcels(stores.parcels, 400, T0 + 20 * DAY_MS + 400 * DAY_MS)).toBe(0);
      expect(await reclaimIdleParcels(stores.parcels, 400, T0 + 20 * DAY_MS + 400 * DAY_MS + 1)).toBe(1);
    });

    it('never reclaims a parcel of a player with an account', async () => {
      const ada = await account(app, 'Ada');
      await claim(app, ada, A);
      expect(await reclaimIdleParcels(stores.parcels, 30, T0 + 400 * DAY_MS)).toBe(0);
      expect((await mine(app, ada)).parcel_id).toBe(A.parcel_id);
    });

    it('the period is adjustable and 0 turns reclaiming off', async () => {
      const g = await install(app);
      await claim(app, g.token, A);
      expect(await reclaimIdleParcels(stores.parcels, 0, T0 + 400 * DAY_MS)).toBe(0);
      expect(await reclaimIdleParcels(stores.parcels, 7, T0 + 7 * DAY_MS)).toBe(0);
      expect(await reclaimIdleParcels(stores.parcels, 7, T0 + 7 * DAY_MS + 1)).toBe(1);
    });

    it('works through every idle parcel in batches', async () => {
      const ids = Array.from({ length: 7 }, (_, i) => ({ parcel_id: `p-35130${i}`, center: [-122.41 - i / 1000, 37.77] }));
      for (const parcel of ids) await claim(app, (await install(app)).token, parcel);
      expect(await reclaimIdleParcels(stores.parcels, 30, T0 + IDLE + 1, 3)).toBe(7);
      expect((await stores.archived()).map(r => r.parcel_id).sort()).toEqual(ids.map(p => p.parcel_id).sort());
    });

    it('the scheduler reclaims on start and on its interval, logs, and stops', async () => {
      const g = await install(app);
      await claim(app, g.token, A);
      const lines: string[] = [];
      let now = T0 + IDLE + 1;
      const stop = scheduleIdleReclaim(stores.parcels, 30, () => now, line => { lines.push(line); }, 20);
      try {
        await expect.poll(() => lines.length).toBe(1);
        expect(lines[0]).toBe('idle parcel reclaim: 1 parcel(s) idle over 30 days returned');
        const h = await install(app);
        await claim(app, h.token, B);
        now = clock + IDLE + 1;
        await expect.poll(() => lines.length).toBe(2);
      } finally { stop(); }
    });
  });
}

describe.skipIf(!DSN)('PgParcelStore: reclaiming against concurrent writes and claims', () => {
  let app: FastifyInstance;
  let stores: Stores;
  beforeEach(async () => {
    await truncateAll(pool!);
    clock = T0;
    stores = makers[1][2](() => clock);
    app = await appFor(stores, { parcelGuestWrites: true });
  });
  afterEach(async () => { await app.close(); });

  it('skips a parcel whose row is being written, and reclaims it on the next round', async () => {
    const g = await install(app);
    await claim(app, g.token, A);
    const lock = await pool!.connect();
    try {
      await lock.query('BEGIN');
      await lock.query("SELECT 1 FROM parcel_claims WHERE parcel_id = $1 FOR UPDATE", [A.parcel_id]);
      expect(await reclaimIdleParcels(stores.parcels, 30, T0 + IDLE + 1)).toBe(0);
      await lock.query('COMMIT');
    } finally { lock.release(); }
    expect(await reclaimIdleParcels(stores.parcels, 30, T0 + IDLE + 1)).toBe(1);
  });

  it('two reclaimers at once archive each parcel exactly once', async () => {
    for (const parcel of [A, B, C]) await claim(app, (await install(app)).token, parcel);
    const other = new PgParcelStore(pool!);
    const [x, y] = await Promise.all([reclaimIdleParcels(stores.parcels, 30, T0 + IDLE + 1, 1), reclaimIdleParcels(other, 30, T0 + IDLE + 1, 1)]);
    expect(x + y).toBe(3);
    expect((await pool!.query('SELECT parcel_id FROM parcel_reclaims ORDER BY parcel_id')).rows.map(r => r.parcel_id)).toEqual([A, B, C].map(p => p.parcel_id));
    expect((await pool!.query('SELECT count(*)::int AS n FROM parcel_claims')).rows[0].n).toBe(0);
  });

  it('newcomers racing for a just-reclaimed parcel: exactly one wins', async () => {
    const g = await install(app);
    await claim(app, g.token, A);
    clock = T0 + IDLE + 5;
    const racers = await Promise.all(Array.from({ length: 5 }, () => install(app)));
    const [reclaimed, ...claims] = await Promise.all([reclaimIdleParcels(stores.parcels, 30, T0 + IDLE + 1),
      ...racers.map(r => claim(app, r.token, A))]);
    expect(reclaimed).toBe(1);
    // Claims that ran before the reclaim met the old owner; at most one of the others wins.
    expect(claims.filter(r => r.statusCode === 201).length).toBeLessThanOrEqual(1);
    expect(claims.every(r => r.statusCode === 201 || r.json().code === 'PARCEL_TAKEN')).toBe(true);
    const after = await Promise.all(racers.map(r => claim(app, r.token, A)));
    expect(after.filter(r => r.statusCode === 201 || r.statusCode === 200)).toHaveLength(1);
  });

  it('deleting the guest player removes the archived copy too (no orphaned saves)', async () => {
    const g = await install(app);
    await claim(app, g.token, A);
    await reclaimIdleParcels(stores.parcels, 30, T0 + IDLE + 1);
    await pool!.query('DELETE FROM players WHERE id = $1', [g.player]);
    expect((await pool!.query('SELECT count(*)::int AS n FROM parcel_reclaims')).rows[0].n).toBe(0);
  });
});

describe('switches', () => {
  it('PARCEL_GUEST_WRITES: off unless exactly 1; anything else refuses to start', () => {
    expect(parcelGuestWritesFromEnv({})).toBe(false);
    expect(parcelGuestWritesFromEnv({ PARCEL_GUEST_WRITES: '' })).toBe(false);
    expect(parcelGuestWritesFromEnv({ PARCEL_GUEST_WRITES: '0' })).toBe(false);
    expect(parcelGuestWritesFromEnv({ PARCEL_GUEST_WRITES: '1' })).toBe(true);
    for (const bad of ['true', 'yes', ' 1', '2']) expect(parcelGuestWritesFromEnv({ PARCEL_GUEST_WRITES: bad })).toBeNull();
  });
  it('PARCEL_IDLE_RECLAIM_DAYS: 30 by default, 0 turns it off, whole days up to 3650', () => {
    expect(parcelIdleDaysFromEnv({})).toBe(30);
    expect(parcelIdleDaysFromEnv({ PARCEL_IDLE_RECLAIM_DAYS: '' })).toBe(30);
    expect(parcelIdleDaysFromEnv({ PARCEL_IDLE_RECLAIM_DAYS: '0' })).toBe(0);
    expect(parcelIdleDaysFromEnv({ PARCEL_IDLE_RECLAIM_DAYS: '45' })).toBe(45);
    expect(parcelIdleDaysFromEnv({ PARCEL_IDLE_RECLAIM_DAYS: '3650' })).toBe(3650);
    for (const bad of ['-1', '1.5', '3651', 'thirty', ' 30']) expect(parcelIdleDaysFromEnv({ PARCEL_IDLE_RECLAIM_DAYS: bad })).toBeNull();
  });
});
