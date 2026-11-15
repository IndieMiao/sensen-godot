/** Sign in with Apple server notifications, contract v1.4 (which supersedes §3's old unlink-on-consent wording).
 * Apple DocC "Processing changes for Sign in with Apple accounts": signed {iss,aud,iat,jti,events}; exp optional.
 * No private signing key, app token, shared game key, email, or caller-supplied player is accepted as authority here.
 */
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import type { FastifyInstance } from 'fastify';
import { APPLE_ISSUER } from './apple.js';
import { deleteAccount, type DeleteDeps } from './delete.js';
import { IdTokenError, verifyRs256, type KeySource } from './jwt.js';
import type { PendingSignIns } from './link.js';

// Bound notification replay storage and stale signed input together. Unlike a login, Apple can retry delivery.
export const APPLE_NOTIFICATION_MAX_AGE_MS = 30 * 86_400_000;
const SKEW_S = 60;
type EventType = 'consent-revoked' | 'account-deleted' | 'ignored';
export interface AppleNotification { aud: string; jti: string; sub: string; type: EventType; at: number; issued: number }
const hash = (s: string) => createHash('sha256').update(s).digest('hex');
const record = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v);
const nonempty = (v: unknown, max: number): v is string => typeof v === 'string' && v.length > 0 && v.length <= max;
const seconds = (v: unknown): v is number => typeof v === 'number' && Number.isSafeInteger(v) && v >= 0 && v <= 8_640_000_000_000;

export async function verifyAppleNotification(payload: unknown, opts: {
  audiences: string[]; keys: KeySource; refreshKeys?: KeySource; now: () => number;
}): Promise<AppleNotification> {
  const t = await verifyRs256(payload, opts.keys, opts.refreshKeys), now = opts.now();
  if (t.iss !== APPLE_ISSUER) throw new IdTokenError('BAD_ISSUER');
  if (typeof t.aud !== 'string' || !opts.audiences.includes(t.aud)) throw new IdTokenError('BAD_AUDIENCE');
  if (!seconds(t.iat) || t.iat * 1000 > now + SKEW_S * 1000 || now - t.iat * 1000 > APPLE_NOTIFICATION_MAX_AGE_MS)
    throw new IdTokenError('BAD_ISSUED_TIME');
  if (t.exp !== undefined && (!seconds(t.exp) || t.exp * 1000 <= now - SKEW_S * 1000)) throw new IdTokenError('EXPIRED');
  if (!nonempty(t.jti, 256)) throw new IdTokenError('BAD_JTI');
  let e = t.events;
  if (typeof e === 'string') { try { e = JSON.parse(e); } catch { throw new IdTokenError('BAD_EVENTS'); } }
  if (!record(e) || !nonempty(e.type, 80) || !nonempty(e.sub, 255) || !seconds(e.event_time) ||
      e.event_time > t.iat + SKEW_S || e.event_time * 1000 > now + SKEW_S * 1000 || now - e.event_time * 1000 > APPLE_NOTIFICATION_MAX_AGE_MS)
    throw new IdTokenError('BAD_EVENTS');
  const type: EventType = e.type === 'consent-revoked' ? 'consent-revoked'
    : e.type === 'account-deleted' || e.type === 'account-delete' ? 'account-deleted' : 'ignored';
  return { aud: t.aud, jti: t.jti, sub: e.sub, type, at: e.event_time * 1000, issued: t.iat * 1000 };
}

interface Entry {
  digest: string; expires: number; player: string | null; created: number | null;
  action: 'revoke' | 'unlink' | 'delete' | 'ignore'; done: boolean;
}
/** Operational delivery journal, separate from accounts/save format. No raw JWS, jti, Apple sub, email or token.
 * A pending target is kept before mutation so deletion can resume after the identity row disappears. */
