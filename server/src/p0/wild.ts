/**
 * Wild sites (v4q(3), SGODOT-355; v4 §1.4–1.5): the catalogue tools/wild_sites_build.ts made (server/data/wild_sites.json),
 * read once. A site is `wd-<row>-<col>` (one per 0.5° cell, added to, never taken away from); batch 1 opens quarries and
 * veins, geodes, abysses and ruins are grey pins (Not open yet), woods, waterside and bloom stay off the map. Per player:
 * the nearest 3 open sites from the home's base point (q(184), as the nearest 3 cities) are free for good, with a quarry
 * and a vein among them; the map reads the sites in its viewport (GET /v1/p0/wild), at most VIEWPORT_CAP, nearest the
 * home's base point first, ties by id (the same every time, q(137) ⑤; review B5).
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

/** A mine: a vein has one main (`main`), a quarry yields every main (`main` null) and is told apart by its side yield. */
export interface WildMine { floors: number; main: string | null; yields: string[]; main_from: number; side: number | null; open_to: number | null }
export interface WildSite {
  id: string; type: string; lat: number; lng: number; name: string; short: string; near: string; near_name: string;
  climate: string; continent: string; country: string; coastal: boolean; open: boolean; mine?: WildMine;
}
interface MineRule { mains: string[]; one_main?: boolean; main_from: number; open_to?: number }
interface WildRules { grid_deg: number; open: string[]; map: string[]; map_min_zoom: number; mines: Record<string, MineRule>; type_words: Record<string, string> }
interface WildTable { seed: string; revision: number; grid_deg: number; types: string[]; fields: string[]; rows: unknown[][] }

export interface Catalogue { revision: number; grid: number; byId: Map<string, WildSite>; map: Set<string>; minZoom: number }
const loaded = new WeakMap<object, Catalogue | null>();

export const isWild = (id: unknown): id is `wd-${string}` => typeof id === 'string' && id.startsWith(WILD_PREFIX);
const rulesOf = (c: P0Content) => (worldOf(c) as unknown as { wild?: WildRules } | undefined)?.wild;

