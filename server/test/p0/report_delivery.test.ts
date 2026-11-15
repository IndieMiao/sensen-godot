import { appendFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { P0Voice, type ReportLine } from '../../src/p0/online/voice.js';
import { loadOutposts } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { ReportDeliveryService } from '../../src/p0/report_delivery.js';
import { REPORT_KEEP_MS } from '../../src/p0/report_outbox.js';

const ID = 'R-20261115-0123ABCD', OTHER = 'R-20261115-4567EFGH', T0 = Date.UTC(2026, 10, 15);
const line: ReportLine = { kind: 'voice_report', v: 2, id: ID, at: new Date(T0).toISOString(),
  reporter_code: 'WKRW4-9CH60', reported_code: '55YF1-3C0J8', name: 'PRIVATE_NAME', reason: 'harassment',
  place: 'sh_tea_1', room: 1, channel: 'oss' };
const env = { P0_REPORT_MAIL: 'on', SMTP_HOST: 'smtpdm-us-east-1.aliyuncs.com', SMTP_PORT: '465', SMTP_SECURITY: 'ssl',
  SMTP_USER: 'reports@notify.gensen.app', SMTP_PASS: 'fake-only', MAIL_FROM: 'reports@notify.gensen.app', MAIL_TO: 'moderator@example.test' };
const dirs: string[] = [], services: ReportDeliveryService[] = [];
afterEach(async () => {
  for (const s of services.splice(0)) await s.close();
  vi.restoreAllMocks();
  for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true });
});
function setup(enabled = true) {
  const dir = mkdtempSync(path.join(tmpdir(), 'report-service-')); dirs.push(dir);
  const reports = path.join(dir, 'reports.jsonl'), outbox = path.join(dir, 'outbox.json');
  let time = T0;
  const rooms = new OutpostRooms(loadOutposts());
  const voice = new P0Voice(null, rooms, { reports, ages: path.join(dir, 'ages.json'), blocks: path.join(dir, 'blocks.json') }, () => time);
  const send = vi.fn(async (_notice: unknown) => {}), close = vi.fn(), warn = vi.fn();
  const makeMailer = vi.fn(() => ({ send, close }));
  const create = () => {
    const s = new ReportDeliveryService({ voice, reports, outbox, now: () => time, env: enabled ? env : { ...env, P0_REPORT_MAIL: 'off' },
      makeMailer, warn, intervalMs: 60_000 });
    services.push(s); return s;
  };
  return { reports, outbox, voice, rooms, send, close, warn, create, makeMailer, advance: (ms: number) => { time += ms; } };
}

