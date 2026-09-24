import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { Content } from '../domain/content.js';
import { waterContains, type FishingSite, type FishingPoint } from '../domain/fishing.js';
import { walkable, type Navigation } from '../realtime/model.js';

export interface PondLocation {
  id: string; region_id: string; name: string; kind: 'pond'; category: string;
  lat: number; lng: number; template_id: string; decoration_seed: number;
  layout_revision: number; generation_version: number; enabled: boolean;
}
export interface PondTemplate {
  id: string; revision: number; extent: [number, number]; polygon: FishingPoint[];
  navigation: Navigation; fish_profile: string;
}
export interface PondRoom {
  location: PondLocation; revision: string; template: PondTemplate; site: FishingSite; capacity: number;
}
export const DEFAULT_POND_CATALOG = fileURLToPath(new URL('../../../assets/ponds/catalog.json', import.meta.url));

/** A published, immutable catalog is persisted alongside the server content.
 * Its separate fingerprint fences scene admission without rewriting farm saves.
 */
export class PondCatalog {
  readonly revision: string;
  readonly capacity: number;
  private readonly locations = new Map<string, PondLocation>();
  private readonly templates: Record<string, PondTemplate>;
  constructor(file = DEFAULT_POND_CATALOG) {
    const raw = readFileSync(file);
    const data = JSON.parse(raw.toString());
    if (data.version !== 1 || !Number.isInteger(data.room_capacity) || data.room_capacity < 1 || data.room_capacity > 300
      || !Array.isArray(data.locations) || data.locations.length > 10000 || !data.templates) throw new Error('POND_CATALOG_INVALID');
    this.capacity = data.room_capacity;
    this.revision = createHash('sha256').update(raw).digest('hex');
    this.templates = data.templates;
    for (const [id, template] of Object.entries(this.templates)) {
      if (template.id !== id || template.revision !== 1 || !Array.isArray(template.polygon)
        || template.polygon.length < 3 || template.polygon.length > 128 || template.extent?.length !== 2
        || !template.extent.every(n => Number.isFinite(n) && n > 0 && n <= 32)
        || !template.polygon.every(p => Array.isArray(p) && p.length === 2 && p.every(Number.isFinite)
          && p[0] > 0 && p[0] < template.extent[0] && p[1] < 0 && p[1] > -template.extent[1])) throw new Error('POND_TEMPLATE_INVALID');
      const nav = template.navigation;
      if (!nav || nav.cell !== .25 || nav.rows.length !== template.extent[1] / nav.cell
        || !nav.rows.every(row => row.length === template.extent[0] / nav.cell && /^[01]+$/.test(row))
        || !walkable(nav, nav.spawn) || waterContains({ polygon: template.polygon } as FishingSite, nav.spawn)) throw new Error('POND_NAVIGATION_INVALID');
    }
    for (const location of data.locations as PondLocation[]) {
      const template = this.templates[location.template_id];
      if (!/^pond_[a-z_]+_[0-9]{2}$/.test(location.id) || this.locations.has(location.id) || location.kind !== 'pond'
        || !['los_angeles', 'shanghai'].includes(location.region_id) || !template || location.layout_revision !== template.revision
        || !Number.isFinite(location.lat) || Math.abs(location.lat) > 85 || !Number.isFinite(location.lng) || Math.abs(location.lng) > 180
        || !Number.isSafeInteger(location.decoration_seed) || location.decoration_seed < 0 || typeof location.enabled !== 'boolean') throw new Error('POND_LOCATION_INVALID');
      this.locations.set(location.id, location);
    }
  }
  list(region: string): PondLocation[] {
    return structuredClone([...this.locations.values()].filter(p => p.enabled && p.region_id === region));
  }
  room(id: unknown, revision: unknown, content: Content): PondRoom {
    if (revision !== this.revision) throw new Error('POND_UPDATE_REQUIRED');
    const location = typeof id === 'string' ? this.locations.get(id) : undefined;
    if (!location?.enabled) throw new Error('POND_NOT_FOUND');
    const template = this.templates[location.template_id];
    const profile = content.fishing.sites[template.fish_profile];
    if (!profile) throw new Error('POND_PROFILE_INVALID');
    return structuredClone({ location, revision: this.revision, template, capacity: this.capacity,
      site: { name: location.name, space: 'pond', stand: template.navigation.spawn,
        polygon: template.polygon, fish_weights: profile.fish_weights } });
  }
}
