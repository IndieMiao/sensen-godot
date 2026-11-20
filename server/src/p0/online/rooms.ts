/**
 * P0 outpost rooms (SGODOT-227): the server picks the instance (Room 1, Room 2 …) for each outpost,
 * holds seats and counts who is online. Pure state; the WebSocket hub drives it and owns the clock.
 */

/** Outpost roles, the same ids as the counter entries (open_keeper_greeting(role), SGODOT-224). */
export type OutpostRole = 'tackle' | 'tea' | 'post' | 'market' | 'mine_hut' | 'casino' | 'church' | 'pond' | 'landmark';   // casino: San Francisco's card room only (SGODOT-351); church: Grace Cathedral, a place to see (11-06); pond: a pond's room, `pond:<id>` (outposts.ts pondRoomSpec); landmark: `landmark:<id>` (landmarkRoomSpec, SGODOT-462)
export interface OutpostSpec {
  id: string;
  role: OutpostRole;
  /** Players per instance: indoor 12, Market Square 30 (§9.3.2). */
  capacity: number;
  /** Walkable box in room metres [min_x, max_x, min_z, max_z]; positions outside are clamped. */
  bounds: [number, number, number, number];
  /** Anchor names of the seats (seat_table1_1 …); empty when the space has none. */
  seats: string[];
  /** The room kit this spec's walls and seats are (p0_outposts.json `art`). */
  art?: string;
  /** The room older clients still draw while a newer kit takes its place (the market plaza over the fruit shop,
   * SGODOT-218): its kit, walls and seats. Those clients name no layout and stay in its instances; a client that names
   * `art` gets the new walls and seats in instances of its own, so neither sees the other through the other's walls. */
  before?: { art: string; bounds: [number, number, number, number]; seats: string[] };
  /** Set on a layout's own spec (`art`, over a `before`): '' for the room older clients have. */
  layout?: string;
}
export interface Occupant {
  player: string; outpost: string; room: number;
  /** The layout group (OutpostSpec.before): '' for the room older clients have, else the newer kit the client named. */
  layout: string;
  /** Small id within the instance, used in snapshot frames (lowest free, from 1). */
  id: number;
  x: number; z: number; yaw: number; action: string; seat: string;
  /** Last accepted input sequence and its time. */
  seq: number; at: number;
  /** When the player took its seat (ms; 0 or absent standing): SIT_SETTLE_MS on, its inputs are its own again. */
  satAt?: number;
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
/** SGODOT-478: a sit puts the player on the seat's spot (the client's `at`) at once, past walking speed, when it is this
 * near — a pew's middle is about 1.9 m along it from its aisle end (q(304)); further is TOO_FAR, nothing changes. */
export const SEAT_REACH_M = 3;
/** SGODOT-478: for this long after sitting the client's inputs leave the player on the seat — it is still gliding there
 * (0.3 s onto a chair, about 0.8 s along a pew) and each frame of the glide is further than STAND_DISTANCE from it, which
 * stood every sitter up one frame later (since the glide came, 10-08). After it, moving away stands up as ever. */
export const SIT_SETTLE_MS = 1500;
/** q(311): a newcomer's places, in the client's order (the spawn first, then the two rings of six round it): at most this
 * many are read (1 + 6 + 6); each is clamped to the room like any position. */
export const SPAWN_CANDIDATES_MAX = 13;
/** q(311): a place is free when nobody in the room stands this near it (about twice a body's radius). */
export const SPAWN_FREE_M = 0.45;

export class OutpostRooms {
  private specs = new Map<string, OutpostSpec>();
  private rooms = new Map<string, Map<number, Map<string, Occupant>>>();
  private byPlayer = new Map<string, Occupant>();
  private recent = new Map<string, { outpost: string; layout: string; room: number; until: number }>();

  /** Generated outposts (SGODOT-280, `gn-…~market0`) are not in the table: `resolve` gives their spec on first join, and
   * it is dropped again once their last room empties, so only places someone is in are kept (12,490 cities). */
  private fixed = new Set<string>();
  constructor(specs: OutpostSpec[], private now: () => number = Date.now,
    private resolve?: (outpost: string, layout: string) => OutpostSpec | undefined) {
    for (const spec of specs) {
      if (!Number.isInteger(spec.capacity) || spec.capacity < 1) throw new Error('BAD_CAPACITY');
      for (const one of layouts(spec)) {
        this.specs.set(groupOf(spec.id, one.layout ?? ''), one);
        this.fixed.add(groupOf(spec.id, one.layout ?? ''));
      }
    }
  }

  /** The spec of an outpost's room older clients have, or of the layout a newer client named. */
  spec(outpost: string, layout = ''): OutpostSpec | undefined { return this.specs.get(groupOf(outpost, layout)); }

