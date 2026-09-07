/**
 * MemoryAccountStore 与 PgAccountStore 的一致性（同 store_conformance 的理由：两套实现
 * 改一处忘另一处没有编译错误）。PG 部分没有 TEST_DATABASE_URL 时跳过，CI 下必须有。
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import pg from 'pg';
import type { AccountStore } from '../../src/http/accounts.js';
import { MemoryAccountStore } from '../../src/http/memory_accounts.js';
import { PgAccountStore } from '../../src/db/pg_accounts.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import type { FirebaseIdentity } from '../../src/http/firebase_token.js';

const DSN = process.env.TEST_DATABASE_URL;
if (process.env.CI === '1' && !DSN) throw new Error('CI 下必须设置 TEST_DATABASE_URL');

let pool: pg.Pool | undefined;
beforeAll(async () => {
  if (!DSN) return;
  pool = new pg.Pool({ connectionString: DSN, max: 5 });
  await migrate(pool);
});
afterAll(async () => { await pool?.end(); });

const T0 = Date.UTC(2026, 8, 7, 8, 0, 0);
const identity = (uid = 'uid-1', over: Partial<FirebaseIdentity> = {}): FirebaseIdentity => ({
  uid, email: `${uid}@example.test`, emailVerified: false, signInProvider: 'password',
  authTime: T0 / 1000, expiresAt: T0 / 1000 + 3600, ...over,
});

const impls: [string, () => Promise<AccountStore>][] = [
  ['memory', async () => new MemoryAccountStore()],
  ...(DSN ? [['pg', async () => { await truncateAll(pool!); return new PgAccountStore(pool!); }] as [string, () => Promise<AccountStore>]] : []),
];

describe.each(impls)('AccountStore[%s]', (_name, make) => {
  let s: AccountStore;
  beforeEach(async () => { s = await make(); });

  it('同一 uid 两次登录是同一用户；第二次刷新 last_seen 与邮箱验证状态', async () => {
    const a = await s.signIn(identity(), T0);
    const b = await s.signIn(identity('uid-1', { emailVerified: true }), T0 + 5000);
    expect(a.created).toBe(true);
    expect(b.created).toBe(false);
    expect(b.user.id).toBe(a.user.id);
    expect(b.user.last_seen_at).toBe(T0 + 5000);
    expect(b.user.email_verified).toBe(true);
    expect(b.user.created_at).toBe(T0);
    expect(await s.userByFirebaseUid('uid-1')).toEqual(b.user);
    expect(await s.userById(a.user.id)).toEqual(b.user);
  });

  it('并发首次登录只建一个用户，所有人拿到同一个 user_id', async () => {
    const rs = await Promise.all(Array.from({ length: 6 }, () => s.signIn(identity('race'), T0)));
    const ids = new Set(rs.map(r => r.user.id));
    expect(ids.size).toBe(1);
    expect(rs.filter(r => r.created).length).toBe(1);
    expect((await s.identitiesOf(rs[0].user.id)).length).toBe(1);
  });

  it('身份记录带登录方式；不同 uid 各自独立', async () => {
    const a = await s.signIn(identity('a', { signInProvider: 'apple.com' }), T0);
    const b = await s.signIn(identity('b'), T0);
    expect(await s.identitiesOf(a.user.id)).toEqual([
      { provider: 'firebase', provider_uid: 'a', user_id: a.user.id, sign_in_provider: 'apple.com', created_at: T0 },
    ]);
    expect(await s.identitiesOf(b.user.id)).toHaveLength(1);
    expect(a.user.id).not.toBe(b.user.id);
  });

  it('删号：用户与身份都没了、墓碑留下、再登录是新用户；重复删返回 false', async () => {
    const { user } = await s.signIn(identity(), T0);
    const tomb = { user_id: user.id, provider_uid: 'uid-1', requested_at: T0 + 1, source: 'app' as const, apple_revocation: 'n/a' as const };
    expect(await s.deleteUser(user.id, tomb)).toBe(true);
    expect(await s.userById(user.id)).toBeNull();
    expect(await s.userByFirebaseUid('uid-1')).toBeNull();
    expect(await s.identitiesOf(user.id)).toEqual([]);
    expect(await s.deletion(user.id)).toEqual(tomb);
    expect(await s.deleteUser(user.id, tomb)).toBe(false);
    const again = await s.signIn(identity(), T0 + 10);
    expect(again.created).toBe(true);
    expect(again.user.id).not.toBe(user.id);
  });

  it('非 uuid 的 id 当不存在，不抛', async () => {
    expect(await s.userById('not-a-uuid')).toBeNull();
    expect(await s.deletion('not-a-uuid')).toBeNull();
  });
});
