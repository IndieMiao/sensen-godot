/**
 * accounts.json (SGODOT-488; contract-accounts.md §4, tech-plan §1.2–1.3): who a token is, which Apple / Google account
 * a player is linked to, and the players deleted these 30 days. Beside the save, written whole (.tmp then rename) only
 * when it changes: a player made or claimed, a token issued or revoked, a link, a deletion — never on a plain request.
 * Tokens are kept as their sha256 only. Apple's refresh token (kept for revoking the authorization at deletion) is
 * AES-256-GCM under P0_ACCOUNTS_KEY: the nightly archive of the data volume is plain on the host (后裔 on tech-plan).
 * One process, one thread: a check and the write after it run in one synchronous stretch (the caller keeps every await
 * before it, §1.3).
 */
import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes } from 'node:crypto';
import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';

export type Provider = 'apple' | 'google' | 'email';
/** Every sign-in a player may be linked to, in the order `linked` lists them. */
export const PROVIDERS: readonly Provider[] = ['apple', 'google', 'email'];
/** `refresh` is the token as Apple gave it on the way in and out; on disk it is sealed. */
export interface AppleLink { sub: string; aud: string; refresh?: string }
export interface GoogleLink { sub: string }
/** An email sign-in (contract v1.5): `sub` is the address's emailId — HMAC under P0_ACCOUNTS_KEY — never the address. */
export interface EmailLink { sub: string }
export type AnyLink = AppleLink | GoogleLink | EmailLink;
export interface Linked { apple?: AppleLink; google?: GoogleLink; email?: EmailLink }
export interface AccountRow extends Linked { player: string; created_at: number; claimed_at?: number }
export type TokenKind = 'user' | 'admin';

/** How long a deleted player's id is refused (claim, a legacy read making a save): the transition plus a week (周瑜 ⑤). */
export const DELETED_KEEP_MS = 30 * 86_400_000;
/** Bytes a token has at least (32: 64 hex). */
export const TOKEN_MIN_BYTES = 32;

interface TokenRow { player: string; kind: TokenKind; at: number; expires_at?: number; via?: string /* the code's key it came by */ }
/** A test code (contract v1.4 §4): its player, when made, and a note such as `review-play` (never a person). */
interface CodeRow { player: string; at: number; note: string }
interface FileShape { v: 1; players: Record<string, AccountRow>; tokens: Record<string, TokenRow>; identities: Record<string, string>;
  deleted: Record<string, number>; codes: Record<string, CodeRow> }

/** A token's hash, the hex read as one case (a token is hex: AB and ab are the same bytes; 周瑜 on PR-A). */
/** A code as typed, as kept: Crockford base32 — case, spaces and dashes dropped, I / L read as 1, O as 0. */
export const normalizeCode = (code: string): string =>
  code.toUpperCase().replace(/[\s-]+/g, '').replace(/[IL]/g, '1').replace(/O/g, '0');
export const hashToken = (token: string): string => createHash('sha256').update(token.toLowerCase()).digest('hex');
/** A token as the contract has it: hex, at least TOKEN_MIN_BYTES. */
export const tokenShapeOk = (token: unknown): token is string =>
  typeof token === 'string' && /^[0-9a-f]+$/i.test(token) && token.length >= TOKEN_MIN_BYTES * 2 && token.length <= 256;

export class P0Accounts {
  private d: FileShape = { v: 1, players: {}, tokens: {}, identities: {}, deleted: {}, codes: {} };
  constructor(private file?: string, private key?: Buffer | null, private now: () => number = Date.now) {
    if (file && existsSync(file)) {
      const saved = JSON.parse(readFileSync(file, 'utf8')) as Partial<FileShape>;
      this.d = { v: 1, players: saved.players ?? {}, tokens: saved.tokens ?? {}, identities: saved.identities ?? {}, deleted: saved.deleted ?? {},
        codes: saved.codes ?? {} };
    }
    if (this.prune()) this.flush();
  }