  private specFor(outpost: string, layout: string): OutpostSpec | undefined {
    const known = this.specs.get(groupOf(outpost, layout));
    if (known || !this.resolve) return known;
    const made = this.resolve(outpost, layout);
    if (!made || made.id !== outpost || (made.layout ?? '') !== layout || !Number.isInteger(made.capacity) || made.capacity < 1) return undefined;
    this.specs.set(groupOf(outpost, layout), made);
    return made;
  }
  occupant(player: string): Occupant | undefined { return this.byPlayer.get(player); }

  /** Occupants of one instance, for rosters and snapshot frames. */
  members(outpost: string, room: number, layout = ''): Occupant[] {
    return [...(this.rooms.get(groupOf(outpost, layout))?.get(room)?.values() ?? [])];
  }

  /** Lowest-numbered instance with a free place, or the one this player just left. `layout`: the room kit the client
   * draws — a newer kit of the outpost's (OutpostSpec.before) puts it in that layout's instances; any other, or none
   * (every client before SGODOT-218), in the instances of the room older clients have, as before. `spawns` (q(311)): the
   * newcomer's places in order, from a client that sends them on its first join of a visit — it stands on the first
   * nobody in the room stands within SPAWN_FREE_M of (all of them, those who block each other too), or at `at` when none
   * is free; without them (older clients, a reconnect) at `at` as ever. */
  join(player: string, outpost: string, at: [number, number] = [0, 0], layout = '', spawns?: [number, number][]): Placement {
    if (layout && !this.specFor(outpost, layout)) layout = '';
    const spec = this.specFor(outpost, layout);
    if (!spec) throw new Error('UNKNOWN_OUTPOST');
    this.leave(player, false);
    const group = groupOf(outpost, layout);
    const rooms = this.rooms.get(group) ?? new Map<number, Map<string, Occupant>>();
    this.rooms.set(group, rooms);
    const free = (n: number) => (rooms.get(n)?.size ?? 0) < spec.capacity;
    const back = this.recent.get(player);
    let room = back && back.outpost === outpost && back.layout === layout && back.until >= this.now() && free(back.room) ? back.room : 0;
    const rejoined = room > 0;
    for (let n = 1; !room && n <= MAX_ROOMS; n++) if (free(n)) room = n;
    if (!room) throw new Error('SERVER_FULL');
    this.recent.delete(player);
    if (!rooms.has(room)) rooms.set(room, new Map());
    const members = rooms.get(room)!;
    const taken = new Set([...members.values()].map(m => m.id));
    let id = 1;
    while (taken.has(id)) id++;
    const [x, z] = spawns?.length ? freePlace(spec, [...members.values()], spawns, at) : clamp(spec, at);
    const occupant: Occupant = { player, outpost, layout, room, id, x, z, yaw: 0, action: 'idle', seat: '', seq: -1, at: this.now() };
    members.set(player, occupant);
    this.byPlayer.set(player, occupant);
    return { outpost, room, capacity: spec.capacity, rejoined };
  }

  /** Account deletion: discard both a live occupant and its reconnect location. */
  forget(player: string): Occupant | undefined {
    this.recent.delete(player);
    return this.leave(player, false);
  }

  /** Frees the seat and the place. `remember` keeps the instance for a quick reconnect. */
  leave(player: string, remember = true): Occupant | undefined {
    const o = this.byPlayer.get(player);
    if (!o) return undefined;
    this.byPlayer.delete(player);
    const group = groupOf(o.outpost, o.layout);
    const rooms = this.rooms.get(group)!;
    const members = rooms.get(o.room)!;
    members.delete(player);
    if (!members.size) rooms.delete(o.room);
    if (remember) this.recent.set(player, { outpost: o.outpost, layout: o.layout, room: o.room, until: this.now() + REJOIN_MS });
    if (!rooms.size && !this.fixed.has(group)) { this.rooms.delete(group); this.specs.delete(group); }   // made again on the next join
    return o;
  }

  /** Client-authoritative movement, kept inside the room and within walking speed of the last accepted spot. */
  move(player: string, x: number, z: number, yaw: number, action: string): Occupant | undefined {
    const o = this.byPlayer.get(player);
    if (!o) return undefined;
    const now = this.now();
    const reach = MAX_SPEED * Math.max(0, now - o.at) / 1000 + SLACK;
    let [nx, nz] = clamp(this.specs.get(groupOf(o.outpost, o.layout))!, [x, z]);
    const d = Math.hypot(nx - o.x, nz - o.z);
    if (d > reach) { nx = o.x + (nx - o.x) * reach / d; nz = o.z + (nz - o.z) * reach / d; }
    if (o.seat && now - (o.satAt ?? 0) < SIT_SETTLE_MS) {   // still gliding onto the seat: it stays there
      o.yaw = yaw; o.at = now; o.action = 'sit';
      return o;
    }
    if (o.seat && Math.hypot(nx - o.x, nz - o.z) > STAND_DISTANCE) o.seat = '';
    o.x = nx; o.z = nz; o.yaw = yaw; o.at = now;
    o.action = o.seat ? 'sit' : action;
    return o;
  }

