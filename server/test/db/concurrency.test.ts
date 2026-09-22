import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import pg from 'pg';
import path from 'node:path';
import { PgStore } from '../../src/db/pg_store.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import { assertResettable, ResetRefused } from '../../src/db/reset.js';
import { loadBlueprint, plotFor } from '../../src/http/app.js';
import { installKeyHmac, newInstallKey } from '../../src/http/auth.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { createInitialState } from '../../src/domain/state.js';
import { at, SH } from '../domain/helpers.js';
import { payloadHash } from '../../src/http/hash.js';
import type { FarmRow } from '../../src/http/dto.js';
import { randomUUID } from 'node:crypto';
import { isTillable, type PlotLayout } from '../../src/domain/plot.js';

/** 一小片可开垦格，代替过去写死的固定田畦（SGODOT-128 自由格子种田）。 */
function soilCells(p: PlotLayout, count: number): string[] {
  const out: string[] = [];
  for (let j = 0; j < p.gy && out.length < count; j++)
    for (let i = 0; i < p.gx && out.length < count; i++)
      if (isTillable(p, `${i},${j}`)) out.push(`${i},${j}`);
  return out;
}


const DSN = process.env.TEST_DATABASE_URL;
/**
 * CI 必须提供 TEST_DATABASE_URL——DB 层的单写者语义只有真库能验证，允许静默 skip
 * 等于允许这一层永远没被测过（Codex 二审 Important 12）。本机没库时才跳过。
 */
if (process.env.CI === '1' && !DSN)
  throw new Error('CI 下必须设置 TEST_DATABASE_URL，DB 套件不允许 skip');

const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const bp = loadBlueprint(path.join(ROOT, 'assets', 'blueprints'), 'sh_a', 2)!;
const sets = plotFor(content);
const NOW = at('2026-09-04T10:00:00+08:00');