  find(player: string): AccountRow | undefined {
    const r = this.d.players[player];
    return r ? { ...r, ...(r.apple ? { apple: { ...r.apple, refresh: this.open(r.apple.refresh) } } : {}) } : undefined;
  }
  /** The row made on first sight of the player (guest, claim): created_at now. */
  ensure(player: string): AccountRow {
    if (!this.d.players[player]) { this.d.players[player] = { player, created_at: this.now() }; this.flush(); }
    return this.find(player)!;
  }
  markClaimed(player: string): void { this.ensure(player); this.d.players[player].claimed_at = this.now(); this.flush(); }
  clearClaimed(player: string): void { if (this.d.players[player]) { delete this.d.players[player].claimed_at; this.flush(); } }

  /** The player a token stands for, and its kind; an admin token past its day is none. */
  byToken(token: string): { player: string; kind: TokenKind } | undefined {
    const t = this.d.tokens[hashToken(token)];
    if (!t || (t.expires_at !== undefined && t.expires_at <= this.now())) return undefined;
    return { player: t.player, kind: t.kind };
  }
  /** Whether the hash is someone's already (a token is one player's only, contract §1 claim). */
  tokenOwner(token: string): string | undefined { return this.d.tokens[hashToken(token)]?.player; }
  /** `via`: the code it came by (codeKey), so revoking the code revokes exactly the tokens it gave. */
  issue(player: string, token: string, kind: TokenKind = 'user', expiresAt?: number, via?: string): void {
    this.d.tokens[hashToken(token)] = { player, kind, at: this.now(), ...(expiresAt !== undefined ? { expires_at: expiresAt } : {}),
      ...(via ? { via } : {}) };
    this.flush();
  }
  /** Every user token of the player but `keep` (a token in hand, not a hash); admin ones only with `admin`. The hashes revoked. */
  revokeAll(player: string, keep?: string, opts: { admin?: boolean } = {}): string[] {
    const spare = keep ? hashToken(keep) : '';
    const gone = Object.entries(this.d.tokens)
      .filter(([h, t]) => t.player === player && h !== spare && (t.kind === 'user' || opts.admin)).map(([h]) => h);
    for (const h of gone) delete this.d.tokens[h];
    if (gone.length) this.flush();
    return gone;
  }
  /** One token gone (session/logout: this phone only); whether it was there. */
  revoke(token: string): boolean {
    const h = hashToken(token);
    if (!this.d.tokens[h]) return false;
    delete this.d.tokens[h];
    this.flush();
    return true;
  }
  /** The player's user tokens (a claim checks one against them). */
  userTokenCount(player: string): number { return Object.values(this.d.tokens).filter(t => t.player === player && t.kind === 'user').length; }

  /** An Apple notification is second-precision. Do not revoke a session issued in a later second (a reauthorization
   * since the event), including across restart. Uses the existing token timestamps; no file-shape change. */
  userSessionAfter(player: string, throughMs: number): boolean {
    return Object.values(this.d.tokens).some(t => t.player === player && t.kind === 'user' && t.at > throughMs);
  }

  /** Notification-only invalidation: preserve the Apple binding on consent-revoked, or remove only Apple on account
   * deletion with another sign-in still linked. One write, rollback in-memory state on I/O failure; never revoke admin. */
  invalidateApple(player: string, sub: string, throughMs: number, unlink: boolean): boolean {
    const row = this.d.players[player];
    if (!row?.apple || row.apple.sub !== sub || row.created_at > throughMs || this.userSessionAfter(player, throughMs)) return false;
    const before = this.d;
    this.d = structuredClone(before);
    for (const [h, t] of Object.entries(this.d.tokens)) if (t.player === player && t.kind === 'user') delete this.d.tokens[h];
    if (unlink) {
      delete this.d.identities[`apple:${sub}`];
      delete this.d.players[player].apple;
    } else delete this.d.players[player].apple!.refresh;
    try { this.flush(); } catch (e) { this.d = before; throw e; }
    return true;
  }

