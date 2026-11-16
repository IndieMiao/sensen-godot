/** v1.6.11: real code/name routes and committed files. Inject only; no listener or client/provider acceptance. */
import Fastify, { type FastifyInstance } from 'fastify';
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { registerP0Admin } from '../../src/p0/admin.js';
import { registerCodeRoutes } from '../../src/p0/accounts/codes.js';
import { identify, isRefusal } from '../../src/p0/accounts/identify.js';
import { NameLimiter, registerNameRoutes } from '../../src/p0/accounts/name.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';
import { loadP0Content } from '../../src/p0/content.js';
import { P0Store } from '../../src/p0/store.js';

const content = loadP0Content(), NOW = Date.UTC(2026, 10, 16, 4), KEY = Buffer.alloc(32, 23);
const token = (n: number) => n.toString(16).padStart(2, '0').repeat(32);
const dirs: string[] = [], apps: FastifyInstance[] = [];
afterEach(async () => {
  for (const a of apps.splice(0)) await a.close();
  for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true });
});
const app = () => { const a = Fastify(); apps.push(a); return a; };
function fixture() {
  const dir = mkdtempSync(path.join(tmpdir(), 'p0-code-route-')); dirs.push(dir);
  const stateFile = path.join(dir, 'state.json'), accountFile = path.join(dir, 'accounts.json');
  const store = new P0Store(content, stateFile), accounts = new P0Accounts(accountFile, KEY, () => NOW);
  const server = app(), admin = app(), renamed: string[] = [];
  let discardNameResponse = false;
  server.addHook('onSend', async (req, reply, payload) => {
    // Drop only the serialized success after commit. No-listener lost-body fault, not a socket-disconnect test.
    if (discardNameResponse && req.url === '/v1/p0/account/name' && reply.statusCode === 200) return '';
    return payload;
  });
  registerCodeRoutes(server, { store, accounts, now: () => NOW });
  registerNameRoutes(server, { store, now: () => NOW, limiter: new NameLimiter(), renamed: p => renamed.push(p),
    identify: (req, reply) => {
      const who = identify(req.headers, { accounts, legacyId: false });
      if (isRefusal(who)) { reply.code(who.status).send(who.body); return null; }
      if (who.via !== 'token') { reply.code(401).send({ ok: false, code: 'unauthenticated' }); return null; }
      return who.player;
    } });
  registerP0Admin(admin, { content, store, accounts, now: () => NOW, key: 'qa-admin', log: () => {} });
  const issue = async (player?: string) => (await admin.inject({ method: 'POST', url: '/admin/code',
    headers: { 'x-p0-admin': 'qa-admin' }, payload: { note: 'review-routing', ...(player ? { player } : {}) } })).json();
  let attempts = 0;
  const signIn = (code: string, t = token(1)) => server.inject({ method: 'POST', url: '/v1/p0/session/code',
    payload: { code, token: t }, remoteAddress: `198.51.100.${++attempts}` });
  const save = (name: string) => server.inject({ method: 'POST', url: '/v1/p0/account/name',
    headers: { authorization: 'Bearer ' + token(1) }, payload: { name } });
  const reloadedSignIn = (code: string, t: string) => {
    const freshApp = app();
    registerCodeRoutes(freshApp, { store: new P0Store(content, stateFile),
      accounts: new P0Accounts(accountFile, KEY, () => NOW), now: () => NOW });
    return freshApp.inject({ method: 'POST', url: '/v1/p0/session/code', payload: { code, token: t } });
  };
  return { store, accounts, stateFile, issue, signIn, save, renamed, reloadedSignIn,
    loseNameResponse: () => { discardNameResponse = true; } };
}

