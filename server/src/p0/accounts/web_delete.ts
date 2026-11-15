/** SGODOT-484: browser proof-of-identity deletion, outside the game's x-p0-key namespace. Never creates a farm/session. */
import { randomBytes } from 'node:crypto';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { deleteAccount, type DeleteDeps } from './delete.js';
import { verifyAppleIdToken, type AppleVerifyOptions } from './apple.js';
import { verifyGoogleIdToken, type GoogleVerifyOptions } from './google.js';
import { codeShapeOk, emailReady, normalizeEmail, type EmailRouteDeps } from './email.js';
import { IdTokenError, sha256Hex } from './jwt.js';
import type { Provider } from './store.js';
import { supportCode } from '../support.js';
import { webDeletePage } from './web_delete_page.js';

type Result = { status: number; body: Record<string, unknown> };
type Verified = { provider: Provider; sub: string; player: string };
interface Ticket { ip: string; nonce: string; at: number; verified?: Verified; job?: Promise<Result>; result?: Result }
export interface WebDeleteDeps extends DeleteDeps {
  appleWeb?: AppleVerifyOptions;
  googleWeb?: GoogleVerifyOptions;
  appleClientId?: string; googleClientId?: string;
  email: EmailRouteDeps;
  startEmail: (req: FastifyRequest, reply: FastifyReply) => Promise<unknown>;
  apiBase: string;
  origins: string[];
  warn?: (event: string) => void;
}
const TEN_MIN = 600_000, MAX_TICKETS = 2000;
const failed = (status: number, code: string, extra = {}): Result => ({ status, body: { ok: false, code, ...extra } });
const success = (): Result => ({ status: 200, body: { ok: true } });