  /** Whether this player may take the seat now (no state change). */
  canSit(player: string, seat: string): 'ok' | 'SEAT_TAKEN' | 'NO_SEAT' | 'NOT_IN_ROOM' {
    const o = this.byPlayer.get(player);
    if (!o) return 'NOT_IN_ROOM';
    if (!this.specs.get(groupOf(o.outpost, o.layout))!.seats.includes(seat)) return 'NO_SEAT';
    if (this.members(o.outpost, o.room, o.layout).some(m => m.seat === seat && m.player !== player)) return 'SEAT_TAKEN';
    return 'ok';
  }

  /** One player per seat. A player already seated elsewhere moves to the new seat. */
  sit(player: string, seat: string): 'ok' | 'SEAT_TAKEN' | 'NO_SEAT' | 'NOT_IN_ROOM' {
    const code = this.canSit(player, seat);
    if (code !== 'ok') return code;
    const o = this.byPlayer.get(player)!;
    o.seat = seat;
    o.action = 'sit';
    o.satAt = this.now();
    return 'ok';
  }

  /** A sit with the seat's spot (room metres, the client's): the seat checked first, then the player put there at once
   * (inside the room, within SEAT_REACH_M, else TOO_FAR) and seated. A refused sit never moves the player. */
  sitAt(player: string, seat: string, at?: [number, number]): 'ok' | 'SEAT_TAKEN' | 'NO_SEAT' | 'NOT_IN_ROOM' | 'TOO_FAR' {
    const code = this.canSit(player, seat);
    if (code !== 'ok' || !at) return code === 'ok' ? this.sit(player, seat) : code;
    const o = this.byPlayer.get(player)!;
    const [x, z] = clamp(this.specs.get(groupOf(o.outpost, o.layout))!, at);
    if (Math.hypot(x - o.x, z - o.z) > SEAT_REACH_M) return 'TOO_FAR';
    o.x = x; o.z = z; o.at = this.now();
    return this.sit(player, seat);
  }

  stand(player: string): void {
    const o = this.byPlayer.get(player);
    if (o?.seat) { o.seat = ''; o.action = 'idle'; o.satAt = 0; }
  }

  /** Online count per outpost across its instances, for the map pins ("Lotus Tea House · 5 online"): every
   * hand-written outpost, and a generated one while someone is in it — its layouts' instances together. */
  presence(): Record<string, { online: number; rooms: number }> {
    const out: Record<string, { online: number; rooms: number }> = {};
    for (const [group, spec] of this.specs) {
      const rooms = this.rooms.get(group);
      const sum = out[spec.id] ?? { online: 0, rooms: 0 };
      out[spec.id] = { online: sum.online + [...(rooms?.values() ?? [])].reduce((n, m) => n + m.size, 0), rooms: sum.rooms + (rooms?.size ?? 0) };
    }
    return out;
  }

  /** Everyone in any outpost room (all P0 outposts are in Shanghai): Ama's "N people around Shanghai". */
  total(): number { return this.byPlayer.size; }

  /** Drops expired reconnect reservations. */
  sweep(): void {
    const now = this.now();
    for (const [player, r] of this.recent) if (r.until < now) this.recent.delete(player);
  }
}

/** The instances an outpost's layout lives in: the outpost id itself for the room older clients have. */
const groupOf = (outpost: string, layout: string) => layout ? `${outpost}@${layout}` : outpost;

/** An outpost's specs by layout: one, or with a `before` the room older clients have ('') and its newer kit's. */
export function layouts(spec: OutpostSpec): OutpostSpec[] {
  if (!spec.before) return [spec];
  const { before, ...now } = spec;
  return [{ ...now, art: before.art, bounds: before.bounds, seats: before.seats, layout: '' }, { ...now, layout: spec.art ?? '' }];
}

/** q(311): the first of `spawns` (at most SPAWN_CANDIDATES_MAX, each clamped to the room) nobody in `others` stands
 * within SPAWN_FREE_M of; `at` clamped when none is. */
function freePlace(spec: OutpostSpec, others: Occupant[], spawns: [number, number][], at: [number, number]): [number, number] {
  for (const p of spawns.slice(0, SPAWN_CANDIDATES_MAX)) {
    const [x, z] = clamp(spec, p);
    if (others.every(o => Math.hypot(o.x - x, o.z - z) >= SPAWN_FREE_M)) return [x, z];
  }
  return clamp(spec, at);
}

function clamp(spec: OutpostSpec, [x, z]: [number, number]): [number, number] {
  const [x0, x1, z0, z1] = spec.bounds;
  const finite = (v: number, fallback: number) => Number.isFinite(v) ? v : fallback;
  return [Math.min(x1, Math.max(x0, finite(x, x0))), Math.min(z1, Math.max(z0, finite(z, z0)))];
}
