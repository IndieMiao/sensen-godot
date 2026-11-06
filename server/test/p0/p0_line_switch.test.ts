// 421 (preview B): P0_LINE=close tells every client to leave the connection it keeps (P0Line) for a request each.
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { registerP0LineSwitch } from '../../src/p0/line_switch.js';

async function reply(value: string | undefined) {
  const app = Fastify();
  registerP0LineSwitch(app, value);
  app.get('/v1/p0/state', async () => ({ ok: true }));
  app.post('/v1/p0/commands', async (_q, r) => r.code(409).send({ ok: false, code: 'stale_state' }));
  const read = await app.inject({ method: 'GET', url: '/v1/p0/state' });
  const refused = await app.inject({ method: 'POST', url: '/v1/p0/commands', payload: {} });
  const missing = await app.inject({ method: 'GET', url: '/v1/p0/nothing' });
  await app.close();
  return [read, refused, missing].map(r => r.headers['x-p0-line']);
}

describe('P0_LINE (421)', () => {
  it('close: on every reply, a refusal and a 404 too', async () => {
    expect(await reply('close')).toEqual(['close', 'close', 'close']);
  });
  it('unset or anything else: nothing added', async () => {
    expect(await reply(undefined)).toEqual([undefined, undefined, undefined]);
    expect(await reply('1')).toEqual([undefined, undefined, undefined]);
  });
});
