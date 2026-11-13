/**
 * What the P0 server needs before it leaves the Mac (SGODOT-232 D1; deploying still needs the user's approval):
 * a demo access key on every /v1/p0/* route, a request limit per player plus a total per address, a small body
 * limit, and hourly snapshots of the JSON save beside the live file.
 * The outpost rooms' WebSocket (/v1/p0/online, SGODOT-227) upgrades on the raw server and never reaches these hooks;
 * it checks the same keys itself (registerP0Online deps.keys) and limits its own messages.
 */
import { bearerOf } from './accounts/identify.js';
import { hashToken } from './accounts/store.js';
import rateLimit from '@fastify/rate-limit';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { copyFileSync, existsSync, mkdirSync, readdirSync, rmSync } from 'node:fs';
import path from 'node:path';
import type { P0Gate } from './gate.js';

export interface P0GuardOptions {
  keys: string[];            // P0_ACCESS_KEYS; empty = no key needed (local playtests)
  perMinute: number;         // requests per player id per minute (P0_RATE_PER_MINUTE)
  perAddress: number;        // requests per client address per minute, whatever ids it sends (P0_RATE_PER_IP)
}

export function guardOptionsFromEnv(env: NodeJS.ProcessEnv = process.env): P0GuardOptions {
  return {
    keys: (env.P0_ACCESS_KEYS ?? '').split(',').map(k => k.trim()).filter(Boolean),
    perMinute: Number(env.P0_RATE_PER_MINUTE ?? 600),
    perAddress: Number(env.P0_RATE_PER_IP ?? 2000),
  };
}

/**
 * Behind Caddy the client address comes from X-Forwarded-For: P0_TRUST_PROXY=1 trusts only proxies on loopback and
 * private networks (Caddy reaches P0 over the Docker network), so the address taken is the first public one counting
 * back from the socket — the one Caddy appended — and anything a client wrote into the header in front of it is
 * ignored (PR #26 review). Fastify 5's numeric hop count left req.ip on the socket address, so it is not used.
 * Off (no option) on a directly published port.
 */
export const trustProxyFromEnv = (env: NodeJS.ProcessEnv = process.env): { trustProxy?: string } =>
  (env.P0_TRUST_PROXY === '1' ? { trustProxy: 'loopback, uniquelocal' } : {});

/**
 * Whether a request is for the P0 game routes. It reads the route Fastify matched (routeOptions.url), not the raw
 * URL: the router decodes %XX, so /v1/%70%30/state reaches /v1/p0/state (PR #26 review). A request that matched no
 * route is judged on its decoded path, so an unknown /v1/p0/ path still needs the key.
 */
export function isP0Request(req: FastifyRequest): boolean {
  const route = req.routeOptions?.url;
  if (route) return route.startsWith('/v1/p0/');
  const raw = req.url.split('?')[0];
  let decoded = raw;
  try { decoded = decodeURIComponent(raw); } catch { /* malformed escapes: judge the raw path */ }
  return decoded.toLowerCase().startsWith('/v1/p0/') || raw.toLowerCase().startsWith('/v1/p0/');
}

/**
 * Register before the P0 routes. /v1/healthz stays open for the container health check. With a gate, Update (426) and
 * Maintenance (503) answer right after the key check and before the rate limits (gate.ts).
 */
export async function registerP0Guard(app: FastifyInstance, opts: P0GuardOptions, gate?: P0Gate): Promise<void> {
  const keys = new Set(opts.keys);
  app.addHook('onRequest', async (req, reply) => {
    if (keys.size === 0 || !isP0Request(req)) return;
    if (!keys.has(String(req.headers['x-p0-key'] ?? ''))) return reply.code(401).send({ ok: false, code: 'bad_key' });
  });
  if (gate) {
    app.addHook('onRequest', async (req, reply) => {
      if (!isP0Request(req)) return;
      const refused = gate.check(req.headers);
      if (refused) return reply.code(refused.status).send(refused.body);
    });
  }
  // A total per address first: a player id is the client's own word, so changing it every request must not help.
  const perAddress = new Map<string, number>();
  let minute = -1;
  app.addHook('onRequest', async (req, reply) => {
    if (!isP0Request(req)) return;
    const now = Math.floor(Date.now() / 60_000);
    if (now !== minute) { perAddress.clear(); minute = now; }
    const n = (perAddress.get(req.ip) ?? 0) + 1;
    perAddress.set(req.ip, n);
    if (n > opts.perAddress) return reply.code(429).send({ ok: false, code: 'rate_limited' });
  });
  await app.register(rateLimit, {
    max: opts.perMinute,
    timeWindow: '1 minute',
    allowList: req => !isP0Request(req),
    // SGODOT-488: a token's request counts by its token (its hash's head), an id's by the id as before
    keyGenerator: req => { const t = bearerOf(req.headers); return t ? `${req.ip}|t:${hashToken(t).slice(0, 16)}` : `${req.ip}|${String(req.headers['x-p0-player'] ?? '')}`; },
    errorResponseBuilder: () => ({ ok: false, code: 'rate_limited', statusCode: 429 }),
  });
}

/** Copy the live save to <dir>/p0-state-<UTC hour>.json and keep the newest `keep` copies. With `accounts` (SGODOT-488,
 * tech-plan §1.3) accounts.json goes beside it as <dir>/accounts-<the same hour>.json, kept the same: a save put back
 * from an hour ago comes back with the tokens and links of that hour, never newer ones that would not match it. */
export function snapshotState(file: string, dir: string, keep: number, now = Date.now(), accounts?: string): string | null {
  if (!existsSync(file)) return null;
  mkdirSync(dir, { recursive: true });
  const hour = new Date(now).toISOString().slice(0, 13).replace(/[-T:]/g, '');
  const to = path.join(dir, `p0-state-${hour}.json`);
  copyFileSync(file, to);
  if (accounts && existsSync(accounts)) copyFileSync(accounts, path.join(dir, `accounts-${hour}.json`));
  for (const kind of ['p0-state', 'accounts']) {
    const all = readdirSync(dir).filter(f => new RegExp(`^${kind}-\\d{10}\\.json$`).test(f)).sort();
    for (const old of all.slice(0, Math.max(0, all.length - keep))) rmSync(path.join(dir, old));
  }
  return to;
}
