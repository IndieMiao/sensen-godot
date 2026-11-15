import Fastify from 'fastify';
import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { pruneReportFile } from '../../src/p0/report_retention.js';
import { ReportOutbox, REPORT_KEEP_MS } from '../../src/p0/report_outbox.js';
import { ReportDeliveryService } from '../../src/p0/report_delivery.js';
import { registerP0Admin } from '../../src/p0/admin.js';
import { P0Store } from '../../src/p0/store.js';
import { loadP0Content } from '../../src/p0/content.js';

const T = Date.UTC(2026, 10, 15), ID = 'R-20261115-0123ABCD', ID2 = 'R-20261115-4567EFGH';
const dirs: string[] = [], services: ReportDeliveryService[] = [];
afterEach(async () => { for (const s of services.splice(0)) await s.close(); vi.restoreAllMocks(); for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true }); });
const fresh = () => { const d = mkdtempSync(path.join(tmpdir(), 'retention-')); dirs.push(d); return d; };
const row = (at: number, v?: number) => JSON.stringify({ kind: 'voice_report', ...(v ? { v, id: ID } : { reporter: 'OLD_PRIVATE_ID' }), name: 'PRIVATE_NAME', at: new Date(at).toISOString() });
const notice = (at = T) => ({ id: ID, reporter_support: 'WKRW4-9CH60', reported_support: '55YF1-3C0J8', reason: 'Harassment' as const,
  place: 'sh_tea_1', room: 1, channel: 'oss' as const, at: new Date(at).toISOString() });

