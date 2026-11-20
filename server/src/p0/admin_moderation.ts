/** SGODOT-484: called only from registerP0Admin's authenticated loopback app. A report never applies a sanction. */
import type { FastifyInstance } from 'fastify';
import type { P0Store } from './store.js';
import { supportCode } from './support.js';
import { nextNameReset } from './accounts/notices.js';

export interface ModerationActions {
  dropVoice(player: string): Promise<void>;
  kick(player: string): void;
  renamed(player: string): void;
}
const PLAYER = /^[A-Za-z0-9_-]{8,64}$/;
const SUPPORT = /^[0-9A-HJKMNP-TV-Z]{5}-[0-9A-HJKMNP-TV-Z]{5}$/;
const REPORT = /^R-\d{8}-[0-9A-HJKMNP-TV-Z]{8}$/;
const WEEK = 7 * 86_400_000;

/** No first-match fallback: a colliding support code must never select an arbitrary player. */
export function moderationPlayers(store: P0Store, code: string, encode = supportCode): string[] {
  return store.all().filter(s => encode(s.player) === code).map(s => s.player);
}

export function registerModerationRoutes(app: FastifyInstance, deps: {
  store: P0Store; actions: ModerationActions; now(): number; log(line: string): void;
}): void {
  app.post('/admin/moderate', async (req, reply) => {
    const body = req.body;
    if (!body || typeof body !== 'object' || Array.isArray(body)) return reply.code(400).send({ ok: false, code: 'schema' });
    const b = body as Record<string, unknown>, now = deps.now();
    if (Object.keys(b).some(k => !['player', 'support_code', 'action', 'until', 'report'].includes(k))
      || (Object.hasOwn(b, 'player') === Object.hasOwn(b, 'support_code'))
      || typeof b.action !== 'string' || !['reset_name', 'voice', 'suspended'].includes(b.action)
      || (b.report !== undefined && (typeof b.report !== 'string' || !REPORT.test(b.report))))
      return reply.code(400).send({ ok: false, code: 'schema' });
    const action = b.action as 'reset_name' | 'voice' | 'suspended';
    if (action === 'reset_name' ? b.until !== undefined
      : !Object.hasOwn(b, 'until') || !(b.until === null || (typeof b.until === 'number' && Number.isSafeInteger(b.until)
        && b.until > now && b.until <= 8_640_000_000_000_000)))
      return reply.code(400).send({ ok: false, code: 'schema' });

    let player: string;
    if (Object.hasOwn(b, 'player')) {
      if (typeof b.player !== 'string' || !PLAYER.test(b.player)) return reply.code(400).send({ ok: false, code: 'schema' });
      player = b.player;
    } else {
      if (typeof b.support_code !== 'string' || !SUPPORT.test(b.support_code)) return reply.code(400).send({ ok: false, code: 'schema' });
      const matches = moderationPlayers(deps.store, b.support_code);
      if (matches.length > 1) return reply.code(409).send({ ok: false, code: 'ambiguous_support_code' });
      if (!matches.length) return reply.code(404).send({ ok: false, code: 'unknown_player' });
      player = matches[0];
    }
    const saved = deps.store.peek(player);
    if (!saved) return reply.code(404).send({ ok: false, code: 'unknown_player' });
    let nameReset: ReturnType<typeof nextNameReset> | undefined;
    if (action === 'reset_name') {
      try { nameReset = nextNameReset(saved); }
      catch { return reply.code(500).send({ ok: false, code: 'notice_failed' }); }
    }
    const next = structuredClone(saved);
    next.sanctions ??= {};
    if (action === 'reset_name') {
      next.account_notices = { ...next.account_notices, name_reset: nameReset! };
      next.profile ??= {};
      delete next.profile.name;
      next.profile.name_locked_until = now + WEEK;
      next.sanctions.name_reset_at = now;
    } else {
      next.sanctions[action] = { until: b.until as number | null, at: now,
        ...(typeof b.report === 'string' ? { report: b.report } : {}) };
    }
    next.seq++;
    const code = supportCode(player);
    try { deps.store.put(next); }
    catch {
      deps.log(JSON.stringify({ admin: 'moderation_write_failed', support_code: code, action, at: now }));
      return reply.code(500).send({ ok: false, code: 'moderation_write_failed' });
    }
    // Start lease release before kick's departed hook; do not lose the awaited operation to a fire-and-forget drop.
    let incomplete = false;
    if (action === 'reset_name') {
      try { deps.actions.renamed(player); } catch { incomplete = true; }
    } else {
      let dropping: Promise<void> | undefined;
      try { dropping = deps.actions.dropVoice(player); } catch { incomplete = true; }
      if (action === 'suspended') { try { deps.actions.kick(player); } catch { incomplete = true; } }
      try { await dropping; } catch { incomplete = true; }
    }
    deps.log(JSON.stringify({ admin: 'moderate', support_code: code, action, at: now,
      ...(action === 'reset_name' ? { until: now + WEEK } : { until: b.until }),
      ...(b.report ? { report: b.report } : {}), incomplete }));
    return incomplete ? reply.code(500).send({ ok: false, code: 'moderation_incomplete', applied: true })
      : { ok: true, support_code: code, action };
  });
}
