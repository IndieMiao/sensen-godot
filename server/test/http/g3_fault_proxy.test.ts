import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import http from 'node:http';
import { createG3FaultProxy } from '../../tools/g3_fault_proxy.js';
import type { DecorationPlacement } from '../../src/domain/state.js';

describe('loopback G3 fault proxy', () => {
  let upstream: http.Server;
  let proxy: ReturnType<typeof createG3FaultProxy>;
  let base: string;
  let commandCalls: number;
  let applied: Map<string, object>;
  let state: any;
  let version: number;
  const heldRequests: AbortController[] = [];
  const credentials = { authorization: 'Bearer fixture-token-do-not-log', install_key: 'fixture-install-key-do-not-log' };

  beforeEach(async () => {
    commandCalls = 0;
    applied = new Map();
    version = 4;
    state = { wallet: 100, xp: { total: 50 }, inventory: {
      seeds: { R: { bought: 0, bound: 0 } }, produce: { L: 3, C: 2 }, dishes: { salad: 0, tea: 0 },
    }, decorations: [] };
    const view = () => ({ farm_id: 'fixture-owner-farm', version, state: structuredClone(state) });
    upstream = http.createServer(async (request, response) => {
      const chunks: Buffer[] = [];
      for await (const chunk of request) chunks.push(chunk);
      const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : {};
      response.setHeader('content-type', 'application/json');
      if (request.url === '/v1/farms/me') {
        const stored = view();
        stored.state.decorations = stored.state.decorations.map(({ anchor_id, prop_id, offset_q }: DecorationPlacement) =>
          ({ prop_id, offset_q: [...offset_q], anchor_id }));
        response.end(JSON.stringify(stored)); return;
      }
      if (request.url === '/v1/auth/anonymous') {
        response.end(JSON.stringify({ token: credentials.authorization, installation_received: body.install_key === credentials.install_key })); return;
      }
      if (request.url === '/v1/farms/me/commands') {
        commandCalls++;
        if (applied.has(body.idempotency_key)) {
          response.end(JSON.stringify({ outcome: 'replayed', replayed_outcome: 'applied', ...applied.get(body.idempotency_key) })); return;
        }
        if (body.payload?.reject) { response.statusCode = 422; response.end(JSON.stringify({ code: 'INSUFFICIENT_ITEMS', outcome: 'rejected' })); return; }
        if (body.type === 'buy_seeds') { state.wallet -= 8; state.inventory.seeds.R.bought += 2; }
        if (body.type === 'cook_dish') { state.inventory.produce.L--; state.inventory.produce.C--; state.inventory.dishes.salad++; }
        if (body.type === 'save_decorations') state.decorations = body.payload.props;
        version++;
        applied.set(body.idempotency_key, view());
        response.end(JSON.stringify({ outcome: 'applied', ...view() })); return;
      }
      response.statusCode = 404;
      response.end('{}');
    });
    await new Promise<void>(resolve => upstream.listen(0, '127.0.0.1', resolve));
    const address = upstream.address() as { port: number };
    proxy = createG3FaultProxy(address.port);
    base = `http://127.0.0.1:${await proxy.listen(0)}`;
  });
  afterEach(async () => {
    for (const controller of heldRequests.splice(0)) controller.abort();
    await proxy.close();
    upstream.closeAllConnections();
    await new Promise<void>(resolve => upstream.close(() => resolve()));
  });

  const envelope = (type: string, key = 'a'.repeat(32), payload: object = {}) => ({ type, idempotency_key: key, base_version: 4, payload });
  async function management(route: string, body?: object) {
    const response = await fetch(base + '/__fault/' + route, body ? {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
    } : undefined);
    return { status: response.status, body: await response.json() as any };
  }
  function command(body: object, hold = false) {
    const controller = new AbortController();
    if (hold) heldRequests.push(controller);
    return fetch(base + '/v1/farms/me/commands', { method: 'POST',
      headers: { 'content-type': 'application/json', authorization: credentials.authorization },
      body: JSON.stringify(body), signal: controller.signal,
    });
  }
  async function waitHeld(count: number) {
    await vi.waitFor(async () => {
      expect((await management('status')).body.fault.held_total).toBe(count);
    }, { interval: 10, timeout: 2000 });
  }

  it.each(['buy_seeds', 'cook_dish', 'save_decorations'])('holds %s after commit and passes a same-key replay without repeating costs', async type => {
    await management('arm', { type, mode: 'after_commit', replay: 'hold' });
    const body = envelope(type, 'a'.repeat(32), { props: [{ anchor_id: 'courtyard', prop_id: 'bench', offset_q: [-4, 3] }] });
    let received = false;
    const lost = command(body, true).then(() => { received = true; }).catch(() => null);
    await waitHeld(1);
    expect(received).toBe(false);
    expect(commandCalls).toBe(1);
    const retry = command(body, true).catch(() => null);
    await waitHeld(2);
    expect(commandCalls).toBe(1);
    for (const controller of heldRequests) controller.abort();
    await Promise.all([lost, retry]);
    await management('replay', { replay: 'pass' });
    const replay = await command(body);
    expect((await replay.json() as any).outcome).toBe('replayed');
    const report = (await management('verify', {})).body.fault;
    expect(report.applied_responses).toBe(1);
    expect(report.replayed_responses).toBe(1);
    expect(report.unchanged_since_first_commit).toBe(true);
    expect(report.total_delta).toEqual(report.first_delta);
    expect(report.snapshot_error).toBe(false);
    expect(applied.size).toBe(1);
    if (type === 'buy_seeds') expect(report.total_delta.wallet).toBe(-8);
    if (type === 'cook_dish') expect(report.total_delta.dishes.salad).toBe(1);
    if (type === 'save_decorations') expect(report.latest.decoration_count).toBe(1);
  });

  it('ignores JSONB object-key order while detecting an actual layout change', async () => {
    const props: DecorationPlacement[] = [{ anchor_id: 'courtyard', prop_id: 'bench', offset_q: [-4, 3] }];
    await management('arm', { type: 'save_decorations', mode: 'after_commit', replay: 'hold' });
    const pending = command(envelope('save_decorations', 'c'.repeat(32), { props }), true).catch(() => null);
    await waitHeld(1);
    const reloaded = await (await fetch(base + '/v1/farms/me', { headers: { authorization: credentials.authorization } })).json() as any;
    expect(reloaded.state.decorations).toEqual(props);
    expect(JSON.stringify(reloaded.state.decorations)).not.toBe(JSON.stringify(props));
    heldRequests[0].abort();
    await pending;
    await management('replay', { replay: 'pass' });
    expect((await (await command(envelope('save_decorations', 'c'.repeat(32), { props }))).json() as any).outcome).toBe('replayed');
    const result = (await management('verify', {})).body;
    expect(result.snapshot_format).toBe('g3-fault-resources-v2');
    expect(result.fault.unchanged_since_first_commit).toBe(true);
    expect(result.fault.after_first_commit.decorations_digest).toBe(result.fault.latest.decorations_digest);
    expect(result.fault.applied_responses).toBe(1);
    expect(result.fault.replayed_responses).toBe(1);
    state.decorations[0].offset_q = [4, 3];
    const changed = (await management('verify', {})).body.fault;
    expect(changed.unchanged_since_first_commit).toBe(false);
    expect(changed.latest.decorations_digest).not.toBe(changed.after_first_commit.decorations_digest);
    expect(changed.snapshot_error).toBe(false);
  });

  it('holds before forwarding, proves no cost, then sends the original command exactly once', async () => {
    await management('arm', { type: 'buy_seeds', mode: 'before_forward', replay: 'hold' });
    const body = envelope('buy_seeds');
    const dropped = command(body, true).catch(() => null);
    await waitHeld(1);
    expect(commandCalls).toBe(0);
    let report = (await management('verify', {})).body.fault;
    expect(report.unchanged_before_forward).toBe(true);
    expect(report.total_delta.wallet).toBe(0);
    heldRequests[0].abort();
    await dropped;
    await management('replay', { replay: 'pass' });
    expect((await (await command(body)).json() as any).outcome).toBe('applied');
    report = (await management('verify', {})).body.fault;
    expect(commandCalls).toBe(1);
    expect(report.total_delta.wallet).toBe(-8);
    expect(report.applied_responses).toBe(1);
  });

  it('passes a rejected command instead of labeling it a held commit', async () => {
    await management('arm', { type: 'cook_dish', mode: 'after_commit' });
    const response = await command(envelope('cook_dish', 'b'.repeat(32), { reject: true }));
    expect(response.status).toBe(422);
    const report = (await management('status')).body.fault;
    expect(report.applied_responses).toBe(0);
    expect(report.held_total).toBe(0);
    expect(report.after_first_commit).toBeNull();
  });

  it('does not expose credentials, raw keys, or player identifiers through telemetry', async () => {
    await fetch(base + '/v1/auth/anonymous', { method: 'POST',
      headers: { 'content-type': 'application/json' }, body: JSON.stringify({ install_key: credentials.install_key }) });
    await management('arm', { type: 'buy_seeds', mode: 'before_forward' });
    const pending = command(envelope('buy_seeds'), true).catch(() => null);
    await waitHeld(1);
    const report = JSON.stringify((await management('verify', {})).body);
    expect(report).not.toContain(credentials.authorization);
    expect(report).not.toContain(credentials.install_key);
    expect(report).not.toContain('fixture-owner-farm');
    expect(report).not.toContain('a'.repeat(32));
    heldRequests[0].abort();
    await pending;
  });

  it('keeps the armed fault for its selected type and refuses non-QA proxy routes and browser-origin controls', async () => {
    await management('arm', { type: 'cook_dish', mode: 'after_commit' });
    expect((await command(envelope('buy_seeds'))).status).toBe(200);
    expect((await management('status')).body.armed.type).toBe('cook_dish');
    expect((await fetch(base + '/https://farm.sensenjoy.cn/v1')).status).toBe(404);
    expect((await fetch(base + '/__fault/status', { headers: { origin: 'https://elsewhere.invalid' } })).status).toBe(403);
    expect((await management('arm', { type: 'qa_advance_day', mode: 'after_commit' })).status).toBe(400);
  });
});
