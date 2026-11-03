/**
 * Enterable POIs (SGODOT-313; the user 11-03 "POI 提前"; plan pm/plans/poi-enter-plan-2026-11-03.md, q row pending): a
 * map POI the template table picks a kit for opens a room of its own, `poi:<template>@<city cluster>:<12 hex>` — the hex
 * the client's hash of the tile feature id, which changes when Mapbox updates its tiles: a room key only, never saved.
 * The table (assets/p0/poi_templates.json) is the client's too: capacity, and each template's kit, walls and seats.
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const POI_ROOM = 'poi:';
const POI_ROOM_RE = /^poi:([a-z][a-z0-9_]{0,31})@(gn-[0-9]{1,12}):([0-9a-f]{12})$/;
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
export const DEFAULT_POI_TEMPLATES = path.join(ROOT, 'assets/p0/poi_templates.json');

export interface PoiTemplate { art: string; door: string; bounds: [number, number, number, number]; seats: string[] }
export interface PoiTable { capacity: number; templates: Record<string, PoiTemplate>; maki: Record<string, string>; class: Record<string, string> }
export interface PoiRoom { template: string; cluster: string; key: string }

/** The table, checked: a capacity of 2–64, each template with a kit, walls and distinct seat_ names, every maki / class
 * row naming a template there. */
export function loadPoiTemplates(file = DEFAULT_POI_TEMPLATES): PoiTable {
  const t = JSON.parse(readFileSync(file, 'utf8')) as PoiTable;
  if (!Number.isInteger(t.capacity) || t.capacity < 2 || t.capacity > 64 || !t.templates || typeof t.templates !== 'object') throw new Error('POI_SCHEMA');
  for (const [id, p] of Object.entries(t.templates)) {
    const [x0, x1, z0, z1] = p.bounds ?? [];
    if (!/^[a-z][a-z0-9_]{0,31}$/.test(id) || !p.art || !p.door || !(x0 < x1 && z0 < z1) || !Array.isArray(p.seats) ||
      p.seats.some(s => !/^seat_[a-z0-9_]+$/.test(s)) || new Set(p.seats).size !== p.seats.length) throw new Error('POI_SCHEMA:' + id);
  }
  for (const rows of [t.maki ?? {}, t.class ?? {}]) for (const [k, v] of Object.entries(rows)) if (!t.templates[v]) throw new Error('POI_SCHEMA:' + k);
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
  return (room: string): { id: string; role: 'poi'; capacity: number; bounds: [number, number, number, number]; seats: string[] } | undefined => {
    const p = parsePoiRoom(room);
    const t = p ? table.templates[p.template] : undefined;
    if (!p || !t || !city(p.cluster)) return undefined;
    return { id: room, role: 'poi', capacity: table.capacity, bounds: t.bounds, seats: t.seats };
  };
}

/** The template a map POI opens (its maki, else its class), or "" — no Go in. */
export function templateFor(table: PoiTable, maki: string, cls: string): string {
  return table.maki[maki] ?? table.class[cls] ?? '';
}
