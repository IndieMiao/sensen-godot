/**
 * Wild sites (v4q(3), SGODOT-355; v4 §1.4–1.5): the catalogue tools/wild_sites_build.ts made (server/data/wild_sites.json),
 * read once. A site is `wd-<row>-<col>` (one per 0.5° cell, added to, never taken away from); batch 1 opens quarries and
 * veins, the rest stay in the catalogue, off the map. Per player: the nearest 3 open sites from the home's base point
 * (q(184), as the nearest 3 cities) are free for good, with a quarry and a vein among them; the map reads the sites in its
 * viewport (GET /v1/p0/wild), at most VIEWPORT_CAP, the free, visited and nearest first.
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { distanceKm, tripByKm } from './clusters.js';
import type { P0Content } from './content.js';
import { clusterById, homeBase, homeOf } from './home.js';
import type { P0State } from './state.js';
import { worldOf } from './world.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
export const WILD_PREFIX = 'wd-';
export const VIEWPORT_CAP = 40;
/** Below this zoom the map is a continent's: no wild pins (contract-c §4; the frames may move it). */
export const VIEWPORT_MIN_ZOOM = 6;

export interface WildMine { floors: number; main: string; main_from: number; side: number | null; open_to: number | null }
export interface WildSite {
  id: string; type: string; lat: number; lng: number; name: string; short: string;
  near: string; near_name: string; climate: string; continent: string; coastal: boolean; open: boolean; mine?: WildMine;
}
interface MineRule { mains: string[]; main_from: number; open_to?: number }
interface WildRules { grid_deg: number; open: string[]; mines: Record<string, MineRule>; type_words: Record<string, string> }
interface WildTable { seed: string; revision: number; grid_deg: number; types: string[]; fields: string[]; rows: unknown[][] }

export interface Catalogue { revision: number; grid: number; byId: Map<string, WildSite> }
const loaded = new WeakMap<object, Catalogue | null>();

export const isWild = (id: unknown): id is string => typeof id === 'string' && id.startsWith(WILD_PREFIX);
const rulesOf = (c: P0Content) => (worldOf(c) as unknown as { wild?: WildRules } | undefined)?.wild;

/** The catalogue made from a table: the world's own (seed and revision) or an error — another world's points are never used. */
export function catalogueOf(c: P0Content, table: WildTable): Catalogue {
  const w = worldOf(c), rules = rulesOf(c);
  if (!w || !rules) throw new Error('world_gen.json has no world / wild block');
  if (table.seed !== w.seed || table.revision !== w.revision) {
    throw new Error(`server/data/wild_sites.json is for seed ${table.seed} revision ${table.revision}, the world is ${w.seed} revision ${w.revision}: rerun tools/wild_sites_build.ts`);
  }
  const at = (f: string) => table.fields.indexOf(f);
  const [row, col, lat, lng, type, main, side, floors, coastal, near, word] =
    ['row', 'col', 'lat', 'lng', 'type', 'main', 'side', 'floors', 'coastal', 'near', 'word'].map(at);
  const byId = new Map<string, WildSite>();
  for (const r of table.rows) {
    const t = table.types[r[type] as number], cl = clusterById(c, r[near] as string), id = `${WILD_PREFIX}${r[row]}-${r[col]}`;
    const s: WildSite = { id, type: t, lat: r[lat] as number, lng: r[lng] as number, name: `${r[word]} ${rules.type_words[t]}`,
      short: r[word] as string, near: r[near] as string, near_name: cl?.name ?? '', climate: cl?.climate ?? '',
      continent: cl?.continent ?? '', coastal: r[coastal] === 1, open: rules.open.includes(t) };
    const rule = rules.mines[t];
    if (rule) {
      s.mine = { floors: r[floors] as number, main: r[main] as string, main_from: rule.main_from, side: r[side] as number | null,
        open_to: rule.open_to === undefined ? null : rule.open_to };
    }
    byId.set(id, s);
  }
  return { revision: table.revision, grid: table.grid_deg, byId };
}

/** The catalogue, read once per content; null when the file is not there (no wild sites: every lookup is empty). */
export function catalogue(c: P0Content): Catalogue | null {
  if (!loaded.has(c)) {
    let table: WildTable | null = null;
    try { table = JSON.parse(readFileSync(path.join(ROOT, 'server/data/wild_sites.json'), 'utf8')) as WildTable; }
    catch { table = null; }
    loaded.set(c, table && rulesOf(c) ? catalogueOf(c, table) : null);
  }
  return loaded.get(c)!;
}
/** Tests and tools: a catalogue given, not read. */
export const useCatalogue = (c: P0Content, cat: Catalogue | null) => { loaded.set(c, cat); };

export const wildById = (c: P0Content, id: unknown): WildSite | undefined => (isWild(id) ? catalogue(c)?.byId.get(id) : undefined);

/** Open sites within km of a point, nearest first (ties by id). */
function around(cat: Catalogue, at: { lat: number; lng: number }, km: number): { s: WildSite; km: number }[] {
  const g = cat.grid, cols = Math.round(360 / g);
  const dr = Math.ceil(km / 111.2 / g) + 1, dc = Math.min(cols / 2, Math.ceil(km / (111.2 * Math.max(0.05, Math.cos(at.lat * Math.PI / 180))) / g) + 1);
  const r0 = Math.floor((at.lat + 90) / g), c0 = Math.floor((at.lng + 180) / g), out: { s: WildSite; km: number }[] = [];
  for (let r = r0 - dr; r <= r0 + dr; r++) for (let k = c0 - dc; k <= c0 + dc; k++) {
    const s = cat.byId.get(`${WILD_PREFIX}${r}-${((k % cols) + cols) % cols}`);
    if (!s || !s.open) continue;
    const d = distanceKm(at, s);
    if (d <= km) out.push({ s, km: d });
  }
  return out.sort((a, b) => a.km - b.km || (a.s.id < b.s.id ? -1 : 1));
}

