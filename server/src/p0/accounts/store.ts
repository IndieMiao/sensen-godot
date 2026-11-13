/**
 * accounts.json (SGODOT-488; contract-accounts.md §4, tech-plan §1.2–1.3): who a token is, which Apple / Google account
 * a player is linked to, and the players deleted these 30 days. Beside the save, written whole (.tmp then rename) only
 * when it changes: a player made or claimed, a token issued or revoked, a link, a deletion — never on a plain request.
 * Tokens are kept as their sha256 only. Apple's refresh token (kept for revoking the authorization at deletion) is
 * AES-256-GCM under P0_ACCOUNTS_KEY: the nightly archive of the data volume is plain on the host (后裔 on tech-plan).
 * One process, one thread: a check and the write after it run in one synchronous stretch (the caller keeps every await
 * before it, §1.3).
 */
import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';

export type Provider = 'apple' | 'google';
/** `refresh` is the token as Apple gave it on the way in and out; on disk it is sealed. */
export interface AppleLink { sub: string; aud: string; refresh?: string }
export interface GoogleLink { sub: string }
export interface Linked { apple?: AppleLink; google?: GoogleLink }
export interface AccountRow extends Linked { player: string; created_at: number; claimed_at?: number }
export type TokenKind = 'user' | 'admin';

/** How long a deleted player's id is refused (claim, a legacy read making a save): the transition plus a week (周瑜 ⑤). */
export const DELETED_KEEP_MS = 30 * 86_400_000;
/** Bytes a token has at least (32: 64 hex). */
export const TOKEN_MIN_BYTES = 32;

interface TokenRow { player: string; kind: TokenKind; at: number; expires_at?: number }
interface FileShape { v: 1; players: Record<string, AccountRow>; tokens: Record<string, TokenRow>; identities: Record<string, string>;
  deleted: Record<string, number> }

export const hashToken = (token: string): string => createHash('sha256').update(token).digest('hex');
/** A token as the contract has it: hex, at least TOKEN_MIN_BYTES. */
export const tokenShapeOk = (token: unknown): token is string =>
  typeof token === 'string' && /^[0-9a-f]+$/i.test(token) && token.length >= TOKEN_MIN_BYTES * 2 && token.length <= 256;

export class P0Accounts {
  private d: FileShape = { v: 1, players: {}, tokens: {}, identities: {}, deleted: {} };
  constructor(private file?: string, private key?: Buffer | null, private now: () => number = Date.now) {
    if (file && existsSync(file)) {
      const saved = JSON.parse(readFileSync(file, 'utf8')) as Partial<FileShape>;
      this.d = { v: 1, players: saved.players ?? {}, tokens: saved.tokens ?? {}, identities: saved.identities ?? {}, deleted: saved.deleted ?? {} };
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
  issue(player: string, token: string, kind: TokenKind = 'user', expiresAt?: number): void {
    this.d.tokens[hashToken(token)] = { player, kind, at: this.now(), ...(expiresAt !== undefined ? { expires_at: expiresAt } : {}) };
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
  /** The player's user tokens (a claim checks one against them). */
  userTokenCount(player: string): number { return Object.values(this.d.tokens).filter(t => t.player === player && t.kind === 'user').length; }

  byIdentity(provider: Provider, sub: string): string | undefined { return this.d.identities[`${provider}:${sub}`]; }
  link(player: string, provider: Provider, info: AppleLink | GoogleLink): void {
    const row = this.d.players[player] ?? (this.d.players[player] = { player, created_at: this.now() });
    const was = row[provider];
    if (was) delete this.d.identities[`${provider}:${was.sub}`];
    this.d.identities[`${provider}:${info.sub}`] = player;
    if (provider === 'apple') { const a = info as AppleLink; row.apple = { sub: a.sub, aud: a.aud, ...(a.refresh ? { refresh: this.seal(a.refresh) } : {}) }; }
    else row.google = { sub: info.sub };
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
  linked(player: string): Provider[] { const r = this.d.players[player]; return r ? (['apple', 'google'] as const).filter(p => r[p]) : []; }

  markDeleted(player: string, at: number): void { this.d.deleted[player] = at; this.flush(); }
  isDeleted(player: string): boolean { const at = this.d.deleted[player]; return at !== undefined && this.now() - at < DELETED_KEEP_MS; }
  /** This player's row, links and every token (accounts.json only; the save is P0Store.remove). */
  remove(player: string): void {
    const row = this.d.players[player];
    for (const p of ['apple', 'google'] as const) if (row?.[p]) delete this.d.identities[`${p}:${row[p]!.sub}`];
    delete this.d.players[player];
    for (const [h, t] of Object.entries(this.d.tokens)) if (t.player === player) delete this.d.tokens[h];
    this.flush();
  }
  adminTokens(): { player: string; tail: string; expires_at: number }[] {
    return Object.values(this.d.tokens).filter(t => t.kind === 'admin' && (t.expires_at ?? Infinity) > this.now())
      .map(t => ({ player: t.player, tail: t.player.slice(-4), expires_at: t.expires_at ?? 0 }));
  }
  players(): string[] { return Object.keys(this.d.players); }

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
    writeFileSync(tmp, JSON.stringify(this.d));
    renameSync(tmp, this.file);
  }
}
