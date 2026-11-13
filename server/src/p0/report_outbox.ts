/** SGODOT-484: durable, single-process report delivery. The authoritative report writer must commit first, then
 * enqueue its stable report id; a replay uses that same id. No routes, timers or real SMTP are enabled by this module. */
import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { REPORT_ID, reportMailText, type ReportMailNotice } from './report_mail.js';

export interface ReportDelivery { send(notice: ReportMailNotice): Promise<void> }
export interface ReportOutboxPolicy { gapMs: number; retryMs: number; maxRetryMs: number; dailyAttempts: number }
export const REPORT_OUTBOX_POLICY: Readonly<ReportOutboxPolicy> = Object.freeze({
  gapMs: 30_000, retryMs: 60_000, maxRetryMs: 3_600_000, dailyAttempts: 200,
});
interface Entry { id: string; notice: ReportMailNotice; attempts: number; next: number; sent: boolean }
interface State { v: 1; entries: Entry[]; day: number; used: number; next: number }
const integer = (n: unknown): n is number => Number.isSafeInteger(n) && Number(n) >= 0;
const DAY = 86_400_000;

/** Projection is deliberate: internal name snapshots, IDs, IPs and tokens never enter this separate file. */
function publicNotice(n: ReportMailNotice): ReportMailNotice {
  reportMailText(n);
  return { id: n.id, reporter_support: n.reporter_support, reported_support: n.reported_support, reason: n.reason,
    place: n.place, room: n.room, at: new Date(n.at).toISOString(), channel: n.channel };
}

export class ReportOutbox {
  private state: State = { v: 1, entries: [], day: 0, used: 0, next: 0 };
  private active?: Promise<boolean>;
  private closed = false;
  private policy: ReportOutboxPolicy;

  constructor(private file: string, private delivery: ReportDelivery | null, private now: () => number = Date.now,
    policy: ReportOutboxPolicy = REPORT_OUTBOX_POLICY) {
    this.policy = { ...policy };
    if (!file || !Object.values(policy).every(n => integer(n) && n > 0) || policy.dailyAttempts > 2000
      || policy.retryMs > policy.maxRetryMs) throw new Error('REPORT_OUTBOX_INVALID_CONFIG');
    if (!existsSync(file)) return;
    try {
      const s = JSON.parse(readFileSync(file, 'utf8')) as State;
      if (s.v !== 1 || !Array.isArray(s.entries) || !integer(s.day) || !integer(s.used) || !integer(s.next)) throw 0;
      const seen = new Set<string>();
      const entries = s.entries.map(e => {
        if (!REPORT_ID.test(e.id) || e.notice?.id !== e.id || seen.has(e.id) || !integer(e.attempts) || !integer(e.next) || typeof e.sent !== 'boolean') throw 0;
        seen.add(e.id);
        return { id: e.id, notice: publicNotice(e.notice), attempts: e.attempts, next: e.next, sent: e.sent };
      });
      this.state = { v: 1, entries, day: s.day, used: s.used, next: s.next };
    } catch { throw new Error('REPORT_OUTBOX_UNREADABLE'); } // Do not silently discard pending mail or print file contents.
  }

  /** Idempotent after restart, including sent receipts. A caller must replay after an enqueue I/O failure. */
  enqueue(id: string, notice: ReportMailNotice): boolean {
    if (this.closed) throw new Error('REPORT_OUTBOX_CLOSED');
    if (!REPORT_ID.test(id) || notice.id !== id) throw new Error('REPORT_OUTBOX_INVALID_ID');
    const clean = publicNotice(notice), old = this.state.entries.find(e => e.id === id);
    if (old) {
      if (JSON.stringify(old.notice) !== JSON.stringify(clean)) throw new Error('REPORT_OUTBOX_ID_CONFLICT');
      return false;
    }
    this.commit({ ...this.state, entries: [...this.state.entries, { id, notice: clean, attempts: 0, next: 0, sent: false }] });
    return true;
  }

  /** At most one SMTP attempt per tick; concurrent ticks share it. No delivery dependency means default-off. */
  tick(): Promise<boolean> {
    if (this.closed || !this.delivery) return Promise.resolve(false);
    if (this.active) return this.active;
    const task = this.attempt().finally(() => { this.active = undefined; });
    this.active = task;
    return task;
  }

  /** Stops new attempts and waits for the bounded SMTP operation; the owner closes its transport afterwards. */
  async close(): Promise<void> { this.closed = true; await this.active; }

  private async attempt(): Promise<boolean> {
    const now = this.now();
    if (!integer(now)) throw new Error('REPORT_OUTBOX_INVALID_TIME');
    const s = this.state, p = this.policy, day = Math.max(s.day, Math.floor(now / DAY));
    const used = day === s.day ? s.used : 0;
    if (now < s.next || used >= p.dailyAttempts) return false;
    const row = s.entries.find(e => !e.sent && now >= e.next);
    if (!row) return false;
    const attempts = row.attempts + 1;
    const delay = Math.min(p.maxRetryMs, p.retryMs * 2 ** Math.min(attempts - 1, 20));
    // Persist rate budget and retry deadline BEFORE sending, so restart cannot bypass the budget or hammer SMTP.
    this.commit({ ...s, day, used: used + 1, next: now + p.gapMs,
      entries: s.entries.map(e => e === row ? { ...e, attempts, next: now + delay } : e) });
    try { await this.delivery!.send({ ...row.notice }); }
    catch { return false; } // Provider errors can contain credentials; only state/counters describe failure.
    // Use current entries: another report may have been enqueued while SMTP was pending.
    this.commit({ ...this.state, entries: this.state.entries.map(e => e.id === row.id ? { ...e, sent: true } : e) });
    return true;
  }

  private commit(next: State): void {
    try { writeFileSync(this.file + '.tmp', JSON.stringify(next), { mode: 0o600 }); renameSync(this.file + '.tmp', this.file); }
    catch { throw new Error('REPORT_OUTBOX_WRITE_FAILED'); }
    this.state = next;
  }
}
