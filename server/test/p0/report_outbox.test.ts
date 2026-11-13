import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { ReportOutbox, type ReportOutboxPolicy } from '../../src/p0/report_outbox.js';
import type { ReportMailNotice } from '../../src/p0/report_mail.js';

const dirs: string[] = [];
afterEach(() => { vi.restoreAllMocks(); for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true }); });
const ID = '11111111-1111-4111-8111-111111111111', OTHER = '22222222-2222-4222-8222-222222222222';
const notice: ReportMailNotice = { reporter_support: 'WKRW4-9CH60', reported_support: '55YF1-3C0J8',
  reason: 'Harassment', place: 'sh_tea_1', room: 1, at: '2026-11-13T00:00:00.000Z', channel: 'play' };
const policy: ReportOutboxPolicy = { gapMs: 100, retryMs: 1000, maxRetryMs: 4000, dailyAttempts: 3 };
function setup() {
  const dir = mkdtempSync(path.join(tmpdir(), 'report-outbox-')); dirs.push(dir);
  const file = path.join(dir, 'outbox.json');
  let time = Date.parse(notice.at);
  const now = () => time, send = vi.fn(async (_n: ReportMailNotice) => {});
  const load = (enabled = true) => new ReportOutbox(file, enabled ? { send } : null, now, policy);
  return { dir, file, send, now, load, tick: (ms: number) => { time += ms; } };
}
const disk = (file: string) => JSON.parse(readFileSync(file, 'utf8'));

