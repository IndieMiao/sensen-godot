/** C-130 起步区配置：解析失败就拒绝启动；环境变量开关；仓库里的旧金山起步区按真实边界生成。 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { activeZone, loadStarterZones, parseStarterZones, pointInRing, STARTER_ZONE_FILE, starterZoneSwitchFromEnv,
  type LngLat } from '../../src/parcels/starter_zone.js';
import { loadParcelRules, communityOf } from '../../src/parcels/rules.js';
import { zoneParcels } from '../../tools/starter_zone_build.js';

const RING: LngLat[] = [[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]];
const zone = (extra: Record<string, unknown> = {}) => ({ id: 'z', community_id: 'sf', name: 'Z', dataset_version: 'd-1',
  boundary: RING, center: [0.5, 0.5], zoom: 17, parcels: { 'p-1': [0.5, 0.5] }, ...extra });
const file = (extra: Record<string, unknown> = {}, zones: unknown[] = [zone()]) => ({ version: 1, enabled: true, zones, ...extra });

describe('starter zone config', () => {
  it('parses a valid file', () => {
    const z = parseStarterZones(file());
    expect(z.enabled).toBe(true);
    expect(z.zones[0].parcels.get('p-1')).toEqual([0.5, 0.5]);
    expect(activeZone(z, 'sf')?.id).toBe('z');
    expect(activeZone(z, 'la')).toBeNull();
    expect(activeZone({ ...z, enabled: false }, 'sf')).toBeNull();
    expect(activeZone(undefined, 'sf')).toBeNull();
    expect(parseStarterZones(file({ enabled: false }, [])).zones).toEqual([]);
  });

  it.each([
    ['no file content', null],
    ['wrong version', file({ version: 2 })],
    ['enabled not a boolean', file({ enabled: 'yes' })],
    ['zones missing', { version: 1, enabled: true }],
    ['two zones for one community', file({}, [zone(), zone({ id: 'y' })])],
    ['bad id', file({}, [zone({ id: 'Bad Id' })])],
    ['open boundary', file({}, [zone({ boundary: RING.slice(0, 4) })])],
    ['too few points', file({}, [zone({ boundary: [[0, 0], [1, 1], [0, 0]] })])],
    ['boundary off the globe', file({}, [zone({ boundary: [[0, 0], [1, 90], [1, 1], [0, 0]] })])],
    ['bad centre', file({}, [zone({ center: [0, 'x'] })])],
    ['zoom out of range', file({}, [zone({ zoom: 25 })])],
    ['no parcels', file({}, [zone({ parcels: {} })])],
    ['parcels as a list', file({}, [zone({ parcels: ['p-1'] })])],
    ['bad parcel id', file({}, [zone({ parcels: { '3512001': [0.5, 0.5] } })])],
    ['bad parcel centre', file({}, [zone({ parcels: { 'p-1': [0.5] } })])],
  ])('refuses %s', (_name, raw) => {
    expect(() => parseStarterZones(raw)).toThrow(STARTER_ZONE_FILE);
  });

  it('PARCEL_STARTER_ZONE: unset follows the file, 0/1 switch it, anything else stops the server', () => {
    expect(starterZoneSwitchFromEnv({})).toBe('file');
    expect(starterZoneSwitchFromEnv({ PARCEL_STARTER_ZONE: '' })).toBe('file');
    expect(starterZoneSwitchFromEnv({ PARCEL_STARTER_ZONE: '0' })).toBe(false);
    expect(starterZoneSwitchFromEnv({ PARCEL_STARTER_ZONE: '1' })).toBe(true);
    for (const v of ['true', 'off', 'yes', ' 1']) expect(starterZoneSwitchFromEnv({ PARCEL_STARTER_ZONE: v })).toBeNull();
    expect(loadStarterZones(DEFAULT_CONTENT_DIR, false).enabled).toBe(false);
    expect(loadStarterZones(DEFAULT_CONTENT_DIR, true).enabled).toBe(true);
  });

  it('point in ring; the build tool keeps parcels whose centre is inside, sorted', () => {
    expect(pointInRing([0.5, 0.5], RING)).toBe(true);
    expect(pointInRing([1.5, 0.5], RING)).toBe(false);
    const features = [
      { properties: { block_id: 'p-b', center_lon: 0.2, center_lat: 0.2 } },
      { properties: { block_id: 'p-a', center_lon: 0.9, center_lat: 0.1 } },
      { properties: { block_id: 'p-out', center_lon: 2, center_lat: 0.5 } },
      { properties: { block_id: 7, center_lon: 0.5, center_lat: 0.5 } },
    ];
    expect(zoneParcels(features, RING)).toEqual({ 'p-a': [0.9, 0.1], 'p-b': [0.2, 0.2] });
  });
});

describe('shipped San Francisco starter zone', () => {
  const shipped = loadStarterZones(DEFAULT_CONTENT_DIR);
  const sf = shipped.zones[0];
  const raw = JSON.parse(readFileSync(path.join(DEFAULT_CONTENT_DIR, STARTER_ZONE_FILE), 'utf8'));
  const inside = (p: LngLat) => pointInRing(p, sf.boundary);

  it('is on, belongs to the San Francisco community and names a registered dataset', () => {
    expect(shipped.enabled).toBe(true);
    expect(shipped.zones).toHaveLength(1);
    expect(sf).toMatchObject({ id: 'sf-starter', community_id: 'sf', zoom: 16.4 });
    expect(communityOf(loadParcelRules(DEFAULT_CONTENT_DIR), sf.dataset_version)).toBe('sf');
    expect(raw.zones[0].dataset_version).toBe('sf-dynamic-farm-20261124-r6');
  });

  it('California, Hyde, Bay and The Embarcadero bound it (C-130#45); Grant Ave between Green and Vallejo is the landing point', () => {
    // Street centre-line crossings from OpenStreetMap, 2026-11-25 (C-130 rework of D-270).
    const crossing: Record<string, LngLat> = { hydeCalifornia: [-122.417411, 37.791], drummCalifornia: [-122.396352, 37.793687],
      bayEmbarcadero: [-122.40596, 37.806627], hydeBay: [-122.420194, 37.804801] };
    const ring = sf.boundary.map((p) => JSON.stringify(p));
    for (const c of Object.values(crossing)) expect(ring).toContain(JSON.stringify(c));
    expect(sf.boundary[0]).toEqual(crossing.hydeCalifornia);
    expect(sf.boundary[sf.boundary.length - 1]).toEqual(crossing.hydeCalifornia);
    const grantGreen: LngLat = [-122.407414, 37.799719], grantVallejo: LngLat = [-122.407227, 37.798778];
    expect(inside(sf.center)).toBe(true);
    expect(sf.center[1]).toBeGreaterThan(grantVallejo[1]);
    expect(sf.center[1]).toBeLessThan(grantGreen[1]);
    expect(Math.abs(sf.center[0] - (grantGreen[0] + grantVallejo[0]) / 2)).toBeLessThan(0.0002);
    // Inside: North Beach, Russian Hill, Telegraph Hill, Nob Hill, Chinatown and the north of the Financial District.
    for (const p of [[-122.4100, 37.8008], [-122.40582, 37.80239], [-122.4194, 37.8021], [-122.41322, 37.79251],
      [-122.40630, 37.79410], [-122.40280, 37.79520]] as LngLat[]) expect(inside(p)).toBe(true);
    // Outside: Fisherman's Wharf (north of Bay), the piers and the Ferry Building (east of The Embarcadero), south of
    // California (Union Square) and Market, west of Hyde.
    for (const p of [[-122.41700, 37.80800], [-122.39750, 37.80150], [-122.39350, 37.79550], [-122.40750, 37.78800],
      [-122.39700, 37.79250], [-122.42050, 37.79800]] as LngLat[]) expect(inside(p)).toBe(false);
  });

  it('lists the 2968 parcels of the r6 dataset whose centre is inside, all within the boundary', () => {
    expect(sf.parcels.size).toBe(2968);
    for (const c of sf.parcels.values()) expect(inside(c)).toBe(true);
    expect(Object.keys(raw.zones[0].parcels)).toEqual([...Object.keys(raw.zones[0].parcels)].sort());
  });
});