/**
 * v4 §1.5: the nearest 3 open wild sites from a home's base point (q(184)), with at least one quarry and one vein — the
 * nearest of a missing type takes the place of the farthest that is not the only one of its type. Frozen into the save
 * with the city fallback (travel.wild_near3) and worked out again when the home changes.
 */
export function wildNearOf(c: P0Content, home: string): string[] {
  const cat = catalogue(c), at = homeBase(c, { travel: { home } });
  if (!cat || !at) return [];
  // the search widens until it finds what it wants: three sites, then a missing type wherever it is (李白 on v4q(3) ③a)
  const nearest = (want: (x: WildSite) => boolean, n: number) => {
    let found: { s: WildSite; km: number }[] = [];
    for (let km = 150; km <= 20_000 && found.length < n; km *= 2) found = around(cat, at, km).filter(x => want(x.s));
    return found.slice(0, n);
  };
  const pick = nearest(() => true, 3);
  for (const need of ['quarry', 'vein']) {
    if (pick.some(x => x.s.type === need)) continue;
    const add = nearest(x => x.type === need, 1)[0];
    if (!add) continue;
    // drop the farthest pick whose type another pick also has (else the farthest)
    let drop = -1;
    for (let i = pick.length - 1; i >= 0 && drop < 0; i--) if (pick.filter(x => x.s.type === pick[i].s.type).length > 1) drop = i;
    pick.splice(drop < 0 ? pick.length - 1 : drop, 1);
    pick.push(add);
  }
  return pick.sort((a, b) => a.km - b.km || (a.s.id < b.s.id ? -1 : 1)).map(x => x.s.id);
}

/** The save's frozen nearest 3, else worked out now (a save made before the catalogue). */
export const wildNear3 = (c: P0Content, s: P0State): string[] =>
  (s.travel as { wild_near3?: string[] }).wild_near3 ?? wildNearOf(c, homeOf(c, s));

/** A site as the player sees it: the catalogue's fields and theirs (contract-c §3). */
export function siteFor(c: P0Content, s: P0State, site: WildSite, now: number, near3 = wildNear3(c, s)) {
  const at = homeBase(c, s), km = at ? distanceKm(at, site) : 0;
  const pass = s.travel.passes[site.id];
  return { ...site, km: Math.round(km * 10) / 10, trip: tripByKm(km), free: near3.includes(site.id), visited: !!s.travel.visits[site.id],
    pass_until: pass && pass.until > now ? pass.until : null, best_floor: 0 };
}

export interface Bbox { south: number; west: number; north: number; east: number }
/** `s,w,n,e` in degrees; a box over the 180° line has west > east. Null when it does not read as one. */
export function parseBbox(text: unknown): Bbox | null {
  const p = String(text ?? '').split(',').map(Number);
  if (p.length !== 4 || p.some(x => !Number.isFinite(x))) return null;
  const [south, west, north, east] = p;
  if (south < -90 || north > 90 || south > north || Math.abs(west) > 180 || Math.abs(east) > 180) return null;
  return { south, west, north, east };
}

/**
 * contract-c §4: the open sites in a viewport, at most VIEWPORT_CAP — the free first, then the visited, then the nearest
 * home (ties by id). `total` counts every open site in the box.
 */
export function viewport(c: P0Content, s: P0State, box: Bbox, zoom: number, now: number) {
  const cat = catalogue(c);
  if (!cat || !(zoom >= VIEWPORT_MIN_ZOOM)) return { revision: cat?.revision ?? 0, sites: [], capped: false, total: 0 };
  const g = cat.grid, cols = Math.round(360 / g);
  const r0 = Math.floor((box.south + 90) / g), r1 = Math.floor((box.north + 90) / g);
  const c0 = Math.floor((box.west + 180) / g), span = (((box.east - box.west) % 360) + 360) % 360, c1 = c0 + Math.floor(span / g) + 1;
  const inBox = (x: WildSite) => x.lat >= box.south && x.lat <= box.north
    && (box.west <= box.east ? x.lng >= box.west && x.lng <= box.east : x.lng >= box.west || x.lng <= box.east);
  const near3 = wildNear3(c, s), found: ReturnType<typeof siteFor>[] = [];
  for (let r = r0; r <= r1; r++) for (let k = c0; k <= c1; k++) {
    const x = cat.byId.get(`${WILD_PREFIX}${r}-${((k % cols) + cols) % cols}`);
    if (x && x.open && inBox(x)) found.push(siteFor(c, s, x, now, near3));
  }
  const rank = (x: ReturnType<typeof siteFor>) => (x.free ? 0 : x.visited ? 1 : 2);
  found.sort((a, b) => rank(a) - rank(b) || a.km - b.km || (a.id < b.id ? -1 : 1));
  return { revision: cat.revision, sites: found.slice(0, VIEWPORT_CAP), capped: found.length > VIEWPORT_CAP, total: found.length };
}