export class AppleNotificationJournal {
  private entries: Record<string, Entry> = {};
  private authorizations: Record<string, number> = {};
  private revocations: Record<string, number> = {};
  private jobs = new Map<string, Promise<void>>();
  constructor(private file?: string, private now: () => number = Date.now) {
    if (file && existsSync(file)) {
      let d: unknown;
      try { d = JSON.parse(readFileSync(file, 'utf8')); } catch { throw new Error('APPLE_NOTIFICATION_JOURNAL_INVALID'); }
      if (!record(d) || d.v !== 1 || !record(d.entries)) throw new Error('APPLE_NOTIFICATION_JOURNAL_INVALID');
      for (const [k, x] of Object.entries(d.entries)) {
        if (!/^[a-f0-9]{64}$/.test(k) || !record(x) || !/^[a-f0-9]{64}$/.test(String(x.digest)) ||
            typeof x.expires !== 'number' || !Number.isFinite(x.expires) || typeof x.done !== 'boolean' ||
            !['revoke', 'unlink', 'delete', 'ignore'].includes(String(x.action)) ||
            !(x.player === null || typeof x.player === 'string' && /^[A-Za-z0-9_-]{8,64}$/.test(x.player)) ||
            !(x.created === null || typeof x.created === 'number' && Number.isFinite(x.created)))
          throw new Error('APPLE_NOTIFICATION_JOURNAL_INVALID');
        this.entries[k] = x as unknown as Entry;
      }
      if (!record(d.authorizations)) throw new Error('APPLE_NOTIFICATION_JOURNAL_INVALID');
      for (const [k, at] of Object.entries(d.authorizations)) {
        if (!/^[a-f0-9]{64}$/.test(k) || typeof at !== 'number' || !Number.isFinite(at)) throw new Error('APPLE_NOTIFICATION_JOURNAL_INVALID');
        this.authorizations[k] = at;
      }
      if (!record(d.revocations)) throw new Error('APPLE_NOTIFICATION_JOURNAL_INVALID');
      for (const [k, at] of Object.entries(d.revocations)) {
        if (!/^[a-f0-9]{64}$/.test(k) || typeof at !== 'number' || !Number.isFinite(at)) throw new Error('APPLE_NOTIFICATION_JOURNAL_INVALID');
        this.revocations[k] = at;
      }
    }
  }
  /** Verified Apple JWT iat protects renewed credentials even after the new user token logs out. */
  authorized = (sub: string, issuedAt: number): void => {
    const key = hash(sub);
    const revoked = this.revocations[key];
    if (revoked !== undefined && issuedAt <= revoked + 999) throw new IdTokenError('AUTHORIZATION_REVOKED');
    if ((this.authorizations[key] ?? -1) >= issuedAt) return;
    const next = { ...this.authorizations };
    for (const [k, at] of Object.entries(next)) if (at < this.now() - APPLE_NOTIFICATION_MAX_AGE_MS - 86_400_000) delete next[k];
    if (!next[key] && Object.keys(next).length >= 100_000) throw new Error('APPLE_NOTIFICATION_JOURNAL_FULL');
    next[key] = issuedAt;
    this.persist(this.entries, next); this.authorizations = next;
  };
  authorizedAfter(sub: string, throughMs: number): boolean { return (this.authorizations[hash(sub)] ?? -1) > throughMs; }
  private revoked(sub: string, at: number): void {
    const key = hash(sub);
    if ((this.revocations[key] ?? -1) >= at) return;
    const next = { ...this.revocations };
    for (const [k, t] of Object.entries(next)) if (t < this.now() - APPLE_NOTIFICATION_MAX_AGE_MS - 86_400_000) delete next[k];
    if (!next[key] && Object.keys(next).length >= 100_000) throw new Error('APPLE_NOTIFICATION_JOURNAL_FULL');
    next[key] = at;
    this.persist(this.entries, this.authorizations, next); this.revocations = next;
  }
  private persist(entries: Record<string, Entry>, authorizations = this.authorizations, revocations = this.revocations): void {
    if (!this.file) return;
    writeFileSync(this.file + '.tmp', JSON.stringify({ v: 1, entries, authorizations, revocations }), { mode: 0o600 });
    renameSync(this.file + '.tmp', this.file);
  }
  private write(key: string, entry: Entry): void {
    const next = { ...this.entries };
    for (const [k, v] of Object.entries(next)) if (v.done && v.expires < this.now()) delete next[k];
    if (!next[key] && Object.keys(next).length >= 100_000) throw new Error('APPLE_NOTIFICATION_JOURNAL_FULL');
    next[key] = entry;
    this.persist(next);
    this.entries = next;
  }
  async run(event: AppleNotification, plan: () => Omit<Entry, 'digest' | 'expires' | 'done'>,
      apply: (entry: Entry) => Promise<void>): Promise<void> {
    const key = hash(JSON.stringify([event.aud, event.jti]));
    const digest = hash(JSON.stringify([event.aud, event.sub, event.type, event.at]));
    const current = this.entries[key];
    if (current && current.digest !== digest) throw new IdTokenError('JTI_CONFLICT');
    const job = this.jobs.get(key);
    if (job) return job;
    if (current?.done) return;
    const run = async () => {
      const entry = current ?? { ...plan(), digest, expires: event.issued + APPLE_NOTIFICATION_MAX_AGE_MS + 86_400_000, done: false };
      if (!current) this.write(key, entry); // fail closed: no account operation if journaling fails
      if (event.type !== 'ignored') this.revoked(event.sub, event.at); // pre-event ID tokens cannot sign in again
      await apply(entry); // failure remains pending; never mark successful before durable account cleanup
      this.write(key, { ...entry, done: true });
    };
    const promise = run().finally(() => this.jobs.delete(key));
    this.jobs.set(key, promise);
    return promise;
  }
}

