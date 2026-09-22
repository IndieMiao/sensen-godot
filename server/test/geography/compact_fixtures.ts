import type { GeoFeature, GeoPoint } from '../../src/geography/farm_terrain.js';
import { CENTER, fixtureGeography } from './fixtures.js';
/** Explicitly synthetic geographic sample for the 160m source window / 40-cell plot. */
export function compactPoint(x: number, y: number): GeoPoint {
  return [CENTER.lng + (x - 19.5) / 40 * 160 / (111320 * Math.cos(CENTER.lat * Math.PI / 180)),
    CENTER.lat + (y - 19.5) / 40 * 160 / 111320];
}
export function compactRectangle(x: number, y: number, w: number, h: number): GeoPoint[] {
  return [[x,y],[x+w,y],[x+w,y+h],[x,y+h],[x,y]].map(([a,b])=>compactPoint(a,b));
}
export function compactFixtureGeography(features?: GeoFeature[]) {
  return fixtureGeography(features ?? [
    { id:'compact_fixture/land',kind:'land',surface:'soil',polygon:compactRectangle(-1,-1,42,42) },
    { id:'compact_fixture/meadow',kind:'land',surface:'lawn',polygon:compactRectangle(3,6,13,9) },
    { id:'compact_fixture/water',kind:'water',polygon:compactRectangle(30,5,7,8),holes:[compactRectangle(32,8,2,2)] },
    { id:'compact_fixture/road',kind:'road',line:[compactPoint(22,3),compactPoint(17,9),compactPoint(21,18)] },
  ]);
}
