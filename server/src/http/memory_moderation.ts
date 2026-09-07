/** 内存 ModerationStore：HTTP 层测试用；语义与 PgModerationStore 保持一致。 */
import type { BanRow, BlockRow, ModerationStore, ReportRow } from './moderation.js';

export class MemoryModerationStore implements ModerationStore {
  private reports: ReportRow[] = [];
  private blockRows: BlockRow[] = [];
  private bans = new Map<string, BanRow>();

  async addReport(r: Omit<ReportRow, 'status' | 'resolved_at' | 'resolved_by' | 'action'>) {
    const key = (x: { reporter_id: string; target_type: string; target_id: string }) => `${x.reporter_id}|${x.target_type}|${x.target_id}`;
    const existing = this.reports.find(x => key(x) === key(r));
    const report: ReportRow = existing ?? { ...r, status: 'open', resolved_at: null, resolved_by: null, action: null };
    if (!existing) this.reports.push(report);
    const distinct = new Set(this.reports.filter(x => x.target_type === r.target_type && x.target_id === r.target_id && x.status === 'open').map(x => x.reporter_id)).size;
    return { report: { ...report }, created: !existing, distinctReporters: distinct };
  }
  async report(id: string) { const r = this.reports.find(x => x.id === id); return r ? { ...r } : null; }
  async openReports(limit: number) {
    return this.reports.filter(r => r.status === 'open').sort((a, b) => a.created_at - b.created_at || (a.id < b.id ? -1 : 1)).slice(0, limit).map(r => ({ ...r }));
  }
  async resolveReport(id: string, by: string, action: string, now: number) {
    const r = this.reports.find(x => x.id === id);
    if (!r || r.status !== 'open') return null;
    Object.assign(r, { status: 'resolved', resolved_at: now, resolved_by: by, action });
    return { ...r };
  }
  async resolveTarget(targetType: string, targetId: string, by: string, action: string, now: number) {
    let n = 0;
    for (const r of this.reports) if (r.status === 'open' && r.target_type === targetType && r.target_id === targetId) {
      Object.assign(r, { status: 'resolved', resolved_at: now, resolved_by: by, action }); n += 1;
    }
    return n;
  }
  async block(blockerId: string, blockedId: string, now: number) {
    if (this.blockRows.some(b => b.blocker_id === blockerId && b.blocked_id === blockedId)) return { created: false };
    this.blockRows.push({ blocker_id: blockerId, blocked_id: blockedId, created_at: now });
    return { created: true };
  }
  async unblock(blockerId: string, blockedId: string) {
    const before = this.blockRows.length;
    this.blockRows = this.blockRows.filter(b => !(b.blocker_id === blockerId && b.blocked_id === blockedId));
    return { removed: this.blockRows.length < before };
  }
  async blockedEither(a: string, b: string) {
    return this.blockRows.some(x => (x.blocker_id === a && x.blocked_id === b) || (x.blocker_id === b && x.blocked_id === a));
  }
  async blockedIdsAround(userId: string) {
    const out = new Set<string>();
    for (const b of this.blockRows) { if (b.blocker_id === userId) out.add(b.blocked_id); if (b.blocked_id === userId) out.add(b.blocker_id); }
    return [...out];
  }
  async blocks(blockerId: string) {
    return this.blockRows.filter(b => b.blocker_id === blockerId).sort((a, b) => b.created_at - a.created_at).map(b => ({ ...b }));
  }
  async ban(userId: string, reason: string, by: string, now: number) { this.bans.set(userId, { user_id: userId, reason, by, created_at: now }); }
  async unban(userId: string) { this.bans.delete(userId); }
  async isBanned(userId: string) { return this.bans.has(userId); }
  async deleteUser(userId: string) {
    this.reports = this.reports.filter(r => r.reporter_id !== userId);
    this.blockRows = this.blockRows.filter(b => b.blocker_id !== userId && b.blocked_id !== userId);
    this.bans.delete(userId);
  }
  async exportUser(userId: string) {
    return { reports_filed: this.reports.filter(r => r.reporter_id === userId).map(r => ({ ...r })), blocks: this.blockRows.filter(b => b.blocker_id === userId).map(b => ({ ...b })) };
  }
}
