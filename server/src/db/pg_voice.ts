/** PostgreSQL VoiceStore。语音内容不落库，只存房间与麦位状态。 */
import type pg from 'pg';
import type { Role, RoomMemberRow, RoomRow, VoiceStore } from '../http/voice.js';

const rowToRoom = (r: Record<string, unknown>): RoomRow => ({
  id: r.id as string, title: r.title as string, host_id: r.host_id as string,
  created_at: Number(r.created_at), closed_at: r.closed_at === null || r.closed_at === undefined ? null : Number(r.closed_at),
});
const rowToMember = (r: Record<string, unknown>): RoomMemberRow => ({
  room_id: r.room_id as string, user_id: r.user_id as string, role: r.role as Role,
  muted: Boolean(r.muted), joined_at: Number(r.joined_at),
});
const isUuid = (s: string): boolean => /^[0-9a-f-]{36}$/i.test(s);

export class PgVoiceStore implements VoiceStore {
  constructor(private readonly pool: pg.Pool) {}

  async createRoom(row: RoomRow) {
    const r = await this.pool.query(
      'INSERT INTO voice_rooms (id, title, host_id, created_at, closed_at) VALUES ($1, $2, $3, $4, NULL) RETURNING *',
      [row.id, row.title, row.host_id, row.created_at]);
    return rowToRoom(r.rows[0]);
  }
  async room(roomId: string) {
    if (!isUuid(roomId)) return null;
    const r = await this.pool.query('SELECT * FROM voice_rooms WHERE id = $1', [roomId]);
    return r.rowCount ? rowToRoom(r.rows[0]) : null;
  }
  async openRooms(limit: number) {
    const r = await this.pool.query('SELECT * FROM voice_rooms WHERE closed_at IS NULL ORDER BY created_at DESC LIMIT $1', [limit]);
    return r.rows.map(rowToRoom);
  }
  async closeRoom(roomId: string, now: number) {
    if (!isUuid(roomId)) return;
    await this.pool.query('UPDATE voice_rooms SET closed_at = $2 WHERE id = $1 AND closed_at IS NULL', [roomId, now]);
    await this.pool.query('DELETE FROM voice_room_members WHERE room_id = $1', [roomId]);
  }
  async join(roomId: string, userId: string, role: Role, now: number) {
    const r = await this.pool.query(
      `INSERT INTO voice_room_members (room_id, user_id, role, muted, joined_at) VALUES ($1, $2, $3, false, $4)
       ON CONFLICT (room_id, user_id) DO UPDATE SET role = voice_room_members.role
       RETURNING *`, [roomId, userId, role, now]);
    return rowToMember(r.rows[0]);
  }
  async leave(roomId: string, userId: string) {
    await this.pool.query('DELETE FROM voice_room_members WHERE room_id = $1 AND user_id = $2', [roomId, userId]);
  }
  async members(roomId: string) {
    if (!isUuid(roomId)) return [];
    const r = await this.pool.query('SELECT * FROM voice_room_members WHERE room_id = $1 ORDER BY joined_at', [roomId]);
    return r.rows.map(rowToMember);
  }
  async member(roomId: string, userId: string) {
    if (!isUuid(roomId) || !isUuid(userId)) return null;
    const r = await this.pool.query('SELECT * FROM voice_room_members WHERE room_id = $1 AND user_id = $2', [roomId, userId]);
    return r.rowCount ? rowToMember(r.rows[0]) : null;
  }
  async setRole(roomId: string, userId: string, role: Role) {
    const r = await this.pool.query(
      'UPDATE voice_room_members SET role = $3 WHERE room_id = $1 AND user_id = $2 RETURNING *', [roomId, userId, role]);
    return r.rowCount ? rowToMember(r.rows[0]) : null;
  }
  async setMuted(roomId: string, userId: string, muted: boolean) {
    const r = await this.pool.query(
      `UPDATE voice_room_members SET muted = $3, role = CASE WHEN $3 AND role = 'speaker' THEN 'listener' ELSE role END
       WHERE room_id = $1 AND user_id = $2 RETURNING *`, [roomId, userId, muted]);
    return r.rowCount ? rowToMember(r.rows[0]) : null;
  }
  async roomsOf(userId: string) {
    if (!isUuid(userId)) return [];
    const r = await this.pool.query(
      `SELECT DISTINCT r.* FROM voice_rooms r
         LEFT JOIN voice_room_members m ON m.room_id = r.id
        WHERE r.host_id = $1 OR m.user_id = $1`, [userId]);
    return r.rows.map(rowToRoom);
  }
  async deleteUser(userId: string) {
    if (!isUuid(userId)) return;
    await this.pool.query('DELETE FROM voice_room_members WHERE user_id = $1', [userId]);
    await this.pool.query('UPDATE voice_rooms SET closed_at = $2 WHERE host_id = $1 AND closed_at IS NULL', [userId, Date.now()]);
  }
}
