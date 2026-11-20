import Fastify from 'fastify';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { registerP0Admin } from '../../src/p0/admin.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';
import { loadP0Content } from '../../src/p0/content.js';
import { P0Store } from '../../src/p0/store.js';
import { P0Voice } from '../../src/p0/online/voice.js';
import { loadOutposts } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import * as support from '../../src/p0/support.js';

const C = loadP0Content(), T = Date.UTC(2026, 10, 15), P = 'delete-admin-target', Q = 'delete-admin-other', KEY = 'fake-admin';
const cleanup: (() => Promise<void>)[] = [];
afterEach(async () => { vi.restoreAllMocks(); for (const fn of cleanup.splice(0)) await fn(); });
function setup() {
  const dir = mkdtempSync(path.join(tmpdir(), 'admin-delete-'));
  const save = path.join(dir, 'save.json'), acc = path.join(dir, 'accounts.json');
  const files = { ages: path.join(dir, 'ages.json'), blocks: path.join(dir, 'blocks.json'), reports: path.join(dir, 'reports.jsonl') };
  const store = new P0Store(C, save), accounts = new P0Accounts(acc, Buffer.alloc(32, 7), () => T);
  for (const p of [P, Q]) { store.get(p, T); accounts.ensure(p); accounts.issue(p, p === P ? '1'.repeat(64) : '2'.repeat(64)); }
  writeFileSync(files.ages, JSON.stringify({ [P]: true, [Q]: false }));
  writeFileSync(files.blocks, JSON.stringify({ [P]: [Q], [Q]: [P] }));
  writeFileSync(files.reports, JSON.stringify({ reporter: P, reported: Q, at: new Date(T).toISOString() }) + '\n');
  const voice = new P0Voice(null, new OutpostRooms(loadOutposts()), files, () => T);
  const hub = { kick: vi.fn() }, log = vi.fn(), admin = Fastify(), app = Fastify();
  registerP0Admin(admin, { content: C, store, accounts, now: () => T, key: KEY, deletion: { voice, hub }, log });
  registerP0Routes(app, { content: C, store, now: () => T, dev: false });
  cleanup.push(async () => { await admin.close(); await app.close(); rmSync(dir, { recursive: true, force: true }); });
  const post = (payload: unknown) => admin.inject({ method: 'POST', url: '/admin/delete', headers: { 'x-p0-admin': KEY }, payload: payload as object });
  const get = (url: string) => admin.inject({ method: 'GET', url, headers: { 'x-p0-admin': KEY } });
  return { store, accounts, voice, hub, log, admin, app, post, get, save, acc, files };
}

