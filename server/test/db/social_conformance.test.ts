/** MemorySocialStore 与 PgSocialStore 的一致性；PG 部分没有 TEST_DATABASE_URL 时跳过，CI 下必须有。 */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import pg from 'pg';
import { randomUUID } from 'node:crypto';
import type { SocialStore } from '../../src/http/social.js';
import { MemorySocialStore } from '../../src/http/memory_social.js';
import { PgSocialStore } from '../../src/db/pg_social.js';
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

const T0 = Date.UTC(2026, 8, 7, 9, 0, 0);
const known = new Set<string>();
/** PG 需要 users 行满足外键；内存版用同一个集合模拟。 */
async function mkUser(): Promise<string> {
  const id = randomUUID();
  known.add(id);
  if (pool) await pool.query('INSERT INTO users (id, email, email_verified, created_at, last_seen_at) VALUES ($1, NULL, false, $2, $2)', [id, T0]);
  return id;
}

const impls: [string, () => Promise<SocialStore>][] = [
  ['memory', async () => new MemorySocialStore(async id => known.has(id))],
  ...(DSN ? [['pg', async () => { await truncateAll(pool!); return new PgSocialStore(pool!); }] as [string, () => Promise<SocialStore>]] : []),
];

describe.each(impls)('SocialStore[%s]', (_name, make) => {
  let s: SocialStore;
  beforeEach(async () => { known.clear(); s = await make(); });

  it('ensureProfile 幂等；update 只改给的字段；handle 撞别人 HANDLE_TAKEN、自己重设不算', async () => {
    const a = await mkUser(); const b = await mkUser();
    const p = await s.ensureProfile(a, 'A', T0);
    expect(await s.ensureProfile(a, 'ignored', T0 + 1)).toEqual(p);
    await s.ensureProfile(b, 'B', T0);
    const u = await s.updateProfile(a, { handle: 'alpha', bio: 'x', avatar: { k: 1 } }, T0 + 5);
    expect(u).toMatchObject({ handle: 'alpha', bio: 'x', avatar: { k: 1 }, display_name: 'A', updated_at: T0 + 5 });
    expect(await s.updateProfile(b, { handle: 'alpha' }, T0 + 6)).toBe('HANDLE_TAKEN');
    expect(await s.updateProfile(a, { handle: 'alpha' }, T0 + 7)).toMatchObject({ handle: 'alpha' });
    expect(await s.updateProfile(a, { handle: null, following_visible: false }, T0 + 8)).toMatchObject({ handle: null, following_visible: false });
    expect(await s.profileByHandle('alpha')).toBeNull();
    expect(await s.updateProfile(randomUUID(), { bio: 'nope' }, T0)).toBeNull();
    expect((await s.profiles([a, b, randomUUID()])).size).toBe(2);
  });

  it('关注幂等、取关幂等、关系与计数一致；followee 不存在 missing', async () => {
    const a = await mkUser(); const b = await mkUser();
    expect(await s.follow(a, b, T0)).toEqual({ created: true });
    expect(await s.follow(a, b, T0 + 1)).toEqual({ created: false });
    expect(await s.relation(a, b)).toEqual({ following: true, followed_by: false, close_friends: false });
    expect(await s.follow(b, a, T0 + 2)).toEqual({ created: true });
    expect(await s.relation(a, b)).toEqual({ following: true, followed_by: true, close_friends: true });
    expect(await s.counts(a)).toEqual({ followers: 1, following: 1 });
    expect(await s.unfollow(a, b)).toEqual({ removed: true });
    expect(await s.unfollow(a, b)).toEqual({ removed: false });
    expect(await s.relation(b, a)).toEqual({ following: true, followed_by: false, close_friends: false });
    expect((await s.follow(a, randomUUID(), T0)).missing).toBe(true);
    expect((await s.follow(a, 'garbage', T0)).missing).toBe(true);
  });

  it('列表倒序 + 键集分页，同一时间戳按对方 id 倒序稳定', async () => {
    const me = await mkUser();
    const ids: string[] = [];
    for (let i = 0; i < 5; i++) { const u = await mkUser(); ids.push(u); await s.follow(u, me, T0 + (i < 2 ? 0 : i)); }
    const p1 = await s.followers(me, null, 2);
    expect(p1.items).toHaveLength(2);
    expect(p1.next_cursor).toBeTruthy();
    const p2 = await s.followers(me, p1.next_cursor, 2);
    const p3 = await s.followers(me, p2.next_cursor, 2);
    const seen = [...p1.items, ...p2.items, ...p3.items].map(f => f.follower_id);
    expect(new Set(seen).size).toBe(5);
    expect(p3.next_cursor).toBeNull();
    const ts = [...p1.items, ...p2.items, ...p3.items].map(f => f.created_at);
    expect(ts).toEqual([...ts].sort((x, y) => y - x));
    const tied = seen.slice(3);
    expect(tied).toEqual([...tied].sort().reverse());
    expect((await s.following(ids[0], null, 10)).items.map(f => f.followee_id)).toEqual([me]);
  });

  it('未读粉丝计数与已读；删号清资料与两个方向的关注', async () => {
    const a = await mkUser(); const b = await mkUser(); const c = await mkUser();
    await s.ensureProfile(a, 'A', T0);
    await s.follow(b, a, T0); await s.follow(c, a, T0 + 1); await s.follow(a, c, T0 + 2);
    expect(await s.unseenFollowerCount(a)).toBe(2);
    await s.markFollowersSeen(a);
    expect(await s.unseenFollowerCount(a)).toBe(0);
    await s.deleteUser(a);
    expect(await s.profile(a)).toBeNull();
    expect(await s.counts(b)).toEqual({ followers: 0, following: 0 });
    expect(await s.counts(c)).toEqual({ followers: 0, following: 0 });
  });
});