describe('test-code routing from committed state', () => {
  it('new/Skip pre-home -> NAME; completed home with default/reset name -> continue, recomputed for the same token', async () => {
    const f = fixture(), { player, code } = await f.issue();
    expect((await f.signIn(code)).json()).toEqual({ ok: true, player, next_step: 'name' });
    // Skip sends no request and leaves no completion fact.
    expect((await f.signIn(code)).json().next_step).toBe('name');
    const next = structuredClone(f.store.peek(player)!);
    delete next.travel.pending; next.profile = { name_locked_until: NOW + 604_800_000 };
    next.sanctions = { name_reset_at: NOW }; f.store.put(next);
    const before = readFileSync(f.stateFile, 'utf8');
    expect((await f.signIn(code)).json()).toEqual({ ok: true, player, next_step: 'continue' });
    expect(readFileSync(f.stateFile, 'utf8')).toBe(before);
    expect((await f.reloadedSignIn(code, token(2))).json().next_step).toBe('continue');
    expect(f.accounts.byToken(token(1))?.player).toBe(player);
  });

  it('a real Save before home selection -> continue even when the success body is discarded', async () => {
    const f = fixture(), { player, code } = await f.issue();
    await f.signIn(code); f.loseNameResponse();
    const lost = await f.save('Mia');
    expect(lost.statusCode).toBe(200); expect(lost.body).toBe('');
    expect(JSON.parse(readFileSync(f.stateFile, 'utf8'))[player].profile).toEqual({ name: 'Mia', name_set_at: NOW });
    expect(f.store.peek(player)!.travel.pending).toBe(true); expect(f.renamed).toEqual([player]);
    expect((await f.signIn(code)).json()).toEqual({ ok: true, player, next_step: 'continue' });
    expect((await f.reloadedSignIn(code, token(2))).json().next_step).toBe('continue');
  });

  it('a real failed Save leaves memory/disk/other accounts intact; live and restarted code login still require NAME', async () => {
    const f = fixture(), { player, code } = await f.issue();
    f.store.get('unrelated-farm-001', NOW); await f.signIn(code);
    const before = readFileSync(f.stateFile, 'utf8'), live = structuredClone(f.store.peek(player)!);
    const other = structuredClone(f.store.peek('unrelated-farm-001')!);
    mkdirSync(f.stateFile + '.tmp'); // Actual writeFileSync EISDIR, not a mocked put.
    expect((await f.save('Mia')).statusCode).toBe(500);
    expect(f.store.peek(player)).toEqual(live); expect(f.store.peek('unrelated-farm-001')).toEqual(other);
    expect(readFileSync(f.stateFile, 'utf8')).toBe(before); expect(f.renamed).toEqual([]);
    expect((await f.signIn(code)).json()).toEqual({ ok: true, player, next_step: 'name' });
    expect((await f.reloadedSignIn(code, token(2))).json().next_step).toBe('name');
    rmSync(f.stateFile + '.tmp', { recursive: true });
    expect((await f.save('Mia')).json().ok).toBe(true);
    expect((await f.signIn(code)).json().next_step).toBe('continue'); expect(f.renamed).toEqual([player]);
  });

  it.each([undefined, null, 0, NOW])('name_set_at=%s keeps null/0 compatibility', async at => {
    const f = fixture(), { player, code } = await f.issue(), s = structuredClone(f.store.peek(player)!);
    s.profile = { name_set_at: at as number }; f.store.put(s);
    const expected = at == null ? 'name' : 'continue';
    expect((await f.signIn(code)).json().next_step).toBe(expected);
    expect((await f.reloadedSignIn(code, token(2))).json().next_step).toBe(expected);
  });

  it.each([
    ['timestamp string', { name_set_at: '1' }, true], ['negative timestamp', { name_set_at: -1 }, true],
    ['fractional timestamp', { name_set_at: 1.5 }, true], ['unsafe timestamp', { name_set_at: Number.MAX_SAFE_INTEGER + 1 }, true],
    ['bad timestamp on existing home', { name_set_at: false }, false], ['nonboolean pending', {}, 'false'],
  ])('refuses %s before issuing a token or successful route', async (_label, profile, pending) => {
    const f = fixture(), { player, code } = await f.issue(), s = f.store.peek(player)!;
    s.profile = profile as typeof s.profile; (s.travel as { pending?: unknown }).pending = pending;
    const r = await f.signIn(code);
    expect(r.statusCode).toBe(500); expect(r.json().next_step).toBeUndefined();
    expect(f.accounts.byToken(token(1))).toBeUndefined();
  });

  it('uses the code owner, rejects cross-account tokens, and never recreates a missing save', async () => {
    const f = fixture(), fresh = await f.issue();
    f.store.get('existing-home-001', NOW); const old = await f.issue('existing-home-001');
    expect((await f.signIn(fresh.code, token(1))).json().next_step).toBe('name');
    expect((await f.signIn(old.code, token(1))).json()).toEqual({ ok: false, code: 'schema' });
    expect((await f.signIn(old.code, token(2))).json()).toEqual({ ok: true, player: old.player, next_step: 'continue' });
    expect(f.accounts.byToken(token(1))?.player).toBe(fresh.player);
    f.store.remove(fresh.player);
    expect((await f.signIn(fresh.code, token(3))).json()).toEqual({ ok: false, code: 'bad_code' });
    expect(f.store.peek(fresh.player)).toBeUndefined(); expect(f.accounts.byToken(token(3))).toBeUndefined();
  });
});
