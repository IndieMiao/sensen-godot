/** PostgreSQL LocationStore：每人一行最新位置（user_locations），不存轨迹。 */
import type pg from 'pg';
import type { LocationRow, LocationStore } from '../http/location.js';

const rowTo = (r: Record<string, unknown>): LocationRow => ({
  user_id: r.user_id as string, lat: Number(r.lat), lng: Number(r.lng),
  accuracy_m: r.accuracy_m === null || r.accuracy_m === undefined ? null : Number(r.accuracy_m),
  updated_at: Number(r.updated_at),
});
const isUuid = (s: string): boolean => /^[0-9a-f-]{36}$/i.test(s);

export class PgLocationStore implements LocationStore {
  constructor(private readonly pool: pg.Pool) {}

  async upsert(userId: string, lat: number, lng: number, accuracyM: number | null, now: number) {
    const r = await this.pool.query(
      `INSERT INTO user_locations (user_id, lat, lng, accuracy_m, updated_at) VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (user_id) DO UPDATE SET lat = EXCLUDED.lat, lng = EXCLUDED.lng, accuracy_m = EXCLUDED.accuracy_m, updated_at = EXCLUDED.updated_at
       RETURNING *`, [userId, lat, lng, accuracyM, now]);
    return rowTo(r.rows[0]);
  }
  async remove(userId: string) {
    if (!isUuid(userId)) return;
    await this.pool.query('DELETE FROM user_locations WHERE user_id = $1', [userId]);
  }
  async get(userId: string) {
    if (!isUuid(userId)) return null;
    const r = await this.pool.query('SELECT * FROM user_locations WHERE user_id = $1', [userId]);
    return r.rowCount ? rowTo(r.rows[0]) : null;
  }
  async many(userIds: string[]) {
    const ids = userIds.filter(isUuid);
    const out = new Map<string, LocationRow>();
    if (ids.length === 0) return out;
    const r = await this.pool.query('SELECT * FROM user_locations WHERE user_id = ANY($1::uuid[])', [ids]);
    for (const row of r.rows) { const l = rowTo(row); out.set(l.user_id, l); }
    return out;
  }
}
