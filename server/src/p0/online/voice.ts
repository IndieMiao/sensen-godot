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
import { createHash, randomUUID } from 'node:crypto';
import { appendFileSync, existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import type { FastifyInstance } from 'fastify';
import { AccessToken, RoomServiceClient, TrackSource } from 'livekit-server-sdk';
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
/** Roles whose rooms have no voice (the user, 11-02: Market Square's 30 not this time). */
export const NO_VOICE_ROLES = new Set(['market']);
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
type Refusal = { code: string; status: number };
const refuse = (code: string, status: number): Refusal => ({ code, status });

export interface P0VoiceFiles { blocks: string; ages: string; reports: string }

export class P0Voice {
  private leases = new Map<string, Lease>();   // by player
  private blocks: Record<string, string[]>;    // player → the players they block
  private ages: Record<string, boolean>;       // player → 13+ (true) or not (false); absent: not asked yet
  private reported = new Set<string>();        // "reporter reported": a second report says so (不知火舞's spec §6), not a second line
  private media?: P0VoiceMedia;
  /** The hub's way to a player's socket (set once the hub is up). */
  tell: (player: string, payload: object) => void = () => {};

  constructor(readonly config: P0VoiceConfig | null, private rooms: OutpostRooms, private files: P0VoiceFiles | null,
    private now: () => number = Date.now, media?: P0VoiceMedia) {
    this.blocks = readJson(files?.blocks) as Record<string, string[]>;
    this.ages = readJson(files?.ages) as Record<string, boolean>;
    this.media = media ?? (config ? new RoomServiceClient(config.url.replace(/^ws/, 'http'), config.apiKey, config.apiSecret,
      { requestTimeout: 2, failover: false }) : undefined);
  }

  /** The LiveKit room of a hub instance: the place hashed (no `:` or `~` reaches the SFU: 亚瑟), and its number. */
  roomName(o: Pick<Occupant, 'outpost' | 'room'>): string {
    return `${this.config?.namespace ?? 'p0-off'}-${createHash('sha256').update(o.outpost).digest('hex').slice(0, 12)}-${o.room}`;
  }

  status(player: string) {
    return { ok: true, available: !!this.config, age: player in this.ages ? (this.ages[player] ? 'ok' : 'no') : 'unknown' };
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
    if (!this.config) return refuse('VOICE_OFF', 403);
    if (this.ages[player] !== true) return refuse('AGE_GATE', 403);
    const o = this.rooms.occupant(player);
    if (!o) return refuse('NOT_IN_ROOM', 403);
    const spec = this.rooms.spec(o.outpost);
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
    if (mine && mine.room !== room) await this.release(mine);
    const lease: Lease = mine?.room === room && mine.peer === o.id ? mine : { id: randomUUID(), player, room, peer: o.id, expires: 0 };
    lease.expires = now + VOICE_LEASE_MS;
    this.leases.set(player, lease);
    // the lease rides as the participant's metadata: a peer id is the lowest free one and comes back at once, so a removal
    // checks it is still this lease's participant before it goes (周瑜 on #647)
    const token = new AccessToken(this.config!.apiKey, this.config!.apiSecret, { identity: String(o.id), ttl: 60, name: `Traveller ${o.id}`,
      metadata: lease.id });
    token.addGrant({ roomJoin: true, room, canPublish: true, canPublishSources: [TrackSource.MICROPHONE], canSubscribe: true,
      canPublishData: false, canUpdateOwnMetadata: false });
    return { ok: true, url: this.config!.url, token: await token.toJwt(), lease_id: lease.id, room, capacity: Math.max(2, spec.capacity),
      lease_ms: VOICE_LEASE_MS, self: String(o.id), blocked: this.blockedPeers(player) };
  }

  heartbeat(player: string, leaseId: string): Refusal | Record<string, unknown> {
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

  /** Block (or unblock) someone in this player's room by their peer id; the blocker hears the new list at once (their
   * phone shuts both ways, 384), the one blocked is told nothing. */
  block(player: string, peer: number, on: boolean): Refusal | Record<string, unknown> {
    const target = this.playerAt(player, peer);
    if (!target) return refuse('NOT_IN_ROOM', 404);
    const list = new Set(this.blocks[player] ?? []);
    if (on) list.add(target); else list.delete(target);
    if (list.size) this.blocks[player] = [...list]; else delete this.blocks[player];
    writeJson(this.files?.blocks, this.blocks);
    this.tell(player, { t: 'voice_blocks', blocked: this.blockedPeers(player) });
    return { ok: true, blocked: this.blockedPeers(player) };
  }

  /** Report: one line — who, whom, when, where — for a person to read later (the user, 11-02); nothing else happens.
   * The same person again (this server's run): `already`, no second line (You already reported this). */
  report(player: string, peer: number, reason: string): Refusal | Record<string, unknown> {
    const target = this.playerAt(player, peer);
    const o = this.rooms.occupant(player);
    if (!target || !o) return refuse('NOT_IN_ROOM', 404);
    const key = player + ' ' + target;
    if (this.reported.has(key)) return { ok: true, already: true };
    this.reported.add(key);
    const line = { kind: 'voice_report', at: new Date(this.now()).toISOString(), reporter: player, reported: target,
      place: o.outpost, room: o.room, reason: reason.slice(0, 200) };
    console.log(JSON.stringify(line));
    if (this.files?.reports) appendFileSync(this.files.reports, JSON.stringify(line) + '\n');
    return { ok: true, already: false };
  }

  /** The hub's hooks: someone came into a room (whoever there blocks them hears their new list; so do they, if they block
   * anyone there), or left one (their grant ends, and LiveKit lets them go). */
  joined(o: Occupant): void {
    let mine = false;
    for (const m of this.rooms.members(o.outpost, o.room)) {
      if (m.player === o.player) continue;
      if (this.blocking(m.player, o.player)) this.tell(m.player, { t: 'voice_blocks', blocked: this.blockedPeers(m.player) });
      if (this.blocking(o.player, m.player)) mine = true;
    }
    if (mine) this.tell(o.player, { t: 'voice_blocks', blocked: this.blockedPeers(o.player) });
  }
  departed(o: Occupant): void {
    const lease = this.leases.get(o.player);
    if (lease && lease.room === this.roomName(o)) void this.release(lease);
  }

  /** The peers in this player's room they block (theirs only: who blocks them is never said, 384). */
  blockedPeers(player: string): string[] {
    const o = this.rooms.occupant(player);
    if (!o) return [];
    return this.rooms.members(o.outpost, o.room).filter(m => m.player !== player && this.blocking(player, m.player)).map(m => String(m.id));
  }

  private blocking(a: string, b: string): boolean {
    return (this.blocks[a] ?? []).includes(b);
  }

  private playerAt(player: string, peer: number): string | undefined {
    const o = this.rooms.occupant(player);
    if (!o || !Number.isInteger(peer)) return undefined;
    return this.rooms.members(o.outpost, o.room).find(m => m.id === peer && m.player !== player)?.player;
  }

  private async drop(player: string): Promise<void> {
    const lease = this.leases.get(player);
    if (lease) await this.release(lease);
  }

  /** Ends a lease: out of the server's books at once, and out of LiveKit if that participant is still this lease's — never
   * whoever took the peer id since. A failure is logged and tried again (RELEASE_TRIES); one gone already is done. */
  private async release(lease: Lease, attempt = 1): Promise<void> {
    if (this.leases.get(lease.player) === lease) this.leases.delete(lease.player);
    if (!this.media) return;
    const identity = String(lease.peer);
    try {
      const p = await this.media.getParticipant(lease.room, identity);
      if (p.metadata !== lease.id) return;   // someone else is that peer id now
      await this.media.removeParticipant(lease.room, identity);
    } catch (error) {
      const e = error as { status?: number; code?: string; message?: string };
      if (e?.status === 404 || e?.code === 'not_found') return;   // left LiveKit already
      console.warn(JSON.stringify({ voice: 'release_failed', room: lease.room, peer: identity, attempt, error: String(e?.message ?? error).slice(0, 200) }));
      if (attempt < RELEASE_TRIES) setTimeout(() => { void this.release(lease, attempt + 1); }, RELEASE_RETRY_MS).unref?.();
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
export function registerP0Voice(app: FastifyInstance, voice: P0Voice): void {
  const playerOf = (h: Record<string, unknown>) => { const id = String(h['x-p0-player'] ?? ''); return PLAYER_RE.test(id) ? id : null; };
  const answer = (reply: { code(n: number): { send(b: object): unknown } }, r: Refusal | Record<string, unknown>) =>
    'status' in r && typeof r.status === 'number' && 'code' in r ? reply.code(r.status).send({ ok: false, code: r.code }) : reply.code(200).send(r);
  const body = (b: unknown) => (b && typeof b === 'object' ? b : {}) as Record<string, unknown>;
  // a peer id as the grant and voice_blocks write it ("2", LiveKit's identity) or as a number: both (蒙恬 on #647)
  const peerOf = (v: unknown): number | null => typeof v === 'number' ? (Number.isInteger(v) ? v : null)
    : typeof v === 'string' && /^\d{1,5}$/.test(v) ? Number(v) : null;
  const unauth = { code: 'UNAUTHENTICATED', status: 401 };
  app.get('/v1/p0/voice/status', async (req, reply) => {
    const p = playerOf(req.headers);
    return p ? voice.status(p) : answer(reply, unauth);
  });
  app.post('/v1/p0/voice/age', async (req, reply) => {
    const p = playerOf(req.headers), b = body(req.body);
    if (!p) return answer(reply, unauth);
    if (typeof b.ok !== 'boolean') return answer(reply, { code: 'SCHEMA', status: 400 });
    return answer(reply, voice.setAge(p, b.ok) ?? voice.status(p));
  });
  app.post('/v1/p0/voice/join', async (req, reply) => {
    const p = playerOf(req.headers);
    if (!p) return answer(reply, unauth);
    try { return answer(reply, await voice.join(p)); }
    catch { return answer(reply, { code: 'VOICE_UNAVAILABLE', status: 503 }); }
  });
  app.post('/v1/p0/voice/heartbeat', async (req, reply) => {
    const p = playerOf(req.headers);
    return p ? answer(reply, voice.heartbeat(p, String(body(req.body).lease_id ?? ''))) : answer(reply, unauth);
  });
  app.post('/v1/p0/voice/leave', async (req, reply) => {
    const p = playerOf(req.headers);
    if (!p) return answer(reply, unauth);
    await voice.leave(p, String(body(req.body).lease_id ?? ''));
    return { ok: true };
  });
  app.post('/v1/p0/voice/block', async (req, reply) => {
    const p = playerOf(req.headers), b = body(req.body);
    if (!p) return answer(reply, unauth);
    const peer = peerOf(b.peer);
    if (peer === null || typeof b.on !== 'boolean') return answer(reply, { code: 'SCHEMA', status: 400 });
    return answer(reply, voice.block(p, peer, b.on));
  });
  app.post('/v1/p0/voice/report', async (req, reply) => {
    const p = playerOf(req.headers), b = body(req.body);
    if (!p) return answer(reply, unauth);
    const peer = peerOf(b.peer);
    if (peer === null) return answer(reply, { code: 'SCHEMA', status: 400 });
    return answer(reply, voice.report(p, peer, typeof b.reason === 'string' ? b.reason : ''));
  });
}
