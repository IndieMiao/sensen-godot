/** MemoryModerationStore 与 PgModerationStore 的一致性；PG 部分没有 TEST_DATABASE_URL 时跳过。 */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import pg from 'pg';
import { randomUUID } from 'node:crypto';
import type { ModerationStore } from '../../src/http/moderation.js';
import { MemoryModerationStore } from '../../src/http/memory_moderation.js';
import { PgModerationStore } from '../../src/db/pg_moderation.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';

const DSN = process.env.TEST_DATABASE_URL;
if (process.env.CI === '1' && !DSN) throw new Error('CI 下必须设置 TEST_DATABASE_URL');

let pool: pg.Pool | undefined;
beforeAll(async () => {
  if (!DSN) return;
  pool = new pg.Pool({ connectionString: DSN, max: 5 });
  await migrate(pool);
});
afterAll(async () => { await pool?.end(); });

const T0 = Date.UTC(2026, 8, 7, 11, 0, 0);
async function mkUser(): Promise<string> {
  const id = randomUUID();
  if (pool) await pool.query('INSERT INTO users (id, email, email_verified, created_at, last_seen_at) VALUES ($1, NULL, false, $2, $2)', [id, T0]);
  return id;
}
const impls: [string, () => Promise<ModerationStore>][] = [
  ['memory', async () => new MemoryModerationStore()],
  ...(DSN ? [['pg', async () => { await truncateAll(pool!); return new PgModerationStore(pool!); }] as [string, () => Promise<ModerationStore>]] : []),
];

describe.each(impls)('ModerationStore[%s]', (_name, make) => {
  let s: ModerationStore;
  beforeEach(async () => { s = await make(); });

  it('举报去重 + 不同举报人计数；open 列表正序；resolve 单条与按目标', async () => {
    const t = randomUUID(); const r1 = await mkUser(); const r2 = await mkUser(); const admin = await mkUser();
    const mk = (reporter: string, target = t, now = T0) => ({ id: randomUUID(), reporter_id: reporter, target_type: 'post' as const, target_id: target, reason: 'spam', detail: '', created_at: now });
    const a = await s.addReport(mk(r1));
    expect(a).toMatchObject({ created: true, distinctReporters: 1 });
    const again = await s.addReport(mk(r1, t, T0 + 5));
    expect(again).toMatchObject({ created: false, distinctReporters: 1 });
    expect(again.report.id).toBe(a.report.id);
    const b = await s.addReport(mk(r2, t, T0 + 1));
    expect(b.distinctReporters).toBe(2);
    const other = await s.addReport(mk(r1, randomUUID(), T0 + 2));
    expect((await s.openReports(10)).map(x => x.id)).toEqual([a.report.id, b.report.id, other.report.id]);
    expect((await s.resolveReport(other.report.id, admin, 'dismiss', T0 + 9))).toMatchObject({ status: 'resolved', action: 'dismiss', resolved_by: admin, resolved_at: T0 + 9 });
    expect(await s.resolveReport(other.report.id, admin, 'dismiss', T0 + 9)).toBeNull();
    expect(await s.resolveTarget('post', t, admin, 'remove_content', T0 + 10)).toBe(2);
    expect(await s.openReports(10)).toEqual([]);
    expect((await s.report(a.report.id))!.action).toBe('remove_content');
    expect(await s.report('garbage')).toBeNull();
  });

  it('拉黑幂等、任一方向判定、around 集合、列表倒序；封禁与解封；删号与导出', async () => {
    const a = await mkUser(); const b = await mkUser(); const c = await mkUser();
    expect(await s.block(a, b, T0)).toEqual({ created: true });
    expect(await s.block(a, b, T0)).toEqual({ created: false });
    expect(await s.block(c, a, T0 + 1)).toEqual({ created: true });
    expect(await s.blockedEither(a, b)).toBe(true);
    expect(await s.blockedEither(b, a)).toBe(true);
    expect(await s.blockedEither(b, c)).toBe(false);
    expect((await s.blockedIdsAround(a)).sort()).toEqual([b, c].sort());
    expect((await s.blocks(a)).map(x => x.blocked_id)).toEqual([b]);
    expect(await s.unblock(a, b)).toEqual({ removed: true });
    expect(await s.unblock(a, b)).toEqual({ removed: false });
    expect(await s.unblock(a, 'garbage')).toEqual({ removed: false });
    await s.ban(b, 'x', a, T0);
    expect(await s.isBanned(b)).toBe(true);
    await s.unban(b);
    expect(await s.isBanned(b)).toBe(false);
    await s.addReport({ id: randomUUID(), reporter_id: a, target_type: 'user', target_id: b, reason: 'spam', detail: '', created_at: T0 });
    expect((await s.exportUser(a)).reports_filed).toHaveLength(1);
    expect((await s.exportUser(a)).blocks).toHaveLength(0);
    await s.deleteUser(a);
    expect(await s.blockedIdsAround(c)).toEqual([]);
    expect(await s.openReports(10)).toEqual([]);
  });
});
