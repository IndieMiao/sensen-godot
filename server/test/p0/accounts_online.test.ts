/** The room's WebSocket and the voice routes ask identify too (SGODOT-488 A1), and a player can be kicked (4001). */
import Fastify from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import WebSocket from 'ws';
import { identify } from '../../src/p0/accounts/identify.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';
import { registerP0Online } from '../../src/p0/online/hub.js';
import { loadOutposts } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { P0Voice, registerP0Voice } from '../../src/p0/online/voice.js';

const T = (n: number) => n.toString(16).padStart(64, '0');
const apps: ReturnType<typeof Fastify>[] = [];
afterEach(async () => { for (const a of apps.splice(0)) await a.close(); });

async function setup() {
  const accounts = new P0Accounts();
  accounts.ensure('p0-alpha0001'); accounts.issue('p0-alpha0001', T(1));
  const who = (h: Record<string, unknown>) => identify(h, { accounts, legacyId: false, warn: () => {} });
  const rooms = new OutpostRooms(loadOutposts());
  const app = Fastify(); apps.push(app);
  const hub = registerP0Online(app, { rooms, identify: who });
  registerP0Voice(app, new P0Voice(null, rooms, null), who);
  await app.listen({ port: 0, host: '127.0.0.1' });
  return { app, hub, accounts, port: (app.server.address() as { port: number }).port };
}
const attempt = (port: number, headers: Record<string, string>) => new Promise<{ status: number; body: string } | WebSocket>(resolve => {
  const ws = new WebSocket(`ws://127.0.0.1:${port}/v1/p0/online`, { headers });
  ws.once('open', () => resolve(ws));
  ws.once('unexpected-response', (_q, res) => { let body = ''; res.on('data', d => body += d); res.on('end', () => resolve({ status: res.statusCode ?? 0, body })); });
  ws.once('error', () => undefined);
});

describe('the room WebSocket with accounts', () => {
  it('opens for a token, refuses an unknown one with the routes\' JSON, and a kick closes it with 4001', async () => {
    const { hub, port } = await setup();
    expect(await attempt(port, { authorization: `Bearer ${T(2)}` })).toEqual({ status: 401, body: JSON.stringify({ ok: false, code: 'unauthenticated' }) });
    const ws = await attempt(port, { authorization: `Bearer ${T(1)}` }) as WebSocket;
    expect(ws).toBeInstanceOf(WebSocket);
    const closed = new Promise<number>(r => ws.once('close', code => r(code)));
    await new Promise(r => setTimeout(r, 50));
    expect(hub.kick('p0-alpha0001')).toBe(true);
    expect(await closed).toBe(4001);
    expect(hub.kick('p0-alpha0001')).toBe(false);
  });
  it('an old build on a claimed id is sent to update, not let in', async () => {
    const { accounts, port } = await setup();
    accounts.markClaimed('p0-alpha0001');
    const r = await attempt(port, { 'x-p0-player': 'p0-alpha0001' });
    expect(r).toMatchObject({ status: 426 });
  });
});

describe('the voice routes with accounts', () => {
  it('take the token\'s player and turn away an unknown token', async () => {
    const { app } = await setup();
    expect((await app.inject({ method: 'GET', url: '/v1/p0/voice/status', headers: { authorization: `Bearer ${T(1)}` } })).statusCode).toBe(200);
    const no = await app.inject({ method: 'GET', url: '/v1/p0/voice/status', headers: { authorization: `Bearer ${T(3)}` } });
    expect([no.statusCode, no.json().code]).toEqual([401, 'unauthenticated']);   // identify's own answer, as the routes give it
  });
  it('send identify\'s refusal as it is: session_replaced, update_required', async () => {
    const { app, accounts } = await setup();
    const replaced = await app.inject({ method: 'POST', url: '/v1/p0/voice/join', headers: { authorization: `Bearer ${T(9)}`, 'x-p0-player': 'p0-alpha0001' } });
    expect([replaced.statusCode, replaced.json().code]).toEqual([401, 'session_replaced']);
    accounts.markClaimed('p0-alpha0001');
    const old = await app.inject({ method: 'GET', url: '/v1/p0/voice/blocks', headers: { 'x-p0-player': 'p0-alpha0001' } });
    expect([old.statusCode, old.json().code]).toEqual([426, 'update_required']);
  });
});
