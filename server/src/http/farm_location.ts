export interface FarmLocation { lat: number; lng: number }
export type PlacementBounds = [south: number, west: number, north: number, east: number];

const METERS_PER_DEGREE = 111320;
const FOOTPRINT_MARGIN_M = 300;

export function isFarmLocation(value: unknown): value is FarmLocation {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  if (Object.keys(value).length !== 2) return false;
  const { lat, lng } = value as Record<string, unknown>;
  return typeof lat === 'number' && Number.isFinite(lat) && Math.abs(lat) <= 85
    && typeof lng === 'number' && Number.isFinite(lng) && Math.abs(lng) <= 180;
}

/** Supported city bounds leave room for the template's full map footprint. */
export function withinPlacementBounds(location: FarmLocation, bounds?: PlacementBounds): boolean {
  if (!bounds) return false;
  const dlat = FOOTPRINT_MARGIN_M / METERS_PER_DEGREE;
  const dlng = dlat / Math.cos(location.lat * Math.PI / 180);
  return location.lat - dlat >= bounds[0] && location.lng - dlng >= bounds[1]
    && location.lat + dlat <= bounds[2] && location.lng + dlng <= bounds[3];
}
