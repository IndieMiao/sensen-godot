/** Reads a snapshot directory, checks every file hash and normalizes the records. */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import type { Polygon } from './geo.js';
import { sha256, type SnapshotManifest, type SnapshotSource } from './sources.js';

export interface ParcelRecord {
  parcel_id: string;
  aliases: string[];
  name: string;
  address: string | null;
  /** lon/lat polygons */
  polygons: Polygon[];
}

export interface BuildingRecord {
  source: string;
  area_id: number;
  mblr: string | null;
  polygons: Polygon[];
}

export interface Snapshot {
  manifest: SnapshotManifest;
  manifest_sha256: string;
  parcels: ParcelRecord[];
  /** In source priority order (manifest order). */
  buildings: BuildingRecord[];
  building_sources: string[];
  rejected: { source: string; reason: string; id: string }[];
}

type Feature = { properties?: Record<string, unknown> | null; geometry?: { type: string; coordinates: unknown } | null };

function polygonsOf(geometry: Feature['geometry']): Polygon[] {
  if (!geometry) return [];
  const coords = geometry.coordinates as number[][][] | number[][][][];
  const list = geometry.type === 'Polygon' ? [coords as number[][][]] : geometry.type === 'MultiPolygon' ? (coords as number[][][][]) : [];
  const out: Polygon[] = [];
  for (const poly of list) {
    const rings = poly
      .map(ring => ring.filter(p => Array.isArray(p) && Number.isFinite(p[0]) && Number.isFinite(p[1])).map(p => [p[0], p[1]] as [number, number]))
      .filter(ring => ring.length >= 4);
    if (rings.length > 0) out.push(rings);
  }
  return out;
}

const text = (v: unknown) => (v === null || v === undefined ? '' : String(v).trim());
const isActive = (v: unknown) => v === undefined || v === null || v === true || v === 1 || v === '1' || v === 'true';

export function loadSnapshot(dir: string): Snapshot {
  const rawManifest = readFileSync(path.join(dir, 'source-manifest.json'), 'utf8');
  const manifest = JSON.parse(rawManifest) as SnapshotManifest;
  const rejected: Snapshot['rejected'] = [];
  const read = (src: SnapshotSource) => src.files.flatMap(f => {
    const body = readFileSync(path.join(dir, f.file), 'utf8');
    if (sha256(body) !== f.sha256) throw new Error(`snapshot file changed: ${f.file}`);
    return (JSON.parse(body).features ?? []) as Feature[];
  });

  const parcelSources = manifest.sources.filter(s => s.role === 'parcels');
  if (parcelSources.length !== 1) throw new Error('a snapshot needs exactly one parcel source');
  const groups = new Map<string, { blklot: string; feature: Feature }[]>();
  for (const feature of read(parcelSources[0])) {
    const p = feature.properties ?? {};
    const blklot = text(p.blklot);
    const map = text(p.mapblklot) || blklot;
    if (!isActive(p.active)) continue;
    if (!/^[A-Za-z0-9]{1,40}$/.test(map) || !/^[A-Za-z0-9]{1,40}$/.test(blklot)) {
      rejected.push({ source: parcelSources[0].label, reason: 'invalid_id', id: map || blklot });
      continue;
    }
    if (!groups.has(map)) groups.set(map, []);
    groups.get(map)!.push({ blklot, feature });
  }
  const parcels: ParcelRecord[] = [];
  for (const [id, members] of [...groups.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) {
    members.sort((a, b) => (a.blklot === id ? -1 : b.blklot === id ? 1 : a.blklot < b.blklot ? -1 : a.blklot > b.blklot ? 1 : 0));
    const main = members.find(m => polygonsOf(m.feature.geometry).length > 0);
    if (!main) {
      rejected.push({ source: parcelSources[0].label, reason: 'no_geometry', id });
      continue;
    }
    const withAddress = members.find(m => text(m.feature.properties?.from_address_num) && text(m.feature.properties?.street_name)) ?? main;
    const pp = withAddress.feature.properties ?? {};
    const number = text(pp.from_address_num);
    const street = [text(pp.street_name), text(pp.street_type)].filter(Boolean).join(' ');
    const address = number && street && number !== '0' ? `${number} ${street}` : null;
    parcels.push({
      parcel_id: id,
      aliases: [...new Set(members.map(m => m.blklot))].sort(),
      name: address ?? `SF Parcel ${id}`,
      address,
      polygons: polygonsOf(main.feature.geometry),
    });
  }

  const buildingSources = manifest.sources.filter(s => s.role === 'buildings');
  const buildings: BuildingRecord[] = [];
  for (const src of buildingSources) {
    const seen = new Set<number>();
    for (const feature of read(src)) {
      const p = feature.properties ?? {};
      const areaId = Number(p.area_id);
      const polygons = polygonsOf(feature.geometry);
      if (!Number.isInteger(areaId) || polygons.length === 0) {
        rejected.push({ source: src.label, reason: 'invalid_building', id: text(p.area_id) });
        continue;
      }
      if (seen.has(areaId)) continue;
      seen.add(areaId);
      const mblr = text(p.mblr).replace(/^SF/, '') || null;
      buildings.push({ source: src.label, area_id: areaId, mblr, polygons });
    }
  }
  buildings.sort((a, b) => buildingSources.findIndex(s => s.label === a.source) - buildingSources.findIndex(s => s.label === b.source) || a.area_id - b.area_id);
  return {
    manifest, manifest_sha256: sha256(rawManifest), parcels, buildings,
    building_sources: buildingSources.map(s => s.label), rejected,
  };
}
