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
import { buildApp, blueprintSets, loadBlueprint } from '../../src/http/app.js';
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
const sets = blueprintSets(bp);
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
    content, timezone: SH, blueprint: sets, now: () => clock, contentVersion: CV })],
  ['PgStore', Boolean(DSN), () => new PgStore({
    pool: pool!, content, contentVersion: CV, timezone: () => SH,
    blueprint: () => sets, now: () => clock })],
];

for (const [name, enabled, makeStore] of makers) {
  describe.skipIf(!enabled)(`${name} 的跨实现不变量`, () => {
    let app: FastifyInstance;

    beforeEach(async () => {
      clock = T0;
      qa = new Set();
      if (pool) await truncateAll(pool);
      app = await buildApp({
        store: makeStore() as never, content, contentVersion: CV,
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
        cells: Object.keys(farm.json().state.cells) as string[] };
    }
    const cmd = (token: string, body: object) =>
      app.inject({ method: 'POST', url: '/v1/farms/me/commands', headers: authed(token), payload: body });
    const me = (token: string) =>
      app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(token) });

    it('QA 时间变换在写路径上生效', async () => {
      // 这条就是 MemoryStore 曾经漏掉的那一处。
      const s = await seed();
      qa.add(s.player_id);
      const skip = await cmd(s.token, { idempotency_key: 'q1', base_version: s.version,
        type: 'qa_skip_days', payload: { days: 1 } });
      expect(skip.statusCode).toBe(200);
      const next = await cmd(s.token, { idempotency_key: 'c1', base_version: skip.json().version,
        type: 'clear_cells', payload: { cell_ids: [s.cells[0]] } });
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
        type: 'clear_cells', payload: { cell_ids: [s.cells[0]] } };
      const a = await cmd(s.token, body);
      const b = await cmd(s.token, body);
      expect(a.json().outcome).toBe('applied');
      expect(b.json().outcome).toBe('replayed');
      expect((await me(s.token)).json().version).toBe(s.version + 1);
    });

    it('base_version 落后时报 409 而不是覆盖', async () => {
      const s = await seed();
      await cmd(s.token, { idempotency_key: 'x1', base_version: s.version,
        type: 'clear_cells', payload: { cell_ids: [s.cells[0]] } });
      const stale = await cmd(s.token, { idempotency_key: 'x2', base_version: s.version,
        type: 'clear_cells', payload: { cell_ids: [s.cells[1]] } });
      expect(stale.statusCode).toBe(409);
      expect(stale.json().code).toBe('VERSION_CONFLICT');
    });

    it('被拒的命令不涨版本', async () => {
      const s = await seed();
      const r = await cmd(s.token, { idempotency_key: 'bad', base_version: s.version,
        type: 'till_cells', payload: { cell_ids: [s.cells[0]] } });   // 没清理就翻土
      expect(r.statusCode).toBe(422);
      expect((await me(s.token)).json().version).toBe(s.version);
    });

    it('真实时钟回拨时有效时间不倒退', async () => {
      const s = await seed();
      clock = T0 + 60_000;
      await cmd(s.token, { idempotency_key: 'm1', base_version: s.version,
        type: 'clear_cells', payload: { cell_ids: [s.cells[0]] } });
      const high = (await me(s.token)).json().state.clock.last_effective_now;
      clock = T0;
      const v = (await me(s.token)).json().version;
      await cmd(s.token, { idempotency_key: 'm2', base_version: v,
        type: 'till_cells', payload: { cell_ids: [s.cells[0]] } });
      expect((await me(s.token)).json().state.clock.last_effective_now).toBeGreaterThanOrEqual(high);
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
