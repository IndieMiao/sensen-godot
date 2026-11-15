/**
 * P0 voice in the online rooms (SGODOT-383; the user, 11-02 via 奕星, q(274)): everyone in an outpost's room or a pond's
 * hears everyone else in it, through LiveKit. The voice room is the online room — the hub's instance, one LiveKit room per
 * `<outpost or pond:id>` and room number — so a grant goes only to a player the hub has in a room right now, and leaving
 * that room ends it. LiveKit sees the hub's peer id (never the player id, the P0 server's only credential: 亚瑟 on the
 * plan). Market Square has none (the user). Off unless P0_VOICE=on with the LiveKit keys (tools/p0_server.ts).
 *
 * The least against harassment the user set: Mute is the phone's own; Block is kept here, by player, and works both ways
 * on the blocker's phone alone (SGODOT-384, 周瑜 on #647): it takes none of their tracks, and LiveKit lets them take none
 * of its own (its track subscription permissions) — so only the blocker is ever told (the grant's and voice_blocks'
 * `blocked`); the one blocked never learns it. Report is a log line for a person to read later.
 * The 13+ gate is a yes / no per player (no birthday is kept); without a yes there is no grant. Blocks and the gate live in
 * their own small files beside the save, never in it.
 */
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { appendFileSync, existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import type { FastifyInstance } from 'fastify';
import { AccessToken, RoomServiceClient, TrackSource } from 'livekit-server-sdk';
import { supportCode } from '../support.js';
import { publicPlayer } from './hub.js';
import type { Occupant, OutpostRooms } from './rooms.js';

export interface P0VoiceConfig { url: string; apiKey: string; apiSecret: string; namespace: string }
/** The LiveKit side the server calls (tests replace it). A participant's metadata is the lease that let them in. */
export interface P0VoiceMedia {
  getParticipant(room: string, identity: string): Promise<{ metadata?: string }>;
  removeParticipant(room: string, identity: string): Promise<void>;
}
/** A lease's removal from LiveKit: tried this many times, this far apart, each failure logged (周瑜 on #647). */
export const RELEASE_TRIES = 3, RELEASE_RETRY_MS = 2_000;

export const VOICE_LEASE_MS = 20_000;
/** Roles whose rooms have no voice. Market Square's layers of 30 have it since q(286) (the user, 11-04: "286 Y", the
 * whole layer, no fall-off with distance; it had none since 11-02). Grace Cathedral has none (奕星 11-06: a place to see,
 * nothing to do there; the live LiveKit plan's 5,000 participant minutes a month are a hard cap for all voice). */
export const NO_VOICE_ROLES = new Set<string>(['church']);
const PLAYER_RE = /^[A-Za-z0-9_-]{8,64}$/;

/** P0_VOICE=on with LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET (P0_VOICE_NAMESPACE, default p0-dev); else off. */
export function p0VoiceFromEnv(env: Record<string, string | undefined>): P0VoiceConfig | null {
  if (env.P0_VOICE !== 'on') return null;
  const url = env.LIVEKIT_URL ?? '', apiKey = env.LIVEKIT_API_KEY ?? '', apiSecret = env.LIVEKIT_API_SECRET ?? '';
  if (!/^wss?:\/\//.test(url) || !apiKey || !apiSecret) throw new Error('P0_VOICE=on needs LIVEKIT_URL (ws:// or wss://), LIVEKIT_API_KEY and LIVEKIT_API_SECRET');
  const namespace = env.P0_VOICE_NAMESPACE ?? 'p0-dev';
  if (!/^[a-z0-9-]{3,40}$/.test(namespace)) throw new Error('P0_VOICE_NAMESPACE: 3–40 of a-z, 0-9 and -');
  return { url, apiKey, apiSecret, namespace };
}

interface Lease { id: string; player: string; room: string; peer: number; expires: number }
type Refusal = { code: string; status: number; until?: string | null };
export type VoiceBan = { until: string | null } | null;
const refuse = (code: string, status: number): Refusal => ({ code, status });

export interface P0VoiceFiles { blocks: string; ages: string; reports: string }

/** The report sheet's reasons (q(28)'s, 不知火舞's account spec §7): Offensive name or bio / Harassment / Offensive voice
 *  chat / Cheating or bots / Something else. Anything else (an old build's free text, nothing) is `other`. */
export const REPORT_REASONS = ['offensive_name', 'harassment', 'offensive_voice', 'cheating', 'other'] as const;
export type ReportReason = typeof REPORT_REASONS[number];
export const reportReason = (r: unknown): ReportReason => (REPORT_REASONS as readonly unknown[]).includes(r) ? r as ReportReason : 'other';
const CHANNELS = ['oss', 'play', 'appstore'];

/** A report as kept (voice_reports.jsonl, a year) and handed on (onReport → 苏烈's mail queue, SGODOT-484 550d0c5d): its
 *  own id, the two support codes (no player id: tech-plan §3.2), the reported one's name at that moment (ours alone: never
 *  in the mail), the reason, where, and the reporter's build channel. */
export interface ReportLine {
  kind: 'voice_report'; v: 2; id: string; at: string;
  reporter_code: string; reported_code: string; name: string | null;
  reason: ReportReason; place: string; room: number; channel: string;
}

const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
/** R-YYYYMMDD-XXXXXXXX: the UTC day and 40 random bits in Crockford, made once when the line is written. */
export function reportId(at: number): string {
  const day = new Date(at).toISOString().slice(0, 10).replace(/-/g, '');
  let bits = BigInt('0x' + randomBytes(5).toString('hex')), tail = '';
  for (let i = 0; i < 8; i++) { tail = CROCKFORD[Number(bits & 31n)] + tail; bits >>= 5n; }
  return `R-${day}-${tail}`;
}

export class P0Voice {
  private leases = new Map<string, Lease>();   // by player
  private pendingReleases = new Map<string, Lease>(); // Also retain exhausted retries for an explicit management retry.
  private releaseTimers = new Map<string, ReturnType<typeof setTimeout>>();
  private releaseCalls = new Map<string, Promise<boolean>>();
  private blocks: Record<string, string[]>;    // player → the players they block
  private ages: Record<string, boolean>;       // player → 13+ (true) or not (false); absent: not asked yet
  private reported = new Set<string>();        // "reporter reported": a second report says so (不知火舞's spec §6), not a second line
  private media?: P0VoiceMedia;
  /** The hub's way to a player's socket (set once the hub is up). */
  tell: (player: string, payload: object) => void = () => {};
  /** The hub's: a Block or Unblock between two players takes each out of (or back into) the other's view (seenChanged). */
  seen: (a: string, b: string) => void = () => {};
  /** A player's name as their save has it now (the report's snapshot); null when they never gave one. */
  nameOf: (player: string) => string | null = () => null;
  /** A report kept: handed on once its line is written (SGODOT-484, 苏烈's queue takes it by id). */
  onReport: (line: ReportLine) => void = () => {};
  /** SGODOT-484: server-owned moderation, independent of the age check and saved blocks. */
  voiceBan: (player: string) => { until: number | null } | null | undefined = () => null;

  constructor(readonly config: P0VoiceConfig | null, private rooms: OutpostRooms, private files: P0VoiceFiles | null,
    private now: () => number = Date.now, media?: P0VoiceMedia) {
    this.blocks = readJson(files?.blocks) as Record<string, string[]>;
    this.ages = readJson(files?.ages) as Record<string, boolean>;
    this.media = media ?? (config ? new RoomServiceClient(config.url.replace(/^ws/, 'http'), config.apiKey, config.apiSecret,
      { requestTimeout: 2, failover: false }) : undefined);
  }

  /** The LiveKit room of a hub instance: the place hashed (no `:` or `~` reaches the SFU: 亚瑟), with its layout group
   * when it has one (SGODOT-218: the market plaza's Room 1 is not the fruit shop's), and its number. */
  roomName(o: Pick<Occupant, 'outpost' | 'room'> & { layout?: string }): string {
    const place = o.layout ? `${o.outpost}@${o.layout}` : o.outpost;
    return `${this.config?.namespace ?? 'p0-off'}-${createHash('sha256').update(place).digest('hex').slice(0, 12)}-${o.room}`;
  }

  status(player: string) {
    return { ok: true, available: !!this.config, age: player in this.ages ? (this.ages[player] ? 'ok' : 'no') : 'unknown',
      ban: this.currentBan(player) };
  }

  /** Validate the stored millisecond value before testing expiry. A malformed record is neither absent nor permanent.
   * Return a fresh minimal projection; no caller/older reply can mutate or cache the stored sanction. */
  private currentBan(player: string): VoiceBan {
    const record = this.voiceBan(player);
    if (record === null || record === undefined) return null;
    const until = record.until;
    if (until === null) return { until: null };
    if (typeof until !== 'number' || !Number.isSafeInteger(until) || Math.abs(until) > 8_640_000_000_000_000)
      throw new Error('VOICE_BAN_INVALID');
    return until <= this.now() ? null : { until: new Date(until).toISOString() };
  }

  private banRefusal(player: string): Refusal | null {
    try {
      const ban = this.currentBan(player);
      return ban ? { code: 'VOICE_BANNED', status: 403, until: ban.until } : null;
    } catch { return refuse('VOICE_UNAVAILABLE', 503); }
  }

  /** The 13+ gate's answer, once: a no stays a no on this server (a yes after a no is refused). */
  setAge(player: string, ok: boolean): Refusal | null {
    if (this.ages[player] === false && ok) return refuse('AGE_GATE', 403);
    this.ages[player] = ok;
    writeJson(this.files?.ages, this.ages);
    if (!ok) void this.drop(player);
    return null;
  }

  private gate(player: string): { o: Occupant; spec: NonNullable<ReturnType<OutpostRooms['spec']>> } | Refusal {
    const ban = this.banRefusal(player);
    if (ban) { void this.drop(player); return ban; }
    if (!this.config) return refuse('VOICE_OFF', 403);
    if (this.ages[player] !== true) return refuse('AGE_GATE', 403);
    const o = this.rooms.occupant(player);
    if (!o) return refuse('NOT_IN_ROOM', 403);
    const spec = this.rooms.spec(o.outpost, o.layout);
    if (!spec || NO_VOICE_ROLES.has(spec.role)) return refuse('VOICE_NOT_HERE', 403);
    return { o, spec };
  }

  async join(player: string): Promise<Refusal | Record<string, unknown>> {
    const g = this.gate(player);
    if ('code' in g) return g;
    const { o, spec } = g;
    const room = this.roomName(o), now = this.now();
    this.sweep();
    const mine = this.leases.get(player);
    const others = [...this.leases.values()].filter(l => l.room === room && l.player !== player).length;
    if (!(mine?.room === room) && others >= spec.capacity) return refuse('VOICE_ROOM_FULL', 409);
    if (mine && mine.room !== room) {
      await this.release(mine);
      const current = this.gate(player);
      if ('code' in current) return current;
      if (current.o !== o) return refuse('LEASE_EXPIRED', 410);
    }
    const lease: Lease = mine?.room === room && mine.peer === o.id ? mine : { id: randomUUID(), player, room, peer: o.id, expires: 0 };
    lease.expires = now + VOICE_LEASE_MS;
    this.leases.set(player, lease);
    // the lease rides as the participant's metadata: a peer id is the lowest free one and comes back at once, so a removal
    // checks it is still this lease's participant before it goes (周瑜 on #647)
    const token = new AccessToken(this.config!.apiKey, this.config!.apiSecret, { identity: String(o.id), ttl: 60, name: `Traveller ${o.id}`,
      metadata: lease.id });
    token.addGrant({ roomJoin: true, room, canPublish: true, canPublishSources: [TrackSource.MICROPHONE], canSubscribe: true,
      canPublishData: false, canUpdateOwnMetadata: false });
    const signed = await token.toJwt();
    const ban = this.banRefusal(player);
    if (ban) { await this.release(lease); return ban; }
    // Deletion / departure may run while JWT signing is pending. Do not hand out a grant for the removed lease.
    if (this.leases.get(player) !== lease || this.rooms.occupant(player) !== o || this.ages[player] !== true)
      return refuse('LEASE_EXPIRED', 410);
    return { ok: true, url: this.config!.url, token: signed, lease_id: lease.id, room, capacity: Math.max(2, spec.capacity),
      lease_ms: VOICE_LEASE_MS, self: String(o.id), blocked: this.phoneBlocks(player) };
  }

  heartbeat(player: string, leaseId: string): Refusal | Record<string, unknown> {
    const ban = this.banRefusal(player);
    if (ban) { void this.drop(player); return ban; }
    const lease = this.leases.get(player);
    if (!lease || lease.id !== leaseId || lease.expires < this.now()) return refuse('LEASE_EXPIRED', 410);
    const o = this.rooms.occupant(player);
    if (!o || this.roomName(o) !== lease.room || o.id !== lease.peer) { void this.release(lease); return refuse('LEASE_EXPIRED', 410); }
    lease.expires = this.now() + VOICE_LEASE_MS;
    return { ok: true, room: lease.room, lease_ms: VOICE_LEASE_MS };
  }

  async leave(player: string, leaseId: string): Promise<void> {
    const lease = this.leases.get(player);
    if (lease && lease.id === leaseId) await this.release(lease);
  }

  /** Account deletion: release voice, remove age and both sides of saved blocks, but retain the one-year report log.
   * Starts releasing the lease before awaiting; the caller can kick the WS immediately while blocks still hide it. */
  async removePlayer(player: string): Promise<void> {
    await this.drop(player);
    const ages = { ...this.ages }, blocks = { ...this.blocks };
    const hadAge = Object.hasOwn(ages, player), hadBlocks = Object.hasOwn(blocks, player);
    delete ages[player]; delete blocks[player];
    let changedBlocks = hadBlocks;
    for (const [other, list] of Object.entries(blocks)) {
      const next = list.filter(id => id !== player);
      if (next.length === list.length) continue;
      changedBlocks = true;
      if (next.length) blocks[other] = next; else delete blocks[other];
    }
    // Publish the new memory state only after both writes; a partial disk failure can then be retried.
    if (hadAge) writeJson(this.files?.ages, ages);
    if (changedBlocks) writeJson(this.files?.blocks, blocks);
    this.ages = ages; this.blocks = blocks;
    this.refused.delete(player);
    for (const key of this.reported) if (key.startsWith(player + ' ') || key.endsWith(' ' + player)) this.reported.delete(key);
  }

  /** Block (or unblock) someone in this player's room by their peer id; the blocker hears the new list at once (their
   * phone shuts both ways, 384), the one blocked is told nothing. */
  block(player: string, peer: number, on: boolean): Refusal | Record<string, unknown> {
    const target = this.playerAt(player, peer);
    if (!target) return refuse('NOT_IN_ROOM', 404);
    const list = new Set(this.blocks[player] ?? []);
    if (on) list.add(target); else list.delete(target);
    if (list.size) this.blocks[player] = [...list]; else delete this.blocks[player];
    writeJson(this.files?.blocks, this.blocks);
    this.tellBlocks(player);
    this.seen(player, target);   // in one room they go out of each other's sight at once (and come back on Unblock)
    return { ok: true, blocked: this.blockedPeers(player) };
  }

  /** Whether a and b are kept out of each other's sight in a room (the hub's hides): a Block either way (q(28), 383 V3). */
  hides(a: string, b: string): boolean { return this.blocking(a, b) || this.blocking(b, a); }

  /** Who this player blocks, as handles (the roster's public `player`, never an id): their Blocked list, which outlives a
   * room — the blocked are out of sight, so Unblock is from this list (unblock). */
  blockedList(player: string): { handle: string; name?: string }[] {
    return (this.blocks[player] ?? []).map(p => { const name = this.nameOf(p); return { handle: publicPlayer(p), ...(name ? { name } : {}) }; });
  }

  /** Unblock by handle, from the Blocked list, wherever the two are. */
  unblock(player: string, handle: string): Refusal | Record<string, unknown> {
    const target = (this.blocks[player] ?? []).find(p => publicPlayer(p) === handle);
    if (!target) return refuse('NOT_BLOCKED', 404);
    const list = (this.blocks[player] ?? []).filter(p => p !== target);
    if (list.length) this.blocks[player] = list; else delete this.blocks[player];
    writeJson(this.files?.blocks, this.blocks);
    this.tellBlocks(player);
    this.seen(player, target);
    return { ok: true, blocked: this.blockedList(player) };
  }

  /** Report: one line for a person to read later (the user, 11-02) — v2 (SGODOT-484): its id, the two support codes, the
   * reported one's name then, the reason, where, the channel — then handed on (onReport). Nothing else happens. The
   * same person again (this server's run): `already`, no second line (You already reported this). */
  report(player: string, peer: number, reason: unknown, channel: unknown = ''): Refusal | Record<string, unknown> {
    const target = this.playerAt(player, peer);
    const o = this.rooms.occupant(player);
    if (!target || !o) return refuse('NOT_IN_ROOM', 404);
    const key = player + ' ' + target;
    if (this.reported.has(key)) return { ok: true, already: true };
    this.reported.add(key);
    const at = this.now();
    const line: ReportLine = { kind: 'voice_report', v: 2, id: reportId(at), at: new Date(at).toISOString(),
      reporter_code: supportCode(player), reported_code: supportCode(target), name: this.nameOf(target),
      reason: reportReason(reason), place: o.outpost, room: o.room, channel: CHANNELS.includes(String(channel)) ? String(channel) : '' };
    // the docker log: the id and the codes only (tech-plan §3.2)
    console.log(JSON.stringify({ kind: line.kind, id: line.id, reporter_code: line.reporter_code, reported_code: line.reported_code }));
    if (this.files?.reports) appendFileSync(this.files.reports, JSON.stringify(line) + '\n');
    this.onReport(line);
    return { ok: true, already: false };
  }

  /** The hub's hooks: someone came into a room (whoever there blocks them hears their new list, and so does whoever's
   * phone still refuses the peer id they took — a peer id comes back at once, and the next one to take it is no one
   * they blocked; they hear theirs, if they block anyone there), or left one (their grant ends and LiveKit lets them go;
   * whoever blocked them hears nothing — their phone keeps refusing that id, never opened to all while the one blocked
   * may still be in LiveKit or back under a new id: 李元芳 on 384 b5b6a124). */
  joined(o: Occupant): void {
    let mine = false;
    for (const m of this.rooms.members(o.outpost, o.room, o.layout)) {
      if (m.player === o.player) continue;
      if (this.blocking(m.player, o.player) || this.refused.get(m.player)?.has(String(o.id))) this.tellBlocks(m.player);
      if (this.blocking(o.player, m.player)) mine = true;
    }
    if (mine) this.tellBlocks(o.player);
  }
  departed(o: Occupant): void {
    const lease = this.leases.get(o.player);
    if (lease && lease.room === this.roomName(o)) void this.release(lease);
    this.refused.delete(o.player);   // their next room's grant brings their list there
  }

  /** The peer ids each phone was last given as blocked (the grant, voice_blocks): what it refuses until told again. */
  private refused = new Map<string, Set<string>>();

  /** This player's blocked peers, noted as what their phone will refuse. */
  private phoneBlocks(player: string): string[] {
    const list = this.blockedPeers(player);
    this.refused.set(player, new Set(list));
    return list;
  }

  private tellBlocks(player: string): void {
    this.tell(player, { t: 'voice_blocks', blocked: this.phoneBlocks(player) });
  }

  /** The peers in this player's room they block (theirs only: who blocks them is never said, 384). */
  blockedPeers(player: string): string[] {
    const o = this.rooms.occupant(player);
    if (!o) return [];
    return this.rooms.members(o.outpost, o.room, o.layout).filter(m => m.player !== player && this.blocking(player, m.player)).map(m => String(m.id));
  }

  private blocking(a: string, b: string): boolean {
    return (this.blocks[a] ?? []).includes(b);
  }

  private playerAt(player: string, peer: number): string | undefined {
    const o = this.rooms.occupant(player);
    if (!o || !Number.isInteger(peer)) return undefined;
    return this.rooms.members(o.outpost, o.room, o.layout).find(m => m.id === peer && m.player !== player)?.player;
  }

  /** End only the live lease (moderation / session revocation). Keep age, blocks, reports and room occupancy. */
  async drop(player: string, options: { requireConfirmed?: boolean } = {}): Promise<void> {
    const lease = this.leases.get(player);
    const targets = new Map(options.requireConfirmed
      ? [...this.pendingReleases.values()].filter(l => l.player === player).map(l => [l.id, l]) : []);
    if (lease) targets.set(lease.id, lease);
    const results = await Promise.all([...targets.values()].map(l => this.release(l)));
    if (options.requireConfirmed && results.some(confirmed => !confirmed)) throw new Error('VOICE_RELEASE_UNCONFIRMED');
  }

  /** Ends a lease: out of the server's books at once, and out of LiveKit if that participant is still this lease's — never
   * whoever took the peer id since. A failure is logged and tried again (RELEASE_TRIES); one gone already is done. */
  private release(lease: Lease, attempt = 1): Promise<boolean> {
    const running = this.releaseCalls.get(lease.id);
    if (running) return running;
    const job = this.releaseOnce(lease, attempt).finally(() => this.releaseCalls.delete(lease.id));
    this.releaseCalls.set(lease.id, job);
    return job;
  }

  private async releaseOnce(lease: Lease, attempt: number): Promise<boolean> {
    if (this.leases.get(lease.player) === lease) this.leases.delete(lease.player);
    this.pendingReleases.set(lease.id, lease);
    const confirmed = () => {
      this.pendingReleases.delete(lease.id);
      const timer = this.releaseTimers.get(lease.id);
      if (timer) clearTimeout(timer);
      this.releaseTimers.delete(lease.id);
      return true;
    };
    if (!this.media) return confirmed();
    const identity = String(lease.peer);
    try {
      const p = await this.media.getParticipant(lease.room, identity);
      if (p.metadata !== lease.id) return confirmed();   // someone else is that peer id now
      await this.media.removeParticipant(lease.room, identity);
      return confirmed();
    } catch (error) {
      const e = error as { status?: number; code?: string; message?: string };
      if (e?.status === 404 || e?.code === 'not_found') return confirmed();   // left LiveKit already
      console.warn(JSON.stringify({ voice: 'release_failed', room: lease.room, peer: identity, attempt, error: String(e?.message ?? error).slice(0, 200) }));
      if (attempt < RELEASE_TRIES && !this.releaseTimers.has(lease.id)) {
        const timer = setTimeout(() => {
          this.releaseTimers.delete(lease.id);
          void this.release(lease, attempt + 1);
        }, RELEASE_RETRY_MS);
        timer.unref?.();
        this.releaseTimers.set(lease.id, timer);
      }
      return false; // Ordinary callers still resolve; management can distinguish unconfirmed cleanup.
    }
  }

  private sweep(): void {
    const now = this.now();
    for (const lease of [...this.leases.values()]) if (lease.expires < now) void this.release(lease);
  }
}

function readJson(file?: string): Record<string, unknown> {
  if (!file || !existsSync(file)) return {};
  try {
    const v: unknown = JSON.parse(readFileSync(file, 'utf8'));
    return v && typeof v === 'object' && !Array.isArray(v) ? v as Record<string, unknown> : {};
  } catch { return {}; }
}

function writeJson(file: string | undefined, value: object): void {
  if (!file) return;
  writeFileSync(file + '.tmp', JSON.stringify(value));
  renameSync(file + '.tmp', file);
}

/** POST /v1/p0/voice/{age,join,heartbeat,leave,block,report} and GET /v1/p0/voice/status, behind the P0 guard as every
 * route. A refusal is an HTTP error with {ok: false, code} (PartyVoiceSession reads a non-2xx as one). */
export function registerP0Voice(app: FastifyInstance, voice: P0Voice,
  identify?: (headers: Record<string, unknown>) => { player: string } | { status: number; body: object }): void {
  // SGODOT-488: the routes' identify when there are accounts, its refusal sent as it is (session_replaced,
  // account_deleted, 426 update_required … as the routes, the room and the limits answer it); the x-p0-player header as
  // before when not, refused UNAUTHENTICATED.
  const refusals = new WeakMap<object, { status: number; body: object }>();
  const playerOf = (h: Record<string, unknown>) => {
    if (identify) { const w = identify(h); if ('status' in w) { refusals.set(h, w); return null; } return w.player; }
    const id = String(h['x-p0-player'] ?? ''); return PLAYER_RE.test(id) ? id : null;
  };
  const deny = (reply: { code(n: number): { send(b: object): unknown } }, h: Record<string, unknown>) => {
    const r = refusals.get(h);
    return r ? reply.code(r.status).send(r.body) : reply.code(401).send({ ok: false, code: 'UNAUTHENTICATED' });
  };
  const answer = (reply: { code(n: number): { send(b: object): unknown } }, r: Refusal | Record<string, unknown>) => {
    if ('status' in r && typeof r.status === 'number' && 'code' in r) {
      // Keep only the contractual field, never spread internal sanctions or provider details into a refusal.
      if (r.code === 'VOICE_BANNED') {
        if (!Object.hasOwn(r, 'until') || !(r.until === null || (typeof r.until === 'string'
          && Number.isFinite(Date.parse(r.until)) && new Date(r.until).toISOString() === r.until)))
          return reply.code(503).send({ ok: false, code: 'VOICE_UNAVAILABLE' });
        return reply.code(r.status).send({ ok: false, code: r.code, until: r.until });
      }
      return reply.code(r.status).send({ ok: false, code: r.code });
    }
    return reply.code(200).send(r);
  };
  const status = (player: string) => {
    try { return voice.status(player); } catch { return refuse('VOICE_UNAVAILABLE', 503); }
  };
  const body = (b: unknown) => (b && typeof b === 'object' ? b : {}) as Record<string, unknown>;
  // a peer id as the grant and voice_blocks write it ("2", LiveKit's identity) or as a number: both (蒙恬 on #647)
  const peerOf = (v: unknown): number | null => typeof v === 'number' ? (Number.isInteger(v) ? v : null)
    : typeof v === 'string' && /^\d{1,5}$/.test(v) ? Number(v) : null;
  app.get('/v1/p0/voice/status', async (req, reply) => {
    const p = playerOf(req.headers);
    return p ? answer(reply, status(p)) : deny(reply, req.headers);
  });
  app.post('/v1/p0/voice/age', async (req, reply) => {
    const p = playerOf(req.headers), b = body(req.body);
    if (!p) return deny(reply, req.headers);
    if (typeof b.ok !== 'boolean') return answer(reply, { code: 'SCHEMA', status: 400 });
    return answer(reply, voice.setAge(p, b.ok) ?? status(p));
  });
  app.post('/v1/p0/voice/join', async (req, reply) => {
    const p = playerOf(req.headers);
    if (!p) return deny(reply, req.headers);
    try { return answer(reply, await voice.join(p)); }
    catch { return answer(reply, { code: 'VOICE_UNAVAILABLE', status: 503 }); }
  });
  app.post('/v1/p0/voice/heartbeat', async (req, reply) => {
    const p = playerOf(req.headers);
    return p ? answer(reply, voice.heartbeat(p, String(body(req.body).lease_id ?? ''))) : deny(reply, req.headers);
  });
  app.post('/v1/p0/voice/leave', async (req, reply) => {
    const p = playerOf(req.headers);
    if (!p) return deny(reply, req.headers);
    await voice.leave(p, String(body(req.body).lease_id ?? ''));
    return { ok: true };
  });
  app.post('/v1/p0/voice/block', async (req, reply) => {
    const p = playerOf(req.headers), b = body(req.body);
    if (!p) return deny(reply, req.headers);
    const peer = peerOf(b.peer);
    if (peer === null || typeof b.on !== 'boolean') return answer(reply, { code: 'SCHEMA', status: 400 });
    return answer(reply, voice.block(p, peer, b.on));
  });
  app.get('/v1/p0/voice/blocks', async (req, reply) => {
    const p = playerOf(req.headers);
    return p ? { ok: true, blocked: voice.blockedList(p) } : deny(reply, req.headers);
  });
  app.post('/v1/p0/voice/unblock', async (req, reply) => {
    const p = playerOf(req.headers), b = body(req.body);
    if (!p) return deny(reply, req.headers);
    if (typeof b.handle !== 'string' || !/^[0-9a-f]{16}$/.test(b.handle)) return answer(reply, { code: 'SCHEMA', status: 400 });
    return answer(reply, voice.unblock(p, b.handle));
  });
  app.post('/v1/p0/voice/report', async (req, reply) => {
    const p = playerOf(req.headers), b = body(req.body);
    if (!p) return deny(reply, req.headers);
    const peer = peerOf(b.peer);
    if (peer === null) return answer(reply, { code: 'SCHEMA', status: 400 });
    return answer(reply, voice.report(p, peer, b.reason, req.headers['x-p0-channel']));
  });
}
