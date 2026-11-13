/**
 * P0 outpost realtime rooms (SGODOT-227): WebSocket /v1/p0/online and GET /v1/p0/presence on the P0
 * playtest server. Same message shapes as the realtime gateway (joined / roster / peer / left / result)
 * and the same snapshot frame v1, so the client reuses OnlineCrowd. Identity is the x-p0-player header
 * (no token, local and dev servers only); presence lives in memory only, never in the P0 save file.
 * Positions are the client's: the server only keeps them inside the room and within walking speed.
 */
import { createHash } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { IncomingMessage } from 'node:http';
import type { Duplex } from 'node:stream';
import { WebSocket, WebSocketServer } from 'ws';
import { defaultAppearance, type Appearance, type AppearanceCatalog } from './appearance.js';
import { upgradeRefusal, type P0Gate } from '../gate.js';
import { P0_ACTIONS, snapshotFrame } from './frame.js';
import { OutpostRooms, SPAWN_CANDIDATES_MAX, type Occupant } from './rooms.js';
import { landmarkOfRoom, POND_ROOM, pondOfRoom } from './outposts.js';

export const PATH = '/v1/p0/online';
export const PLAYER_RE = /^[A-Za-z0-9_-]{8,64}$/;
export const LIMITS = {
  connections: 512,
  /** Largest client message (bytes); inputs are about 120. */
  payload: 1024,
  /** Token bucket: 40 messages burst, 20 per second refill (inputs are sent at 10 Hz). */
  burst: 40, refill_per_s: 20,
  snapshot_ms: 100,
  idle_ms: 30_000,
  appearance_ms: 500,
  /** Socket backpressure: skip frames above, close above. */
  skip_bytes: 64 * 1024, close_bytes: 256 * 1024,
  /** Pond rooms: the fishing states go out every this many snapshot ticks (OnlineCrowd drops one older than 1 s). */
  fishing_ticks: 5,
  /** A landed or lost fish stays shown this long, then the line is in. */
  result_ms: 3_000,
};

/** A pond room's fishing (11-02, pond multiplayer): what the others see of a line — its cast, bite, reel and the fish
 * landed, the shape OnlineCrowd.fishing_snapshot / FishingPresentation.configure_remote read (the realtime room's
 * fishingView). Shown only: the catch itself is each player's own command on their own save, never this. */
export const FISH_PHASES = ['casting', 'waiting', 'hook', 'playing', 'result'] as const;
interface Fishing { sequence: number; phase: typeof FISH_PHASES[number]; at: number; castAt: number; target: [number, number];
  held: boolean; fish: number; outcome?: 'caught' | 'escaped'; fishId?: string }

interface Conn { ws: WebSocket; player: string; epoch: number; appearance: Appearance; tokens: number; tokenAt: number; lastSeen: number; dressedAt: number;
  fishing?: Fishing; casts: number }
/** keys: the demo access keys (P0_ACCESS_KEYS, SGODOT-232 D1). The upgrade is not a Fastify request, so the
 * guard's onRequest hook never sees it: the hub checks x-p0-key itself. Empty or absent = no key (local playtests). */
/** pass: v5 (SGODOT-278) — may this player join this outpost? An error code (PASS_REQUIRED / TRIP_EXPIRED) when not. */
/** joined / departed: someone came into a room or left one (P0Voice: the blocks to tell, the grant to end). */
export interface P0OnlineDeps { rooms: OutpostRooms; appearances?: AppearanceCatalog; now?: () => number; keys?: string[]; gate?: P0Gate;
  pass?: (player: string, outpost: string) => string | null;
  joined?: (o: Occupant) => void; departed?: (o: Occupant) => void;
  /** hides(a, b): a and b never see each other in a room — a Block either way (P0Voice; q(28), 383 V3, 奕星 11-02). */
  hides?: (a: string, b: string) => boolean;
  /** SGODOT-488: who the upgrade is (accounts/identify.ts), the routes' own answer; absent, x-p0-player as before. */
  identify?: (headers: Record<string, unknown>) => { player: string } | { status: number; body: object } }

