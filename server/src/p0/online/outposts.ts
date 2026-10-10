/** P0 outpost table (assets/p0/p0_outposts.json), shared with the client: id, role, capacity, bounds, seats. */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { OutpostRole, OutpostSpec } from './rooms.js';

export const DEFAULT_P0_OUTPOSTS = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../../assets/p0/p0_outposts.json');
const ROLES: OutpostRole[] = ['tackle', 'tea', 'post', 'market'];
const ID_RE = /^[a-z0-9_]{3,40}$/;

export interface OutpostEntry extends OutpostSpec { name: string; category: string; lat: number; lng: number; art: string; anchors: string }

export function loadOutposts(file = DEFAULT_P0_OUTPOSTS): OutpostEntry[] {
  const data = JSON.parse(readFileSync(file, 'utf8')) as { version: number; outposts: OutpostEntry[] };
  if (data.version !== 1 || !Array.isArray(data.outposts)) throw new Error('OUTPOSTS_SCHEMA');
  const seen = new Set<string>();
  for (const o of data.outposts) {
    const [x0, x1, z0, z1] = o.bounds ?? [];
    if (!ID_RE.test(o.id) || seen.has(o.id) || !ROLES.includes(o.role) || !Number.isInteger(o.capacity) || o.capacity < 1 || o.capacity > 64 ||
      !(x0 < x1 && z0 < z1) || !Array.isArray(o.seats) || o.seats.some(s => !/^seat_[a-z0-9_]+$/.test(s)) || new Set(o.seats).size !== o.seats.length)
      throw new Error('OUTPOSTS_SCHEMA:' + String(o.id));
    seen.add(o.id);
  }
  return data.outposts;
}

/**
 * The room spec of a generated outpost (SGODOT-280, `gn-1850147~market0`): its capacity from the generator, and the walls
 * and seats of the hand-written room its art stands in for (the placeholder rooms until the five layouts are designed,
 * world_gen.json `room`). Undefined for an id the generator does not know.
 */
export function generatedOutpostSpec(table: OutpostEntry[], detail: (outpost: string) => { role: string; art: string; capacity: number } | undefined) {
  const byArt = new Map(table.map(o => [o.art, o]));
  return (outpost: string): OutpostSpec | undefined => {
    if (outpost.indexOf('~') <= 0) return undefined;
    const d = detail(outpost);
    const room = d ? byArt.get(d.art) : undefined;
    if (!d || !room || !ROLES.includes(d.role as OutpostRole)) return undefined;
    return { id: outpost, role: d.role as OutpostRole, capacity: d.capacity, bounds: room.bounds, seats: room.seats };
  };
}