describe('484 admin deletion / preview / incomplete list', () => {
  it('requires admin auth, is absent from the game app, and preview/list do not write files or settle saves', async () => {
    const f = setup();
    const before = [f.save, f.acc, ...Object.values(f.files)].map(p => readFileSync(p, 'utf8'));
    vi.spyOn(f.store, 'find').mockImplementation(() => { throw new Error('preview settled'); });
    vi.spyOn(f.store, 'get').mockImplementation(() => { throw new Error('preview created'); });
    expect((await f.admin.inject({ method: 'POST', url: '/admin/delete', payload: { player: P } })).statusCode).toBe(401);
    expect((await f.app.inject({ method: 'POST', url: '/admin/delete', payload: { player: P }, headers: { 'x-p0-admin': KEY } })).statusCode).toBe(404);
    const preview = (await f.get('/admin/delete/preview?support_code=' + support.supportCode(P))).json();
    expect(preview).toMatchObject({ ok: true, found: true, deleted: false, support_code: support.supportCode(P) });
    expect(JSON.stringify(preview)).not.toContain(P);
    expect((await f.get('/admin/delete/incomplete')).json()).toEqual({ ok: true, players: [] });
    expect([f.save, f.acc, ...Object.values(f.files)].map(p => readFileSync(p, 'utf8'))).toEqual(before);
  });

  it('deletes one account by support code, keeps reports and other account; tombstone repeats are idempotent', async () => {
    const f = setup(), other = structuredClone(f.store.peek(Q)), reports = readFileSync(f.files.reports, 'utf8');
    expect((await f.post({ support_code: support.supportCode(P) })).json()).toEqual({ ok: true });
    expect(new P0Store(C, f.save).peek(P)).toBeUndefined();
    expect(f.accounts.isDeleted(P)).toBe(true);
    expect(f.accounts.byToken('1'.repeat(64))).toBeUndefined();
    expect(f.store.peek(Q)).toEqual(other); expect(readFileSync(f.files.reports, 'utf8')).toBe(reports);
    expect((await f.post({ player: P })).json()).toEqual({ ok: true });
    expect(f.accounts.deletedPlayers()).toEqual([{ player: P, at: T }]);
    expect(JSON.stringify(f.log.mock.calls)).not.toContain(P);
  });

  it('lists and resumes partial save deletion by a tombstone even after its account row is gone', async () => {
    const f = setup(); vi.spyOn(console, 'warn').mockImplementation(() => {});
    mkdirSync(f.save + '.tmp');
    expect((await f.post({ player: P })).json()).toEqual({ ok: true, incomplete: true });
    expect(f.accounts.find(P)).toBeUndefined();
    expect((await f.get('/admin/delete/incomplete')).json().players).toEqual([{ player: P, support_code: support.supportCode(P), deleted_at: T, account_remaining: false, save_remaining: true }]);
    rmSync(f.save + '.tmp', { recursive: true });
    expect((await f.post({ support_code: support.supportCode(P) })).json()).toEqual({ ok: true });
    expect((await f.get('/admin/delete/incomplete')).json().players).toEqual([]);
    expect(f.store.peek(Q)).toBeDefined();
  });

  it('keeps accounts-only and tombstone-only targets resolvable, including voice remnants outside the incomplete list', async () => {
    const f = setup();
    f.store.remove(P); f.accounts.markDeleted(P, T);
    expect((await f.get('/admin/delete/incomplete')).json().players[0]).toMatchObject({ account_remaining: true, save_remaining: false });
    f.accounts.remove(P);
    expect((await f.get('/admin/delete/incomplete')).json().players).toEqual([]);
    expect((await f.post({ support_code: support.supportCode(P) })).json()).toEqual({ ok: true });
    expect(JSON.parse(readFileSync(f.files.ages, 'utf8'))).toEqual({ [Q]: false });
    expect(JSON.parse(readFileSync(f.files.blocks, 'utf8'))).toEqual({});
  });

  it('does not turn an exhausted media cleanup into success just because the active lease was removed', async () => {
    const f = setup();
    vi.spyOn(f.voice, 'drop').mockImplementation(async (_p, options) => { if (options?.requireConfirmed) throw new Error('VOICE_RELEASE_UNCONFIRMED'); });
    expect((await f.post({ player: P })).json()).toEqual({ ok: true, incomplete: true });
    expect(f.accounts.isDeleted(P)).toBe(true); expect(f.store.peek(P)).toBeUndefined();
  });

  it('returns delete_failed on the accounts phase and leaves the save for a subsequent authenticated admin retry', async () => {
    const f = setup(); mkdirSync(f.acc + '.tmp');
    const r = await f.post({ player: P });
    expect([r.statusCode, r.json()]).toEqual([500, { ok: false, code: 'delete_failed' }]);
    expect(f.store.peek(P)).toBeDefined();
    rmSync(f.acc + '.tmp', { recursive: true });
    expect((await f.post({ player: P })).json()).toEqual({ ok: true });
  });

  it('rejects ambiguous codes and malformed selectors without deleting or creating anything', async () => {
    const f = setup();
    for (const payload of [{}, [], { player: P, support_code: support.supportCode(P) }, { player: P, confirm: true }, { player: 'bad' }])
      expect((await f.post(payload)).statusCode).toBe(400);
    expect((await f.post({ player: 'unknown-player' })).statusCode).toBe(404);
    vi.spyOn(support, 'supportCode').mockReturnValue('00000-00000');
    expect((await f.post({ support_code: '00000-00000' })).statusCode).toBe(409);
    expect(f.store.size()).toBe(2); expect(f.accounts.deletedPlayers()).toEqual([]);
  });
});
