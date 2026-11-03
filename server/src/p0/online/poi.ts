/**
 * Enterable POIs (SGODOT-313; the user 11-03 "POI 提前"; q(279) eaf3edc1, pending the user; plan
 * pm/plans/poi-enter-plan-2026-11-03.md): a map POI the template table picks a kit for opens a room of its own,
 * `poi:<template>@<city cluster>:<12 hex>`. The hex is poiRoomKey: the first 12 lowercase hex of the SHA-256 of the
 * client's POI id as UTF-8 — `tile:<feature id>`, or `tile:<name>:<lon>:<lat>` for a feature without one (GodotMapPlugin.kt,
 * MapUnderlay.swift); Godot's `id.sha256_text().left(12)` (亚瑟, D). Every phone works it out alike, so one POI is one
 * room; the server only checks its form. The feature id changes when Mapbox updates its tiles: a room key only, never saved.
 * The table (assets/p0/poi_templates.json) is the client's too: capacity, each template's kit, door sign, walls and seats,
 * the maki / class rows that pick one, and the class names by maki.
 */
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { OutpostSpec } from './rooms.js';

export const POI_ROOM = 'poi:';
const POI_ROOM_RE = /^poi:([a-z][a-z0-9_]{0,31})@(gn-[0-9]{1,12}):([0-9a-f]{12})$/;
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
export const DEFAULT_POI_TEMPLATES = path.join(ROOT, 'assets/p0/poi_templates.json');

export interface PoiTemplate { art: string; door: string; sign: string; bounds: [number, number, number, number]; seats: string[] }
export interface PoiTable { capacity: number; templates: Record<string, PoiTemplate>; maki: Record<string, string>; class: Record<string, string>;
  /** The class name by maki (q(279) ⑥); a maki without one, or a POI picked by its class, takes its template's `door`. */
  names: Record<string, string>;
  /** Makis with no Go in whatever their class (q(279) ③: post offices wait for E9; religious ones, a card only); `*` ends a prefix. */
  skip: string[] }
export interface PoiRoom { template: string; cluster: string; key: string }

/** The table, checked: a capacity of 2–64, each template with a kit, its door's sign_ anchor, walls and distinct seat_
 * names, every maki / class row naming a template there, every name a maki row's. */
export function loadPoiTemplates(file = DEFAULT_POI_TEMPLATES): PoiTable {
  const t = JSON.parse(readFileSync(file, 'utf8')) as PoiTable;
  if (!Number.isInteger(t.capacity) || t.capacity < 2 || t.capacity > 64 || !t.templates || typeof t.templates !== 'object') throw new Error('POI_SCHEMA');
  for (const [id, p] of Object.entries(t.templates)) {
    const [x0, x1, z0, z1] = p.bounds ?? [];
    if (!/^[a-z][a-z0-9_]{0,31}$/.test(id) || !p.art || !p.door || !/^sign_[a-z0-9_]+$/.test(p.sign ?? '') || !(x0 < x1 && z0 < z1) || !Array.isArray(p.seats) ||
      p.seats.some(s => !/^seat_[a-z0-9_]+$/.test(s)) || new Set(p.seats).size !== p.seats.length) throw new Error('POI_SCHEMA:' + id);
  }
  for (const rows of [t.maki ?? {}, t.class ?? {}]) for (const [k, v] of Object.entries(rows)) if (!t.templates[v]) throw new Error('POI_SCHEMA:' + k);
  for (const [k, v] of Object.entries(t.names ?? {})) if (!t.maki[k] || typeof v !== 'string' || !v) throw new Error('POI_SCHEMA:' + k);
  return t;
}

/** A POI room id's parts, or null when it is none. */
export function parsePoiRoom(room: string): PoiRoom | null {
  const m = POI_ROOM_RE.exec(room);
  return m ? { template: m[1], cluster: m[2], key: m[3] } : null;
}

/** The room spec of a POI room whose template is in the table and whose city the content knows (`city`), undefined for
 * any other id: made on first join, dropped once its last room empties, as a pond's is. */
export function poiRoomSpec(table: PoiTable, city: (cluster: string) => boolean) {
  return (room: string): OutpostSpec | undefined => {
    const p = parsePoiRoom(room);
    const t = p ? table.templates[p.template] : undefined;
    if (!p || !t || !city(p.cluster)) return undefined;
    return { id: room, role: 'poi', capacity: table.capacity, bounds: t.bounds, seats: t.seats };
  };
}

/** The place requirePass judges a POI room by: its city's (`<cluster>~poi`, which clusterOf reads as that city), so
 * home's are free and another city's need its pass and being there, as its outposts do; "" when the id is no POI room. */
export function poiPassPlace(room: string): string {
  const p = parsePoiRoom(room);
  return p ? `${p.cluster}~poi` : '';
}

/** A POI id's room key: the first 12 hex of its SHA-256 (the client's the same way). */
export const poiRoomKey = (poiId: string): string => createHash('sha256').update(poiId, 'utf8').digest('hex').slice(0, 12);

/** A maki as the table reads it: Japan's tiles may give `hospital-JP`, `school-JP` (q(279) ③). */
const makiOf = (maki: string): string => maki.replace(/-JP$/, '');

const skipped = (table: PoiTable, maki: string): boolean =>
  (table.skip ?? []).some(k => (k.endsWith('*') ? maki.startsWith(k.slice(0, -1)) : maki === k));

/** The template a map POI opens (its maki, else its class), or "" — no Go in. */
export function templateFor(table: PoiTable, maki: string, cls: string): string {
  const m = makiOf(maki);
  return skipped(table, m) ? '' : table.maki[m] ?? table.class[cls] ?? '';
}

/** A POI's class name — its card subtitle, door and location chip (q(279) ⑥): by its maki, else its template's; "" with none. */
export function poiName(table: PoiTable, maki: string, cls: string): string {
  const template = templateFor(table, maki, cls);
  return template ? table.names[makiOf(maki)] ?? table.templates[template].door : '';
}
