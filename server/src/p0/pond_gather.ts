/**
 * Gathering in the ponds (v4q(11), SGODOT-409; the user 11-04, "C", and 11-05: in tonight's release). Every pond of every
 * city — hand-written, generated, and any city made later — holds gathering points on slots of its shape, worked out
 * here from the pond's id, the same on every server and never saved (as a generated city's places are, world.ts).
 *   - How many of each kind a city gets: a city with points in server/data/gather_points.json (a home city, or one of
 *     the nearest 10 of one) as many as there, every other city one of each T1 kind (v4q(4) ② "other"); then at least
 *     one point a pond (one more T1 Timber where a city has more ponds than points, v4q(11) ⑩).
 *   - Which pond: a home city's beginner pond holds Timber 2, Stone 2, Reeds 1, Clay 1 on fixed slots (v4q(11) ②, 408
 *     v2); the rest go round the city's other ponds. Any other city's go round all its ponds.
 *   - Which slot: from the 12 of the pond's shape (server/data/pond_slots.json, 408 v2, 上官婉儿 / 不知火舞): 1–3 seen
 *     on the opening screen, at most 2 within 3 m of the spawn, no two of a kind on `near` slots, a tall piece (Timber,
 *     Hardwood, Herb) never on a `low_only` slot nor where it `blocks` a chosen one, a slot with `pieces` only those.
 *     Tried in an order of the pond's own hash, so each pond has its own layout ("每个空间适当有变化").
 * A point's id is `<pond id>#<slot>`; gathering one needs the player in that pond (gathering.ts). The town's points
 * (gather_points.ts) stay as they were until the client leaves them.
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { P0Content } from './content.js';
import { gatherCatalogue } from './gather_points.js';
import { writtenCluster } from './home.js';
import { cityPlaces, hash32, placeOf, worldOf } from './world.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');

interface Slot {
  x: number; z: number; zone: string; opening_visible: boolean; spawn_m: number; low_only: boolean;
  stand: [number, number]; blocks: string[]; near: string[]; pieces?: string[];
}
interface KindRule { tier: string; word: string; yield: [string, number][] }
interface Rules { energy: number; cooldown_h: number; kinds: Record<string, KindRule> }

export interface PondPoint {
  id: string; pond: string; slot: string; kind: string; name: string; yield: [string, number][]; energy: number; cooldown_h: number;
  x: number; z: number; stand: [number, number];
}

const TALL = new Set(['wood', 'hardwood', 'herb']);
/** A home city's beginner pond (v4q(11) ②, 408 v2): Timber on C1 (crescent) or F1, Stone F2 and L1, Timber L2, Reeds L3, Clay R2. */
const BEGINNER = (shape: string): [string, string][] =>
  [[shape === 'crescent' ? 'C1' : 'F1', 'wood'], ['F2', 'stone'], ['L1', 'stone'], ['L2', 'wood'], ['L3', 'reed'], ['R2', 'clay']];

let slotFile: Record<string, Record<string, Slot>> | null = null;
const shapes = (): Record<string, Record<string, Slot>> =>
  (slotFile ??= (JSON.parse(readFileSync(path.join(ROOT, 'server/data/pond_slots.json'), 'utf8')) as { shapes: Record<string, Record<string, Slot>> }).shapes);
let handShapes: Map<string, string> | null = null;
/** The hand-written ponds' shapes (assets/p0/p0_ponds.json: San Francisco's, template_id). */
const handShape = (id: string): string | undefined => (handShapes ??= new Map(
  (JSON.parse(readFileSync(path.join(ROOT, 'assets/p0/p0_ponds.json'), 'utf8')) as { locations?: { id: string; template_id: string }[] }).locations
    ?.map(p => [p.id, p.template_id]) ?? [])).get(id);

const rulesOf = (c: P0Content) => (worldOf(c) as unknown as { gather_points?: Rules } | undefined)?.gather_points;
const homesOf = (c: P0Content): string[] =>
  [writtenCluster(c), ...((worldOf(c) as unknown as { home?: { cities?: string[] } } | undefined)?.home?.cities ?? [])];

interface CityPond { id: string; shape: string; beginner: boolean }
/** A city's ponds in a fixed order with their shapes: the hand-written ones by id, else the generator's. */
function pondsOf(c: P0Content, cluster: string): CityPond[] {
  if (cluster === writtenCluster(c)) {
    return Object.entries(c.fishing.places).filter(([, p]) => (p as { cluster?: string }).cluster === cluster).sort(([a], [b]) => (a < b ? -1 : 1))
      .map(([id, p]) => ({ id, shape: handShape(id) ?? 'crescent', beginner: !!(p as { beginner?: boolean }).beginner }));
  }
  return (cityPlaces(c, cluster)?.detail.ponds ?? []).map(p => ({ id: p.id, shape: p.template_id, beginner: !!p.beginner }));
}

/** How many of each kind the city gets (its town table's, else one of each T1), at least one a pond. */
function kindsOf(c: P0Content, cluster: string, ponds: number): string[] {
  const rules = rulesOf(c)!;
  const listed = gatherCatalogue(c)?.byCluster.get(cluster);
  const out: string[] = listed?.length ? listed.map(p => p.kind)
    : Object.entries(rules.kinds).filter(([, r]) => r.tier === 'T1').map(([k]) => k);
  while (out.length < ponds) out.push('wood');
  const order = Object.keys(rules.kinds);
  return out.sort((a, b) => order.indexOf(a) - order.indexOf(b));
}

