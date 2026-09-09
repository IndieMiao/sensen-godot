/** Loopback-only fault injection for the isolated G3 QA server, never a production proxy. */
import { createHash } from 'node:crypto';
import http, { type IncomingHttpHeaders, type ServerResponse } from 'node:http';
import { pathToFileURL } from 'node:url';
import type { Socket } from 'node:net';
import type { DecorationPlacement } from '../src/domain/state.js';

const COMMANDS = new Set(['buy_seeds', 'cook_dish', 'save_decorations']);
const MAX_BODY_BYTES = 1024 * 1024;
type Mode = 'before_forward' | 'after_commit';
type Replay = 'hold' | 'pass';
type Json = Record<string, any>;
type Reply = { status: number; headers: IncomingHttpHeaders; body: Buffer };
type Snapshot = {
  farm_digest: string; version: number; wallet: number; xp: number;
  seeds: Record<string, { bought: number; bound: number }>;
  produce: Record<string, number>; dishes: Record<string, number>;
  decoration_count: number; decorations_digest: string;
};
type Attempt = {
  index: number; replay: boolean; forwarded: boolean; held: boolean;
  status?: number; outcome?: string; code?: string;
};
type Fault = {
  type: string; mode: Mode; replay: Replay; keyDigest: string;
  authorization: string; attempts: Attempt[]; before: Snapshot | null;
  afterFirst: Snapshot | null; latest: Snapshot | null;
  applied: number; replayed: number; held: number; closed: number; snapshotError: boolean;
};

const digest = (value: string) => createHash('sha256').update(value).digest('hex');
const numeric = (value: unknown): number => typeof value === 'number' && Number.isFinite(value) ? value : 0;
function json(body: Buffer): Json {
  try { const value = JSON.parse(body.toString('utf8')); return value && typeof value === 'object' ? value : {}; }
  catch { return {}; }
}
function snapshot(body: Json): Snapshot | null {
  if (typeof body.farm_id !== 'string' || !body.state) return null;
  const state = body.state;
  const seeds = Object.fromEntries(['L', 'R', 'C', 'H'].map(crop => [crop, {
    bought: numeric(state.inventory?.seeds?.[crop]?.bought),
    bound: numeric(state.inventory?.seeds?.[crop]?.bound),
  }]));
  const counts = (source: Json | undefined, keys: string[]) => Object.fromEntries(keys.map(key => [key, numeric(source?.[key])]));
  // JSONB can reorder object keys; hash the schema fields in a fixed tuple order.
  const decorations = (state.decorations ?? []) as DecorationPlacement[];
  const decorationFields = decorations.map(({ anchor_id, prop_id, offset_q }) =>
    [anchor_id, prop_id, offset_q[0], offset_q[1]]);
  return {
    farm_digest: digest(body.farm_id).slice(0, 16), version: numeric(body.version),
    wallet: numeric(state.wallet), xp: numeric(state.xp?.total), seeds,
    produce: counts(state.inventory?.produce, ['L', 'R', 'C', 'H']),
    dishes: counts(state.inventory?.dishes, ['salad', 'tea']),
    decoration_count: decorations.length,
    decorations_digest: digest(JSON.stringify(decorationFields)).slice(0, 16),
  };
}
function resources(value: Snapshot | null) {
  if (!value) return null;
  const { version: _version, ...rest } = value;
  return rest;
}
function delta(before: Snapshot | null, after: Snapshot | null) {
  if (!before || !after) return null;
  return {
    wallet: after.wallet - before.wallet, xp: after.xp - before.xp,
    seeds: Object.fromEntries(Object.keys(before.seeds).map(crop => [crop, {
      bought: after.seeds[crop].bought - before.seeds[crop].bought,
      bound: after.seeds[crop].bound - before.seeds[crop].bound,
    }])),
    produce: Object.fromEntries(Object.keys(before.produce).map(crop => [crop, after.produce[crop] - before.produce[crop]])),
    dishes: Object.fromEntries(Object.keys(before.dishes).map(dish => [dish, after.dishes[dish] - before.dishes[dish]])),
  };
}

