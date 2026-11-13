/**
 * Sign-in's shared parts (SGODOT-489 PR-B; contract-accounts.md §2, §4): the pending sign-in kept while the player
 * names a new farm or picks a conflict's way, the conflicting farm's line, and a sign-in itself — the account's other
 * tokens revoked and its open room socket closed (one phone at a time). session/apple (后裔) and session/google,
 * link/google (周瑜, accounts/google.ts) build on these; none of them keeps its own copy.
 */
import { randomBytes } from 'node:crypto';
import type { P0Store } from '../store.js';
import type { AppleLink, GoogleLink, P0Accounts, Provider } from './store.js';

/** A pending sign-in lasts this long (tech-plan §2.1: Apple's code is spent once and its refresh token in hand). */
export const PENDING_MS = 10 * 60_000;

export interface PendingInfo { provider: Provider; link: AppleLink | GoogleLink; at: number }

/**
 * Pending sign-ins, in memory only: a restart forgets them and the client asks to sign in again (pending_expired). Each
 * is taken once. One past its time is dropped, and handed to `expired` (an Apple one's authorization is revoked then:
 * no Apple ID left holding an authorization for a farm that was never made — 后裔, tech-plan §2.1).
 */
export class PendingSignIns {
  private by = new Map<string, PendingInfo>();
  constructor(private now: () => number = Date.now, private expired?: (info: PendingInfo) => void) {}
  create(provider: Provider, link: AppleLink | GoogleLink): string {
    this.sweep();
    const id = randomBytes(32).toString('hex');
    this.by.set(id, { provider, link, at: this.now() });
    return id;
  }
  /** The pending sign-in, once: a second take, an unknown id or one past PENDING_MS is undefined. */
  take(id: unknown): PendingInfo | undefined {
    this.sweep();
    if (typeof id !== 'string') return undefined;
    const p = this.by.get(id);
    this.by.delete(id);
    return p;
  }
  /** Those past their time go (and to `expired`); called on each create / take, and by a timer in p0_server. */
  sweep(): void {
    for (const [id, p] of this.by) if (this.now() - p.at >= PENDING_MS) { this.by.delete(id); this.expired?.(p); }
  }
  size(): number { return this.by.size; }
}

/** The conflict card's line (q(306): `Home Lv%d · Last played %s`): the other farm's name, home level and last play. */
export function conflictFarm(store: P0Store, player: string, now: number): { name: string | null; home_level: number; last_played_at: number } {
  const s = store.find(player, now);
  return { name: s?.profile?.name ?? null, home_level: s?.homestead.level ?? 1, last_played_at: s?.presence.last_at ?? 0 };
}

export interface SignInDeps { accounts: P0Accounts; kick?: (player: string) => void }

/**
 * A sign-in to `player` with the client's new token (contract §2): every other user token of the account revoked (the
 * other phone's next request is session_replaced; a test device's admin token stays, §2.5), its open room socket closed
 * (4001), the token issued. The answer's body.
 */
export function signIn(deps: SignInDeps, player: string, token: string): { ok: true; player: string; linked: Provider[] } {
  deps.accounts.revokeAll(player, token);
  deps.kick?.(player);
  deps.accounts.issue(player, token);
  return { ok: true, player, linked: deps.accounts.linked(player) };
}
