/**
 * accounts.json (SGODOT-488; contract-accounts.md §4, tech-plan §1.2–1.3): who a token is, which Apple / Google account
 * a player is linked to, and the players deleted these 30 days. Beside the save, written whole (.tmp then rename) only
 * when it changes: a player made or claimed, a token issued or revoked, a link, a deletion.
 * SKELETON (11-13): the interface the others build on; the bodies come in PR-A A1 (11-15).
 */
export type Provider = 'apple' | 'google';
export interface AppleLink { sub: string; aud: string; refresh?: string /* AES-GCM, P0_ACCOUNTS_KEY */ }
export interface GoogleLink { sub: string }
export interface Linked { apple?: AppleLink; google?: GoogleLink }
export interface AccountRow extends Linked { player: string; created_at: number; claimed_at?: number }
export type TokenKind = 'user' | 'admin';

const TODO = (what: string): never => { throw new Error(`P0Accounts.${what}: not yet (PR-A A1)`); };

export class P0Accounts {
  constructor(private file?: string, private key?: Buffer | null) {}
  find(player: string): AccountRow | undefined { return TODO(`find ${player}`); }
  /** The player a token stands for (its sha256 is what is kept), and whether an admin token. */
  byToken(token: string): { player: string; kind: TokenKind } | undefined { return TODO(`byToken ${token.length}`); }
  issue(player: string, token: string, kind: TokenKind = 'user', expiresAt?: number): void { TODO(`issue ${player} ${kind} ${expiresAt}`); }
  /** Every token of the player but `keep`; the hashes revoked. */
  revokeAll(player: string, keep?: string): string[] { return TODO(`revokeAll ${player} ${keep}`); }
  byIdentity(provider: Provider, sub: string): string | undefined { return TODO(`byIdentity ${provider} ${sub}`); }
  link(player: string, provider: Provider, info: AppleLink | GoogleLink): void { TODO(`link ${player} ${provider} ${info.sub}`); }
  unlink(player: string, provider: Provider): void { TODO(`unlink ${player} ${provider}`); }
  markDeleted(player: string, at: number): void { TODO(`markDeleted ${player} ${at}`); }
  isDeleted(player: string): boolean { return TODO(`isDeleted ${player}`); }
  /** This player's row, links and tokens (accounts.json only; the save is P0Store.remove). */
  remove(player: string): void { TODO(`remove ${player}`); }
  adminTokens(): { player: string; tail: string; expires_at: number }[] { return TODO('adminTokens'); }
}
