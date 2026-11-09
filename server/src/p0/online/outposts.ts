/** P0 outpost table (assets/p0/p0_outposts.json), shared with the client: id, role, capacity, bounds, seats. */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { OutpostRole, OutpostSpec } from './rooms.js';

export const DEFAULT_P0_OUTPOSTS = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../../assets/p0/p0_outposts.json');
const ROLES: OutpostRole[] = ['tackle', 'tea', 'post', 'market', 'mine_hut', 'casino', 'church'];
const ID_RE = /^[a-z0-9_]{3,40}$/;

/** A generated place an online room can be made for (world.ts roomPlace): an outpost, or a Mine Hut with its own walls. */
export interface GeneratedRoomPlace { role: string; art: string; capacity: number; bounds?: [number, number, number, number]; seats?: string[];
  /** The kit newer clients draw for this room kind over `art` (world.room[kind].client_art). */
  client_art?: string }

export interface OutpostEntry extends OutpostSpec { name: string; category: string; lat: number; lng: number; art: string; anchors: string }

const BOX = (b: unknown): b is [number, number, number, number] =>
  Array.isArray(b) && b.length === 4 && b.every(v => Number.isFinite(v)) && b[0] < b[1] && b[2] < b[3];
const SEATS = (s: unknown): s is string[] =>
  Array.isArray(s) && s.every(n => typeof n === 'string' && /^seat_[a-z0-9_]+$/.test(n)) && new Set(s).size === s.length;

export function loadOutposts(file = DEFAULT_P0_OUTPOSTS): OutpostEntry[] {
  const data = JSON.parse(readFileSync(file, 'utf8')) as { version: number; outposts: OutpostEntry[] };
  if (data.version !== 1 || !Array.isArray(data.outposts)) throw new Error('OUTPOSTS_SCHEMA');
  const seen = new Set<string>();
  for (const o of data.outposts) {
    const [x0, x1, z0, z1] = o.bounds ?? [];
    if (!ID_RE.test(o.id) || seen.has(o.id) || !ROLES.includes(o.role) || !Number.isInteger(o.capacity) || o.capacity < 1 || o.capacity > 64 ||
      !(x0 < x1 && z0 < z1) || !Array.isArray(o.seats) || o.seats.some(s => !/^seat_[a-z0-9_]+$/.test(s)) || new Set(o.seats).size !== o.seats.length ||
      (o.before !== undefined && (typeof o.before.art !== 'string' || !o.before.art || o.before.art === o.art || !BOX(o.before.bounds) || !SEATS(o.before.seats))))
      throw new Error('OUTPOSTS_SCHEMA:' + String(o.id));
    seen.add(o.id);
  }
  return data.outposts;
}

/**
 * The room spec of a generated outpost (SGODOT-280, `gn-1850147~market0`): its capacity from the generator, and the walls
 * and seats of the hand-written room its art stands in for (the placeholder rooms until the five layouts are designed,
 * world_gen.json `room`), or the walls and seats its room gives itself (the Mine Hut: no hand-written room stands in for
 * it, q(204)). A kit no hand-written room is on any more falls back to the hand-written room of its role: the tackle
 * shop's, on its own kit since SGODOT-214 while generated ones still name the Farm Tools Store for 0.2.9 and older
 * (world_gen.json room.tackle.client_art). Undefined for an id the generator does not know. `layout`: a newer client's
 * kit that took the placeholder room's place (OutpostSpec.before; the market plaza, SGODOT-218) — that kit's walls and
 * seats, for that layout's instances; undefined for any other.
 */
export function generatedOutpostSpec(table: OutpostEntry[], detail: (outpost: string) => GeneratedRoomPlace | undefined) {
  const byArt = new Map<string, { bounds: [number, number, number, number]; seats: string[] }>(table.map(o => [o.art, o]));
  for (const o of table) if (o.before) byArt.set(o.before.art, o.before);
  // SGODOT-218: a layout of its own only for a kit that took a room's place (`before`): the market plaza, as the hand-written
  // square's. A kit newer clients draw over the server's for no such reason (the tackle shop's, SGODOT-214) shares its room.
  const newer = new Set(table.filter(o => o.before).map(o => o.art));
  return (outpost: string, layout = ''): OutpostSpec | undefined => {
    if (outpost.indexOf('~') <= 0) return undefined;
    const d = detail(outpost);
    if (!d || (layout && (!newer.has(layout) || layout !== d.client_art))) return undefined;
    const room = d.bounds && !layout ? { bounds: d.bounds, seats: d.seats ?? [] } : byArt.get(layout || d.art) ?? table.find(o => o.role === d.role);
    if (!room || !ROLES.includes(d.role as OutpostRole)) return undefined;
    return { id: outpost, role: d.role as OutpostRole, capacity: d.capacity, bounds: room.bounds, seats: room.seats, ...(layout ? { layout } : {}) };
  };
}

/** A pond's online room (11-02, the user's pond multiplayer via 奕星): `pond:<pond id>`. */
export const POND_ROOM = 'pond:';
/** Players per pond room (the user, 11-02: 8 to a pond). */
export const POND_CAPACITY = 8;
/** The pond scene's walkable meadow, x / z metres (PondScenery.MEADOW, Rect2(-3, -19, 18, 21)): every template's. */
export const POND_BOUNDS: [number, number, number, number] = [-3, 15, -19, 2];

/** The pond a `pond:<id>` room is for, or "" when the id is no pond room's. */
export const pondOfRoom = (room: string): string => room.startsWith(POND_ROOM) ? room.slice(POND_ROOM.length) : '';

/** The room spec of a pond the content knows (`known`: world.placeOf, hand-written or generated), no seats; undefined
 * for any other id. Made on first join and dropped once the pond's last room empties, as a generated outpost's is. */
export function pondRoomSpec(known: (pond: string) => boolean) {
  return (room: string): OutpostSpec | undefined => {
    const pond = pondOfRoom(room);
    if (!pond || !known(pond)) return undefined;
    return { id: room, role: 'pond', capacity: POND_CAPACITY, bounds: POND_BOUNDS, seats: [] };
  };
}
