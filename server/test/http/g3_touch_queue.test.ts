import Fastify from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { registerG3TouchQueue } from '../../tools/g3_touch_queue.js';

const apps: ReturnType<typeof Fastify>[] = [];
async function queue() {
  const app = Fastify();
  apps.push(app);
  await registerG3TouchQueue(app);
  await app.inject({ method: 'POST', url: '/v1/qa/touch/runs', payload: { run_id: 'device_test', platform: 'Android' } });
  return app;
}
const base = '/v1/qa/touch/runs/device_test';
const action = { id: 1, kind: 'tap', label: 'Cook salad', screen_points: [[100, 200]] };
afterEach(async () => { for (const app of apps.splice(0)) await app.close(); });

describe('isolated G3 touch queue', () => {
  it('keeps a checkpoint single-use until an idempotent acknowledgement arrives', async () => {
    const app = await queue();
    await app.inject({ method: 'POST', url: `${base}/device`, payload: { worker_id: 'worker_1', device: { serial: 'target' } } });
    expect((await app.inject({ method: 'POST', url: `${base}/checkpoints`, payload: action })).statusCode).toBe(200);
    expect((await app.inject({ method: 'POST', url: `${base}/checkpoints`, payload: action })).statusCode).toBe(200);
    expect((await app.inject({ method: 'GET', url: `${base}/next?worker_id=worker_1` })).json().action).toEqual(action);
    expect((await app.inject({ method: 'GET', url: `${base}/next?worker_id=worker_1` })).json().action).toBeNull();
    expect((await app.inject({ method: 'POST', url: `${base}/checkpoints`, payload: { ...action, id: 2 } })).statusCode).toBe(409);
    expect((await app.inject({ method: 'POST', url: `${base}/checkpoints/1/ack`, payload: { worker_id: 'other', ok: true } })).statusCode).toBe(403);
    const ack = { worker_id: 'worker_1', ok: true, adb_args: ['shell', 'input', 'tap', '100', '200'] };
    for (let repeat = 0; repeat < 2; repeat++)
      expect((await app.inject({ method: 'POST', url: `${base}/checkpoints/1/ack`, payload: ack })).statusCode).toBe(200);
    expect((await app.inject({ method: 'GET', url: `${base}/checkpoints/1` })).json().ack).toEqual(ack);
    expect((await app.inject({ method: 'POST', url: `${base}/checkpoints`, payload: { ...action, id: 2 } })).statusCode).toBe(200);
  });

  it('rejects external requests and conflicting workers or checkpoint payloads', async () => {
    const app = await queue();
    expect((await app.inject({ method: 'GET', url: base, remoteAddress: '192.168.1.2' })).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: '/v1/qa/touch/runs', payload: { run_id: 'device_test' } })).statusCode).toBe(409);
    await app.inject({ method: 'POST', url: `${base}/device`, payload: { worker_id: 'worker_1', device: {} } });
    expect((await app.inject({ method: 'POST', url: `${base}/device`, payload: { worker_id: 'worker_2', device: {} } })).statusCode).toBe(409);
    await app.inject({ method: 'POST', url: `${base}/checkpoints`, payload: action });
    expect((await app.inject({ method: 'POST', url: `${base}/checkpoints`, payload: { ...action, label: 'Other' } })).statusCode).toBe(409);
    expect((await app.inject({ method: 'GET', url: `${base}/next?worker_id=wrong` })).statusCode).toBe(403);
  });

  it.each([
    { ...action, kind: 'shell' }, { ...action, screen_points: [[-1, 5]] },
    { ...action, screen_points: [['1', 5]] }, { ...action, id: 0 },
    { ...action, kind: 'swipe', screen_points: [[1, 2], [3, 4]], duration_ms: 1 },
  ])('rejects malformed or arbitrary input actions %#', async malformed => {
    const app = await queue();
    expect((await app.inject({ method: 'POST', url: `${base}/checkpoints`, payload: malformed })).statusCode).toBe(400);
  });

  it('preserves the client report separately from host device classification', async () => {
    const app = await queue();
    const device = { serial: 'emulator-5554', physical_device: false, properties: { 'ro.kernel.qemu': '1' } };
    await app.inject({ method: 'POST', url: `${base}/device`, payload: { worker_id: 'worker_1', device } });
    await app.inject({ method: 'POST', url: `${base}/finish`, payload: { platform: 'Android', passed: true } });
    const run = (await app.inject({ method: 'GET', url: base })).json();
    expect(run.status).toBe('finished');
    expect(run.device).toEqual(device);
    expect(run.report).toEqual({ platform: 'Android', passed: true });
    expect((await app.inject({ method: 'POST', url: `${base}/checkpoints`, payload: action })).statusCode).toBe(409);
  });
});
