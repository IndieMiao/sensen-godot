/**
 * What the P0 server needs before it leaves the Mac (SGODOT-232 D1; deploying still needs the user's approval):
 * a demo access key on every /v1/p0/* request (HTTP and the WebSocket upgrade alike), a request limit per player
 * (or address), a small body limit, and hourly snapshots of the JSON save beside the live file.
 */
import rateLimit from '@fastify/rate-limit';
import type { FastifyInstance } from 'fastify';
import { copyFileSync, existsSync, mkdirSync, readdirSync, rmSync } from 'node:fs';
import path from 'node:path';

export interface P0GuardOptions {
  keys: string[];            // P0_ACCESS_KEYS; empty = no key needed (local playtests)
  perMinute: number;         // requests per player (or address) per minute
}

export function guardOptionsFromEnv(env: NodeJS.ProcessEnv = process.env): P0GuardOptions {
  return {
    keys: (env.P0_ACCESS_KEYS ?? '').split(',').map(k => k.trim()).filter(Boolean),
    perMinute: Number(env.P0_RATE_PER_MINUTE ?? 600),
  };
}

/** Register before the P0 routes. /v1/healthz stays open for the container health check. */
export async function registerP0Guard(app: FastifyInstance, opts: P0GuardOptions): Promise<void> {
  const keys = new Set(opts.keys);
  app.addHook('onRequest', async (req, reply) => {
    if (!req.url.startsWith('/v1/p0/') || keys.size === 0) return;
    if (!keys.has(String(req.headers['x-p0-key'] ?? ''))) return reply.code(401).send({ ok: false, code: 'bad_key' });
  });
  await app.register(rateLimit, {
    max: opts.perMinute,
    timeWindow: '1 minute',
    allowList: req => !req.url.startsWith('/v1/p0/'),
    keyGenerator: req => String(req.headers['x-p0-player'] ?? '') || req.ip,
    errorResponseBuilder: () => ({ ok: false, code: 'rate_limited', statusCode: 429 }),
  });
}

/** Copy the live save to <dir>/p0-state-<UTC hour>.json and keep the newest `keep` copies. */
export function snapshotState(file: string, dir: string, keep: number, now = Date.now()): string | null {
  if (!existsSync(file)) return null;
  mkdirSync(dir, { recursive: true });
  const hour = new Date(now).toISOString().slice(0, 13).replace(/[-T:]/g, '');
  const to = path.join(dir, `p0-state-${hour}.json`);
  copyFileSync(file, to);
  const all = readdirSync(dir).filter(f => /^p0-state-\d{10}\.json$/.test(f)).sort();
  for (const old of all.slice(0, Math.max(0, all.length - keep))) rmSync(path.join(dir, old));
  return to;
}