describe('484 one-year physical report retention', () => {
  it('does not silently normalize impossible dates into a deletable record', () => {
    const file = path.join(fresh(), 'reports.jsonl');
    const input = JSON.stringify({ kind: 'voice_report', at: '2020-02-30T00:00:00Z', name: 'PRIVATE' }) + '\n';
    writeFileSync(file, input);
    expect(pruneReportFile(file, T, true)).toMatchObject({ invalid: 1, expired: 0, changed: false });
    expect(readFileSync(file, 'utf8')).toBe(input);
  });

  it('retries a partially applied file pair after the JSONL succeeded but the queue write failed', async () => {
    const dir = fresh(), reports = path.join(dir, 'reports.jsonl'), outbox = path.join(dir, 'queue.json');
    const queue = new ReportOutbox(outbox, null, () => T); queue.enqueue(ID, notice(T - REPORT_KEEP_MS)); await queue.close();
    writeFileSync(reports, row(T - REPORT_KEEP_MS, 2) + '\n');
    const service = new ReportDeliveryService({ voice: { onReport() {} }, reports, outbox, env: {}, now: () => T }); services.push(service);
    mkdirSync(outbox + '.tmp'); expect(() => service.retention(true)).toThrow('REPORT_OUTBOX_WRITE_FAILED');
    expect(readFileSync(reports, 'utf8')).toBe(''); expect(JSON.parse(readFileSync(outbox, 'utf8')).entries).toHaveLength(1);
    rmSync(outbox + '.tmp', { recursive: true });
    expect(service.retention(true).queue).toMatchObject({ expired: 1, changed: true });
    expect(JSON.parse(readFileSync(outbox, 'utf8')).entries).toEqual([]);
  });

  it('dry-run is byte-preserving; apply deletes both v1/v2 at equality and keeps fresh/future/unknown bytes', () => {
    const file = path.join(fresh(), 'reports.jsonl');
    const expired = row(T - REPORT_KEEP_MS) + '\n' + row(T - REPORT_KEEP_MS - 1, 2) + '\n';
    const retained = row(T - REPORT_KEEP_MS + 1, 2) + '\r\n' + row(T + 1, 2) + '\n' + 'BROKEN_PRIVATE\n' + JSON.stringify({ kind: 'other', at: '1900-01-01T00:00:00.000Z' });
    writeFileSync(file, expired + retained);
    expect(pruneReportFile(file, T)).toEqual({ scanned: 6, expired: 2, retained: 4, invalid: 2, changed: false });
    expect(readFileSync(file, 'utf8')).toBe(expired + retained);
    expect(pruneReportFile(file, T, true)).toMatchObject({ expired: 2, changed: true });
    expect(readFileSync(file, 'utf8')).toBe(retained);
    appendFileSync(file, '\n' + row(T, 2) + '\n');
    expect(pruneReportFile(file, T, true)).toMatchObject({ expired: 0, changed: false });
    expect(readFileSync(file, 'utf8')).toContain(row(T, 2));
  });

  it('missing file is not created; failed atomic replacement keeps old source, retry succeeds without a backup copy', () => {
    const file = path.join(fresh(), 'reports.jsonl');
    expect(pruneReportFile(file, T, true).changed).toBe(false); expect(existsSync(file)).toBe(false);
    const old = row(T - REPORT_KEEP_MS, 2) + '\n'; writeFileSync(file, old); mkdirSync(file + '.retention.tmp');
    expect(() => pruneReportFile(file, T, true)).toThrow('REPORT_RETENTION_WRITE_FAILED');
    expect(readFileSync(file, 'utf8')).toBe(old);
    rmSync(file + '.retention.tmp', { recursive: true }); pruneReportFile(file, T, true);
    expect(readFileSync(file, 'utf8')).toBe(''); expect(existsSync(file + '.retention.tmp')).toBe(false);
  });

  it('removes pending and sent queue records by report time, not retry/delivery time, and persists across reload', async () => {
    const file = path.join(fresh(), 'queue.json'); let now = T;
    const q = new ReportOutbox(file, { send: async () => {} }, () => now);
    q.enqueue(ID, notice()); await q.tick();
    q.enqueue(ID2, { ...notice(T + 1), id: ID2 });
    now += REPORT_KEEP_MS;
    const before = readFileSync(file, 'utf8'); expect(q.retention()).toMatchObject({ expired: 1, retained: 1, changed: false });
    expect(readFileSync(file, 'utf8')).toBe(before);
    q.retention(true); now++;
    expect(new ReportOutbox(file, null, () => now).retention(true)).toMatchObject({ expired: 1, retained: 0 });
    expect(JSON.parse(readFileSync(file, 'utf8')).entries).toEqual([]);
  });

  it('failed queue prune leaves memory and disk retryable; a completed in-flight send cannot resurrect pruned payload', async () => {
    const file = path.join(fresh(), 'queue.json'); let now = T, done!: () => void;
    const q = new ReportOutbox(file, { send: () => new Promise<void>(r => { done = r; }) }, () => now);
    q.enqueue(ID, notice()); const sending = q.tick(); now += REPORT_KEEP_MS;
    mkdirSync(file + '.tmp'); expect(() => q.retention(true)).toThrow('REPORT_OUTBOX_WRITE_FAILED');
    expect(q.retention().expired).toBe(1);
    rmSync(file + '.tmp', { recursive: true }); q.retention(true); done(); await sending;
    expect(JSON.parse(readFileSync(file, 'utf8')).entries).toEqual([]); await q.close();
  });

  it('requires explicit admin apply, default automatic off; approved automatic retention runs without enabling SMTP', async () => {
    const dir = fresh(), reports = path.join(dir, 'reports.jsonl'), outbox = path.join(dir, 'queue.json');
    writeFileSync(reports, row(T - REPORT_KEEP_MS, 2) + '\n');
    const voice = { onReport: (_line: any) => {} }, makeMailer = vi.fn(), warn = vi.fn();
    const service = new ReportDeliveryService({ voice, reports, outbox, env: {}, now: () => T, makeMailer, warn }); services.push(service);
    await service.start(); expect(readFileSync(reports, 'utf8')).not.toBe('');
    const admin = Fastify();
    registerP0Admin(admin, { content: loadP0Content(), store: new P0Store(loadP0Content()), key: 'fake', now: () => T, reportRetention: service, log: () => {} });
    try {
      expect((await admin.inject({ method: 'POST', url: '/admin/reports/retention', payload: { apply: true } })).statusCode).toBe(401);
      expect((await admin.inject({ method: 'GET', url: '/admin/reports/retention', headers: { 'x-p0-admin': 'fake' } })).json().reports.expired).toBe(1);
      expect(readFileSync(reports, 'utf8')).not.toBe('');
      expect((await admin.inject({ method: 'POST', url: '/admin/reports/retention', headers: { 'x-p0-admin': 'fake' }, payload: {} })).statusCode).toBe(400);
      expect((await admin.inject({ method: 'POST', url: '/admin/reports/retention', headers: { 'x-p0-admin': 'fake' }, payload: { apply: true } })).json().reports.changed).toBe(true);
      expect(readFileSync(reports, 'utf8')).toBe('');
    } finally { await admin.close(); await service.close(); }
    writeFileSync(reports, row(T - REPORT_KEEP_MS, 2) + '\n');
    const automatic = new ReportDeliveryService({ voice, reports, outbox, env: { P0_REPORT_RETENTION: 'on' }, now: () => T, makeMailer, warn }); services.push(automatic);
    await automatic.start(); expect(readFileSync(reports, 'utf8')).toBe(''); expect(makeMailer).not.toHaveBeenCalled();
  });
});