export function createG3FaultProxy(upstreamPort = 3103) {
  if (!Number.isInteger(upstreamPort) || upstreamPort < 1 || upstreamPort > 65535) throw new Error('Invalid loopback upstream port');
  let armed: { type: string; mode: Mode; replay: Replay } | null = null;
  let fault: Fault | null = null;
  const sockets = new Set<Socket>();
  const counters = { requests: 0, forwarded: 0, snapshot_reads: 0, upstream_errors: 0 };

  function forward(method: string, url: string, headers: IncomingHttpHeaders, body = Buffer.alloc(0)): Promise<Reply> {
    return new Promise((resolve, reject) => {
      const clean = { ...headers, host: `127.0.0.1:${upstreamPort}`, 'content-length': String(body.length) };
      delete clean.connection;
      delete clean['transfer-encoding'];
      const request = http.request({ hostname: '127.0.0.1', port: upstreamPort, method, path: url, headers: clean }, response => {
        const chunks: Buffer[] = [];
        let size = 0;
        response.on('data', (chunk: Buffer) => {
          size += chunk.length;
          if (size > 8 * MAX_BODY_BYTES) response.destroy(new Error('QA response too large'));
          else chunks.push(chunk);
        });
        response.on('error', reject);
        response.on('end', () => resolve({ status: response.statusCode ?? 502, headers: response.headers, body: Buffer.concat(chunks) }));
      });
      request.setTimeout(15_000, () => request.destroy(new Error('QA upstream timeout')));
      request.on('error', reject);
      request.end(body);
    });
  }
  async function readSnapshot(current: Fault): Promise<Snapshot | null> {
    counters.snapshot_reads++;
    try {
      const reply = await forward('GET', '/v1/farms/me', { authorization: current.authorization });
      const value = reply.status === 200 ? snapshot(json(reply.body)) : null;
      if (!value) current.snapshotError = true;
      return value;
    } catch {
      current.snapshotError = true;
      return null;
    }
  }
  function status() {
    return {
      upstream: `http://127.0.0.1:${upstreamPort}`, snapshot_format: 'g3-fault-resources-v2', armed, counters,
      fault: fault ? {
        type: fault.type, mode: fault.mode, replay: fault.replay, key_digest: fault.keyDigest.slice(0, 16),
        attempts: fault.attempts, applied_responses: fault.applied, replayed_responses: fault.replayed,
        held_total: fault.held, held_open: fault.held - fault.closed,
        before: fault.before, after_first_commit: fault.afterFirst, latest: fault.latest,
        first_delta: delta(fault.before, fault.afterFirst), total_delta: delta(fault.before, fault.latest),
        unchanged_since_first_commit: fault.afterFirst && fault.latest
          ? JSON.stringify(resources(fault.afterFirst)) === JSON.stringify(resources(fault.latest)) : null,
        unchanged_before_forward: fault.before && fault.latest && !fault.attempts.some(attempt => attempt.forwarded)
          ? JSON.stringify(resources(fault.before)) === JSON.stringify(resources(fault.latest)) : null,
        snapshot_error: fault.snapshotError,
      } : null,
    };
  }
  function sendJson(response: ServerResponse, code: number, value: unknown) {
    response.writeHead(code, { 'content-type': 'application/json', 'cache-control': 'no-store' });
    response.end(JSON.stringify(value));
  }
  function sendReply(response: ServerResponse, reply: Reply) {
    if (response.destroyed) return;
    const headers = { ...reply.headers };
    delete headers.connection;
    delete headers['transfer-encoding'];
    response.writeHead(reply.status, headers);
    response.end(reply.body);
  }
  function hold(response: ServerResponse, current: Fault, attempt: Attempt) {
    attempt.held = true;
    current.held++;
    if (response.destroyed) current.closed++;
    else response.once('close', () => { current.closed++; });
    // Deliberately send no headers/body. Client timeout or force-stop closes this socket.
  }
  async function handle(request: http.IncomingMessage, response: ServerResponse) {
    const chunks: Buffer[] = [];
    let size = 0;
    for await (const chunk of request) {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) { sendJson(response, 413, { code: 'BODY_TOO_LARGE' }); return; }
      chunks.push(chunk);
    }
    const body = Buffer.concat(chunks);
    const url = request.url ?? '/';
    const method = request.method ?? 'GET';
    if (url.startsWith('/__fault/')) {
      if (request.headers.origin || (method !== 'GET' && !request.headers['content-type']?.startsWith('application/json'))) {
        sendJson(response, 403, { code: 'LOCAL_JSON_ONLY' }); return;
      }
      const args = json(body);
      if (method === 'GET' && url === '/__fault/status') { sendJson(response, 200, status()); return; }
      if (method === 'POST' && url === '/__fault/arm') {
        if (!COMMANDS.has(args.type) || !['before_forward', 'after_commit'].includes(args.mode)
          || !['hold', 'pass'].includes(args.replay ?? 'hold')) {
          sendJson(response, 400, { code: 'INVALID_FAULT', types: [...COMMANDS], modes: ['before_forward', 'after_commit'], replay: ['hold', 'pass'] }); return;
        }
        if (fault && fault.held > fault.closed) { sendJson(response, 409, { code: 'CLIENT_STILL_WAITING' }); return; }
        fault = null;
        armed = { type: args.type, mode: args.mode, replay: args.replay ?? 'hold' };
        sendJson(response, 200, status()); return;
      }
      if (method === 'POST' && url === '/__fault/replay') {
        if (!['hold', 'pass'].includes(args.replay)) { sendJson(response, 400, { code: 'INVALID_REPLAY_POLICY' }); return; }
        if (fault) fault.replay = args.replay;
        if (armed) armed.replay = args.replay;
        sendJson(response, 200, status()); return;
      }
      if (method === 'POST' && url === '/__fault/disarm') {
        armed = null;
        if (fault) fault.replay = 'pass';
        sendJson(response, 200, status()); return;
      }
      if (method === 'POST' && url === '/__fault/verify') {
        if (!fault) { sendJson(response, 409, { code: 'NO_MATCHED_COMMAND' }); return; }
        fault.latest = await readSnapshot(fault);
        sendJson(response, 200, status()); return;
      }
      sendJson(response, 404, { code: 'NO_MANAGEMENT_ROUTE' }); return;
    }
    if (!url.startsWith('/v1/')) { sendJson(response, 404, { code: 'QA_API_ONLY' }); return; }
    counters.requests++;
    const command = method === 'POST' && url === '/v1/farms/me/commands' ? json(body) : {};
    const keyDigest = typeof command.idempotency_key === 'string' ? digest(command.idempotency_key) : '';
    let current = keyDigest && fault?.keyDigest === keyDigest ? fault : null;
    let first = false;
    if (!current && armed && command.type === armed.type && keyDigest) {
      first = true;
      current = fault = { ...armed, keyDigest, authorization: request.headers.authorization ?? '',
        attempts: [], before: null, afterFirst: null, latest: null,
        applied: 0, replayed: 0, held: 0, closed: 0, snapshotError: false };
      armed = null;
    }
    if (!current) {
      counters.forwarded++;
      sendReply(response, await forward(method, url, request.headers, body)); return;
    }
    current.authorization = request.headers.authorization ?? current.authorization;
    const attempt: Attempt = { index: current.attempts.length + 1, replay: !first, forwarded: false, held: false };
    if (current.attempts.length < 50) current.attempts.push(attempt);
    if (first) {
      current.before = await readSnapshot(current);
      current.latest = current.before;
    }
    if ((first && current.mode === 'before_forward') || (!first && current.replay === 'hold')) {
      hold(response, current, attempt); return;
    }
    counters.forwarded++;
    attempt.forwarded = true;
    const reply = await forward(method, url, request.headers, body);
    const result = json(reply.body);
    attempt.status = reply.status;
    if (typeof result.outcome === 'string') attempt.outcome = result.outcome;
    if (typeof result.code === 'string') attempt.code = result.code;
    if (result.outcome === 'applied') current.applied++;
    if (result.outcome === 'replayed') current.replayed++;
    const committed = reply.status >= 200 && reply.status < 300 && result.replayed_outcome !== 'rejected';
    if (committed && !current.afterFirst) current.afterFirst = snapshot(result);
    current.latest = await readSnapshot(current);
    if (first && current.mode === 'after_commit' && committed) hold(response, current, attempt);
    else sendReply(response, reply);
  }
  const server = http.createServer((request, response) => {
    void handle(request, response).catch(() => {
      counters.upstream_errors++;
      if (!response.destroyed && !response.headersSent) sendJson(response, 502, { code: 'QA_UPSTREAM_ERROR' });
      else response.destroy();
    });
  });
  server.on('connection', socket => { sockets.add(socket); socket.once('close', () => sockets.delete(socket)); });
  return {
    server,
    listen: (port = 3104): Promise<number> => new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(port, '127.0.0.1', () => {
        server.removeListener('error', reject);
        const address = server.address();
        resolve(address && typeof address !== 'string' ? address.port : port);
      });
    }),
    close: (): Promise<void> => new Promise(resolve => {
      for (const socket of sockets) socket.destroy();
      server.close(() => resolve());
    }),
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const proxy = createG3FaultProxy();
  const port = await proxy.listen();
  console.log(JSON.stringify({ listening: `http://127.0.0.1:${port}`, upstream: 'http://127.0.0.1:3103', purpose: 'isolated-g3-qa-only' }));
  process.once('SIGINT', () => { void proxy.close(); });
  process.once('SIGTERM', () => { void proxy.close(); });
}
