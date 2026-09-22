import { createHash } from 'node:crypto';
import type { FarmLocation } from '../../src/http/farm_location.js';
import type { GeoFeature, Geography, GeoPoint } from '../../src/geography/farm_terrain.js';
export const CENTER: FarmLocation = { lat: 31.2304, lng: 121.4737 };
export function geographicPoint(x: number, y: number, center = CENTER): GeoPoint {
  return [center.lng + (x - 31.5) / 64 * 240 / (111320 * Math.cos(center.lat * Math.PI / 180)), center.lat + (y - 31.5) / 64 * 240 / 111320];
}
export function rectangle(x: number, y: number, w: number, h: number): GeoPoint[] {
  return [[x,y],[x+w,y],[x+w,y+h],[x,y+h],[x,y]].map(([a,b]) => geographicPoint(a,b));
}
export function fixtureGeography(features?: GeoFeature[]): Geography {
  const chosen = features ?? [
    { id: 'fixture/land', kind: 'land', polygon: rectangle(-1,-1,66,66), surface: 'soil' },
    { id: 'fixture/meadow', kind: 'land', polygon: rectangle(36,4,18,18), surface: 'lawn' },
    { id: 'fixture/water', kind: 'water', polygon: rectangle(40,42,15,12), holes: [rectangle(45,46,3,3)] },
    { id: 'fixture/road', kind: 'road', line: [geographicPoint(3,7), geographicPoint(17,18), geographicPoint(25,23)] },
  ];
  return { provider: 'osm', features: chosen, fetched_at: '2026-09-21T00:00:00.000Z',
    attribution: 'Synthetic OSM-shaped test fixture; not a claim about Shanghai', license: 'Test fixture',
    source_checksum: createHash('sha256').update(JSON.stringify(chosen)).digest('hex') };
}
