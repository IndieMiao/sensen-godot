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
  /** The pending sign-in, left in place (a request checked before it spends it); undefined as take would be. */
  peek(id: unknown): PendingInfo | undefined {
    this.sweep();
    return typeof id === 'string' ? this.by.get(id) : undefined;
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

/**
 * The farm an Apple / Google account is linked to, if that farm is still there: not deleted and with its save. A link
 * left on a farm that is gone (its save lost, a deletion half done) is dropped here, as found — no conflict card for a
 * farm that does not exist, and the account free to link again (奕星 on PR-A, tech-plan §2.4: checked at link time, no
 * reconciling pass over accounts.json at start).
 */
export function liveOwner(store: P0Store, accounts: P0Accounts, provider: Provider, sub: string, now: number): string | undefined {
  const player = accounts.byIdentity(provider, sub);
  if (!player) return undefined;
  if (!accounts.isDeleted(player) && store.find(player, now)) return player;
  accounts.unlink(player, provider);
  return undefined;
}

/** The conflict card's line (q(306): `Home Lv%d · Last played %s`): the other farm's name, home level and last play. */
export function conflictFarm(store: P0Store, player: string, now: number): { name: string | null; home_level: number; last_played_at: number } {
  const s = store.find(player, now);
  return { name: s?.profile?.name ?? null, home_level: s?.homestead.level ?? 1, last_played_at: s?.presence.last_at ?? 0 };
}

/**
 * What a pending sign-in left unused does at its end (PendingSignIns' `expired`): an Apple one's authorization is
 * withdrawn — unless that Apple ID is linked to a farm. Withdrawing a refresh token withdraws the app's whole
 * authorization for that Apple ID, so a sign-in refused with has_farm (claim's conflict, guest's race) and then left
 * would otherwise sign its own farm out of Apple for good (周瑜 on #1033).
 */
export function expiredSignIn(accounts: Pick<P0Accounts, 'byIdentity'>, revoke: ((aud: string, refresh: string) => Promise<void>) | null,
    warn: (line: string) => void = l => console.warn(l)): (info: PendingInfo) => void {
  return info => {
    if (info.provider !== 'apple' || !revoke) return;
    const link = info.link as AppleLink;
    if (!link.refresh || !link.aud || accounts.byIdentity('apple', link.sub)) return;
    revoke(link.aud, link.refresh).catch(e => warn(JSON.stringify({ apple: 'revoke_failed', error: e instanceof Error ? e.message : typeof e })));
  };
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