export interface AppleNotificationDeps extends Omit<DeleteDeps, 'revokeApple'> {
  audiences: string[]; keys: KeySource; refreshKeys?: KeySource; journal: AppleNotificationJournal;
  pending?: PendingSignIns;
  warn?: (line: string) => void;
}

export async function applyAppleNotification(e: AppleNotification, d: AppleNotificationDeps): Promise<void> {
  const through = e.at + 999; // event_time is seconds; a strictly later second is a newer authorization
  await d.journal.run(e, () => {
    const player = d.accounts.byIdentity('apple', e.sub), row = player ? d.accounts.find(player) : undefined;
    if (e.type === 'ignored' || d.journal.authorizedAfter(e.sub, through) || !player || !row?.apple)
      return { action: 'ignore', player: null, created: null };
    const others = d.accounts.linked(player).filter(p => p !== 'apple');
    return { player, created: row.created_at,
      // Preserve a new farm created after a delayed deletion event, but never leave its old authorization active.
      action: e.type === 'consent-revoked' || row.created_at > through ? 'revoke' : others.length ? 'unlink' : 'delete' };
  }, async entry => {
    if (e.type === 'ignored') return;
    const renewed = d.journal.authorizedAfter(e.sub, through);
    d.pending?.invalidateApple(e.sub, renewed ? through : Infinity);
    if (renewed) return;
    if (entry.action === 'ignore' || !entry.player) return;
    const player = entry.player, row = d.accounts.find(player);
    // An I/O retry must never delete or invalidate a newly authorized/recreated/rebound account.
    if (row && (row.created_at !== entry.created ||
        row.apple && row.apple.sub !== e.sub)) return;
    if (entry.action === 'delete') {
      // Recheck bindings at mutation time; a newly added alternative sign-in must preserve the farm.
      if (row && d.accounts.linked(player).some(p => p !== 'apple')) {
        if (row.apple?.sub === e.sub) d.accounts.invalidateApple(player, e.sub, true);
      } else {
        // Apple initiated deletion: no outbound revoke, no private Apple key needed.
        await deleteAccount({ ...d, revokeApple: undefined }, player);
        await d.voice.drop(player, { requireConfirmed: true });
        return;
      }
    } else if (row?.apple?.sub === e.sub) {
      d.accounts.invalidateApple(player, e.sub, entry.action === 'unlink');
    }
    // For a pending unlink retry the row may no longer have Apple, but this target still needs online cleanup.
    const drop = d.voice.drop(player, { requireConfirmed: true });
    try { d.hub.kick(player); } finally { await drop; }
  });
}

/** Public provider callback, outside /v1/p0: it does not accept shared game keys as authentication. */
export function registerAppleNotifications(app: FastifyInstance, deps: AppleNotificationDeps): void {
  let window = -1;
  const ips = new Map<string, number>();
  app.post('/v1/apple/notifications', { bodyLimit: 8192 }, async (req, reply) => {
    const minute = Math.floor(deps.now() / 60_000);
    if (minute !== window) { window = minute; ips.clear(); }
    if (!ips.has(req.ip) && ips.size >= 10_000) return reply.code(429).send({ ok: false, code: 'rate_limited' });
    const count = (ips.get(req.ip) ?? 0) + 1; ips.set(req.ip, count);
    if (count > 60) return reply.code(429).send({ ok: false, code: 'rate_limited' });
    if (!deps.audiences.length) return reply.code(503).send({ ok: false, code: 'provider_unavailable' });
    if (!record(req.body) || typeof req.body.payload !== 'string') return reply.code(400).send({ ok: false, code: 'schema' });
    let event: AppleNotification;
    try { event = await verifyAppleNotification(req.body.payload, deps); }
    catch (e) {
      if (e instanceof IdTokenError) return reply.code(401).send({ ok: false, code: 'bad_notification' });
      return reply.code(503).send({ ok: false, code: 'provider_unavailable' });
    }
    try { await applyAppleNotification(event, deps); }
    catch (e) {
      if (e instanceof IdTokenError) return reply.code(401).send({ ok: false, code: 'bad_notification' });
      (deps.warn ?? console.warn)(JSON.stringify({ apple_notification: 'incomplete', event: event.type }));
      return reply.code(503).send({ ok: false, code: 'notification_incomplete' });
    }
    return { ok: true };
  });
}