export class P0OnlineHub {
  readonly conns = new Set<Conn>();
  private byPlayer = new Map<string, Conn>();
  private wss = new WebSocketServer({ noServer: true, maxPayload: LIMITS.payload, perMessageDeflate: false });
  private timer?: ReturnType<typeof setInterval>;
  private tick = 0;

  constructor(readonly deps: P0OnlineDeps) {
    this.timer = setInterval(() => this.step(), LIMITS.snapshot_ms);
    this.timer.unref();
  }

  upgrade(req: IncomingMessage, socket: Duplex, head: Buffer): void {
    const keys = this.deps.keys ?? [];
    if (keys.length > 0 && !keys.includes(String(req.headers['x-p0-key'] ?? ''))) {
      socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
      return;
    }
    // SYS-UPDATE / SYS-MAINT (gate.ts): the same 426 / 503 and JSON body as the routes, and no upgrade.
    const refused = this.deps.gate?.check(req.headers);
    if (refused) { socket.end(upgradeRefusal(refused)); return; }
    let player = String(req.headers['x-p0-player'] ?? '');
    if (this.deps.identify) {
      const w = this.deps.identify(req.headers);
      if ('status' in w) {
        const body = JSON.stringify(w.body);
        socket.end(`HTTP/1.1 ${w.status} Refused\r\nContent-Type: application/json\r\nContent-Length: ${Buffer.byteLength(body)}\r\nConnection: close\r\n\r\n${body}`);
        return;
      }
      player = w.player;
    } else if (!PLAYER_RE.test(player)) { socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'); return; }
    if (this.conns.size >= LIMITS.connections) { socket.end('HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n'); return; }
    this.wss.handleUpgrade(req, socket, head, ws => this.accept(ws, player));
  }

  close(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = undefined;
    for (const c of this.conns) c.ws.terminate();
    this.conns.clear();
    this.byPlayer.clear();
    this.wss.close();
  }

  /** Account deletion / session invalidation: leave immediately, forget reconnect state and stop queued inputs.
   * Keep A1's return value (whether a socket was open) and the client's no-reconnect close code. */
  kick(player: string): boolean {
    const c = this.byPlayer.get(player);
    if (c) {
      this.byPlayer.delete(player);
      this.conns.delete(c);
      this.depart(c, false);
      c.ws.close(4001, 'SESSION_REPLACED');
    }
    const orphan = this.deps.rooms.forget(player);
    if (orphan) this.deps.departed?.(orphan);
    return !!c;
  }

  private accept(ws: WebSocket, player: string): void {
    const now = Date.now();
    const old = this.byPlayer.get(player);
    if (old) { this.depart(old, true); old.ws.close(4001, 'SESSION_REPLACED'); }
    const c: Conn = { ws, player, epoch: 0, appearance: defaultAppearance(), tokens: LIMITS.burst, tokenAt: now, lastSeen: now, dressedAt: 0, casts: 0 };
    this.conns.add(c);
    this.byPlayer.set(player, c);
    ws.on('error', () => {});
    ws.on('close', () => {
      this.conns.delete(c);
      if (this.byPlayer.get(player) === c) { this.byPlayer.delete(player); this.depart(c, true); }
    });
    ws.on('message', (raw, binary) => this.message(c, raw as Buffer, binary));
    this.send(c, { t: 'hello', protocol: 1, actions: P0_ACTIONS });
  }

  private message(c: Conn, raw: Buffer, binary: boolean): void {
    if (this.byPlayer.get(c.player) !== c) return;
    const now = Date.now();
    c.tokens = Math.min(LIMITS.burst, c.tokens + (now - c.tokenAt) / 1000 * LIMITS.refill_per_s);
    c.tokenAt = now;
    if (--c.tokens < 0 || binary) { c.ws.close(4002, 'RATE_OR_SCHEMA'); return; }
    c.lastSeen = now;
    let b: Record<string, unknown>;
    try {
      const parsed: unknown = JSON.parse(raw.toString());
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error();
      b = parsed as Record<string, unknown>;
    } catch { c.ws.close(4002, 'SCHEMA'); return; }
    try {
      switch (b.t) {
        case 'ping': this.send(c, { t: 'pong', at: b.at, time: (this.deps.now ?? Date.now)() }); break;
        case 'join': this.join(c, b); break;
        case 'leave': this.depart(c, false); this.send(c, { t: 'departed' }); break;
        case 'input': this.input(c, b); break;
        case 'act': this.act(c, b); break;
        case 'appearance': this.dress(c, b); break;
        case 'fish': this.fish(c, b); break;
        default: throw new Error('SCHEMA');
      }
    } catch (error) {
      const code = error instanceof Error ? error.message : '';
      if (code === 'SCHEMA') c.ws.close(4002, 'SCHEMA');
      else this.send(c, { t: 'error', code: /^[A-Z_]{3,40}$/.test(code) ? code : 'ONLINE_UNAVAILABLE' });
    }
  }

  private join(c: Conn, b: Record<string, unknown>): void {
    if (typeof b.outpost !== 'string') throw new Error('SCHEMA');
    const at = Array.isArray(b.at) && b.at.length === 2 && b.at.every(v => typeof v === 'number' && Number.isFinite(v))
      ? b.at as [number, number] : undefined;
    if (b.appearance !== undefined) c.appearance = this.parseAppearance(b.appearance);
    // A rejoin of the room the player is already in is never refused (a pass running out does not kick, §11.5.1).
    const refused = this.deps.rooms.occupant(c.player)?.outpost === b.outpost ? null : this.deps.pass?.(c.player, b.outpost);
    if (refused) throw new Error(refused);
    this.depart(c, false);
    // SGODOT-218: the room kit this client draws; a newer kit of the outpost's puts it in that layout's instances.
    const layout = typeof b.layout === 'string' && /^[a-z0-9_]{1,40}$/.test(b.layout) ? b.layout : '';
    // q(311): the newcomer's places in order (a newer client's first join of a visit); the pairs that are not two
    // finite numbers are dropped, at most SPAWN_CANDIDATES_MAX read (OutpostRooms.join clamps each to the room).
    const spawns = Array.isArray(b.spawns) ? (b.spawns as unknown[]).slice(0, SPAWN_CANDIDATES_MAX).filter((p): p is [number, number] =>
      Array.isArray(p) && p.length === 2 && p.every(v => typeof v === 'number' && Number.isFinite(v))) : undefined;
    const placed = this.deps.rooms.join(c.player, b.outpost, at, layout, spawns);
    const me = this.deps.rooms.occupant(c.player)!;
    c.epoch++;
    this.send(c, { t: 'joined', protocol: 1, outpost: placed.outpost, room: placed.room, capacity: placed.capacity,
      rejoined: placed.rejoined, self: me.id, epoch: c.epoch, spawn: [me.x, me.z], snapshot_hz: 1000 / LIMITS.snapshot_ms });
    const members = this.deps.rooms.members(me.outpost, me.room, me.layout), mine = this.seenBy(c.player, members);
    this.send(c, { t: 'roster', count: mine.length, members: mine.map(m => this.view(m)) });
    for (const m of members) if (m.player !== c.player && this.sees(m.player, c.player))
      this.toPlayer(m.player, { t: 'peer', count: this.seenBy(m.player, members).length, member: this.view(me) });
    this.deps.joined?.(me);
  }

  /** Leaves the current instance and tells the others. `remember` keeps the place for a quick reconnect. */
  private depart(c: Conn, remember: boolean): void {
    c.fishing = undefined;
    const left = this.deps.rooms.leave(c.player, remember);
    if (!left) return;
    this.deps.departed?.(left);
    const members = this.deps.rooms.members(left.outpost, left.room, left.layout);
    for (const m of members) if (this.sees(m.player, left.player))
      this.toPlayer(m.player, { t: 'left', id: left.id, count: this.seenBy(m.player, members).length });
  }

  private input(c: Conn, b: Record<string, unknown>): void {
    const me = this.deps.rooms.occupant(c.player);
    if (!me || b.epoch !== c.epoch) return;
    if (!Number.isSafeInteger(b.seq) || Number(b.seq) < 0 || Number(b.seq) > 0xffffffff) throw new Error('SCHEMA');
    if (![b.x, b.z, b.yaw].every(v => typeof v === 'number' && Number.isFinite(v) && Math.abs(v) < 10000)) throw new Error('SCHEMA');
    if (Number(b.seq) <= me.seq) return;
    const seated = me.seat;
    const action = typeof b.action === 'string' && P0_ACTIONS.includes(b.action as typeof P0_ACTIONS[number]) && b.action !== 'sit' ? b.action : 'idle';
    this.deps.rooms.move(c.player, Number(b.x), Number(b.z), Number(b.yaw), action);
    me.seq = Number(b.seq);
    if (seated && !me.seat) this.seat(me);
  }

  private act(c: Conn, b: Record<string, unknown>): void {
    const me = this.deps.rooms.occupant(c.player);
    if (!Number.isSafeInteger(b.seq) || !['sit', 'stand'].includes(String(b.action))) throw new Error('SCHEMA');
    if (!me || b.epoch !== c.epoch) { this.send(c, { t: 'result', seq: b.seq, ok: false, code: 'NOT_IN_ROOM' }); return; }
    const before = me.seat;
    const node = String(b.node ?? '').slice(0, 40);
    let code: string = 'ok';
    if (b.action === 'stand') this.deps.rooms.stand(c.player);
    else {
      // The seat checked first, then the player put on its spot at once (SGODOT-478: not at walking speed, so the
      // glide onto it that follows is not "walking away"); a refused sit never moves the player.
      const at = Array.isArray(b.at) && b.at.length === 2 && b.at.every(v => typeof v === 'number' && Number.isFinite(v))
        ? [Number(b.at[0]), Number(b.at[1])] as [number, number] : undefined;
      code = this.deps.rooms.sitAt(c.player, node, at);
    }
    this.send(c, { t: 'result', seq: b.seq, ok: code === 'ok', code: code === 'ok' ? '' : code });
    if (me.seat !== before) this.seat(me);
  }

  private dress(c: Conn, b: Record<string, unknown>): void {
    const now = Date.now();
    if (now - c.dressedAt < LIMITS.appearance_ms) { this.send(c, { t: 'appearance_result', ok: false, code: 'APPEARANCE_RATE_LIMIT' }); return; }
    c.dressedAt = now;
    c.appearance = this.parseAppearance(b.appearance);
    this.send(c, { t: 'appearance_result', ok: true });
    const me = this.deps.rooms.occupant(c.player);
    if (!me) return;
    const members = this.deps.rooms.members(me.outpost, me.room, me.layout);
    for (const m of members) if (m.player !== c.player && this.sees(m.player, c.player))
      this.toPlayer(m.player, { t: 'peer', count: this.seenBy(m.player, members).length, member: this.view(me) });
  }

  /** A pond room's line (`{t:'fish', epoch, phase, target?, held?, fish?, outcome?, fish_id?}`), sent by the client as its
   * fishing panel changes phase (and as the reel's hold and the fish move); `phase: 'none'` takes the line in. Ignored
   * outside a pond room or for a stale epoch; a cast starts a new sequence, so the others draw a new line. */
  private fish(c: Conn, b: Record<string, unknown>): void {
    const me = this.deps.rooms.occupant(c.player);
    if (!me || b.epoch !== c.epoch || !pondOfRoom(me.outpost)) return;
    if (b.phase === 'none') { c.fishing = undefined; return; }
    const phase = FISH_PHASES.find(p => p === b.phase);
    if (!phase) throw new Error('SCHEMA');
    const now = Date.now();
    const [x0, x1, z0, z1] = this.deps.rooms.spec(me.outpost, me.layout)!.bounds;
    const target = Array.isArray(b.target) && b.target.length === 2 && b.target.every(v => typeof v === 'number' && Number.isFinite(v))
      ? [Math.min(x1, Math.max(x0, Number(b.target[0]))), Math.min(z1, Math.max(z0, Number(b.target[1])))] as [number, number] : undefined;
    const was = c.fishing;
    if (phase === 'casting' || !was) {
      if (!target) { if (phase === 'casting') throw new Error('SCHEMA'); return; }   // a line starts where it lands
      c.fishing = { sequence: ++c.casts, phase, at: now, castAt: now, target, held: false, fish: 0.5 };
    } else if (was.phase !== phase) { was.phase = phase; was.at = now; }
    const f = c.fishing!;
    if (typeof b.held === 'boolean') f.held = b.held;
    if (typeof b.fish === 'number' && Number.isFinite(b.fish)) f.fish = Math.min(1, Math.max(0, b.fish));
    if (phase === 'result') {
      f.outcome = b.outcome === 'caught' ? 'caught' : 'escaped';
      f.fishId = f.outcome === 'caught' && typeof b.fish_id === 'string' && /^[a-z0-9_]{1,40}$/.test(b.fish_id) ? b.fish_id : undefined;
      f.held = false;
    }
  }

  /** One line as the others draw it: ages in seconds from its phase's and its cast's start. */
  private fishingView(id: number, f: Fishing, now: number) {
    return { id, sequence: f.sequence, target: f.target, phase: f.phase, age: Math.max(0, now - f.at) / 1000,
      cast_age: Math.max(0, now - f.castAt) / 1000, held: f.held, fish: f.fish,
      ...(f.outcome ? { outcome: f.outcome } : {}), ...(f.fishId ? { fish_id: f.fishId } : {}) };
  }

  private parseAppearance(raw: unknown): Appearance {
    if (this.deps.appearances) return this.deps.appearances.parse(raw);
    if (!raw || typeof raw !== 'object' || JSON.stringify(raw).length > 900) throw new Error('APPEARANCE_INVALID');
    return raw as Appearance;
  }

  /** Seat changes go to everyone in the instance (the frame's action says sit; this says which seat). */
  private seat(me: Occupant): void {
    for (const m of this.deps.rooms.members(me.outpost, me.room, me.layout))
      if (this.sees(m.player, me.player)) this.toPlayer(m.player, { t: 'seat', id: me.id, seat: me.seat });
  }

  /** Whether `viewer` sees `other` in their room: themselves always, anyone but a Block either way (hides). */
  private sees(viewer: string, other: string): boolean { return viewer === other || !this.deps.hides?.(viewer, other); }
  private seenBy(viewer: string, members: Occupant[]): Occupant[] {
    return this.deps.hides ? members.filter(m => this.sees(viewer, m.player)) : members;
  }

  /** A Block or Unblock between two players (P0Voice): sharing a room, each goes out of the other's view at once (left),
   * or comes back into it (peer). */
  seenChanged(a: string, b: string): void {
    const oa = this.deps.rooms.occupant(a), ob = this.deps.rooms.occupant(b);
    if (!oa || !ob || oa.outpost !== ob.outpost || oa.layout !== ob.layout || oa.room !== ob.room) return;
    const members = this.deps.rooms.members(oa.outpost, oa.room, oa.layout);
    for (const [to, other] of [[oa, ob], [ob, oa]] as const) {
      const count = this.seenBy(to.player, members).length;
      this.toPlayer(to.player, this.sees(to.player, other.player) ? { t: 'peer', count, member: this.view(other) } : { t: 'left', id: other.id, count });
    }
  }

  private view(m: Occupant) {
    return { id: m.id, player: publicPlayer(m.player), seat: m.seat, appearance: this.byPlayer.get(m.player)?.appearance ?? defaultAppearance() };
  }

  private step(): void {
    this.tick++;
    const now = Date.now();
    for (const c of this.conns) if (now - c.lastSeen > LIMITS.idle_ms) c.ws.terminate();
    this.deps.rooms.sweep();
    const groups = new Map<string, Occupant[]>();
    for (const c of this.conns) {
      const me = this.deps.rooms.occupant(c.player);
      if (!me || this.byPlayer.get(c.player) !== c) continue;
      const key = me.outpost + '@' + me.layout + ':' + me.room;
      if (!groups.has(key)) groups.set(key, this.deps.rooms.members(me.outpost, me.room, me.layout));
      if (c.ws.bufferedAmount > LIMITS.close_bytes) { c.ws.close(1013, 'SLOW_CLIENT'); continue; }
      if (c.ws.bufferedAmount > LIMITS.skip_bytes || c.ws.readyState !== WebSocket.OPEN) continue;
      c.ws.send(snapshotFrame(this.tick, c.epoch, this.seenBy(c.player, groups.get(key)!)));
    }
    if (this.tick % LIMITS.fishing_ticks === 0) this.fishingStep(now, groups);
  }

  /** The pond rooms' lines to everyone in them, while anyone there has one out (a result goes after LIMITS.result_ms). */
  private fishingStep(now: number, groups: Map<string, Occupant[]>): void {
    for (const members of groups.values()) {
      if (!members.length || !members[0].outpost.startsWith(POND_ROOM)) continue;
      const lines: { player: string; line: ReturnType<P0OnlineHub['fishingView']> }[] = [];
      for (const m of members) {
        const c = this.byPlayer.get(m.player);
        if (c?.fishing?.phase === 'result' && now - c.fishing.at > LIMITS.result_ms) c.fishing = undefined;
        if (c?.fishing) lines.push({ player: m.player, line: this.fishingView(m.id, c.fishing, now) });
      }
      if (!lines.length) continue;
      for (const m of members) {
        const c = this.byPlayer.get(m.player);
        if (c) this.send(c, { t: 'fishing', epoch: c.epoch,
          members: lines.filter(l => l.player !== m.player && this.sees(m.player, l.player)).map(l => l.line) });
      }
    }
  }

  /** A message to one player's socket, from outside the hub (P0Voice's voice_blocks). */
  tell(player: string, payload: object): void { this.toPlayer(player, payload); }

  private toPlayer(player: string, payload: object): void {
    const c = this.byPlayer.get(player);
    if (c) this.send(c, payload);
  }

  private send(c: Conn, payload: object): void {
    if (c.ws.readyState === WebSocket.OPEN) c.ws.send(JSON.stringify(payload));
  }
}

/** What the room sees of a player (11-02): x-p0-player is the P0 server's only credential (with the shared demo key), so a
 * roster never carries it — a stable, one-way handle instead (16 hex of its SHA-256). The clients use the field for the
 * name tag (its first 4: `Traveller 8c3f`, no prefix to show — 奕星 on #646) and the outfit cache only, so an older
 * client reads it as before. */
export const publicPlayer = (player: string): string => createHash('sha256').update('p0-online/' + player).digest('hex').slice(0, 16);

/** Registers the WebSocket upgrade and the presence route; tools/p0_server.ts only calls this. */
export function registerP0Online(app: FastifyInstance, deps: P0OnlineDeps): P0OnlineHub {
  const hub = new P0OnlineHub(deps);
  app.server.on('upgrade', (req, socket, head) => {
    if (req.url?.split('?')[0] === PATH) hub.upgrade(req, socket, head);
  });
  // Ponds' rooms count apart (`ponds`, by pond id): an older client reads `outposts` only (亚瑟 on the 11-02 plan);
  // landmarks' too (`landmarks`, by landmark id, SGODOT-462), never among the outposts an older client looks up
  app.get('/v1/p0/presence', async () => {
    const outposts: Record<string, { online: number; rooms: number }> = {}, ponds: typeof outposts = {}, landmarks: typeof outposts = {};
    for (const [id, p] of Object.entries(deps.rooms.presence())) {
      const pond = pondOfRoom(id), landmark = landmarkOfRoom(id);
      if (pond) ponds[pond] = p;
      else if (landmark) landmarks[landmark] = p;
      else outposts[id] = p;
    }
    return { ok: true, outposts, ponds, landmarks };
  });
  app.addHook('preClose', async () => hub.close());
  return hub;
}