describe('484 durable report outbox (fake delivery only)', () => {
  it('default-off keeps mail on disk without sending, and enabling after restart delivers it once', async () => {
    const { load, send, file } = setup();
    const off = load(false);
    expect(off.enqueue(ID, notice)).toBe(true);
    const before = readFileSync(file, 'utf8');
    expect(await off.tick()).toBe(false);
    expect(readFileSync(file, 'utf8')).toBe(before);
    expect(send).not.toHaveBeenCalled();
    await off.close();
    const on = load();
    expect(await on.tick()).toBe(true);
    expect(send).toHaveBeenCalledTimes(1);
    expect(send).toHaveBeenCalledWith(notice);
    expect(load().enqueue(ID, notice)).toBe(false);
    expect(await load().tick()).toBe(false);
  });

  it('projects only public fields to disk and to delivery; caller mutation cannot change a queued message', async () => {
    const { load, send, file } = setup(), queue = load();
    const internal = { ...notice, name: 'PRIVATE_NAME', reporter: 'private-player', token: 'private-token', to: 'attacker@example.test' };
    queue.enqueue(ID, internal);
    internal.place = 'changed-after-enqueue';
    for (const secret of ['PRIVATE_NAME', 'private-player', 'private-token', 'attacker@example.test', 'changed-after-enqueue'])
      expect(readFileSync(file, 'utf8')).not.toContain(secret);
    await queue.tick();
    expect(send).toHaveBeenCalledWith(notice);
  });

  it('deduplicates stable report ids, rejects id reuse for another payload and refuses raw player ids', () => {
    const { load } = setup(), queue = load();
    expect(queue.enqueue(ID, notice)).toBe(true);
    expect(queue.enqueue(ID, { ...notice })).toBe(false);
    expect(() => queue.enqueue(ID, { ...notice, room: 2 })).toThrow('REPORT_OUTBOX_ID_CONFLICT');
    expect(() => queue.enqueue('player-secret', notice)).toThrow('REPORT_OUTBOX_INVALID_ID');
    expect(() => queue.enqueue(OTHER, { ...notice, reason: 'private free text' } as unknown as ReportMailNotice)).toThrow('REPORT_MAIL_INVALID_NOTICE');
  });

  it('persists the attempt budget before SMTP and exponentially backs off across restart, without logging provider errors', async () => {
    const { load, send, file, tick, now } = setup(), queue = load();
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    send.mockImplementation(async () => {
      expect(disk(file).used).toBeGreaterThan(0);
      expect(disk(file).entries[0].next).toBeGreaterThan(now());
      throw new Error('fake-SMTP-password-private');
    });
    queue.enqueue(ID, notice);
    expect(await queue.tick()).toBe(false);
    tick(999); expect(await load().tick()).toBe(false);
    tick(1); expect(await load().tick()).toBe(false);
    expect(send).toHaveBeenCalledTimes(2);
    expect(disk(file).entries[0].next).toBe(now() + 2000);
    expect(readFileSync(file, 'utf8')).not.toContain('fake-SMTP-password-private');
    expect(warn).not.toHaveBeenCalled();
  });

  it('one failed report does not block another due report; limits are shared by all reports', async () => {
    const { load, send, tick } = setup(), queue = load();
    queue.enqueue(ID, notice); queue.enqueue(OTHER, { ...notice, room: 2 });
    send.mockRejectedValueOnce(new Error('offline'));
    await queue.tick();
    expect(await queue.tick()).toBe(false);
    tick(100); expect(await queue.tick()).toBe(true);
    expect(send.mock.calls.map(([n]) => n.room)).toEqual([1, 2]);
  });

  it('enforces the persisted UTC daily cap and cannot reset it by rolling the clock back', async () => {
    const { load, send, tick } = setup(), queue = load();
    queue.enqueue(ID, notice);
    send.mockRejectedValue(new Error('offline'));
    for (let i = 0; i < 3; i++) { await queue.tick(); tick(4000); }
    expect(send).toHaveBeenCalledTimes(3);
    await load().tick(); expect(send).toHaveBeenCalledTimes(3);
    tick(-86_400_000); await load().tick(); expect(send).toHaveBeenCalledTimes(3);
    tick(2 * 86_400_000); await load().tick(); expect(send).toHaveBeenCalledTimes(4);
  });

  it('coalesces concurrent ticks and preserves a new enqueue while SMTP is pending', async () => {
    const { load, send, file } = setup(), queue = load();
    let done!: () => void;
    send.mockImplementation(() => new Promise<void>(resolve => { done = resolve; }));
    queue.enqueue(ID, notice);
    const a = queue.tick(), b = queue.tick();
    expect(send).toHaveBeenCalledTimes(1);
    queue.enqueue(OTHER, { ...notice, room: 2 });
    done();
    await expect(a).resolves.toBe(true); await expect(b).resolves.toBe(true);
    expect(disk(file).entries.map((e: { id: string; sent: boolean }) => [e.id, e.sent])).toEqual([[ID, true], [OTHER, false]]);
  });

  it('a failed enqueue is not remembered in memory; replay after repairing disk enqueues normally', () => {
    const { load, file } = setup(), queue = load();
    mkdirSync(file + '.tmp');
    expect(() => queue.enqueue(ID, notice)).toThrow('REPORT_OUTBOX_WRITE_FAILED');
    rmSync(file + '.tmp', { recursive: true });
    expect(queue.enqueue(ID, notice)).toBe(true);
    expect(disk(file).entries).toHaveLength(1);
  });

  it('does not send when persisting the attempt budget fails', async () => {
    const { load, file, send } = setup(), queue = load();
    queue.enqueue(ID, notice);
    mkdirSync(file + '.tmp');
    await expect(queue.tick()).rejects.toThrow('REPORT_OUTBOX_WRITE_FAILED');
    expect(send).not.toHaveBeenCalled();
    rmSync(file + '.tmp', { recursive: true });
    await expect(queue.tick()).resolves.toBe(true);
    expect(send).toHaveBeenCalledTimes(1);
  });

  it('keeps a delivered-but-unacknowledged entry pending for replay, with no false exactly-once claim', async () => {
    const { load, file, send, tick } = setup(), queue = load();
    queue.enqueue(ID, notice);
    send.mockImplementationOnce(async () => { mkdirSync(file + '.tmp'); });
    await expect(queue.tick()).rejects.toThrow('REPORT_OUTBOX_WRITE_FAILED');
    expect(disk(file).entries[0].sent).toBe(false);
    rmSync(file + '.tmp', { recursive: true }); tick(1000);
    expect(await load().tick()).toBe(true);
    expect(send).toHaveBeenCalledTimes(2); // SMTP accepted but the local receipt failed: a duplicate is possible.
  });

  it('fails closed on corrupt files instead of discarding queued mail or echoing the contents', () => {
    const { file, load } = setup();
    for (const data of ['PRIVATE_BROKEN_FILE', '{"v":2,"entries":[]}', JSON.stringify({ v: 1, entries: [], day: -1, used: 0, next: 0 })]) {
      writeFileSync(file, data);
      expect(() => load()).toThrow('REPORT_OUTBOX_UNREADABLE');
      expect(readFileSync(file, 'utf8')).toBe(data);
    }
  });

  it('shutdown waits for an in-flight delivery and stops further work', async () => {
    const { load, send } = setup(), queue = load();
    let finish!: () => void;
    send.mockImplementation(() => new Promise<void>(resolve => { finish = resolve; }));
    queue.enqueue(ID, notice); const running = queue.tick();
    let closed = false;
    const closing = queue.close().then(() => { closed = true; });
    await Promise.resolve(); expect(closed).toBe(false);
    expect(await queue.tick()).toBe(false);
    expect(() => queue.enqueue(OTHER, notice)).toThrow('REPORT_OUTBOX_CLOSED');
    finish(); await running; await closing; expect(closed).toBe(true);
  });
});