export function registerWebDeleteRoutes(app: FastifyInstance, deps: WebDeleteDeps): void {
  const tickets = new Map<string, Ticket>(), limits = new Map<string, { start: number; count: number }>();
  const warn = deps.warn ?? (event => console.warn(JSON.stringify({ web_delete: event })));
  const send = (reply: FastifyReply, result: Result) => reply.code(result.status).send(result.body);
  const sweep = () => {
    const now = deps.now();
    for (const [id, t] of tickets) if (now - t.at >= TEN_MIN && !t.job) tickets.delete(id);
    for (const [ip, limit] of limits) if (now - limit.start >= 60_000) limits.delete(ip);
  };
  const allow = (ip: string): boolean => {
    sweep(); const limit = limits.get(ip);
    if (limit) return ++limit.count <= 30;
    if (limits.size >= 10_000) return false;
    limits.set(ip, { start: deps.now(), count: 1 }); return true;
  };

  const perform = async (ticket: Ticket, b: Record<string, unknown>, ip: string): Promise<Result> => {
    if (!ticket.verified) {
      const provider = b.provider;
      let sub: string;
      try {
        if (provider === 'apple') {
          if (!deps.appleWeb || !deps.appleClientId) return failed(503, 'provider_unavailable');
          sub = (await verifyAppleIdToken(b.id_token, ticket.nonce, deps.appleWeb)).sub;
        } else if (provider === 'google') {
          if (!deps.googleWeb || !deps.googleClientId) return failed(503, 'provider_unavailable');
          sub = (await verifyGoogleIdToken(b.id_token, ticket.nonce, deps.googleWeb)).sub;
        } else if (provider === 'email') {
          if (!emailReady(deps.email)) return failed(503, 'provider_unavailable');
          const email = normalizeEmail(b.email);
          if (!email || !codeShapeOk(b.code)) return failed(400, 'schema');
          const result = deps.email.codes.check(email, b.code, ip);
          if (!result.ok) return result.why === 'rate_limited' ? failed(429, result.why, { retry_in: result.retry_in })
            : result.why === 'bad_code' ? failed(401, result.why, { attempts_left: result.attempts_left }) : failed(410, result.why);
          deps.email.codes.take(email);
          sub = deps.accounts.emailId(email);
        } else return failed(400, 'schema');
      } catch (e) {
        return e instanceof IdTokenError ? failed(401, 'bad_token') : failed(503, 'provider_unavailable');
      }
      if (deps.now() - ticket.at >= TEN_MIN) return failed(410, 'code_expired');
      // The identity may have changed while JWKS was fetched: resolve its owner only after the last verification await.
      const player = deps.accounts.byIdentity(provider, sub);
      if (!player || deps.accounts.isDeleted(player) || !deps.accounts.find(player)) return failed(404, 'no_farm');
      ticket.verified = { provider, sub, player };
    }
    const verified = ticket.verified;
    if (b.provider !== verified.provider) return failed(400, 'schema');
    const owner = deps.accounts.byIdentity(verified.provider, verified.sub);
    if (owner && owner !== verified.player) return failed(401, 'bad_token');
    try { await deleteAccount(deps, verified.player); }
    catch (e) {
      if (e instanceof Error && e.message === 'ACCOUNT_DELETE_INCOMPLETE') {
        warn('delete_incomplete:' + supportCode(verified.player)); // Same App contract: identity gone, admin finishes residuals.
        return success();
      }
      warn('delete_failed:' + supportCode(verified.player));
      return failed(500, 'delete_failed'); // Verified ticket allows a retry without spending a second email code.
    }
    return success();
  };

  app.register(async web => {
    web.addHook('onRequest', async (req, reply) => {
      reply.header('Cache-Control', 'no-store').header('Referrer-Policy', 'no-referrer').header('X-Content-Type-Options', 'nosniff');
      const origin = req.headers.origin;
      if (origin && !deps.origins.includes(origin)) return reply.code(403).send({ ok: false, code: 'bad_origin' });
      if (origin) reply.header('Access-Control-Allow-Origin', origin).header('Vary', 'Origin');
      if (req.method === 'OPTIONS') {
        if (!origin) return reply.code(403).send({ ok: false, code: 'bad_origin' });
        return reply.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS').header('Access-Control-Allow-Headers', 'Content-Type').code(204).send();
      }
      if (req.method === 'POST' && !origin) return reply.code(403).send({ ok: false, code: 'bad_origin' });
      if (!allow(req.ip)) return reply.code(429).send({ ok: false, code: 'rate_limited', retry_in: 60 });
    });
    for (const url of ['/v1/web/delete', '/v1/web/email/start', '/v1/web/delete/options']) web.options(url, async () => ({}));
    web.get('/v1/web/delete/page', async (_req, reply) => {
      const nonce = randomBytes(18).toString('base64');
      reply.header('Content-Security-Policy', `default-src 'self'; script-src 'nonce-${nonce}' https://appleid.cdn-apple.com https://accounts.google.com; style-src 'unsafe-inline'; connect-src 'self' ${new URL(deps.apiBase).origin} https://accounts.google.com; frame-src https://accounts.google.com https://appleid.apple.com; img-src 'self' data: https://accounts.google.com; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`);
      return reply.type('text/html; charset=utf-8').send(webDeletePage(deps.apiBase, nonce));
    });
    web.get('/v1/web/delete/options', async (req, reply) => {
      sweep(); if (tickets.size >= MAX_TICKETS) return reply.code(503).send({ ok: false, code: 'provider_unavailable' });
      const challenge = randomBytes(32).toString('hex'), nonce = randomBytes(32).toString('hex');
      tickets.set(challenge, { nonce, ip: req.ip, at: deps.now() });
      return { ok: true, challenge, nonce_hash: sha256Hex(nonce),
        apple_client_id: deps.appleWeb ? deps.appleClientId ?? null : null,
        google_client_id: deps.googleWeb ? deps.googleClientId ?? null : null, email: emailReady(deps.email) };
    });
    web.post('/v1/web/email/start', { bodyLimit: 2048 }, deps.startEmail);
    web.post('/v1/web/delete', { bodyLimit: 8192 }, async (req, reply) => {
      const b = req.body;
      if (!b || typeof b !== 'object' || Array.isArray(b)) return send(reply, failed(400, 'schema'));
      const body = b as Record<string, unknown>;
      if (Object.keys(body).some(k => !['challenge', 'confirmed', 'provider', 'id_token', 'email', 'code'].includes(k))
        || body.confirmed !== true || typeof body.challenge !== 'string' || !/^[a-f0-9]{64}$/.test(body.challenge)
        || typeof body.provider !== 'string' || !['apple', 'google', 'email'].includes(body.provider)) return send(reply, failed(400, 'schema'));
      const ticket = tickets.get(body.challenge);
      if (!ticket || ticket.ip !== req.ip || deps.now() - ticket.at >= TEN_MIN) return send(reply, failed(410, 'code_expired'));
      if (ticket.result) return send(reply, ticket.result);
      if (!ticket.job) ticket.job = perform(ticket, body, req.ip).then(result => {
        if (result.status === 200) ticket.result = result;
        return result;
      }).catch(() => failed(500, 'delete_failed')).finally(() => { ticket.job = undefined; });
      return send(reply, await ticket.job);
    });
  });
}
