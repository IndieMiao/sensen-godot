import { cpSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { deflateSync } from 'node:zlib';
import { PbfWriter } from 'pbf';
import { afterAll, describe, expect, it } from 'vitest';
import { resolveParams } from '../src/config.js';
import { buildDataset } from '../src/dataset.js';
import { ATTRIBUTION, OSM_ATTRIBUTION } from '../src/farm.js';
import { joinRings, osmBuildings } from '../src/osm.js';
import { loadSnapshot } from '../src/snapshot.js';
import { checksumFor, fetchSnapshot, ODBL, SOURCES } from '../src/sources.js';

/** A minimal OSM PBF writer for the tests (granularity 100 nanodegrees, as real files). */
type Tags = Record<string, string>;
interface TestOsm {
  nodes: [number, number, number][];
  ways: { id: number; refs: number[]; tags: Tags }[];
  relations: { id: number; tags: Tags; members: [number, number, string][] }[];
}

function pbfFile(osm: TestOsm, compress: boolean): Uint8Array {
  const strings = [''];
  const sid = (s: string) => { let i = strings.indexOf(s); if (i < 0) { i = strings.length; strings.push(s); } return i; };
  const delta = (v: number[]) => v.map((x, i) => (i === 0 ? x : x - v[i - 1]));
  const group = new PbfWriter();
  group.writeMessage(2, (_: null, p: PbfWriter) => {
    p.writePackedSVarint(1, delta(osm.nodes.map(n => n[0])));
    p.writePackedSVarint(8, delta(osm.nodes.map(n => Math.round(n[2] * 1e7))));
    p.writePackedSVarint(9, delta(osm.nodes.map(n => Math.round(n[1] * 1e7))));
  }, null);
  for (const w of osm.ways) {
    group.writeMessage(3, (_: null, p: PbfWriter) => {
      p.writeVarintField(1, w.id);
      p.writePackedVarint(2, Object.keys(w.tags).map(sid));
      p.writePackedVarint(3, Object.values(w.tags).map(sid));
      p.writePackedSVarint(8, delta(w.refs));
    }, null);
  }
  const relGroup = new PbfWriter();
  for (const r of osm.relations) {
    relGroup.writeMessage(4, (_: null, p: PbfWriter) => {
      p.writeVarintField(1, r.id);
      p.writePackedVarint(2, Object.keys(r.tags).map(sid));
      p.writePackedVarint(3, Object.values(r.tags).map(sid));
      p.writePackedVarint(8, r.members.map(m => sid(m[2])));
      p.writePackedSVarint(9, delta(r.members.map(m => m[1])));
      p.writePackedVarint(10, r.members.map(m => m[0]));
    }, null);
  }
  const block = new PbfWriter();
  block.writeMessage(1, (_: null, p: PbfWriter) => { for (const s of strings) p.writeBytesField(1, new TextEncoder().encode(s)); }, null);
  block.writeBytesField(2, group.finish());
  block.writeBytesField(2, relGroup.finish());
  const header = new PbfWriter();
  header.writeStringField(16, 'test');
  header.writeVarintField(32, 1795219200);
  const parts: Uint8Array[] = [];
  for (const [type, data] of [['OSMHeader', header.finish()], ['OSMData', block.finish()]] as const) {
    const blob = new PbfWriter();
    if (compress) { blob.writeVarintField(2, data.length); blob.writeBytesField(3, deflateSync(data)); } else blob.writeBytesField(1, data);
    const blobBytes = blob.finish();
    const head = new PbfWriter();
    head.writeStringField(1, type);
    head.writeVarintField(3, blobBytes.length);
    const headBytes = head.finish();
    const len = new Uint8Array(4);
    new DataView(len.buffer).setUint32(0, headBytes.length);
    parts.push(len, headBytes, blobBytes);
  }
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  parts.reduce((at, p) => { out.set(p, at); return at + p.length; }, 0);
  return out;
}

// Nodes 1–4: a 10 × 10 µ° square; 5–8 an inner square; 9–11 another way's corners.
const sample: TestOsm = {
  nodes: [
    [1, -122.4, 37.7], [2, -122.399, 37.7], [3, -122.399, 37.701], [4, -122.4, 37.701],
    [5, -122.3996, 37.7004], [6, -122.3994, 37.7004], [7, -122.3994, 37.7006], [8, -122.3996, 37.7006],
    [9, -122.5, 37.9], [10, -122.499, 37.9], [11, -122.499, 37.901],
  ],
  ways: [
    { id: 100, refs: [1, 2, 3, 4, 1], tags: { building: 'house', name: 'A' } },
    { id: 101, refs: [5, 6, 7, 8, 5], tags: { building: 'no' } },
    { id: 102, refs: [1, 2, 3], tags: { building: 'yes' } },
    { id: 103, refs: [9, 10, 11, 9], tags: { building: 'yes' } },
    { id: 200, refs: [1, 2, 3], tags: {} },
    { id: 201, refs: [3, 4, 1], tags: {} },
    { id: 202, refs: [5, 6, 7, 8, 5], tags: {} },
  ],
  relations: [
    { id: 100, tags: { type: 'multipolygon', building: 'apartments' }, members: [[1, 200, 'outer'], [1, 201, 'outer'], [1, 202, 'inner'], [0, 1, '']] },
    { id: 101, tags: { type: 'multipolygon', landuse: 'grass' }, members: [[1, 200, 'outer'], [1, 201, 'outer']] },
  ],
};

describe('OpenStreetMap buildings from a PBF extract (C-113)', () => {
  for (const compress of [false, true]) {
    it(`reads closed building ways and assembles multipolygon relations (${compress ? 'zlib' : 'raw'} blobs)`, () => {
      const { header, features } = osmBuildings(pbfFile(sample, compress), [-122.45, 37.65, -122.35, 37.75]);
      expect(header).toEqual({ writing_program: 'test', source: null, replication_timestamp: '2026-11-21T00:00:00.000Z' });
      // way 101 is building=no, 102 is open, 103 lies outside the bbox; relation 101 is no building.
      expect(features.map(f => f.properties)).toEqual([
        { area_id: 100, osm_type: 'way', osm_id: 100, building: 'house' },
        { area_id: -100, osm_type: 'relation', osm_id: 100, building: 'apartments' },
      ]);
      expect(features[0].geometry).toEqual({
        type: 'Polygon', coordinates: [[[-122.4, 37.7], [-122.399, 37.7], [-122.399, 37.701], [-122.4, 37.701], [-122.4, 37.7]]],
      });
      const relation = features[1].geometry;
      expect(relation.type).toBe('Polygon');
      expect(relation.coordinates).toHaveLength(2);
      expect((relation.coordinates as number[][][])[1][0]).toEqual([-122.3996, 37.7004]);
    });
  }

  it('keeps every building when the bbox holds them all', () => {
    expect(osmBuildings(pbfFile(sample, true), [-123, 37, -122, 38]).features.map(f => f.properties.area_id)).toEqual([100, 103, -100]);
  });

  it('drops segments that never close and joins reversed ones', () => {
    expect(joinRings([[[0, 0], [1, 0]], [[1, 0], [1, 1]]])).toEqual([]);
    expect(joinRings([[[0, 0], [1, 0], [1, 1]], [[0, 0], [0, 1], [1, 1]]])).toEqual([[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]]);
  });

  it('finds an extract in BBBike CHECKSUM.txt and labels the source with the ODbL credit', () => {
    const text = '89735e9f8b5013dc98333bb7175920e0  SanFrancisco.osm.csv.xz\nd144b228dc565c52dba278036aac2954 SanFrancisco.osm.pbf\n';
    expect(checksumFor(text, 'SanFrancisco.osm.pbf')).toBe('d144b228dc565c52dba278036aac2954');
    expect(checksumFor(text, 'SanFrancisco.osm.gz')).toBeNull();
    expect(SOURCES['osm-buildings']).toMatchObject({ role: 'buildings', kind: 'osm-pbf', datasf_dataset: null, license: ODBL });
    expect(ODBL).toContain('© OpenStreetMap contributors');
  });
});

describe('OpenStreetMap as a fallback building source (C-113)', () => {
  const tmp = mkdtempSync(path.join(os.tmpdir(), 'osm-fallback-'));
  afterAll(() => rmSync(tmp, { recursive: true, force: true }));
  const snapDir = path.join(tmp, 'snap');
  cpSync(path.join(import.meta.dirname, 'fixtures', 'sf-test-snapshot'), snapDir, { recursive: true });
  const before = buildDataset(loadSnapshot(snapDir), { dataset_version: 'v', params: resolveParams() });
  const parcels = loadSnapshot(snapDir).parcels;
  const bbox = loadSnapshot(snapDir).manifest.bbox!;
  const centre = (id: string): [number, number] => {
    const ring = parcels.find(p => `p-${p.parcel_id}` === id)!.polygons[0][0];
    return [ring.reduce((a, q) => a + q[0], 0) / ring.length, ring.reduce((a, q) => a + q[1], 0) / ring.length];
  };
  const span = (id: string) => {
    const ring = parcels.find(p => `p-${p.parcel_id}` === id)!.polygons[0][0];
    return Math.min(Math.max(...ring.map(q => q[0])) - Math.min(...ring.map(q => q[0])), Math.max(...ring.map(q => q[1])) - Math.min(...ring.map(q => q[1])));
  };
  // The widest parcel without a footprint inside the test range gets an OSM building; 130 SAN
  // RAFAEL WAY (DataSF footprints) gets a bigger OSM building that must be ignored.
  const empty = before.excluded.map(e => e.block_id)
    .filter(id => { const [x, y] = centre(id); return x > bbox[0] && x < bbox[2] && y > bbox[1] && y < bbox[3]; })
    .sort((a, b) => span(b) - span(a))[0];
  const square = (first: number, [x, y]: [number, number], h: number): [number, number, number][] =>
    [[first, x - h, y - h], [first + 1, x + h, y - h], [first + 2, x + h, y + h], [first + 3, x - h, y + h]];
  const osm: TestOsm = {
    nodes: [...square(1, centre(empty), 0.00006), ...square(5, centre('p-3250003'), 0.0003)],
    ways: [{ id: 900, refs: [1, 2, 3, 4, 1], tags: { building: 'yes' } }, { id: 901, refs: [5, 6, 7, 8, 5], tags: { building: 'house' } }],
    relations: [],
  };
  const extract = path.join(tmp, 'SanFrancisco.osm.pbf');
  writeFileSync(extract, pbfFile(osm, true));

  it('adds the source to an existing snapshot from a local extract, and only once', async () => {
    await expect(fetchSnapshot(snapDir, ['osm-buildings'], bbox, () => {}, { extract })).rejects.toThrow(/--append/);
    await expect(fetchSnapshot(snapDir, ['osm-buildings'], null, () => {}, { extract, append: true })).rejects.toThrow(/--bbox/);
    const manifest = await fetchSnapshot(snapDir, ['osm-buildings'], bbox, () => {}, { extract, append: true });
    expect(manifest.sources.map(s => s.label)).toEqual(['sfgis-parcels', 'sfgis-buildings', 'sfenv-buildings', 'osm-buildings']);
    expect(manifest.sources[3]).toMatchObject({ fallback: true, metadata: { buildings: 2, extract_from: 'local file (--extract)' } });
    expect(manifest.sources[3].fetched_at).toBeTruthy();
    await expect(fetchSnapshot(snapDir, ['osm-buildings'], bbox, () => {}, { extract, append: true })).rejects.toThrow(/already has/);
  });

  it('fills only parcels no DataSF copy covers, credits OSM there and leaves every other farm unchanged', () => {
    const after = buildDataset(loadSnapshot(snapDir), { dataset_version: 'v', params: resolveParams() });
    expect(after.reports.length).toBe(before.reports.length + 1);
    const added = after.reports.find(r => r.block_id === empty)!;
    expect(added).toMatchObject({ building_source: 'osm-buildings', building_area_ids: [900] });
    expect(JSON.parse(after.files.get(`farms/${empty}.json`) as string).attribution).toBe(OSM_ATTRIBUTION);
    expect(after.reports.find(r => r.block_id === 'p-3250003')!.building_source).not.toBe('osm-buildings');
    for (const r of before.reports) expect(after.files.get(`farms/${r.block_id}.json`)).toBe(before.files.get(`farms/${r.block_id}.json`));
    expect(JSON.parse(before.files.get('farms/p-3250003.json') as string).attribution).toBe(ATTRIBUTION);
    const licence = JSON.parse(after.files.get('manifest.json') as string).licence;
    expect(licence).toMatchObject({ dataset: expect.stringContaining('ODbL'), attribution: expect.stringContaining('© OpenStreetMap contributors'), osm_farms: 1 });
    expect(JSON.parse(before.files.get('manifest.json') as string).licence).toBeUndefined();
  });
});