/** Slots for these kinds on this shape, or null when none fit: tall pieces first, each slot tried in the pond's order. */
function place(pond: string, shape: Record<string, Slot>, kinds: string[]): [string, string][] | null {
  const names = Object.keys(shape).sort((a, b) => hash32('pond-slot', pond, a) - hash32('pond-slot', pond, b) || (a < b ? -1 : 1));
  const todo = [...kinds].sort((a, b) => Number(TALL.has(b)) - Number(TALL.has(a)));
  const chosen: [string, string][] = [];
  const ok = (slot: string, kind: string) => {
    const s = shape[slot];
    if (chosen.some(([x]) => x === slot)) return false;
    if (s.pieces && !s.pieces.includes(kind)) return false;
    if (TALL.has(kind) && (s.low_only || s.blocks.some(b => chosen.some(([x]) => x === b)))) return false;
    if (chosen.some(([x, k]) => TALL.has(k) && shape[x].blocks.includes(slot))) return false;
    if (chosen.some(([x, k]) => k === kind && (s.near.includes(x) || shape[x].near.includes(slot)))) return false;
    if (s.spawn_m <= 3 && chosen.filter(([x]) => shape[x].spawn_m <= 3).length >= 2) return false;
    if (s.opening_visible && chosen.filter(([x]) => shape[x].opening_visible).length >= 3) return false;
    return true;
  };
  const go = (i: number): boolean => {
    if (i === todo.length) return chosen.some(([x]) => shape[x].opening_visible);
    for (const slot of names) {
      if (!ok(slot, todo[i])) continue;
      chosen.push([slot, todo[i]]);
      if (go(i + 1)) return true;
      chosen.pop();
    }
    return false;
  };
  return go(0) ? chosen : null;
}

const cache = new WeakMap<P0Content, Map<string, PondPoint[]>>();
/** A city's ponds' points, worked out once and kept (a few dozen per city, only the cities someone is in). */
function cityPoints(c: P0Content, cluster: string): Map<string, PondPoint[]> {
  let byCity = cache.get(c);
  if (!byCity) cache.set(c, byCity = new Map());
  const out = new Map<string, PondPoint[]>();
  const rules = rulesOf(c), ponds = pondsOf(c, cluster);
  if (!rules || !ponds.length) return out;
  const hit = byCity.get(cluster);
  if (hit) { for (const p of hit) out.set(p.pond, [...(out.get(p.pond) ?? []), p]); return out; }
  const kinds = kindsOf(c, cluster, ponds.length);
  const plan = new Map<string, [string, string][] | string[]>(ponds.map(p => [p.id, [] as string[]]));
  let rest = ponds;
  const beginner = homesOf(c).includes(cluster) ? ponds.find(p => p.beginner) : undefined;
  if (beginner) {
    const fixed = BEGINNER(beginner.shape);
    for (const [, kind] of fixed) kinds.splice(kinds.indexOf(kind), 1);
    plan.set(beginner.id, fixed);
    rest = ponds.filter(p => p !== beginner);
  }
  // round the ponds, a kind at a time, so each pond gets a mix
  kinds.forEach((k, i) => (plan.get(rest[i % rest.length].id) as string[]).push(k));
  const all: PondPoint[] = [];
  for (const p of ponds) {
    const shape = shapes()[p.shape] ?? shapes().crescent;
    const want = plan.get(p.id)!;
    const slots = p === beginner ? want as [string, string][] : place(p.id, shape, want as string[]) ?? [];
    for (const [slot, kind] of slots) {
      const r = rules.kinds[kind], s = shape[slot];
      all.push({ id: `${p.id}#${slot}`, pond: p.id, slot, kind, name: r.word, yield: r.yield, energy: rules.energy, cooldown_h: rules.cooldown_h,
        x: s.x, z: s.z, stand: s.stand });
    }
  }
  if (byCity.size > 2000) byCity.delete(byCity.keys().next().value!);
  byCity.set(cluster, all);
  for (const p of all) out.set(p.pond, [...(out.get(p.pond) ?? []), p]);
  return out;
}

/** The pond's city: a hand-written pond's own, a generated one's from its id. */
const clusterOfPond = (c: P0Content, pond: string): string | null =>
  (placeOf(c, pond) as { cluster?: string } | undefined)?.cluster ?? null;

/** A pond's points ([] for a pond nobody knows). */
export function pondPoints(c: P0Content, pond: string): PondPoint[] {
  const cluster = clusterOfPond(c, pond);
  return cluster ? cityPoints(c, cluster).get(pond) ?? [] : [];
}

/** A pond point by id (`<pond id>#<slot>`), or undefined. */
export function pondPointById(c: P0Content, id: unknown): PondPoint | undefined {
  if (typeof id !== 'string') return undefined;
  const cut = id.lastIndexOf('#');
  return cut > 0 ? pondPoints(c, id.slice(0, cut)).find(p => p.id === id) : undefined;
}

/** Every pond of a city with its points (in the city's pond order). */
export function cityPondPoints(c: P0Content, cluster: string): Map<string, PondPoint[]> {
  const out = new Map<string, PondPoint[]>();
  const pts = cityPoints(c, cluster);
  for (const p of pondsOf(c, cluster)) out.set(p.id, pts.get(p.id) ?? []);
  return out;
}

/** A pond's shape (crescent / gourd / meander), as its scene is built. */
export function pondShape(c: P0Content, pond: string): string {
  const cluster = clusterOfPond(c, pond);
  return (cluster ? pondsOf(c, cluster).find(p => p.id === pond)?.shape : undefined) ?? 'crescent';
}

/** A pond's name, as its pin says it. */
export const pondName = (c: P0Content, pond: string): string => (placeOf(c, pond) as { name?: string } | undefined)?.name ?? '';

/** Whether these are the beginner pond's fixed slots (for tests). */
export const beginnerSlots = BEGINNER;
