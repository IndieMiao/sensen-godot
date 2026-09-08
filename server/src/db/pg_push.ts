/** PostgreSQL DeviceStore：token 唯一，换人登录即改归属。 */
import type pg from 'pg';
import type { DeviceRow, DeviceStore, Platform } from '../http/push.js';

const rowTo = (r: Record<string, unknown>): DeviceRow => ({
  user_id: r.user_id as string, token: r.token as string,
  platform: r.platform as Platform, updated_at: Number(r.updated_at),
});
const isUuid = (s: string): boolean => /^[0-9a-f-]{36}$/i.test(s);

export class PgDeviceStore implements DeviceStore {
  constructor(private readonly pool: pg.Pool) {}

  async upsert(userId: string, token: string, platform: Platform, now: number) {
    const r = await this.pool.query(
      `INSERT INTO device_tokens (token, user_id, platform, updated_at) VALUES ($1, $2, $3, $4)
       ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, updated_at = EXCLUDED.updated_at
       RETURNING *`, [token, userId, platform, now]);
    return rowTo(r.rows[0]);
  }
  async remove(token: string) {
    await this.pool.query('DELETE FROM device_tokens WHERE token = $1', [token]);
  }
  async tokensFor(userIds: string[]) {
    const ids = userIds.filter(isUuid);
    if (ids.length === 0) return [];
    const r = await this.pool.query('SELECT * FROM device_tokens WHERE user_id = ANY($1::uuid[])', [ids]);
    return r.rows.map(rowTo);
  }
  async deleteUser(userId: string) {
    if (!isUuid(userId)) return;
    await this.pool.query('DELETE FROM device_tokens WHERE user_id = $1', [userId]);
  }
}