/** The catalogue made from a table: the world's own (seed and revision) or an error — another world's points are never used. */
export function catalogueOf(c: P0Content, table: WildTable): Catalogue {
  const w = worldOf(c), rules = rulesOf(c);
  if (!w || !rules) throw new Error('world_gen.json has no world / wild block');
  if (table.seed !== w.seed || table.revision !== w.revision) {
    throw new Error(`server/data/wild_sites.json is for seed ${table.seed} revision ${table.revision}, the world is ${w.seed} revision ${w.revision}: rerun tools/wild_sites_build.ts`);
  }
  const at = (f: string) => table.fields.indexOf(f);
  const [row, col, lat, lng, type, main, side, floors, coastal, near, word, country] =
    ['row', 'col', 'lat', 'lng', 'type', 'main', 'side', 'floors', 'coastal', 'near', 'word', 'country'].map(at);
  const byId = new Map<string, WildSite>();
  for (const r of table.rows) {
    const t = table.types[r[type] as number], cl = clusterById(c, r[near] as string), id = `${WILD_PREFIX}${r[row]}-${r[col]}`;
    const s: WildSite = { id, type: t, lat: r[lat] as number, lng: r[lng] as number, name: `${r[word]} ${rules.type_words[t]}`,
      short: r[word] as string, near: r[near] as string, near_name: cl?.name ?? '', climate: cl?.climate ?? '',
      continent: cl?.continent ?? '', country: country >= 0 ? (r[country] as string) : '', coastal: r[coastal] === 1, open: rules.open.includes(t) };
    const rule = rules.mines[t];
    if (rule) {
      const m = (r[main] as string | null) ?? null;
      s.mine = { floors: r[floors] as number, main: m, yields: rule.one_main && m ? [m] : [...rule.mains], main_from: rule.main_from,
        side: r[side] as number | null, open_to: rule.open_to === undefined ? null : rule.open_to };
    }
    byId.set(id, s);
  }
  return { revision: table.revision, grid: table.grid_deg, byId, map: new Set(rules.map), minZoom: rules.map_min_zoom };
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
 * v4 §1.5 as the user set it (11-02 庚3, v4q(3) ③): the free 3 from a home's base point (q(184)) are the nearest quarry,
 * the nearest iron vein and the nearest quartz vein — one of each, however far (the search widens until it finds it), so
 * the first week's veins cost no fare (they were "at least one quarry and one vein": 6 of 13 homes paid for the second).
 * Nearest first, ties by id. Frozen into the save with the city fallback (travel.wild_near3) and worked out again when the
 * home changes; saves frozen under the old rule are frozen again with week 3's clean start (v4q(2)).
 */
export function wildNearOf(c: P0Content, home: string): string[] {
  const cat = catalogue(c), at = homeBase(c, { travel: { home } });
  if (!cat || !at) return [];
  const nearest = (want: (x: WildSite) => boolean) => {
    let found: { s: WildSite; km: number }[] = [];
    for (let km = 150; km <= 20_000 && !found.length; km *= 2) found = around(cat, at, km).filter(x => want(x.s));
    return found[0];
  };
  const pick = [nearest(x => x.type === 'quarry'), nearest(x => x.type === 'vein' && x.mine?.main === 'iron_ore'),
    nearest(x => x.type === 'vein' && x.mine?.main === 'quartz')].filter((x): x is { s: WildSite; km: number } => !!x);
  return pick.sort((a, b) => a.km - b.km || (a.s.id < b.s.id ? -1 : 1)).map(x => x.s.id);
}

/**
 * v4q(3) ③a, the priced guarantee (pending the user): from the home's base point, the nearest iron vein, the nearest
 * quartz vein and the nearest 2 quarries — what goes there costs at most Trip 2. Ties by id; frozen with the nearest 3
 * when the home is set or changed (travel.wild_priced).
 */
export function wildPricedOf(c: P0Content, home: string): string[] {
  const cat = catalogue(c), at = homeBase(c, { travel: { home } });
  if (!cat || !at) return [];
  const want: [(x: WildSite) => boolean, number][] = [
    [x => x.type === 'vein' && x.mine?.main === 'iron_ore', 1], [x => x.type === 'vein' && x.mine?.main === 'quartz', 1], [x => x.type === 'quarry', 2]];
  const out: string[] = [];
  for (const [is, n] of want) {
    let found: { s: WildSite; km: number }[] = [];
    for (let km = 150; km <= 20_000 && found.length < n; km *= 2) found = around(cat, at, km).filter(x => is(x.s));
    out.push(...found.slice(0, n).map(x => x.s.id));
  }
  return out;
}
export const wildPriced = (c: P0Content, s: P0State): string[] =>
  (s.travel as { wild_priced?: string[] }).wild_priced ?? wildPricedOf(c, homeOf(c, s));

/** The save's frozen nearest 3, else worked out now (a save made before the catalogue). */
export const wildNear3 = (c: P0Content, s: P0State): string[] => {
  const kept = (s.travel as { wild_near3?: string[] }).wild_near3;   // v7 gives [] until it is filled
  return kept?.length ? kept : wildNearOf(c, homeOf(c, s));
};

/** The free 3 as Today's vein row reads them (v4q(9), 亚瑟): near3's order (nearest first), each `{id, type, main, name,
 * lat, lng}` — `main` a vein's one main (`iron_ore` / `quartz`), null for a quarry; `name` the site's full name, the very
 * field its pin and its mine card show (`siteFor`'s, the viewport's); lat / lng for a Show that flies to a site the
 * viewport has not read yet (亚瑟, C part 2). */
export function near3Sites(c: P0Content, s: P0State, near3 = wildNear3(c, s)):
  { id: string; type: string; main: string | null; name: string; lat: number; lng: number }[] {
  return near3.map(id => wildById(c, id)).filter((x): x is WildSite => !!x)
    .map(x => ({ id: x.id, type: x.type, main: x.mine?.main ?? null, name: x.name, lat: x.lat, lng: x.lng }));
}

/** The nearest free vein of one main (`iron_ore`, `quartz`) — from the save's frozen 3, which hold one of each (庚3): the one
 * Today's vein row (`<name> · Reach Floor 10`) and Pip's line (`There's iron at <name>`) both name, so the two are always
 * the same mine (v4q(9); 亚瑟, 周瑜's Pip line reads this too). null when none of the 3 is one. */
export function nearestFreeVein(c: P0Content, s: P0State, main: string): { id: string; name: string } | null {
  const v = near3Sites(c, s).find(x => x.type === 'vein' && x.main === main);
  return v ? { id: v.id, name: v.name } : null;
}

/** A site as the player sees it: the catalogue's fields and theirs (contract-c §3); best_floor is the deepest floor they
 * reached in its mine (E's records, contract-efg §3), 0 before they went down. */
export function siteFor(c: P0Content, s: P0State, site: WildSite, now: number, near3 = wildNear3(c, s)) {
  const at = homeBase(c, s), km = at ? distanceKm(at, site) : 0;
  const pass = s.travel.passes[site.id];
  return { ...site, km: Math.round(km * 10) / 10, trip: tripByKm(km), free: near3.includes(site.id), visited: !!s.travel.visits[site.id],
    pass_until: pass && pass.until > now ? pass.until : null, best_floor: s.mine?.records?.[site.id]?.deepest ?? 0 };
}

export interface Bbox { south: number; west: number; north: number; east: number }
/** The widest box the viewport read takes, degrees each way: a phone at map_min_zoom sees far less (周瑜 on #616). */
export const BBOX_MAX_DEG = 20;
/** Degrees east from west to east; a box over the 180° line has west > east. */
const spanOf = (b: Bbox) => (b.east >= b.west ? b.east - b.west : b.east - b.west + 360);
/** `s,w,n,e` in degrees. Null when it does not read as one, or is wider than BBOX_MAX_DEG either way. */
export function parseBbox(text: unknown): Bbox | null {
  const p = String(text ?? '').split(',').map(Number);
  if (p.length !== 4 || p.some(x => !Number.isFinite(x))) return null;
  const [south, west, north, east] = p;
  if (south < -90 || north > 90 || south > north || Math.abs(west) > 180 || Math.abs(east) > 180) return null;
  const box = { south, west, north, east };
  return north - south > BBOX_MAX_DEG || spanOf(box) > BBOX_MAX_DEG ? null : box;
}

/**
 * contract-c §4: the map's sites in a viewport (open ones and grey pins), at most VIEWPORT_CAP — nearest the home's base
 * point first, ties by id (review B5: one order, the same however the camera moves). `total` counts them all in the box;
 * the cap counts wild pins only (the city's own pins are not in this read).
 */
export function viewport(c: P0Content, s: P0State, box: Bbox, zoom: number, now: number) {
  const cat = catalogue(c);
  if (!cat || !(zoom >= cat.minZoom)) return { revision: cat?.revision ?? 0, sites: [], capped: false, total: 0 };
  const g = cat.grid, cols = Math.round(360 / g);
  const r0 = Math.floor((box.south + 90) / g), r1 = Math.floor((box.north + 90) / g);
  const c0 = Math.floor((box.west + 180) / g), c1 = c0 + Math.floor(spanOf(box) / g) + 1;
  const inBox = (x: WildSite) => x.lat >= box.south && x.lat <= box.north
    && (box.west <= box.east ? x.lng >= box.west && x.lng <= box.east : x.lng >= box.west || x.lng <= box.east);
  const near3 = wildNear3(c, s), found: ReturnType<typeof siteFor>[] = [];
  for (let r = r0; r <= r1; r++) for (let k = c0; k <= c1; k++) {
    const x = cat.byId.get(`${WILD_PREFIX}${r}-${((k % cols) + cols) % cols}`);
    if (x && cat.map.has(x.type) && inBox(x)) found.push(siteFor(c, s, x, now, near3));
  }
  found.sort((a, b) => a.km - b.km || (a.id < b.id ? -1 : 1));
  return { revision: cat.revision, sites: found.slice(0, VIEWPORT_CAP), capped: found.length > VIEWPORT_CAP, total: found.length };
}
