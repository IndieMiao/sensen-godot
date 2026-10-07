/**
 * P0 outpost rooms (SGODOT-227): the server picks the instance (Room 1, Room 2 …) for each outpost,
 * holds seats and counts who is online. Pure state; the WebSocket hub drives it and owns the clock.
 */

/** Outpost roles, the same ids as the counter entries (open_keeper_greeting(role), SGODOT-224). */
export type OutpostRole = 'tackle' | 'tea' | 'post' | 'market';
export interface OutpostSpec {
  id: string;
  role: OutpostRole;
  /** Players per instance: indoor 12, Market Square 30 (§9.3.2). */
  capacity: number;
  /** Walkable box in room metres [min_x, max_x, min_z, max_z]; positions outside are clamped. */
  bounds: [number, number, number, number];
  /** Anchor names of the seats (seat_table1_1 …); empty when the space has none. */
  seats: string[];
}
export interface Occupant {
  player: string; outpost: string; room: number;
  /** Small id within the instance, used in snapshot frames (lowest free, from 1). */
  id: number;
  x: number; z: number; yaw: number; action: string; seat: string;
  /** Last accepted input sequence and its time. */
  seq: number; at: number;
}
/** `rejoined`: back in the instance this player just left (no "Room 2" notice on a reconnect). */
export interface Placement { outpost: string; room: number; capacity: number; rejoined: boolean }

/** A reconnect within this window goes back to the same instance when it still has a free seat. */
export const REJOIN_MS = 60_000;
export const MAX_ROOMS = 99;
/** Walking speed plus slack for a late input; anything further in one step is clamped. */
export const MAX_SPEED = 6;
const SLACK = 0.5;
/** Moving this far from a seat stands the player up. */
const STAND_DISTANCE = 0.3;

export class OutpostRooms {
  private specs = new Map<string, OutpostSpec>();
  private rooms = new Map<string, Map<number, Map<string, Occupant>>>();
  private byPlayer = new Map<string, Occupant>();
  private recent = new Map<string, { outpost: string; room: number; until: number }>();

  constructor(specs: OutpostSpec[], private now: () => number = Date.now) {
    for (const spec of specs) {
      if (!Number.isInteger(spec.capacity) || spec.capacity < 1) throw new Error('BAD_CAPACITY');
      this.specs.set(spec.id, spec);
    }
  }

  spec(outpost: string): OutpostSpec | undefined { return this.specs.get(outpost); }
  occupant(player: string): Occupant | undefined { return this.byPlayer.get(player); }

  /** Occupants of one instance, for rosters and snapshot frames. */
  members(outpost: string, room: number): Occupant[] {
    return [...(this.rooms.get(outpost)?.get(room)?.values() ?? [])];
  }

  /** Lowest-numbered instance with a free place, or the one this player just left. */
  join(player: string, outpost: string, at: [number, number] = [0, 0]): Placement {
    const spec = this.specs.get(outpost);
    if (!spec) throw new Error('UNKNOWN_OUTPOST');
    this.leave(player, false);
    const rooms = this.rooms.get(outpost) ?? new Map<number, Map<string, Occupant>>();
    this.rooms.set(outpost, rooms);
    const free = (n: number) => (rooms.get(n)?.size ?? 0) < spec.capacity;
    const back = this.recent.get(player);
    let room = back && back.outpost === outpost && back.until >= this.now() && free(back.room) ? back.room : 0;
    const rejoined = room > 0;
    for (let n = 1; !room && n <= MAX_ROOMS; n++) if (free(n)) room = n;
    if (!room) throw new Error('SERVER_FULL');
    this.recent.delete(player);
    if (!rooms.has(room)) rooms.set(room, new Map());
    const members = rooms.get(room)!;
    const taken = new Set([...members.values()].map(m => m.id));
    let id = 1;
    while (taken.has(id)) id++;
    const [x, z] = clamp(spec, at);
    const occupant: Occupant = { player, outpost, room, id, x, z, yaw: 0, action: 'idle', seat: '', seq: -1, at: this.now() };
    members.set(player, occupant);
    this.byPlayer.set(player, occupant);
    return { outpost, room, capacity: spec.capacity, rejoined };
  }

  /** Frees the seat and the place. `remember` keeps the instance for a quick reconnect. */
  leave(player: string, remember = true): Occupant | undefined {
    const o = this.byPlayer.get(player);
    if (!o) return undefined;
    this.byPlayer.delete(player);
    const rooms = this.rooms.get(o.outpost)!;
    const members = rooms.get(o.room)!;
    members.delete(player);
    if (!members.size) rooms.delete(o.room);
    if (remember) this.recent.set(player, { outpost: o.outpost, room: o.room, until: this.now() + REJOIN_MS });
    return o;
  }

  /** Client-authoritative movement, kept inside the room and within walking speed of the last accepted spot. */
  move(player: string, x: number, z: number, yaw: number, action: string): Occupant | undefined {
    const o = this.byPlayer.get(player);
    if (!o) return undefined;
    const now = this.now();
    const reach = MAX_SPEED * Math.max(0, now - o.at) / 1000 + SLACK;
    let [nx, nz] = clamp(this.specs.get(o.outpost)!, [x, z]);
    const d = Math.hypot(nx - o.x, nz - o.z);
    if (d > reach) { nx = o.x + (nx - o.x) * reach / d; nz = o.z + (nz - o.z) * reach / d; }
    if (o.seat && Math.hypot(nx - o.x, nz - o.z) > STAND_DISTANCE) o.seat = '';
    o.x = nx; o.z = nz; o.yaw = yaw; o.at = now;
    o.action = o.seat ? 'sit' : action;
    return o;
  }

  /** One player per seat. A player already seated elsewhere moves to the new seat. */
  sit(player: string, seat: string): 'ok' | 'SEAT_TAKEN' | 'NO_SEAT' | 'NOT_IN_ROOM' {
    const o = this.byPlayer.get(player);
    if (!o) return 'NOT_IN_ROOM';
    if (!this.specs.get(o.outpost)!.seats.includes(seat)) return 'NO_SEAT';
    if (this.members(o.outpost, o.room).some(m => m.seat === seat && m.player !== player)) return 'SEAT_TAKEN';
    o.seat = seat;
    o.action = 'sit';
    return 'ok';
  }

  stand(player: string): void {
    const o = this.byPlayer.get(player);
    if (o?.seat) { o.seat = ''; o.action = 'idle'; }
  }

  /** Online count per outpost across its instances, for the map pins ("Lotus Tea House · 5 online"). */
  presence(): Record<string, { online: number; rooms: number }> {
    const out: Record<string, { online: number; rooms: number }> = {};
    for (const id of this.specs.keys()) {
      const rooms = this.rooms.get(id);
      out[id] = { online: [...(rooms?.values() ?? [])].reduce((sum, m) => sum + m.size, 0), rooms: rooms?.size ?? 0 };
    }
    return out;
  }

  /** Drops expired reconnect reservations. */
  sweep(): void {
    const now = this.now();
    for (const [player, r] of this.recent) if (r.until < now) this.recent.delete(player);
  }
}

function clamp(spec: OutpostSpec, [x, z]: [number, number]): [number, number] {
  const [x0, x1, z0, z1] = spec.bounds;
  const finite = (v: number, fallback: number) => Number.isFinite(v) ? v : fallback;
  return [Math.min(x1, Math.max(x0, finite(x, x0))), Math.min(z1, Math.max(z0, finite(z, z0)))];
}