  byIdentity(provider: Provider, sub: string): string | undefined { return this.d.identities[`${provider}:${sub}`]; }
  link(player: string, provider: Provider, info: AnyLink): void {
    const row = this.d.players[player] ?? (this.d.players[player] = { player, created_at: this.now() });
    const was = row[provider];
    if (was) delete this.d.identities[`${provider}:${was.sub}`];
    this.d.identities[`${provider}:${info.sub}`] = player;
    if (provider === 'apple') { const a = info as AppleLink; row.apple = { sub: a.sub, aud: a.aud, ...(a.refresh ? { refresh: this.seal(a.refresh) } : {}) }; }
    else row[provider] = { sub: info.sub };
    this.flush();
  }
  unlink(player: string, provider: Provider): void {
    const row = this.d.players[player];
    const was = row?.[provider];
    if (!row || !was) return;
    delete this.d.identities[`${provider}:${was.sub}`];
    delete row[provider];
    this.flush();
  }
  /** Whether the account is anyone's to sign in to and no longer an old id's to take (奕星 on v3.2 ⑥): it was claimed,
   * or is linked to an Apple / Google account, or has a test code, or holds a user token. A farm made by a sign-in and
   * signed out is all of this but the last — its id alone must not open it again, nor offer it to claim. */
  isClaimed(player: string): boolean {
    const r = this.d.players[player];
    return !!r && (r.claimed_at !== undefined || PROVIDERS.some(p => !!r[p]))
      || Object.values(this.d.codes).some(c => c.player === player)
      || this.userTokenCount(player) > 0;
  }
  linked(player: string): Provider[] { const r = this.d.players[player]; return r ? PROVIDERS.filter(p => r[p]) : []; }

  markDeleted(player: string, at: number): void { this.d.deleted[player] = at; this.flush(); }
  isDeleted(player: string): boolean { const at = this.d.deleted[player]; return at !== undefined && this.now() - at < DELETED_KEEP_MS; }
  /** Retained deletion records for admin recovery (SGODOT-484), even after the account row is gone. Copies only;
   * the same 30-day limit as isDeleted, without pruning or writing. Not a list of all unfinished deletions. */
  deletedPlayers(): { player: string; at: number }[] {
    const now = this.now();
    return Object.entries(this.d.deleted).filter(([, at]) => now - at < DELETED_KEEP_MS).map(([player, at]) => ({ player, at }));
  }
  /** This player's row, links and every token (accounts.json only; the save is P0Store.remove). */
  remove(player: string): void {
    for (const [k, c] of Object.entries(this.d.codes)) if (c.player === player) delete this.d.codes[k];   // its test code too
    const row = this.d.players[player];
    for (const p of PROVIDERS) if (row?.[p]) delete this.d.identities[`${p}:${row[p]!.sub}`];
    delete this.d.players[player];
    for (const [h, t] of Object.entries(this.d.tokens)) if (t.player === player) delete this.d.tokens[h];
    this.flush();
  }
  /** The admin tokens still in force: the player, its id's tail, the token's own (its hash's last 6, which tells two of
   * one player apart — two test devices) and the end. */
  adminTokens(): { player: string; tail: string; token_tail: string; expires_at: number }[] {
    return Object.entries(this.d.tokens).filter(([, t]) => t.kind === 'admin' && (t.expires_at ?? Infinity) > this.now())
      .map(([h, t]) => ({ player: t.player, tail: t.player.slice(-4), token_tail: h.slice(-6), expires_at: t.expires_at ?? 0 }));
  }
  players(): string[] { return Object.keys(this.d.players); }

