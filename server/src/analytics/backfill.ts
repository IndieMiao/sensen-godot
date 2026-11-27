/**
 * 把已有注册补发进 Mixpanel（C-203，可选，一次性）：按 users.created_at 给每个账号报一条 account_created，方便从开服第一天算留存。
 * 时间取账号建立时间，去重键与实时上报相同（accountCreatedInsertId），重复运行或与实时上报重叠都只算一次。
 * 入口 tools/mixpanel_backfill_signups.ts；不加 --send 只数不发，不会自动运行。
 */
import { EVENTS, accountCreatedInsertId } from './events.js';
import type { Analytics } from './mixpanel.js';

/** 注册方式：邀请账号 invite；Apple / Google 首登建号 apple / google；其余是邮箱注册 email。取账号最早的一条身份。 */
export const SIGNUPS_SQL = `
  SELECT u.id, u.created_at,
    COALESCE((SELECT CASE WHEN i.sign_in_provider LIKE 'invite:%' THEN 'invite'
                          WHEN i.provider IN ('apple', 'google') THEN i.provider ELSE 'email' END
                FROM user_identities i WHERE i.user_id = u.id ORDER BY i.created_at, i.provider LIMIT 1), 'email') AS method
    FROM users u WHERE u.created_at >= $1 ORDER BY u.created_at, u.id`;

export interface SignupRow { id: string; created_at: string | number; method: string }
export interface Queryable { query(sql: string, params: unknown[]): Promise<{ rows: SignupRow[] }> }

/** 返回找到的账号数；send=false 只数不报。每 batch 条就等这一批发完，队列不会积压。 */
export async function backfillSignups(db: Queryable, analytics: Analytics, o: { since: number; send: boolean; batch?: number }): Promise<number> {
  const { rows } = await db.query(SIGNUPS_SQL, [o.since]);
  if (!o.send) return rows.length;
  const batch = o.batch ?? 500;
  for (const [i, r] of rows.entries()) {
    analytics.track(EVENTS.accountCreated, r.id, { method: r.method, backfill: true },
      { time: Number(r.created_at), insertId: accountCreatedInsertId(r.id) });
    if ((i + 1) % batch === 0) await analytics.flush();
  }
  await analytics.close();
  return rows.length;
}
