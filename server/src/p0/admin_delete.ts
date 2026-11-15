/** SGODOT-484 / contract v1.6.8. Registered only behind the existing loopback admin authentication. */
import type { FastifyInstance } from 'fastify';
import { deleteAccount, previewAccountDeletion, type DeleteDeps } from './accounts/delete.js';
import { supportCode } from './support.js';

const PLAYER = /^[A-Za-z0-9_-]{8,64}$/, SUPPORT = /^[0-9A-HJKMNP-TV-Z]{5}-[0-9A-HJKMNP-TV-Z]{5}$/;
type Target = { player: string } | { status: number; code: string };

/** Include tombstones and accounts-only remnants, not just existing farms. No arbitrary first match on collision. */
export function deletionCandidates(deps: Pick<DeleteDeps, 'store' | 'accounts'>): string[] {
  return [...new Set([...deps.store.all().map(s => s.player), ...deps.accounts.players(),
    ...deps.accounts.deletedPlayers().map(p => p.player)])];
}

function targetOf(deps: DeleteDeps, input: unknown): Target {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return { status: 400, code: 'schema' };
  const b = input as Record<string, unknown>, keys = Object.keys(b);
  if (keys.length !== 1 || !['player', 'support_code'].includes(keys[0])) return { status: 400, code: 'schema' };
  const candidates = deletionCandidates(deps);
  if ('player' in b) {
    if (typeof b.player !== 'string' || !PLAYER.test(b.player)) return { status: 400, code: 'schema' };
    return candidates.includes(b.player) ? { player: b.player } : { status: 404, code: 'unknown_player' };
  }
  if (typeof b.support_code !== 'string' || !SUPPORT.test(b.support_code)) return { status: 400, code: 'schema' };
  const matches = candidates.filter(p => supportCode(p) === b.support_code);
  return matches.length > 1 ? { status: 409, code: 'ambiguous_support_code' }
    : matches.length === 1 ? { player: matches[0] } : { status: 404, code: 'unknown_player' };
}

export function registerAdminDelete(app: FastifyInstance, deps: DeleteDeps, log: (line: string) => void): void {
  app.get('/admin/delete/incomplete', async () => {
    const accounts = new Set(deps.accounts.players());
    return { ok: true, players: deps.accounts.deletedPlayers().flatMap(({ player, at }) => {
    const account_remaining = accounts.has(player), save_remaining = !!deps.store.peek(player);
    return account_remaining || save_remaining ? [{ player, support_code: supportCode(player), deleted_at: at,
      account_remaining, save_remaining }] : [];
    }) };
  });

  app.get('/admin/delete/preview', async (req, reply) => {
    const target = targetOf(deps, req.query);
    if ('code' in target) return reply.code(target.status).send({ ok: false, code: target.code });
    return { ok: true, ...previewAccountDeletion(deps, target.player) };
  });

  app.post('/admin/delete', async (req, reply) => {
    const target = targetOf(deps, req.body);
    if ('code' in target) return reply.code(target.status).send({ ok: false, code: target.code });
    // Preview is a read-only check, never store.get/find. The operator can request the same preview before confirming.
    const preview = previewAccountDeletion(deps, target.player);
    try {
      await deleteAccount(deps, target.player);
      // Retried deletion must not forget a still-unconfirmed media lease merely because its active lease is gone.
      await deps.voice.drop(target.player, { requireConfirmed: true });
    } catch (e) {
      const incomplete = e instanceof Error && ['ACCOUNT_DELETE_INCOMPLETE', 'VOICE_RELEASE_UNCONFIRMED'].includes(e.message);
      log(JSON.stringify({ admin: incomplete ? 'delete_incomplete' : 'delete_failed', support_code: preview.support_code, at: deps.now() }));
      return incomplete ? { ok: true, incomplete: true } : reply.code(500).send({ ok: false, code: 'delete_failed' });
    }
    log(JSON.stringify({ admin: 'delete', support_code: preview.support_code, at: deps.now() }));
    return { ok: true };
  });
}
