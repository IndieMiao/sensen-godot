/** PostgreSQL AccountStore。首次登录的并发用「先插身份、撞唯一键就让位」处理，见 signIn。 */
import { randomUUID } from 'node:crypto';
import type pg from 'pg';
import type { AccountStore, DeletionRecord, IdentityRow, UserRow } from '../http/accounts.js';
import type { FirebaseIdentity } from '../http/firebase_token.js';

const rowToUser = (r: Record<string, unknown>): UserRow => ({
  id: r.id as string,
  email: (r.email as string | null) ?? null,
  email_verified: r.email_verified as boolean,
  display_name: (r.display_name as string | null) ?? null,
  created_at: Number(r.created_at),
  last_seen_at: Number(r.last_seen_at),
});

const rowToIdentity = (r: Record<string, unknown>): IdentityRow => ({
  provider: 'firebase', provider_uid: r.provider_uid as string, user_id: r.user_id as string,
  sign_in_provider: (r.sign_in_provider as string | null) ?? null, created_at: Number(r.created_at),
});

export class PgAccountStore implements AccountStore {
  constructor(private readonly pool: pg.Pool) {}

  async signIn(identity: FirebaseIdentity, now: number) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const found = await client.query(
        `SELECT user_id FROM user_identities WHERE provider = 'firebase' AND provider_uid = $1 FOR UPDATE`,
        [identity.uid]);
      if (found.rowCount) {
        const user = await this.touch(client, found.rows[0].user_id as string, identity, now);
        await client.query('COMMIT');
        return { user, created: false };
      }
      // 先插用户再插身份：身份表的主键 (provider, uid) 是并发首登的裁判。输掉的那一方
      // 撤掉自己刚插的用户行，改用赢家的——两边都拿到同一个 user_id。
      const userId = randomUUID();
      await client.query(
        `INSERT INTO users (id, email, email_verified, display_name, created_at, last_seen_at)
         VALUES ($1, $2, $3, NULL, $4, $4)`,
        [userId, identity.email ?? null, identity.emailVerified, now]);
      const claimed = await client.query(
        `INSERT INTO user_identities (provider, provider_uid, user_id, sign_in_provider, created_at)
         VALUES ('firebase', $1, $2, $3, $4) ON CONFLICT (provider, provider_uid) DO NOTHING RETURNING user_id`,
        [identity.uid, userId, identity.signInProvider ?? null, now]);
      if (claimed.rowCount) {
        const r = await client.query('SELECT * FROM users WHERE id = $1', [userId]);
        await client.query('COMMIT');
        return { user: rowToUser(r.rows[0]), created: true };
      }
      await client.query('DELETE FROM users WHERE id = $1', [userId]);
      const winner = await client.query(
        `SELECT user_id FROM user_identities WHERE provider = 'firebase' AND provider_uid = $1`, [identity.uid]);
      const user = await this.touch(client, winner.rows[0].user_id as string, identity, now);
      await client.query('COMMIT');
      return { user, created: false };
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  }

  private async touch(client: pg.PoolClient, userId: string, identity: FirebaseIdentity, now: number): Promise<UserRow> {
    const r = await client.query(
      `UPDATE users SET last_seen_at = $2, email = COALESCE($3, email), email_verified = $4
        WHERE id = $1 RETURNING *`,
      [userId, now, identity.email ?? null, identity.emailVerified]);
    return rowToUser(r.rows[0]);
  }

  async userByFirebaseUid(uid: string) {
    const r = await this.pool.query(
      `SELECT u.* FROM users u JOIN user_identities i ON i.user_id = u.id
        WHERE i.provider = 'firebase' AND i.provider_uid = $1`, [uid]);
    return r.rowCount ? rowToUser(r.rows[0]) : null;
  }

  async userById(id: string) {
    if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
    const r = await this.pool.query('SELECT * FROM users WHERE id = $1', [id]);
    return r.rowCount ? rowToUser(r.rows[0]) : null;
  }

  async identitiesOf(userId: string) {
    const r = await this.pool.query(
      'SELECT * FROM user_identities WHERE user_id = $1 ORDER BY created_at, provider_uid', [userId]);
    return r.rows.map(rowToIdentity);
  }

  async deleteUser(userId: string, t: DeletionRecord) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const del = await client.query('DELETE FROM users WHERE id = $1', [userId]);
      if (!del.rowCount) { await client.query('ROLLBACK'); return false; }
      await client.query(
        `INSERT INTO account_deletions (user_id, provider_uid, requested_at, source, apple_revocation)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (user_id) DO UPDATE SET requested_at = EXCLUDED.requested_at, source = EXCLUDED.source`,
        [t.user_id, t.provider_uid, t.requested_at, t.source, t.apple_revocation]);
      await client.query('COMMIT');
      return true;
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  }

  async deletion(userId: string) {
    if (!/^[0-9a-f-]{36}$/i.test(userId)) return null;
    const r = await this.pool.query('SELECT * FROM account_deletions WHERE user_id = $1', [userId]);
    if (!r.rowCount) return null;
    const x = r.rows[0];
    return {
      user_id: x.user_id as string, provider_uid: x.provider_uid as string,
      requested_at: Number(x.requested_at), source: x.source as DeletionRecord['source'],
      apple_revocation: x.apple_revocation as DeletionRecord['apple_revocation'],
    };
  }
}
