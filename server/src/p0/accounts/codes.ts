/**
 * Test codes (contract v1.4 §4, must sign in; 周瑜): a sign-in without Apple or Google, for the stores' reviewers and the
 * testers whose phones have no Google — a code an admin hands out (/admin/code, admin.ts), typed on the sign-in page.
 * A code stands for one account, never expires and is not spent, until an admin withdraws it (Play: a reviewer's login
 * must work any time, more than once, from anywhere). A code's sign-in revokes no other device's token: a reviewer may
 * use one code on several phones. The codes are kept as HMAC under P0_ACCOUNTS_KEY (后裔's store), so with no key there
 * are no code routes at all. Nothing here logs a code or an address.
 */
import { randomInt } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { P0Store } from '../store.js';
import type { P0State } from '../state.js';
import { tokenShapeOk, type P0Accounts } from './store.js';

/** Crockford base32 without I, L, O and U: none to mistake for 1 or 0 when copied by hand. */
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
/** 12 characters, 60 bits: at five tries a minute, ten thousand addresses together would take millions of years. */
export const CODE_LENGTH = 12;
/** Attempts per address a minute (contract §4: no total bucket — someone could fill it and keep a reviewer out). */
export const CODE_PER_MINUTE = 5;

/** A new code as it is shown and typed: XXXX-XXXX-XXXX. */
export function newCode(): string {
  let s = '';
  for (let i = 0; i < CODE_LENGTH; i++) s += ALPHABET[randomInt(ALPHABET.length)];
  return s.match(/.{4}/g)!.join('-');
}

/** The notes a code may carry: an id such as review-play or cn-tester-03, never a person's name, mail or number. */
export const noteOk = (note: unknown): note is string => typeof note === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$/.test(note);

export interface CodeRouteDeps {
  store: P0Store; accounts: P0Accounts; now: () => number;
  warn?: (line: string) => void;
}

/** Contract v1.6.11: pre-created saves already exist, but may still need NAME and home selection.
 * Skip has no persisted completion marker. A committed Save (including timestamp 0) resumes home selection;
 * a completed home never goes back to NAME, even with a default or moderator-reset name. */
function codeNextStep(state: P0State): 'name' | 'continue' {
  // A missing optional profile (including historical null) is not a malformed parent object.
  // Validate parents before reading fields: arrays and primitives otherwise look like absent progress.
  const object = (value: unknown): boolean => value !== null && typeof value === 'object' && !Array.isArray(value);
  if (!object(state.travel) || (state.profile != null && !object(state.profile)))
    throw new Error('Invalid test-code account state');
  const pending = state.travel?.pending, namedAt = state.profile?.name_set_at;
  if (!state.travel || (pending !== undefined && typeof pending !== 'boolean')
    || (namedAt != null && (typeof namedAt !== 'number' || !Number.isSafeInteger(namedAt) || namedAt < 0)))
    throw new Error('Invalid test-code account state'); // Fixed message; never include a code, token or save.
  return pending === true && namedAt == null ? 'name' : 'continue';
}

/**
 * POST /v1/p0/session/code {code, token}, no identity: the code's account signed in on this phone with the client's
 * token — `{ok: true, player, next_step}` — its other devices kept. A code unknown, withdrawn, or of an account gone: 401
 * bad_code. Five tries a minute from an address (429 rate_limited); a tenth refused in a minute is logged, without the
 * address. The account's first time in has no consent: the client takes it through AGE as an old account (old_consent).
 * Not registered without P0_ACCOUNTS_KEY.
 */
export function registerCodeRoutes(app: FastifyInstance, deps: CodeRouteDeps): void {
  const { store, accounts } = deps;
  if (!accounts.codesOn()) return;
  const warn = deps.warn ?? ((line: string) => console.warn(line));
  const tries = new Map<string, number>();
  let minute = -1, refused = 0;

  app.post('/v1/p0/session/code', async (req, reply) => {
    const b = (req.body && typeof req.body === 'object' ? req.body : {}) as { code?: unknown; token?: unknown };
    const now = deps.now(), m = Math.floor(now / 60_000);
    if (m !== minute) { tries.clear(); minute = m; refused = 0; }
    const n = (tries.get(req.ip) ?? 0) + 1;
    tries.set(req.ip, n);
    if (n > CODE_PER_MINUTE) {
      if (++refused === 10) warn(JSON.stringify({ warn: 'code_tries_refused', minute: new Date(m * 60_000).toISOString() }));
      return reply.code(429).send({ ok: false, code: 'rate_limited' });
    }
    if (!tokenShapeOk(b.token)) return reply.code(400).send({ ok: false, code: typeof b.token === 'string' ? 'token_too_short' : 'schema' });
    const token = String(b.token).toLowerCase();
    const owner = typeof b.code === 'string' && b.code.length <= 32 ? accounts.codeOwner(b.code) : undefined;
    const state = owner && !accounts.isDeleted(owner.player) ? store.peek(owner.player) : undefined;
    if (!owner || !state) return reply.code(401).send({ ok: false, code: 'bad_code' });
    const held = accounts.tokenOwner(token);
    if (held && held !== owner.player) return reply.code(400).send({ ok: false, code: 'schema' });   // a token is one player's only
    const next_step = codeNextStep(state); // Validate the current authoritative facts before issuing a token.
    if (!held) accounts.issue(owner.player, token, 'user', undefined, owner.key);   // no signIn: its other devices stay
    return { ok: true, player: owner.player, next_step };
  });
}
