/**
 * 两套 Store 的一致性：同一串 HTTP 请求打在 MemoryStore 与 PgStore 上，行为必须一样。
 *
 * 它们是同一份写路径语义的两个实现，改一处忘另一处不会有任何编译错误——2026-09-04 的
 * QA 时钟就是这么漏的：PgStore 加了时间变换，MemoryStore 没加，于是测试与本地开发看到
 * 的行为和线上不一致，而线上正是没人天天盯着的那个。
 *
 * 只钉**两边都必须有**的跨实现不变量，各自的细节测试留在原来的套件里。
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import pg from 'pg';
import path from 'node:path';
import { PgStore } from '../../src/db/pg_store.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import { buildApp, loadBlueprint, plotFor } from '../../src/http/app.js';
import type { Store } from '../../src/http/store.js';
import { newInstallKey } from '../../src/http/auth.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { at, SH } from '../domain/helpers.js';

const DSN = process.env.TEST_DATABASE_URL;
if (process.env.CI === '1' && !DSN)
  throw new Error('CI 下必须设置 TEST_DATABASE_URL');

const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const BLUEPRINTS = path.join(ROOT, 'assets', 'blueprints');
const REGIONS = path.join(DEFAULT_CONTENT_DIR, 'regions.json');
const bp = loadBlueprint(BLUEPRINTS, 'sh_a', 2)!;
const sets = plotFor(content);
const T0 = at('2026-09-04T10:00:00+08:00');

let pool: pg.Pool | undefined;
let clock = T0;
let qa: Set<string>;

beforeAll(async () => {
  if (!DSN) return;
  pool = new pg.Pool({ connectionString: DSN, max: 5 });
  await migrate(pool);
});
afterAll(async () => { await pool?.end(); });

const makers: [string, boolean, () => object][] = [
  ['MemoryStore', true, () => new MemoryStore({
    content, timezone: SH, plot: sets, now: () => clock, contentVersion: CV })],
  ['PgStore', Boolean(DSN), () => new PgStore({
    pool: pool!, content, contentVersion: CV, timezone: () => SH,
    plot: sets, now: () => clock })],
];

for (const [name, enabled, makeStore] of makers) {
  describe.skipIf(!enabled)(`${name} 的跨实现不变量`, () => {
    let app: FastifyInstance;
    let currentStore: Store;

    beforeEach(async () => {
      clock = T0;
      qa = new Set();
      if (pool) await truncateAll(pool);
      currentStore = makeStore() as Store;
      app = await buildApp({ guestWrites: true,
        store: currentStore, content, contentVersion: CV,
        blueprintDir: BLUEPRINTS, regionsFile: REGIONS,
        pepper: 'test-pepper', now: () => clock, qaPlayerIds: qa,
      });
    });
    afterEach(async () => { await app.close(); });

    const authed = (token: string) => ({ authorization: `Bearer ${token}` });
    async function seed() {
      const login = await app.inject({ method: 'POST', url: '/v1/auth/anonymous',
        payload: { install_key: newInstallKey() } });
      const { token, player_id } = login.json();
      const farm = await app.inject({ method: 'POST', url: '/v1/farms', headers: authed(token),
        payload: { idempotency_key: 'seed', region_id: 'shanghai',
          layout_patch_id: 'sh_a', blueprint_revision: 2 } });
      return { token, player_id, version: farm.json().version as number,
        farm_id: farm.json().farm_id as string,
        // 开局一格未开垦；j=0/1 两行在布局里是纯土地，拿来当稳定的工作面。
        cells: ["0,0", "1,0", "2,0", "3,0"] };
    }
    const cmd = (token: string, body: object) =>
      app.inject({ method: 'POST', url: '/v1/farms/me/commands', headers: authed(token), payload: body });
    const me = (token: string) =>
      app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(token) });

    it('custom farm position persists across reads, commands and public snapshots', async () => {
      const login = await app.inject({ method: 'POST', url: '/v1/auth/anonymous',
        payload: { install_key: newInstallKey() } });
      const token = login.json().token as string;
      const location = { lat: 31.225, lng: 121.485 };
      const created = await app.inject({ method: 'POST', url: '/v1/farms', headers: authed(token),
        payload: { idempotency_key: 'placed', region_id: 'shanghai', layout_patch_id: 'sh_a',
          blueprint_revision: 2, location } });
      expect(created.statusCode).toBe(201);
      expect(created.json().location).toEqual(location);
      expect((await currentStore.farmById(created.json().farm_id))?.location).toEqual(location);
      expect((await me(token)).json().location).toEqual(location);
      const opened = await cmd(token, { idempotency_key: 'open', base_version: 0,
        type: 'set_visit_access', payload: { access: 'anyone' } });
      expect(opened.json().location).toEqual(location);
      const visitor = await seed();
      const nearby = await app.inject({ method: 'GET', url: '/v1/nearby?region_id=shanghai', headers: authed(visitor.token) });
      expect(nearby.json().entries[0].location).toEqual(location);
      const snapshotUrl = `/v1/farms/${created.json().farm_id}/snapshot`;
      const snapshot = await app.inject({ method: 'GET', url: snapshotUrl, headers: authed(visitor.token) });
      expect(snapshot.json().location).toEqual(location);
      await cmd(token, { idempotency_key: 'hide', base_version: opened.json().version,
        type: 'set_location_visible', payload: { visible: false } });
      const hidden = await app.inject({ method: 'GET', url: snapshotUrl, headers: authed(visitor.token) });
      expect(hidden.json().snapshot_taken_at).toBe(snapshot.json().snapshot_taken_at);
      expect(hidden.json()).not.toHaveProperty('location');
      expect(hidden.json()).not.toHaveProperty('region_id');
      const hiddenNearby = await app.inject({ method: 'GET', url: '/v1/nearby?region_id=shanghai', headers: authed(visitor.token) });
      expect(hiddenNearby.json().entries[0]).not.toHaveProperty('location');
      expect((await me(token)).json().location).toEqual(location);
    });

    it('concurrent creation replays the chosen position and cannot move an existing farm', async () => {
      const login = await app.inject({ method: 'POST', url: '/v1/auth/anonymous',
        payload: { install_key: newInstallKey() } });
      const token = login.json().token as string;
      const location = { lat: 31.225, lng: 121.485 };
      const payload = { idempotency_key: 'placed', region_id: 'shanghai', layout_patch_id: 'sh_a',
        blueprint_revision: 2, location };
      const create = (body: object) => app.inject({ method: 'POST', url: '/v1/farms',
        headers: authed(token), payload: body });
      const [first, retry] = await Promise.all([create(payload), create(payload)]);
      expect([first.statusCode, retry.statusCode].sort()).toEqual([200, 201]);
      expect(first.json().farm_id).toBe(retry.json().farm_id);
      const different = await create({ ...payload, location: { lat: 31.235, lng: 121.495 } });
      expect(different.statusCode).toBe(409);
      expect(different.json().code).toBe('IDEMPOTENCY_MISMATCH');
      const anotherKey = await create({ ...payload, idempotency_key: 'move' });
      expect(anotherKey.statusCode).toBe(409);
      expect((await me(token)).json().location).toEqual(location);
    });

    it('rejects invalid and cross-city positions before creating a farm; legacy farms stay unplaced', async () => {
      const login = await app.inject({ method: 'POST', url: '/v1/auth/anonymous',
        payload: { install_key: newInstallKey() } });
      const token = login.json().token as string;
      const payload = { idempotency_key: 'bad', region_id: 'shanghai', layout_patch_id: 'sh_a', blueprint_revision: 2 };
      for (const [location, expected] of [[{ lat: '31.2', lng: 121.4 }, 400],
        [{ lat: 34.05, lng: -118.24 }, 422], [{ lat: 30.6701, lng: 121.4 }, 422]]) {
        const response = await app.inject({ method: 'POST', url: '/v1/farms', headers: authed(token),
          payload: { ...payload, location } });
        expect(response.statusCode).toBe(expected);
      }
      expect((await me(token)).statusCode).toBe(404);
      const legacy = await app.inject({ method: 'POST', url: '/v1/farms', headers: authed(token), payload });
      expect(legacy.statusCode).toBe(201);
      expect(legacy.json()).not.toHaveProperty('location');
      expect((await me(token)).json()).not.toHaveProperty('location');
    });

    it('QA 时间变换在写路径上生效', async () => {
      // 这条就是 MemoryStore 曾经漏掉的那一处。
      const s = await seed();
      qa.add(s.player_id);
      const skip = await cmd(s.token, { idempotency_key: 'q1', base_version: s.version,
        type: 'qa_skip_days', payload: { days: 1 } });
      expect(skip.statusCode).toBe(200);
      const next = await cmd(s.token, { idempotency_key: 'c1', base_version: skip.json().version,
        type: 'till_cells', payload: { cell_ids: [s.cells[0]] } });
      expect(next.statusCode).toBe(200);
      expect(next.json().state.clock.player_day_id).toBe('2026-09-05');
      expect(next.json().state.clock.weather_day_index).toBe(1);
    });

    it('QA 时间变换在读路径上也生效', async () => {
      const s = await seed();
      qa.add(s.player_id);
      const t0 = (await me(s.token)).json().server_time;
      await cmd(s.token, { idempotency_key: 'q2', base_version: s.version,
        type: 'qa_set_clock', payload: { scale: 480 } });
      clock += 3 * 60_000;
      expect((await me(s.token)).json().server_time - t0).toBe(24 * 3600_000);
    });

    it('同一幂等键重放不产生第二次副作用', async () => {
      const s = await seed();
      const body = { idempotency_key: 'dup', base_version: s.version,
        type: 'till_cells', payload: { cell_ids: [s.cells[0]] } };
      const a = await cmd(s.token, body);
      const b = await cmd(s.token, body);
      expect(a.json().outcome).toBe('applied');
      expect(b.json().outcome).toBe('replayed');
      expect((await me(s.token)).json().version).toBe(s.version + 1);
    });

    it('base_version 落后时报 409 而不是覆盖', async () => {
      const s = await seed();
      await cmd(s.token, { idempotency_key: 'x1', base_version: s.version,
        type: 'till_cells', payload: { cell_ids: [s.cells[0]] } });
      const stale = await cmd(s.token, { idempotency_key: 'x2', base_version: s.version,
        type: 'till_cells', payload: { cell_ids: [s.cells[1]] } });
      expect(stale.statusCode).toBe(409);
      expect(stale.json().code).toBe('VERSION_CONFLICT');
    });

    it('被拒的命令不涨版本', async () => {
      const s = await seed();
      // 房子占的格永远不可开垦：一条稳定被领域层拒绝的命令。
      const r = await cmd(s.token, { idempotency_key: 'bad', base_version: s.version,
        type: 'till_cells', payload: { cell_ids: [sets.anchors.house.join(',')] } });
      expect(r.statusCode).toBe(422);
      expect((await me(s.token)).json().version).toBe(s.version);
    });

    it('真实时钟回拨时有效时间不倒退', async () => {
      const s = await seed();
      clock = T0 + 60_000;
      await cmd(s.token, { idempotency_key: 'm1', base_version: s.version,
        type: 'till_cells', payload: { cell_ids: [s.cells[0]] } });
      const high = (await me(s.token)).json().state.clock.last_effective_now;
      clock = T0;
      const v = (await me(s.token)).json().version;
      await cmd(s.token, { idempotency_key: 'm2', base_version: v,
        type: 'till_cells', payload: { cell_ids: [s.cells[0]] } });
      expect((await me(s.token)).json().state.clock.last_effective_now).toBeGreaterThanOrEqual(high);
    });

    it('G2：nearby 只列开放访问的、排除自己、按建场顺序', async () => {
      const a = await seed();
      const b = await seed();
      const c = await seed();
      for (const s of [a, b])
        expect((await cmd(s.token, { idempotency_key: 'va', base_version: s.version,
          type: 'set_visit_access', payload: { access: 'anyone' } })).statusCode).toBe(200);
      const seen = await app.inject({ method: 'GET', url: '/v1/nearby?region_id=shanghai', headers: authed(c.token) });
      expect(seen.statusCode).toBe(200);
      expect(seen.json().count).toBe(2);
      // 测试时钟不走，三座同毫秒建成 → 排序键 (created_at, id) 退化成按 id；两套 Store 必须一致。
      expect(seen.json().entries.map((e: { farm_id: string }) => e.farm_id)).toEqual([a.farm_id, b.farm_id].sort());
      const selfView = await app.inject({ method: 'GET', url: '/v1/nearby?region_id=shanghai', headers: authed(a.token) });
      expect(selfView.json().entries.map((e: { farm_id: string }) => e.farm_id)).toEqual([b.farm_id]);
      expect(selfView.json().count).toBe(1);
    });

    it('G2：快照同槽复用、跨槽内容不变 revision 不动、内容变了才 +1', async () => {
      const a = await seed();
      const v = await seed();
      await cmd(a.token, { idempotency_key: 'va', base_version: a.version,
        type: 'set_visit_access', payload: { access: 'anyone' } });
      const url = `/v1/farms/${a.farm_id}/snapshot`;
      const s1 = await app.inject({ method: 'GET', url, headers: authed(v.token) });
      expect(s1.statusCode).toBe(200);
      expect(s1.json().snapshot_revision).toBe(1);
      // 同槽内主人操作了，访客仍拿到同一份——不暴露操作时刻。
      await cmd(a.token, { idempotency_key: 'c1', base_version: a.version + 1,
        type: 'till_cells', payload: { cell_ids: [a.cells[0]] } });
      const s2 = await app.inject({ method: 'GET', url, headers: authed(v.token) });
      expect(s2.json().snapshot_taken_at).toBe(s1.json().snapshot_taken_at);
      expect(s2.json().cells).toEqual(s1.json().cells);
      // 跨槽：内容变了 → revision 2
      clock += 15 * 60_000;
      const s3 = await app.inject({ method: 'GET', url, headers: authed(v.token) });
      expect(s3.json().snapshot_revision).toBe(2);
      expect(s3.json().cells.find((c: { cell_id: string }) => c.cell_id === a.cells[0]).state).toBe('tilled');
      // 再跨槽：内容没变 → revision 仍 2，只有 taken_at 推进
      clock += 15 * 60_000;
      const s4 = await app.inject({ method: 'GET', url, headers: authed(v.token) });
      expect(s4.json().snapshot_revision).toBe(2);
      expect(s4.json().snapshot_taken_at).toBe(s3.json().snapshot_taken_at + 15 * 60_000);
    });

    it('G2：ensureSystemFarm 幂等，且出现在 nearby 里', async () => {
      const { PRESET_SPECS, buildPresetFarm, presetHmac } = await import('../../src/domain/presets.js');
      const spec = PRESET_SPECS.find(s => s.region === 'shanghai')!;
      const bpB = loadBlueprint(BLUEPRINTS, spec.layout, spec.revision)!;
      const farm = buildPresetFarm(spec, plotFor(content), content, SH, clock);
      await currentStore.ensureSystemFarm(presetHmac(spec.layout), farm);
      await currentStore.ensureSystemFarm(presetHmac(spec.layout), farm);
      const me = await seed();
      const seen = await app.inject({ method: 'GET', url: '/v1/nearby?region_id=shanghai', headers: authed(me.token) });
      expect(seen.json().entries.filter((e: { farm_id: string }) => e.farm_id === farm.id)).toHaveLength(1);
      expect(seen.json().entries[0].avatar_ref).toBe(spec.avatar_ref);
      const snap = await app.inject({ method: 'GET', url: `/v1/farms/${farm.id}/snapshot`, headers: authed(me.token) });
      expect(snap.statusCode).toBe(200);
      expect(snap.json().avatar_ref).toBe(spec.avatar_ref);
    });

    it('非白名单玩家发 QA 命令一律 403', async () => {
      const s = await seed();
      const r = await cmd(s.token, { idempotency_key: 'q3', base_version: s.version,
        type: 'qa_skip_days', payload: { days: 1 } });
      expect(r.statusCode).toBe(403);
      expect(r.json().code).toBe('QA_ONLY');
    });
  });
}
