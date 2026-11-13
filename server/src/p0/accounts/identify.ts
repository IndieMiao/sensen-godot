/**
 * Who a request is (SGODOT-488; contract-accounts.md §0–§1): every route, the voice routes, the room's WebSocket and the
 * request limits ask here, one answer for all four (tech-plan §2.1).
 * - A bearer token: its player. `x-p0-player` beside it (new clients send both until a rollback is ruled out) is only
 *   compared — the token wins, a mismatch is logged.
 * - A token not (or no longer) known: `session_replaced` when that player has tokens of others (signed in on another
 *   phone), `account_deleted` when the id is a deleted one, else `unauthenticated`.
 * - `x-p0-player` alone: a deleted one is refused, P0_LEGACY_ID or not. P0_LEGACY_ID takes any other as it is
 *   (devserver, shots, tests). Otherwise a player who has claimed is sent to update (426 update_required: an old build on
 *   a claimed account), and anyone else is taken as before (the transition: old builds keep playing until the forced update).
 */
import type { P0Accounts } from './store.js';

const PLAYER_RE = /^[A-Za-z0-9_-]{8,64}$/;

export type Who = { player: string; via: 'token' | 'legacy' };
export type Refusal = { status: number; body: { ok: false; code: string; url?: string } };
export interface IdentifyDeps {
  accounts: P0Accounts;
  legacyId: boolean;
  /** The store's download link for update_required (the gate's), when there is one. */
  updateUrl?: () => string | undefined;
  warn?: (line: string) => void;
}

export const isRefusal = (w: Who | Refusal): w is Refusal => 'status' in w;
const refuse = (status: number, code: string, extra: Record<string, string> = {}): Refusal => ({ status, body: { ok: false, code, ...extra } });

/** The bearer token in `authorization`, or '' (not one, or not shaped like one). */
export function bearerOf(headers: Record<string, unknown>): string {
  const m = /^Bearer\s+([0-9a-fA-F]{64,256})$/.exec(String(headers.authorization ?? ''));
  return m ? m[1].toLowerCase() : '';
}

export function identify(headers: Record<string, unknown>, deps: IdentifyDeps): Who | Refusal {
  const id = String(headers['x-p0-player'] ?? '');
  const legacy = PLAYER_RE.test(id) ? id : '';
  const token = bearerOf(headers);
  if (token) {
    const t = deps.accounts.byToken(token);
    if (t) {
      if (legacy && legacy !== t.player) (deps.warn ?? console.warn)(JSON.stringify({ warn: 'player_header_mismatch', token_player: t.player.slice(-4), header: legacy.slice(-4) }));
      return { player: t.player, via: 'token' };
    }
    if (legacy && deps.accounts.isDeleted(legacy)) return refuse(401, 'account_deleted');
    if (legacy && deps.accounts.userTokenCount(legacy) > 0) return refuse(401, 'session_replaced');
    return refuse(401, 'unauthenticated');
  }
  if (!legacy) return refuse(400, 'bad_player');
  // a deleted id first, P0_LEGACY_ID or not: a read by it would make its save anew (周瑜 / 奕星 on PR-A 27e54099e)
  if (deps.accounts.isDeleted(legacy)) return refuse(401, 'account_deleted');
  if (deps.legacyId) return { player: legacy, via: 'legacy' };
  if (deps.accounts.isClaimed(legacy)) {
    const url = deps.updateUrl?.();
    return refuse(426, 'update_required', url ? { url } : {});
  }
  return { player: legacy, via: 'legacy' };
}