describe.skipIf(!DSN)('PostgreSQL 单写者与幂等', () => {
  let pool: pg.Pool;
  let store: PgStore;

  beforeAll(async () => {
    pool = new pg.Pool({ connectionString: DSN, max: 30 });
    await migrate(pool);
  });
  afterAll(async () => { await pool?.end(); });
  beforeEach(async () => {
    await truncateAll(pool);
    store = new PgStore({
      pool, content, contentVersion: CV, timezone: () => SH,
      plot: sets, now: () => NOW,
    });
  });

  const newFarm = (ownerId: string): FarmRow => ({
    id: randomUUID(), owner_id: ownerId, region_id: 'shanghai', layout_patch_id: 'sh_a',
    blueprint_revision: 2, version: 0, location_visible: true, visit_access: 'only_me',
    state: createInitialState({
      player_day_id: '2026-09-04', field_condition: 'sunny', now: NOW, wallet: 180,
    }),
  });

  async function seedFarm() {
    const { player } = await store.authAnonymous(installKeyHmac(newInstallKey(), 'p'));
    const farm = newFarm(player.id);
    const r = await store.createFarm({
      ownerId: player.id, idempotencyKey: 'seed', payloadHash: 'h',
      regionId: 'shanghai', layoutPatchId: 'sh_a', blueprintRevision: 2, build: () => farm,
    });
    expect(r.kind).toBe('created');
    return player.id;
  }

  const cells = soilCells(sets, 12);
  const env = (key: string, base: number, ids: string[]) => ({
    idempotency_key: key, base_version: base, type: 'till_cells' as const,
    payload: { cell_ids: ids },
  });

  it('测试 A：20 条并发命令带同一 base_version，恰有一条 applied，其余 409', async () => {
    const owner = await seedFarm();
    const results = await Promise.all(Array.from({ length: 20 }, (_, i) =>
      store.applyCommand(owner, env(`k${i}`, 0, [cells[i % cells.length]]),
        { type: 'till_cells', cell_ids: [cells[i % cells.length]] })));
    const applied = results.filter(r => r.kind === 'applied');
    const conflicts = results.filter(r => r.kind === 'version_conflict');
    expect(applied).toHaveLength(1);
    expect(conflicts).toHaveLength(19);
    const farm = await store.farmByOwner(owner);
    expect(farm!.version).toBe(1);
  });

  it('测试 B：按 409 更新版本换新 key 重发，最终全部 applied，版本严格递增无空洞', async () => {
    const owner = await seedFarm();
    const wanted = cells.slice(0, 9);
    let applied = 0;
    for (const [i, cell] of wanted.entries()) {
      let attempt = 0;
      for (;;) {
        const farm = await store.farmByOwner(owner);
        const out = await store.applyCommand(owner, env(`b${i}-${attempt}`, farm!.version, [cell]),
          { type: 'till_cells', cell_ids: [cell] });
        if (out.kind === 'applied') { applied += 1; break; }
        expect(out.kind).toBe('version_conflict');
        attempt += 1;
      }
    }
    expect(applied).toBe(9);
    const farm = await store.farmByOwner(owner);
    expect(farm!.version).toBe(9);
    const log = await pool.query(
      'SELECT base_version FROM commands WHERE farm_id = $1 AND outcome = $2 ORDER BY id',
      [farm!.id, 'applied']);
    expect(log.rows.map(r => r.base_version)).toEqual([0, 1, 2, 3, 4, 5, 6, 7, 8]);
  });

  it('同一幂等键并发只应用一次', async () => {
    const owner = await seedFarm();
    const e = env('same', 0, [cells[0]]);
    const cmd = { type: 'till_cells' as const, cell_ids: [cells[0]] };
    const results = await Promise.all(Array.from({ length: 10 }, () => store.applyCommand(owner, e, cmd)));
    expect(results.filter(r => r.kind === 'applied')).toHaveLength(1);
    expect(results.filter(r => r.kind === 'replayed').length).toBeGreaterThan(0);
    const farm = await store.farmByOwner(owner);
    expect(farm!.version).toBe(1);
  });

  it('不同农场并行不互相阻塞', async () => {
    const a = await seedFarm();
    const b = await seedFarm();
    const [ra, rb] = await Promise.all([
      store.applyCommand(a, env('a', 0, [cells[0]]), { type: 'till_cells', cell_ids: [cells[0]] }),
      store.applyCommand(b, env('b', 0, [cells[0]]), { type: 'till_cells', cell_ids: [cells[0]] }),
    ]);
    expect(ra.kind).toBe('applied');
    expect(rb.kind).toBe('applied');
  });

  it('失败命令也落日志，同 key 重放拿回失败结果', async () => {
    const owner = await seedFarm();
    const bad = { idempotency_key: 'bad', base_version: 0, type: 'water_cells' as const,
      payload: { cell_ids: [cells[0]] } };
    const first = await store.applyCommand(owner, bad, { type: 'water_cells', cell_ids: [cells[0]] });
    expect(first.kind).toBe('rejected');
    const again = await store.applyCommand(owner, bad, { type: 'water_cells', cell_ids: [cells[0]] });
    expect(again.kind).toBe('replayed');
    const farm = await store.farmByOwner(owner);
    expect(farm!.version).toBe(0); // 失败不推进版本
  });

  it('版本不匹配的农场 fail closed，但旧命令的重试仍能拿回结果', async () => {
    const owner = await seedFarm();
    const e = env('v1', 0, [cells[0]]);
    await store.applyCommand(owner, e, { type: 'till_cells', cell_ids: [cells[0]] });
    // 模拟部署了新内容
    const stale = new PgStore({
      pool, content, contentVersion: 'CHANGED', timezone: () => SH, plot: sets, now: () => NOW,
    });
    const replay = await stale.applyCommand(owner, e, { type: 'till_cells', cell_ids: [cells[0]] });
    expect(replay.kind).toBe('replayed'); // 幂等查表先于版本门控
    const fresh = await stale.applyCommand(owner, env('v2', 1, [cells[1]]),
      { type: 'till_cells', cell_ids: [cells[1]] });
    expect(fresh.kind).toBe('version_mismatch');
  });

  it('建农场：同 key 同 payload 重放，同 key 换 payload 报 mismatch', async () => {
    const { player } = await store.authAnonymous(installKeyHmac(newInstallKey(), 'p'));
    const farm = newFarm(player.id);
    const a = await store.createFarm({ ownerId: player.id, idempotencyKey: 'k', payloadHash: 'h1',
      regionId: 'shanghai', layoutPatchId: 'sh_a', blueprintRevision: 2, build: () => farm });
    expect(a.kind).toBe('created');
    const b = await store.createFarm({ ownerId: player.id, idempotencyKey: 'k', payloadHash: 'h1',
      regionId: 'shanghai', layoutPatchId: 'sh_a', blueprintRevision: 2, build: () => farm });
    expect(b.kind).toBe('replayed');
    const c = await store.createFarm({ ownerId: player.id, idempotencyKey: 'k', payloadHash: 'h2',
      regionId: 'los_angeles', layoutPatchId: 'la_a', blueprintRevision: 2, build: () => farm });
    expect(c.kind).toBe('idempotency_mismatch');
  });

  it('活跃 token 上限在事务里生效，并发签发也不会超过 5 个', async () => {
    const hmac = installKeyHmac(newInstallKey(), 'p');
    await Promise.all(Array.from({ length: 12 }, () => store.authAnonymous(hmac)));
    const r = await pool.query('SELECT count(*)::int AS n FROM tokens');
    expect(r.rows[0].n).toBeLessThanOrEqual(5);
  });
});

describe('reset 守卫', () => {
  it('拒绝非开发主机的 DSN', () => {
    process.env.ALLOW_RESET = '1';
    expect(() => assertResettable('postgres://u:p@farm.sensenjoy.cn:5432/db')).toThrowError(ResetRefused);
    expect(() => assertResettable('postgres://u:p@192.168.124.53:5432/db')).not.toThrow();
    delete process.env.ALLOW_RESET;
  });

  it('没有 ALLOW_RESET=1 时即使在开发主机上也拒绝', () => {
    expect(() => assertResettable('postgres://u:p@192.168.124.53:5432/db')).toThrowError(ResetRefused);
  });
});
