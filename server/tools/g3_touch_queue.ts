import type { FastifyInstance } from 'fastify';

interface Checkpoint {
  id: number;
  kind: 'tap' | 'swipe';
  label: string;
  screen_points: [number, number][];
  duration_ms?: number;
  [key: string]: unknown;
}
interface TouchRun {
  run_id: string;
  status: 'running' | 'finished';
  setup: Record<string, unknown>;
  device?: Record<string, unknown>;
  worker_id?: string;
  checkpoints: { action: Checkpoint; worker_id?: string; ack?: Record<string, unknown> }[];
  report?: Record<string, unknown>;
}
const validId = (value: unknown): value is string => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,96}$/.test(value);
const object = (value: unknown): value is Record<string, unknown> => !!value && typeof value === 'object' && !Array.isArray(value);

/** Registered only by the disposable loopback QA server, never by the production app. */
export async function registerG3TouchQueue(app: FastifyInstance): Promise<void> {
  const runs = new Map<string, TouchRun>();
  await app.register(async api => {
    api.addHook('onRequest', async (request, reply) => {
      if (!['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(request.ip))
        return reply.code(403).send({ code: 'LOOPBACK_ONLY' });
    });
    api.post('/runs', async (request, reply) => {
      const body = request.body;
      if (!object(body) || !validId(body.run_id)) return reply.code(400).send({ code: 'INVALID_RUN' });
      const prior = runs.get(body.run_id);
      if (prior) return reply.code(409).send({ code: 'RUN_EXISTS' });
      if (runs.size >= 32) return reply.code(429).send({ code: 'QA_RUN_LIMIT' });
      runs.set(body.run_id, { run_id: body.run_id, status: 'running', setup: structuredClone(body), checkpoints: [] });
      return { run_id: body.run_id };
    });
    api.get<{ Params: { run: string } }>('/runs/:run', async (request, reply) => {
      const run = runs.get(request.params.run);
      return run ?? reply.code(404).send({ code: 'NO_RUN' });
    });
    api.post<{ Params: { run: string } }>('/runs/:run/device', async (request, reply) => {
      const run = runs.get(request.params.run);
      if (!run) return reply.code(404).send({ code: 'NO_RUN' });
      const body = request.body;
      if (!object(body) || !validId(body.worker_id) || !object(body.device))
        return reply.code(400).send({ code: 'INVALID_WORKER' });
      if (run.worker_id && run.worker_id !== body.worker_id) return reply.code(409).send({ code: 'WORKER_EXISTS' });
      run.worker_id = body.worker_id;
      run.device = structuredClone(body.device);
      return { attached: true };
    });
    api.post<{ Params: { run: string } }>('/runs/:run/checkpoints', async (request, reply) => {
      const run = runs.get(request.params.run);
      if (!run) return reply.code(404).send({ code: 'NO_RUN' });
      const body = request.body;
      if (!object(body) || !Number.isSafeInteger(body.id) || (body.id as number) < 1
        || !['tap', 'swipe'].includes(String(body.kind)) || typeof body.label !== 'string'
        || !Array.isArray(body.screen_points) || body.screen_points.length !== (body.kind === 'tap' ? 1 : 2)
        || body.screen_points.some(p => !Array.isArray(p) || p.length !== 2
          || p.some(n => !Number.isFinite(n) || n < 0 || n > 32768))
        || (body.kind === 'swipe' && (!Number.isSafeInteger(body.duration_ms)
          || (body.duration_ms as number) < 50 || (body.duration_ms as number) > 10000)))
        return reply.code(400).send({ code: 'INVALID_CHECKPOINT' });
      const existing = run.checkpoints.find(c => c.action.id === body.id);
      if (existing) return JSON.stringify(existing.action) === JSON.stringify(body)
        ? { id: body.id } : reply.code(409).send({ code: 'CHECKPOINT_MISMATCH' });
      if (run.status !== 'running' || body.id !== run.checkpoints.length + 1 || run.checkpoints.some(c => !c.ack))
        return reply.code(409).send({ code: 'CHECKPOINT_ORDER' });
      run.checkpoints.push({ action: structuredClone(body) as Checkpoint });
      return { id: body.id };
    });
    api.get<{ Params: { run: string }; Querystring: { worker_id?: string } }>('/runs/:run/next', async (request, reply) => {
      const run = runs.get(request.params.run);
      if (!run) return reply.code(404).send({ code: 'NO_RUN' });
      if (!run.worker_id || run.worker_id !== request.query.worker_id) return reply.code(403).send({ code: 'WRONG_WORKER' });
      const pending = run.checkpoints.find(c => !c.worker_id && !c.ack);
      // Never re-lease an action: a worker may have tapped before losing its acknowledgement.
      if (pending) pending.worker_id = run.worker_id;
      return { status: run.status, action: pending?.action ?? null, report: run.report ?? null };
    });
    api.get<{ Params: { run: string; id: string } }>('/runs/:run/checkpoints/:id', async (request, reply) => {
      const checkpoint = runs.get(request.params.run)?.checkpoints.find(c => c.action.id === Number(request.params.id));
      return checkpoint ? { id: checkpoint.action.id, ack: checkpoint.ack ?? null }
        : reply.code(404).send({ code: 'NO_CHECKPOINT' });
    });
    api.post<{ Params: { run: string; id: string } }>('/runs/:run/checkpoints/:id/ack', async (request, reply) => {
      const checkpoint = runs.get(request.params.run)?.checkpoints.find(c => c.action.id === Number(request.params.id));
      if (!checkpoint) return reply.code(404).send({ code: 'NO_CHECKPOINT' });
      const body = request.body;
      if (!object(body) || typeof body.ok !== 'boolean' || !validId(body.worker_id))
        return reply.code(400).send({ code: 'INVALID_ACK' });
      if (checkpoint.worker_id !== body.worker_id) return reply.code(403).send({ code: 'WRONG_WORKER' });
      if (checkpoint.ack) return JSON.stringify(checkpoint.ack) === JSON.stringify(body)
        ? { acknowledged: true } : reply.code(409).send({ code: 'ACK_MISMATCH' });
      checkpoint.ack = structuredClone(body);
      return { acknowledged: true };
    });
    api.post<{ Params: { run: string } }>('/runs/:run/finish', async (request, reply) => {
      const run = runs.get(request.params.run);
      if (!run) return reply.code(404).send({ code: 'NO_RUN' });
      if (!object(request.body)) return reply.code(400).send({ code: 'INVALID_REPORT' });
      run.report = structuredClone(request.body);
      run.status = 'finished';
      return { finished: true };
    });
  }, { prefix: '/v1/qa/touch' });
}
