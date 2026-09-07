/** PostgreSQL ModerationStore。 */
import type pg from 'pg';
import type { BlockRow, ModerationStore, ReportRow } from '../http/moderation.js';

const isUuid = (s: string): boolean => /^[0-9a-f-]{36}$/i.test(s);
const rowToReport = (r: Record<string, unknown>): ReportRow => ({
  id: r.id as string, reporter_id: r.reporter_id as string, target_type: r.target_type as ReportRow['target_type'],
  target_id: r.target_id as string, reason: r.reason as string, detail: r.detail as string, created_at: Number(r.created_at),
  status: r.status as ReportRow['status'], resolved_at: r.resolved_at == null ? null : Number(r.resolved_at),
  resolved_by: (r.resolved_by as string | null) ?? null, action: (r.action as string | null) ?? null,
});
const rowToBlock = (r: Record<string, unknown>): BlockRow => ({ blocker_id: r.blocker_id as string, blocked_id: r.blocked_id as string, created_at: Number(r.created_at) });

export class PgModerationStore implements ModerationStore {
  constructor(private readonly pool: pg.Pool) {}

  async addReport(r: Omit<ReportRow, 'status' | 'resolved_at' | 'resolved_by' | 'action'>) {
    const ins = await this.pool.query(
      `INSERT INTO reports (id, reporter_id, target_type, target_id, reason, detail, created_at, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, 'open')
       ON CONFLICT (reporter_id, target_type, target_id) DO NOTHING RETURNING *`,
      [r.id, r.reporter_id, r.target_type, r.target_id, r.reason, r.detail, r.created_at]);
    const row = ins.rowCount ? ins.rows[0]
      : (await this.pool.query('SELECT * FROM reports WHERE reporter_id = $1 AND target_type = $2 AND target_id = $3', [r.reporter_id, r.target_type, r.target_id])).rows[0];
    const d = await this.pool.query(
      `SELECT count(DISTINCT reporter_id)::int AS n FROM reports WHERE target_type = $1 AND target_id = $2 AND status = 'open'`, [r.target_type, r.target_id]);
    return { report: rowToReport(row), created: (ins.rowCount ?? 0) > 0, distinctReporters: d.rows[0].n as number };
  }
  async report(id: string) {
    if (!isUuid(id)) return null;
    const r = await this.pool.query('SELECT * FROM reports WHERE id = $1', [id]);
    return r.rowCount ? rowToReport(r.rows[0]) : null;
  }
  async openReports(limit: number) {
    const r = await this.pool.query(`SELECT * FROM reports WHERE status = 'open' ORDER BY created_at, id LIMIT $1`, [limit]);
    return r.rows.map(rowToReport);
  }
  async resolveReport(id: string, by: string, action: string, now: number) {
    if (!isUuid(id)) return null;
    const r = await this.pool.query(
      `UPDATE reports SET status = 'resolved', resolved_at = $2, resolved_by = $3, action = $4 WHERE id = $1 AND status = 'open' RETURNING *`, [id, now, by, action]);
    return r.rowCount ? rowToReport(r.rows[0]) : null;
  }
  async resolveTarget(targetType: string, targetId: string, by: string, action: string, now: number) {
    const r = await this.pool.query(
      `UPDATE reports SET status = 'resolved', resolved_at = $3, resolved_by = $4, action = $5 WHERE target_type = $1 AND target_id = $2 AND status = 'open'`,
      [targetType, targetId, now, by, action]);
    return r.rowCount ?? 0;
  }
  async block(blockerId: string, blockedId: string, now: number) {
    const r = await this.pool.query('INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING', [blockerId, blockedId, now]);
    return { created: (r.rowCount ?? 0) > 0 };
  }
  async unblock(blockerId: string, blockedId: string) {
    if (!isUuid(blockedId)) return { removed: false };
    const r = await this.pool.query('DELETE FROM blocks WHERE blocker_id = $1 AND blocked_id = $2', [blockerId, blockedId]);
    return { removed: (r.rowCount ?? 0) > 0 };
  }
  async blockedEither(a: string, b: string) {
    if (!isUuid(a) || !isUuid(b)) return false;
    const r = await this.pool.query(
      'SELECT 1 FROM blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1) LIMIT 1', [a, b]);
    return (r.rowCount ?? 0) > 0;
  }
  async blockedIdsAround(userId: string) {
    const r = await this.pool.query(
      'SELECT blocked_id AS id FROM blocks WHERE blocker_id = $1 UNION SELECT blocker_id AS id FROM blocks WHERE blocked_id = $1', [userId]);
    return r.rows.map(x => x.id as string);
  }
  async blocks(blockerId: string) {
    const r = await this.pool.query('SELECT * FROM blocks WHERE blocker_id = $1 ORDER BY created_at DESC, blocked_id DESC', [blockerId]);
    return r.rows.map(rowToBlock);
  }
  async ban(userId: string, reason: string, by: string, now: number) {
    await this.pool.query(
      `INSERT INTO account_bans (user_id, reason, banned_by, created_at) VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id) DO UPDATE SET reason = EXCLUDED.reason, banned_by = EXCLUDED.banned_by, created_at = EXCLUDED.created_at`,
      [userId, reason, by, now]);
  }
  async unban(userId: string) { await this.pool.query('DELETE FROM account_bans WHERE user_id = $1', [userId]); }
  async isBanned(userId: string) {
    const r = await this.pool.query('SELECT 1 FROM account_bans WHERE user_id = $1', [userId]);
    return (r.rowCount ?? 0) > 0;
  }
  async deleteUser(userId: string) {
    await this.pool.query('DELETE FROM reports WHERE reporter_id = $1', [userId]);
    await this.pool.query('DELETE FROM blocks WHERE blocker_id = $1 OR blocked_id = $1', [userId]);
    await this.pool.query('DELETE FROM account_bans WHERE user_id = $1', [userId]);
  }
  async exportUser(userId: string) {
    const [r, b] = await Promise.all([
      this.pool.query('SELECT * FROM reports WHERE reporter_id = $1 ORDER BY created_at, id', [userId]),
      this.pool.query('SELECT * FROM blocks WHERE blocker_id = $1 ORDER BY created_at, blocked_id', [userId]),
    ]);
    return { reports_filed: r.rows.map(rowToReport), blocks: b.rows.map(rowToBlock) };
  }
}
