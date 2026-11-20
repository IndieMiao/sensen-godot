/** SGODOT-484, contract v1.6.10 §1.2 (edb9eaf8): private versioned notices, not timestamps or game seq. */
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { P0State } from '../state.js';
import type { P0Store } from '../store.js';
import { identify, isRefusal, type IdentifyDeps } from './identify.js';

export interface NameResetWatermark { version: number; ack_version: number }
const record = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v);
const whole = (v: unknown, minimum: number): v is number => typeof v === 'number' && Number.isSafeInteger(v) && v >= minimum;
const failed = () => new Error('NOTICE_FAILED');

/** Shared by GET, ACK and management. Returns a copy; malformed new data never falls back to old timestamps. */
export function nameResetWatermark(s: P0State): NameResetWatermark {
  const notices: unknown = s.account_notices;
  if (notices !== undefined) {
    if (!record(notices) || !record(notices.name_reset)) throw failed();
    const { version, ack_version } = notices.name_reset;
    if (!whole(version, 1) || !whole(ack_version, 0) || ack_version > version) throw failed();
    return { version, ack_version };
  }
  if (s.sanctions !== undefined && !record(s.sanctions)) throw failed();
  const old = s.sanctions?.name_reset_at;
  if (old === undefined) return { version: 0, ack_version: 0 };
  if (!whole(old, 0)) throw failed();
  return { version: 1, ack_version: 0 };
}

/** Compute before modifying even the clone; overflow rejects the entire management operation. */
export function nextNameReset(s: P0State): NameResetWatermark {
  const current = nameResetWatermark(s);
  if (current.version === Number.MAX_SAFE_INTEGER) throw failed();
  return { version: current.version + 1, ack_version: current.ack_version };
}

export function registerAccountNoticeRoutes(app: FastifyInstance, deps: { store: P0Store; identify: IdentifyDeps }): void {
  app.register(async notices => {
    notices.addHook('onSend', async (_req, reply, payload) => { reply.header('Cache-Control', 'no-store'); return payload; });
    const ownState = (req: FastifyRequest, reply: FastifyReply): P0State | undefined => {
      const who = identify(req.headers, deps.identify);
      if (isRefusal(who)) { reply.code(who.status).send(who.body); return; }
      if (who.via !== 'token') { reply.code(401).send({ ok: false, code: 'unauthenticated' }); return; }
      if (deps.identify.accounts.isDeleted(who.player)) { reply.code(401).send({ ok: false, code: 'account_deleted' }); return; }
      const state = deps.store.peek(who.player); // Never find/get: they settle parcels or create a save.
      if (!state) { reply.code(401).send({ ok: false, code: 'unauthenticated' }); return; }
      return state;
    };
    notices.get('/v1/p0/account/notices', async (req, reply) => {
      const state = ownState(req, reply);
      if (!state) return reply;
      try {
        const { version, ack_version } = nameResetWatermark(state);
        return { ok: true, name_reset: version > ack_version ? { version } : null };
      } catch { return reply.code(500).send({ ok: false, code: 'notice_failed' }); }
    });
    notices.post('/v1/p0/account/notices/ack', async (req, reply) => {
      const state = ownState(req, reply);
      if (!state) return reply;
      const b = req.body;
      if (!record(b) || Object.keys(b).length !== 2 || b.kind !== 'name_reset' || !whole(b.version, 1))
        return reply.code(400).send({ ok: false, code: 'schema' });
      // This entire read/clone/check/put stays synchronous: an ACK cannot overwrite a newer reset captured before await.
      try {
        const current = nameResetWatermark(state);
        if (b.version > current.version) return reply.code(409).send({ ok: false, code: 'notice_version_conflict' });
        if (b.version <= current.ack_version) return { ok: true };
        const next = structuredClone(state);
        next.account_notices = { ...next.account_notices,
          name_reset: { version: current.version, ack_version: Math.max(current.ack_version, b.version) } };
        deps.store.put(next); // No seq increment, profile/lock changes or broadcasts. Failed put restores previous memory.
        return { ok: true };
      } catch { return reply.code(500).send({ ok: false, code: 'notice_failed' }); }
    });
  });
}
