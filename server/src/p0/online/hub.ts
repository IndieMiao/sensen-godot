/**
 * P0 outpost realtime rooms (SGODOT-227): WebSocket /v1/p0/online and GET /v1/p0/presence on the P0
 * playtest server. Same message shapes as the realtime gateway (joined / roster / peer / left / result)
 * and the same snapshot frame v1, so the client reuses OnlineCrowd. Identity is the x-p0-player header
 * (no token, local and dev servers only); presence lives in memory only, never in the P0 save file.
 * Positions are the client's: the server only keeps them inside the room and within walking speed.
 */
import type { FastifyInstance } from 'fastify';
import type { IncomingMessage } from 'node:http';
import type { Duplex } from 'node:stream';
import { WebSocket, WebSocketServer } from 'ws';
import { defaultAppearance, type Appearance, type AppearanceCatalog } from '../../realtime/appearance.js';
import { P0_ACTIONS, snapshotFrame } from './frame.js';
import { OutpostRooms, type Occupant } from './rooms.js';

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
};

interface Conn { ws: WebSocket; player: string; epoch: number; appearance: Appearance; tokens: number; tokenAt: number; lastSeen: number; dressedAt: number }
/** keys: the demo access keys (P0_ACCESS_KEYS, SGODOT-232 D1). The upgrade is not a Fastify request, so the
 * guard's onRequest hook never sees it: the hub checks x-p0-key itself. Empty or absent = no key (local playtests). */
export interface P0OnlineDeps { rooms: OutpostRooms; appearances?: AppearanceCatalog; now?: () => number; keys?: string[] }

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
    const player = String(req.headers['x-p0-player'] ?? '');
    if (!PLAYER_RE.test(player)) { socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'); return; }
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

  private accept(ws: WebSocket, player: string): void {
    const now = Date.now();
    const old = this.byPlayer.get(player);
    if (old) { this.depart(old, true); old.ws.close(4001, 'SESSION_REPLACED'); }
    const c: Conn = { ws, player, epoch: 0, appearance: defaultAppearance(), tokens: LIMITS.burst, tokenAt: now, lastSeen: now, dressedAt: 0 };
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
    this.depart(c, false);
    const placed = this.deps.rooms.join(c.player, b.outpost, at);
    const me = this.deps.rooms.occupant(c.player)!;
    c.epoch++;
    this.send(c, { t: 'joined', protocol: 1, outpost: placed.outpost, room: placed.room, capacity: placed.capacity,
      rejoined: placed.rejoined, self: me.id, epoch: c.epoch, spawn: [me.x, me.z], snapshot_hz: 1000 / LIMITS.snapshot_ms });
    const members = this.deps.rooms.members(me.outpost, me.room);
    this.send(c, { t: 'roster', count: members.length, members: members.map(m => this.view(m)) });
    for (const m of members) if (m.player !== c.player) this.toPlayer(m.player, { t: 'peer', count: members.length, member: this.view(me) });
  }

  /** Leaves the current instance and tells the others. `remember` keeps the place for a quick reconnect. */
  private depart(c: Conn, remember: boolean): void {
    const left = this.deps.rooms.leave(c.player, remember);
    if (!left) return;
    const members = this.deps.rooms.members(left.outpost, left.room);
    for (const m of members) this.toPlayer(m.player, { t: 'left', id: left.id, count: members.length });
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
      // Check the seat first; only then step onto it (the move from the stand point onto the chair is not
      // "walking away"), so a refused sit never moves the player.
      code = this.deps.rooms.canSit(c.player, node);
      if (code === 'ok' && Array.isArray(b.at) && b.at.length === 2 && b.at.every(v => typeof v === 'number' && Number.isFinite(v)))
        this.deps.rooms.move(c.player, Number(b.at[0]), Number(b.at[1]), me.yaw, 'idle');
      if (code === 'ok') code = this.deps.rooms.sit(c.player, node);
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
    const members = this.deps.rooms.members(me.outpost, me.room);
    for (const m of members) if (m.player !== c.player) this.toPlayer(m.player, { t: 'peer', count: members.length, member: this.view(me) });
  }

  private parseAppearance(raw: unknown): Appearance {
    if (this.deps.appearances) return this.deps.appearances.parse(raw);
    if (!raw || typeof raw !== 'object' || JSON.stringify(raw).length > 900) throw new Error('APPEARANCE_INVALID');
    return raw as Appearance;
  }

  /** Seat changes go to everyone in the instance (the frame's action says sit; this says which seat). */
  private seat(me: Occupant): void {
    for (const m of this.deps.rooms.members(me.outpost, me.room)) this.toPlayer(m.player, { t: 'seat', id: me.id, seat: me.seat });
  }

  private view(m: Occupant) {
    return { id: m.id, player: m.player, seat: m.seat, appearance: this.byPlayer.get(m.player)?.appearance ?? defaultAppearance() };
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
      const key = me.outpost + ':' + me.room;
      if (!groups.has(key)) groups.set(key, this.deps.rooms.members(me.outpost, me.room));
      if (c.ws.bufferedAmount > LIMITS.close_bytes) { c.ws.close(1013, 'SLOW_CLIENT'); continue; }
      if (c.ws.bufferedAmount > LIMITS.skip_bytes || c.ws.readyState !== WebSocket.OPEN) continue;
      c.ws.send(snapshotFrame(this.tick, c.epoch, groups.get(key)!));
    }
  }

  private toPlayer(player: string, payload: object): void {
    const c = this.byPlayer.get(player);
    if (c) this.send(c, payload);
  }

  private send(c: Conn, payload: object): void {
    if (c.ws.readyState === WebSocket.OPEN) c.ws.send(JSON.stringify(payload));
  }
}

/** Registers the WebSocket upgrade and the presence route; tools/p0_server.ts only calls this. */
export function registerP0Online(app: FastifyInstance, deps: P0OnlineDeps): P0OnlineHub {
  const hub = new P0OnlineHub(deps);
  app.server.on('upgrade', (req, socket, head) => {
    if (req.url?.split('?')[0] === PATH) hub.upgrade(req, socket, head);
  });
  app.get('/v1/p0/presence', async () => ({ ok: true, outposts: deps.rooms.presence() }));
  app.addHook('preClose', async () => hub.close());
  return hub;
}