describe('484 report callback, replay and lifecycle', () => {
  it('a failed authoritative append sends nothing and the player can retry the same report', async () => {
    const f = setup(), service = f.create(); await service.start();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    f.rooms.join('reporter-test', 'sh_tea_1'); f.rooms.join('reported-test', 'sh_tea_1');
    const peer = f.rooms.occupant('reported-test')!.id;
    mkdirSync(f.reports);
    expect(() => f.voice.report('reporter-test', peer, 'harassment')).toThrow();
    expect(f.send).not.toHaveBeenCalled();
    rmSync(f.reports, { recursive: true });
    expect(f.voice.report('reporter-test', peer, 'harassment')).toEqual({ ok: true, already: false });
    await service.poll(); expect(f.send).toHaveBeenCalledTimes(1);
    expect(f.voice.report('reporter-test', peer, 'harassment')).toEqual({ ok: true, already: true });
  });

  it('off does not construct SMTP, yet durably captures a real P0Voice report after append', async () => {
    const f = setup(false), service = f.create();
    await service.start(); // Missing JSONL is normal on a new server.
    const log = vi.spyOn(console, 'log').mockImplementation(() => {});
    f.rooms.join('reporter-test', 'sh_tea_1'); f.rooms.join('reported-test', 'sh_tea_1');
    f.voice.nameOf = () => 'PRIVATE_NAME';
    expect(f.voice.report('reporter-test', f.rooms.occupant('reported-test')!.id, 'harassment', 'oss')).toMatchObject({ ok: true });
    const saved = JSON.parse(readFileSync(f.reports, 'utf8'));
    const queued = JSON.parse(readFileSync(f.outbox, 'utf8')).entries;
    expect(queued[0].id).toBe(saved.id);
    expect(saved.name).toBe('PRIVATE_NAME');
    expect(readFileSync(f.outbox, 'utf8')).not.toMatch(/PRIVATE_NAME|reporter-test|reported-test/);
    await service.poll();
    expect(f.makeMailer).not.toHaveBeenCalled(); expect(f.send).not.toHaveBeenCalled();
    log.mockRestore();
  });

  it('replays v2 after a lost callback, skips legacy/malformed lines, and does not resend after restart', async () => {
    const f = setup();
    writeFileSync(f.reports, [JSON.stringify({ kind: 'voice_report', reporter: 'OLD_PRIVATE_ID' }),
      'BROKEN_PRIVATE_LINE', JSON.stringify(line), JSON.stringify(line)].join('\n') + '\n');
    const first = f.create(); await first.start(); await first.close();
    expect(f.send).toHaveBeenCalledTimes(1);
    expect(f.warn.mock.calls).toEqual([['invalid_report_rows']]);
    f.advance(60_000);
    const again = f.create(); await again.start();
    expect(f.send).toHaveBeenCalledTimes(1);
    expect(JSON.stringify(f.warn.mock.calls)).not.toMatch(/PRIVATE/);
    expect(readFileSync(f.outbox, 'utf8')).not.toMatch(/PRIVATE/);
  });

  it('an enqueue failure cannot fail the persisted report; periodic replay repairs it in the same process', async () => {
    const f = setup(), service = f.create(); await service.start();
    mkdirSync(f.outbox + '.tmp');
    appendFileSync(f.reports, JSON.stringify(line) + '\n');
    expect(() => f.voice.onReport(line)).not.toThrow();
    expect(f.warn).toHaveBeenCalledWith('enqueue_failed');
    rmSync(f.outbox + '.tmp', { recursive: true });
    await service.poll();
    expect(f.send).toHaveBeenCalledTimes(1);
    expect(JSON.parse(readFileSync(f.outbox, 'utf8')).entries[0].sent).toBe(true);
  });

  it('counts conflicting ids and continues to later valid rows, preserving the original payload on every replay', async () => {
    const f = setup(), service = f.create();
    writeFileSync(f.reports, JSON.stringify(line) + '\n');
    await service.replay(); // A was already queued before the conflicting append.
    appendFileSync(f.reports, [JSON.stringify({ ...line, id: 'bad-private-id' }),
      JSON.stringify({ ...line, room: 2 }), JSON.stringify({ ...line, id: OTHER, name: null })].join('\n') + '\n');
    const originalFile = readFileSync(f.reports, 'utf8');
    expect(await service.replay()).toEqual({ added: 1, skipped: 1, invalid: 1, conflicts: 1 });
    const entries = JSON.parse(readFileSync(f.outbox, 'utf8')).entries;
    expect(entries.map((e: { id: string }) => e.id)).toEqual([ID, OTHER]);
    expect(entries[0].notice.room).toBe(1);
    expect(await service.replay()).toEqual({ added: 0, skipped: 2, invalid: 1, conflicts: 1 });
    expect(JSON.parse(readFileSync(f.outbox, 'utf8')).entries).toEqual(entries);
    expect(readFileSync(f.reports, 'utf8')).toBe(originalFile);
    expect(f.warn.mock.calls).toEqual([['conflicting_report_rows'], ['invalid_report_rows'], ['conflicting_report_rows'], ['invalid_report_rows']]);
    expect(JSON.stringify(f.warn.mock.calls)).not.toMatch(/PRIVATE|R-20261115/);
  });

  it('still aborts replay on a genuine queue write failure and recovers both rows after repair', async () => {
    const f = setup(), service = f.create();
    writeFileSync(f.reports, [JSON.stringify(line), JSON.stringify({ ...line, id: OTHER })].join('\n') + '\n');
    mkdirSync(f.outbox + '.tmp');
    await expect(service.replay()).rejects.toThrow('REPORT_REPLAY_FAILED');
    expect(f.warn).not.toHaveBeenCalledWith('conflicting_report_rows');
    rmSync(f.outbox + '.tmp', { recursive: true });
    expect(await service.replay()).toEqual({ added: 2, skipped: 0, invalid: 0, conflicts: 0 });
  });

  it('expired reports and future timestamps are not mailed, including previously queued reports', async () => {
    const f = setup(), service = f.create(); await service.start();
    appendFileSync(f.reports, JSON.stringify(line) + '\n'); f.voice.onReport(line);
    f.advance(REPORT_KEEP_MS);
    appendFileSync(f.reports, JSON.stringify({ ...line, id: OTHER, at: new Date(T0 + REPORT_KEEP_MS + 1000).toISOString() }) + '\n');
    await service.poll(); expect(f.send).not.toHaveBeenCalled();
  });

  it('shutdown waits for SMTP, clears the timer and restores the previous callback without further sends', async () => {
    const f = setup(), prior = f.voice.onReport, service = f.create();
    await service.start();
    appendFileSync(f.reports, JSON.stringify(line) + '\n'); f.voice.onReport(line);
    let done!: () => void;
    f.send.mockImplementationOnce(() => new Promise<void>(resolve => { done = resolve; }));
    const running = service.poll(); await vi.waitFor(() => expect(f.send).toHaveBeenCalledTimes(1));
    let closed = false; const stopping = service.close().then(() => { closed = true; });
    await Promise.resolve(); expect(closed).toBe(false); expect(f.close).not.toHaveBeenCalled();
    done(); await running; await stopping;
    expect(f.close).toHaveBeenCalledTimes(1); expect(f.voice.onReport).toBe(prior);
    await service.poll(); await service.close(); expect(f.send).toHaveBeenCalledTimes(1);
  });

  it('periodic timer recovers newly appended records without an onReport call', async () => {
    vi.useFakeTimers();
    try {
      const f = setup(), service = f.create(); await service.start();
      appendFileSync(f.reports, JSON.stringify(line) + '\n');
      await vi.advanceTimersByTimeAsync(60_000);
      await service.poll();
      expect(f.send).toHaveBeenCalledTimes(1);
      await service.close(); expect(vi.getTimerCount()).toBe(0);
    } finally { vi.useRealTimers(); }
  });
});
