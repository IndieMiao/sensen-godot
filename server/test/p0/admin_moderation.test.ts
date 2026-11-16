/** Exercises the real admin request → durable save → live voice/WS → future identity checks chain, isolated locally. */
import Fastify from 'fastify';
import { mkdtempSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import path from 'node:path';
import { tmpdir } from 'node:os';
import WebSocket from 'ws';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { registerP0Admin } from '../../src/p0/admin.js';
import { identify, inForce } from '../../src/p0/accounts/identify.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';
import { renameAt } from '../../src/p0/accounts/name.js';
import { loadP0Content } from '../../src/p0/content.js';
import { registerP0Online } from '../../src/p0/online/hub.js';
import { loadOutposts } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { P0Voice, registerP0Voice, RELEASE_RETRY_MS } from '../../src/p0/online/voice.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';
import * as support from '../../src/p0/support.js';

const C = loadP0Content(), T0 = Date.UTC(2026, 10, 15), TARGET = 'player-target', OTHER = 'player-other';
const KEY = 'fake-admin-key', TOKEN = '1'.repeat(64), OTHER_TOKEN = '2'.repeat(64), ADMIN_TOKEN = '3'.repeat(64);
const cleanup: (() => Promise<void>)[] = [];
afterEach(async () => { vi.restoreAllMocks(); for (const fn of cleanup.splice(0)) await fn(); });
async function setup() {
  const dir = mkdtempSync(path.join(tmpdir(), 'admin-moderation-'));
  const save = path.join(dir, 'state.json'), files = { ages: path.join(dir, 'ages.json'), blocks: path.join(dir, 'blocks.json'), reports: path.join(dir, 'reports.jsonl') };
  let time = T0;
  const now = () => time;
  const store = new P0Store(C, save), accounts = new P0Accounts(undefined, undefined, now);
  for (const p of [TARGET, OTHER]) { store.get(p, now()); accounts.ensure(p); }
  accounts.issue(TARGET, TOKEN); accounts.issue(TARGET, ADMIN_TOKEN, 'admin', T0 + 86_400_000); accounts.issue(OTHER, OTHER_TOKEN);
  const rooms = new OutpostRooms(loadOutposts()), participants = new Map<string, string>();
  const removed = vi.fn(async (room: string, peer: string) => { participants.delete(room + '/' + peer); });
  const getParticipant = vi.fn(async (room: string, peer: string) => ({ metadata: participants.get(room + '/' + peer) }));
  const voice = new P0Voice({ url: 'ws://fake.test', apiKey: 'fake', apiSecret: 'fake-only-secret-of-at-least-32-characters', namespace: 'moderation-test' }, rooms, files, now,
    { getParticipant, removeParticipant: removed });
  voice.setAge(TARGET, true); voice.setAge(OTHER, true);
  voice.voiceBan = p => store.peek(p)?.sanctions?.voice;
  const identity = { accounts, legacyId: false, suspended: (p: string) => inForce(store.peek(p)?.sanctions?.suspended, now()) };
  const who = (h: Record<string, unknown>) => identify(h, identity);
  const app = Fastify(), admin = Fastify(), audit: string[] = [], sockets: WebSocket[] = [];
  registerP0Routes(app, { content: C, store, now, dev: false, identify: identity });
  registerP0Voice(app, voice, who);
  const hub = registerP0Online(app, { rooms, identify: who, departed: o => voice.departed(o), nameOf: p => store.peek(p)?.profile?.name ?? null });
  const actions = { dropVoice: vi.fn((p: string) => voice.drop(p, { requireConfirmed: true })), kick: vi.fn((p: string) => { hub.kick(p); }), renamed: vi.fn((p: string) => hub.renamed(p)) };
  registerP0Admin(admin, { content: C, store, now, accounts, key: KEY, moderation: actions, log: l => audit.push(l) });
  await app.listen({ host: '127.0.0.1', port: 0 });
  const port = (app.server.address() as { port: number }).port;
  cleanup.push(async () => { for (const ws of sockets) ws.terminate(); await app.close(); await admin.close(); rmSync(dir, { recursive: true, force: true }); });
  const headers = { authorization: `Bearer ${TOKEN}`, 'x-p0-player': TARGET };
  const connect = async (token = TOKEN) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/v1/p0/online`, { headers: { authorization: `Bearer ${token}` } }); sockets.push(ws);
    await new Promise<void>((resolve, reject) => { ws.once('open', resolve); ws.once('error', reject); });
    const joined = new Promise<void>(resolve => ws.on('message', (data, binary) => { if (!binary && JSON.parse(String(data)).t === 'joined') resolve(); }));
    ws.send(JSON.stringify({ t: 'join', outpost: 'sh_tea_1' })); await joined; return ws;
  };
  const grant = async (p: string) => { const g = await voice.join(p) as Record<string, any>; participants.set(g.room + '/' + g.self, g.lease_id); return g; };
  const post = (payload: object) => admin.inject({ method: 'POST', url: '/admin/moderate', headers: { 'x-p0-admin': KEY }, payload });
  return { app, admin, store, accounts, save, files, now, advance: (ms: number) => { time += ms; }, voice, rooms, hub,
    audit, actions, removed, getParticipant, headers, port, connect, grant, post };
}

describe('484 admin-only manual moderation', () => {
  it.each(['get', 'remove'] as const)('real drop reports %s media failure as applied-but-incomplete, and background retry can finish', async stage => {
    const f = await setup(), ws = await f.connect(), grant = await f.grant(TARGET);
    const ages = readFileSync(f.files.ages, 'utf8');
    const closed = new Promise<number>(resolve => ws.once('close', resolve));
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const fault = stage === 'get' ? f.getParticipant : f.removed;
    fault.mockRejectedValueOnce(new Error('PRIVATE_MEDIA_FAILURE'));
    try {
      const r = await f.post({ player: TARGET, action: 'suspended', until: null });
      expect([r.statusCode, r.json()]).toEqual([500, { ok: false, code: 'moderation_incomplete', applied: true }]);
      expect(await closed).toBe(4001);
      expect(new P0Store(C, f.save).peek(TARGET)?.sanctions?.suspended).toEqual({ at: T0, until: null });
      expect(f.actions.kick).toHaveBeenCalledWith(TARGET);
      expect(JSON.parse(f.audit.at(-1)!)).toMatchObject({ incomplete: true });
      expect(JSON.stringify(f.audit)).not.toContain('PRIVATE_MEDIA_FAILURE');
      await vi.waitFor(() => expect(f.getParticipant).toHaveBeenCalledTimes(2), { timeout: RELEASE_RETRY_MS + 1500 });
      expect(f.removed).toHaveBeenCalledWith(grant.room, grant.self);
      await expect(f.voice.drop(TARGET, { requireConfirmed: true })).resolves.toBeUndefined();
      expect(readFileSync(f.files.ages, 'utf8')).toBe(ages);
    } finally {
      f.getParticipant.mockResolvedValue({ metadata: undefined });
      await f.voice.drop(TARGET, { requireConfirmed: true });
    }
  });

  it('an exhausted real drop remains unconfirmed on another admin request until media removal succeeds', async () => {
    const f = await setup(); await f.connect(); await f.grant(TARGET);
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    f.getParticipant.mockRejectedValue(new Error('media down'));
    try {
      const payload = { player: TARGET, action: 'voice', until: null };
      expect((await f.post(payload)).statusCode).toBe(500);
      await expect(f.voice.drop(TARGET)).resolves.toBeUndefined();
      expect(f.getParticipant).toHaveBeenCalledTimes(1); // Automatic callers must not bypass the retry backoff.
      await vi.waitFor(() => expect(f.getParticipant).toHaveBeenCalledTimes(3), { timeout: RELEASE_RETRY_MS * 2 + 1500 });
      // The live lease is already gone, but this must not silently become ok on another management call.
      expect((await f.post(payload)).json()).toMatchObject({ code: 'moderation_incomplete', applied: true });
      f.getParticipant.mockResolvedValue({ metadata: undefined }); // Provider confirms it is no longer this lease.
      expect((await f.post(payload)).json()).toMatchObject({ ok: true });
    } finally {
      f.getParticipant.mockResolvedValue({ metadata: undefined });
      await f.voice.drop(TARGET, { requireConfirmed: true });
    }
  }, 10_000);

  it('requires the management key and never registers on the public game listener', async () => {
    const f = await setup(), payload = { player: TARGET, action: 'suspended', until: null };
    expect((await f.admin.inject({ method: 'POST', url: '/admin/moderate', payload })).statusCode).toBe(401);
    expect((await f.app.inject({ method: 'POST', url: '/admin/moderate', headers: { 'x-p0-admin': KEY }, payload })).statusCode).toBe(404);
    expect(f.store.peek(TARGET)?.sanctions).toBeUndefined();
  });

  it('persists a voice ban through an admin request, drops the current lease and refuses join/heartbeat without clearing age/blocks or WS', async () => {
    const f = await setup(), ws = await f.connect(), other = await f.connect(OTHER_TOKEN);
    const grant = await f.grant(TARGET), otherGrant = await f.grant(OTHER);
    f.voice.block(TARGET, f.rooms.occupant(OTHER)!.id, true);
    const ages = readFileSync(f.files.ages, 'utf8'), blocks = readFileSync(f.files.blocks, 'utf8');
    const result = await f.post({ support_code: support.supportCode(TARGET), action: 'voice', until: T0 + 1000, report: 'R-20261115-0123ABCD' });
    expect(result.json()).toMatchObject({ ok: true, action: 'voice' });
    expect(new P0Store(C, f.save).peek(TARGET)?.sanctions?.voice).toEqual({ at: T0, until: T0 + 1000, report: 'R-20261115-0123ABCD' });
    expect(f.removed).toHaveBeenCalledWith(grant.room, grant.self);
    expect(ws.readyState).toBe(WebSocket.OPEN); expect(other.readyState).toBe(WebSocket.OPEN);
    for (const [url, payload] of [['/v1/p0/voice/join', {}], ['/v1/p0/voice/heartbeat', { lease_id: grant.lease_id }]] as const) {
      const r = await f.app.inject({ method: 'POST', url, headers: f.headers, payload });
      expect([r.statusCode, r.json().code]).toEqual([403, 'VOICE_BANNED']);
    }
    expect(f.voice.heartbeat(OTHER, otherGrant.lease_id)).toMatchObject({ ok: true });
    expect(readFileSync(f.files.ages, 'utf8')).toBe(ages); expect(readFileSync(f.files.blocks, 'utf8')).toBe(blocks);
    f.advance(1000); await expect(f.voice.join(TARGET)).resolves.toMatchObject({ ok: true });
    expect(JSON.stringify(f.audit)).not.toContain(TARGET);
  });

  it('persists suspension then immediately kicks WS/voice; user/admin tokens and future WS/voice requests see suspended', async () => {
    const f = await setup(), ws = await f.connect(), other = await f.connect(OTHER_TOKEN), grant = await f.grant(TARGET);
    const closed = new Promise<number>(resolve => ws.once('close', resolve));
    expect((await f.post({ player: TARGET, action: 'suspended', until: null })).json().ok).toBe(true);
    expect(await closed).toBe(4001); expect(f.rooms.occupant(TARGET)).toBeUndefined();
    expect(f.removed).toHaveBeenCalledWith(grant.room, grant.self);
    expect(other.readyState).toBe(WebSocket.OPEN);
    for (const token of [TOKEN, ADMIN_TOKEN]) {
      const r = await f.app.inject({ method: 'GET', url: '/v1/p0/state', headers: { authorization: `Bearer ${token}` } });
      expect([r.statusCode, r.json()]).toEqual([403, { ok: false, code: 'suspended', until: null }]);
    }
    const voice = await f.app.inject({ method: 'POST', url: '/v1/p0/voice/join', headers: f.headers, payload: {} });
    expect([voice.statusCode, voice.json().code]).toEqual([403, 'suspended']);
    const status = await new Promise<number>((resolve, reject) => {
      const again = new WebSocket(`ws://127.0.0.1:${f.port}/v1/p0/online`, { headers: f.headers });
      again.once('unexpected-response', (_req, res) => { res.resume(); res.once('end', () => resolve(res.statusCode!)); });
      again.once('open', () => { again.terminate(); reject(new Error('suspended player rejoined')); }); again.once('error', reject);
    });
    expect(status).toBe(403);
    expect(f.accounts.byToken(TOKEN)).toBeDefined(); // Keep identity so every entry can return the contractual suspended error.
    expect(new P0Store(C, f.save).peek(TARGET)?.sanctions?.suspended?.until).toBeNull();
  });

  it('resets the name and locks renaming for seven days while retaining all other account data', async () => {
    const f = await setup(), state = f.store.peek(TARGET)!;
    state.profile = { name: 'Bad Name', name_set_at: T0 - 20 * 86_400_000 }; f.store.put(state);
    const inventory = structuredClone(state.bag);
    const result = await f.post({ player: TARGET, action: 'reset_name' });
    expect(result.json().ok).toBe(true);
    const saved = new P0Store(C, f.save).peek(TARGET)!;
    expect(saved.profile?.name).toBeUndefined(); expect(saved.profile?.name_locked_until).toBe(T0 + 7 * 86_400_000);
    expect(renameAt(saved.profile)).toBe(T0 + 7 * 86_400_000);
    expect(saved.bag).toEqual(inventory); expect(saved.seq).toBe(state.seq + 1);
    expect(f.actions.renamed).toHaveBeenCalledWith(TARGET); expect(f.actions.dropVoice).not.toHaveBeenCalled();
    expect(JSON.stringify(f.audit)).not.toContain('Bad Name');
  });

  it('refuses malformed input and unknown/ambiguous support codes without creating or mutating a player', async () => {
    const f = await setup(), before = readFileSync(f.save, 'utf8');
    for (const p of [{}, { player: TARGET, support_code: support.supportCode(TARGET), action: 'reset_name' },
      { player: TARGET, action: 'voice' }, { player: TARGET, action: 'voice', until: T0 },
      { player: TARGET, action: 'reset_name', until: null }, { player: TARGET, action: 'other' },
      { player: TARGET, action: ['voice'], until: null }, { player: TARGET, action: { toString: 'voice' }, until: null }])
      expect((await f.post(p)).statusCode).toBe(400);
    expect((await f.post({ support_code: '00000-00000', action: 'reset_name' })).statusCode).toBe(404);
    expect((await f.post({ player: 'unknown-player', action: 'reset_name' })).statusCode).toBe(404);
    vi.spyOn(support, 'supportCode').mockReturnValue('00000-00000');
    expect((await f.post({ support_code: '00000-00000', action: 'reset_name' })).statusCode).toBe(409);
    expect(readFileSync(f.save, 'utf8')).toBe(before);
  });

  it('a failed save write rolls back the cloned state and performs no disconnect, then retry persists correctly', async () => {
    const f = await setup(), before = readFileSync(f.save, 'utf8');
    mkdirSync(f.save + '.tmp');
    const failed = await f.post({ player: TARGET, action: 'suspended', until: null });
    expect([failed.statusCode, failed.json().code]).toEqual([500, 'moderation_write_failed']);
    expect(f.store.peek(TARGET)?.sanctions).toBeUndefined();
    expect(readFileSync(f.save, 'utf8')).toBe(before);
    expect(f.actions.dropVoice).not.toHaveBeenCalled(); expect(f.actions.kick).not.toHaveBeenCalled();
    rmSync(f.save + '.tmp', { recursive: true });
    expect((await f.post({ player: TARGET, action: 'suspended', until: null })).json().ok).toBe(true);
    expect(f.actions.kick).toHaveBeenCalledWith(TARGET);
  });

  it('reports applied-but-incomplete cleanup while still trying WS kick after a voice error', async () => {
    const f = await setup(); f.actions.dropVoice.mockRejectedValueOnce(new Error('PRIVATE_PROVIDER_ERROR'));
    const r = await f.post({ player: TARGET, action: 'suspended', until: null });
    expect([r.statusCode, r.json()]).toEqual([500, { ok: false, code: 'moderation_incomplete', applied: true }]);
    expect(f.actions.kick).toHaveBeenCalledWith(TARGET);
    expect(new P0Store(C, f.save).peek(TARGET)?.sanctions?.suspended).toBeDefined();
    expect(JSON.stringify(f.audit)).not.toContain('PRIVATE_PROVIDER_ERROR');
  });
});
