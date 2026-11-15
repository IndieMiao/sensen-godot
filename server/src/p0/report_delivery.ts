/** SGODOT-484: reports are authoritative JSONL; the outbox is a retryable delivery projection, never a second report.
 * No provider/configuration errors or report contents are printed here. One instance per P0 server/data volume. */
import { createReadStream } from 'node:fs';
import { createInterface } from 'node:readline';
import type { P0Voice, ReportLine } from './online/voice.js';
import { createReportMailer, reportSmtpFromEnv, type ReportSmtpConfig } from './report_mail.js';
import { reportLineNotice } from './report_notice.js';
import { REPORT_KEEP_MS, ReportOutbox, type ReportDelivery } from './report_outbox.js';

type Mailer = ReportDelivery & { close(): void };
interface Options {
  voice: Pick<P0Voice, 'onReport'>;
  reports: string; outbox: string;
  env: Record<string, string | undefined>;
  now?: () => number;
  intervalMs?: number;
  makeMailer?: (config: ReportSmtpConfig) => Mailer;
  warn?: (event: string) => void;
}
export interface ReplayResult { added: number; skipped: number; invalid: number; conflicts: number }

export class ReportDeliveryService {
  private readonly now: () => number;
  private readonly warn: (event: string) => void;
  private readonly mailer: Mailer | null;
  private readonly queue: ReportOutbox;
  private timer?: ReturnType<typeof setInterval>;
  private running?: Promise<void>;
  private closing?: Promise<void>;
  private stopped = false;
  private started = false;
  private readonly previous: P0Voice['onReport'];
  private readonly receive: P0Voice['onReport'];

  constructor(private readonly options: Options) {
    this.now = options.now ?? Date.now;
    this.warn = options.warn ?? (event => console.warn(JSON.stringify({ report_delivery: event })));
    if (!Number.isSafeInteger(options.intervalMs ?? 30_000) || (options.intervalMs ?? 30_000) < 1)
      throw new Error('REPORT_DELIVERY_INVALID_INTERVAL');
    const config = reportSmtpFromEnv(options.env);
    this.mailer = config ? (options.makeMailer ?? createReportMailer)(config) : null;
    try { this.queue = new ReportOutbox(options.outbox, this.mailer, this.now); }
    catch (e) { this.mailer?.close(); throw e; }
    this.previous = options.voice.onReport;
    this.receive = line => {
      if (this.stopped) return; // It is already in JSONL; a subsequent start will replay it.
      try { this.add(line); }
      catch { this.warn('enqueue_failed'); } // Never turn an already-persisted report into an HTTP failure.
    };
  }

  async start(): Promise<void> {
    if (this.started || this.stopped) return;
    this.started = true;
    this.options.voice.onReport = this.receive;
    await this.poll();
    if (!this.stopped) {
      this.timer = setInterval(() => { void this.poll(); }, this.options.intervalMs ?? 30_000);
      this.timer.unref();
    }
  }

  /** Re-read authoritative rows so an enqueue failure is recovered without needing a process restart.
   * A malformed line is counted, not logged; an I/O/queue write failure stops this scan for the next retry. */
  async replay(): Promise<ReplayResult> {
    const result: ReplayResult = { added: 0, skipped: 0, invalid: 0, conflicts: 0 };
    const input = createReadStream(this.options.reports, { encoding: 'utf8' });
    const lines = createInterface({ input, crlfDelay: Infinity });
    try {
      for await (const raw of lines) {
        if (this.stopped) break;
        let parsed: unknown;
        try { parsed = JSON.parse(raw); }
        catch { result.invalid++; continue; }
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) { result.invalid++; continue; }
        let notice: ReturnType<typeof reportLineNotice>;
        try { notice = reportLineNotice(parsed as Record<string, unknown>); }
        catch { result.invalid++; continue; }
        if (!notice || !this.current(notice.at)) { result.skipped++; continue; }
        try {
          if (this.queue.enqueue(notice.id, notice)) result.added++; else result.skipped++;
        } catch (e) {
          // Preserve the first payload and the source file; one conflicting row must not starve later reports.
          // Disk failures and all other errors still abort this scan for retry.
          if (!(e instanceof Error && e.message === 'REPORT_OUTBOX_ID_CONFLICT')) throw e;
          result.conflicts++;
        }
      }
    } catch (e) {
      if ((e as NodeJS.ErrnoException)?.code !== 'ENOENT') throw new Error('REPORT_REPLAY_FAILED');
    } finally {
      lines.close(); input.destroy();
      if (result.conflicts) this.warn('conflicting_report_rows');
    }
    if (result.invalid) this.warn('invalid_report_rows');
    return result;
  }

  poll(): Promise<void> {
    if (this.stopped) return Promise.resolve();
    if (this.running) return this.running;
    this.running = (async () => {
      try { await this.replay(); } catch { this.warn('replay_failed'); }
      if (!this.stopped) {
        try { await this.queue.tick(); } catch { this.warn('queue_write_failed'); }
      }
    })().finally(() => { this.running = undefined; });
    return this.running;
  }

  close(): Promise<void> {
    if (this.closing) return this.closing;
    this.stopped = true;
    if (this.timer) clearInterval(this.timer);
    if (this.options.voice.onReport === this.receive) this.options.voice.onReport = this.previous;
    this.closing = (async () => {
      try { await this.running; await this.queue.close(); } finally { this.mailer?.close(); }
    })();
    return this.closing;
  }

  private current(at: string): boolean {
    const timestamp = Date.parse(at), now = this.now();
    return timestamp <= now && now - timestamp < REPORT_KEEP_MS;
  }

  private add(line: ReportLine): void {
    const notice = reportLineNotice({ ...line });
    if (notice && this.current(notice.at)) this.queue.enqueue(notice.id, notice);
  }
}