  // ---------------------------------------------------------------- test codes (contract v1.4 §4)
  /** Whether codes can be kept: they are keyed by HMAC under P0_ACCOUNTS_KEY (a backup leaked cannot be tried offline
   * against a plain sha256), so without the key the code routes stay off. */
  codesOn(): boolean { return !!this.key; }
  /** A code's key: HMAC-SHA256 under P0_ACCOUNTS_KEY of the code as typed once normalized (normalizeCode). */
  codeKey(code: string): string {
    if (!this.key) throw new Error('P0Accounts: codes need P0_ACCOUNTS_KEY');
    return createHmac('sha256', this.key).update(normalizeCode(code)).digest('hex');
  }
  /** An email address's identity (contract v1.5): HMAC-SHA256 under P0_ACCOUNTS_KEY of the address normalized (trim,
   * lower case; Gmail's dots and + kept) — the only form it is kept in. Its own prefix keeps it apart from codeKey. */
  emailId(email: string): string {
    if (!this.key) throw new Error('P0Accounts: email sign-in needs P0_ACCOUNTS_KEY');
    return createHmac('sha256', this.key).update('p0-email:' + email.trim().toLowerCase()).digest('hex');
  }
  /** One code per player: a new one replaces the old (whose tokens go with it). The key of the new one. */
  setCode(player: string, code: string, note: string): string {
    this.revokeCode(player);
    const k = this.codeKey(code);
    this.d.codes[k] = { player, at: this.now(), note: note.slice(0, 64) };
    this.flush();
    return k;
  }
  /** The player a code stands for, and its key; undefined for none (or with no key). */
  codeOwner(code: string): { player: string; key: string } | undefined {
    if (!this.key) return undefined;
    const k = this.codeKey(code), c = this.d.codes[k];
    return c ? { player: c.player, key: k } : undefined;
  }
  /** The player's code withdrawn, and exactly the tokens it gave (an Apple / Google sign-in of that player stays). The
   * number of tokens revoked; -1 when there was no code. */
  revokeCode(player: string): number {
    const keys = Object.entries(this.d.codes).filter(([, c]) => c.player === player).map(([k]) => k);
    if (!keys.length) return -1;
    for (const k of keys) delete this.d.codes[k];
    const gone = Object.entries(this.d.tokens).filter(([, t]) => t.via && keys.includes(t.via)).map(([h]) => h);
    for (const h of gone) delete this.d.tokens[h];
    this.flush();
    return gone.length;
  }
  /** The player's code's note and when it was made (admin listing); never the code. */
  codeOf(player: string): { note: string; at: number } | undefined {
    const c = Object.values(this.d.codes).find(x => x.player === player);
    return c ? { note: c.note, at: c.at } : undefined;
  }

  /** The file as it is now, for the hourly snapshot beside the save's (§1.3). */
  path(): string | undefined { return this.file; }

  /** Deleted ids past DELETED_KEEP_MS and admin tokens past their day go. Whether anything did. */
  private prune(): boolean {
    let changed = false;
    for (const [p, at] of Object.entries(this.d.deleted)) if (this.now() - at >= DELETED_KEEP_MS) { delete this.d.deleted[p]; changed = true; }
    for (const [h, t] of Object.entries(this.d.tokens)) if (t.expires_at !== undefined && t.expires_at <= this.now()) { delete this.d.tokens[h]; changed = true; }
    return changed;
  }
  private seal(plain: string): string | undefined {
    if (!this.key) return undefined;   // no key, nothing kept: revoking at deletion is then skipped (logged by the caller)
    const iv = randomBytes(12), c = createCipheriv('aes-256-gcm', this.key, iv);
    const body = Buffer.concat([c.update(plain, 'utf8'), c.final()]);
    return [iv, c.getAuthTag(), body].map(b => b.toString('base64')).join('.');
  }
  private open(sealed?: string): string | undefined {
    if (!sealed || !this.key) return undefined;
    try {
      const [iv, tag, body] = sealed.split('.').map(s => Buffer.from(s, 'base64'));
      const d = createDecipheriv('aes-256-gcm', this.key, iv);
      d.setAuthTag(tag);
      return Buffer.concat([d.update(body), d.final()]).toString('utf8');
    } catch { return undefined; }
  }
  private flush(): void {
    if (!this.file) return;
    const tmp = `${this.file}.tmp`;
    writeFileSync(tmp, JSON.stringify(this.d), { mode: 0o600 });   // tokens' hashes and sealed refresh tokens: the server's only (周瑜 on PR-A)
    renameSync(tmp, this.file);
  }
}
