/**
 * Downloads DataSF parcels and building footprints into a snapshot directory. Raw responses are
 * kept byte-for-byte with their SHA-256; `build` only ever reads a snapshot, never the network.
 */
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { osmBuildings } from './osm.js';

export type Role = 'parcels' | 'buildings';

export interface SourceDef {
  label: string;
  role: Role;
  kind: 'socrata' | 'arcgis' | 'osm-pbf';
  title: string;
  /** Canonical DataSF dataset this copy comes from; null for OpenStreetMap. */
  datasf_dataset: string | null;
  license: string;
  /** socrata: dataset resource endpoint; arcgis: FeatureServer layer URL; osm-pbf: the extract file. */
  url: string;
  geometry_field?: string;
  arcgis_item?: string;
  fields: string[];
  note?: string;
  /** A fallback building source is only used for a parcel no other building source covers (C-113). */
  fallback?: boolean;
}

const ARCGIS = 'https://services.arcgis.com/Zs2aNLFN00jrS4gG/arcgis/rest/services';
const PDDL = 'Open Data Commons Public Domain Dedication and License (PDDL) 1.0';
export const ODBL = 'Open Data Commons Open Database License (ODbL) 1.0; attribution: © OpenStreetMap contributors';
/** The whole city incl. Treasure Island and Yerba Buena (lon/lat): the OSM extract is cut to it when `fetch` gets no --bbox. */
export const SF_BBOX = [-122.516, 37.703, -122.355, 37.833];
const BBBIKE = 'https://download.bbbike.org/osm/bbbike/SanFrancisco';

export const SOURCES: Record<string, SourceDef> = {
  'datasf-parcels': {
    label: 'datasf-parcels', role: 'parcels', kind: 'socrata', title: 'Parcels – Active and Retired',
    datasf_dataset: 'acdm-wktn', license: PDDL, url: 'https://data.sf.gov/resource/acdm-wktn.geojson', geometry_field: 'shape',
    fields: ['mapblklot', 'blklot', 'from_address_num', 'to_address_num', 'street_name', 'street_type', 'active', 'data_as_of'],
  },
  'datasf-buildings': {
    label: 'datasf-buildings', role: 'buildings', kind: 'socrata', title: 'Building Footprints',
    datasf_dataset: 'ynuv-fyni', license: PDDL, url: 'https://data.sf.gov/resource/ynuv-fyni.geojson', geometry_field: 'shape',
    fields: ['area_id', 'mblr', 'sf16_bldgid', 'data_as_of'],
  },
  'sfgis-parcels': {
    label: 'sfgis-parcels', role: 'parcels', kind: 'arcgis', title: 'Active Parcels (from DataSF, pulled daily)',
    datasf_dataset: 'acdm-wktn', license: PDDL, url: `${ARCGIS}/Active_Parcels_from_DataSF_pulled_daily_/FeatureServer/0`,
    arcgis_item: 'f81b5f0adb8c4d6a95282bec1ce10378',
    fields: ['mapblklot', 'blklot', 'from_address_num', 'to_address_num', 'street_name', 'street_type', 'active', 'data_as_of'],
    note: 'City and County of San Francisco ArcGIS Online copy of DataSF acdm-wktn, active parcels only.',
  },
  'sfgis-buildings': {
    label: 'sfgis-buildings', role: 'buildings', kind: 'arcgis', title: 'Building Footprints (from DataSF, pulled weekly)',
    datasf_dataset: 'ynuv-fyni', license: PDDL, url: `${ARCGIS}/Building_Footprints_from_DataSF_pulled_weekly_/FeatureServer/0`,
    arcgis_item: '40f39da4e8be419284c3a82a62dbb4e1', fields: ['area_id', 'mblr', 'data_as_of'],
    note: 'City and County of San Francisco ArcGIS Online copy of DataSF ynuv-fyni. Incomplete as of 2026-11-22: 82,000 of 177,023 rows (area_id 21567–143982).',
  },
  'sfenv-buildings': {
    label: 'sfenv-buildings', role: 'buildings', kind: 'arcgis', title: 'Buildings_filtered (SF Environment copy of DataSF building footprints)',
    datasf_dataset: 'ynuv-fyni', license: `${PDDL} (inherited from DataSF ynuv-fyni; the copy itself states none)`,
    url: `${ARCGIS}/Buildings_filtered/FeatureServer/0`, arcgis_item: '12571fc538e5487598af2b76f2a1febe', fields: ['area_id', 'mblr'],
    note: 'City org copy (2025-02) of the same DataSF records, 127,010 rows; coordinates sit about 1.3 m west-northwest of the sfgis copy. Local fallback only.',
  },
  'osm-buildings': {
    label: 'osm-buildings', role: 'buildings', kind: 'osm-pbf', title: 'OpenStreetMap buildings (BBBike San Francisco extract)',
    datasf_dataset: null, license: ODBL, url: `${BBBIKE}/SanFrancisco.osm.pbf`, fields: ['area_id', 'osm_type', 'osm_id', 'building'],
    fallback: true,
    note: 'C-113: fills parcels the DataSF copies have no footprint for (fallback source, see README). BBBike rebuilds this extract of the OSM planet weekly; '
      + 'the snapshot keeps the file (raw/) and its hash. Closed building ways and multipolygon relations; area_id = way id or -relation id. '
      + 'A dataset using it is a derivative database under the ODbL: credit "© OpenStreetMap contributors" and keep it under the ODbL.',
  },
};

export interface SnapshotFile { file: string; sha256: string; count: number }
export interface SnapshotSource extends SourceDef {
  metadata: Record<string, unknown>; files: SnapshotFile[]; bbox: number[] | null;
  /** Set on a source added later with `fetch --append`; the others share the manifest's fetched_at. */
  fetched_at?: string;
}
export interface SnapshotManifest { snapshot_schema: 1; fetched_at: string; bbox: number[] | null; sources: SnapshotSource[] }

export const sha256 = (data: string | Uint8Array) => createHash('sha256').update(data).digest('hex');

/**
 * C-75: data.sfgov.org now 301-redirects to data.sf.gov, and the Socrata edge answers every request
 * from a mainland-China egress (cardigan-ci, the control host) with a bare nginx 403, homepage and
 * metadata included, with or without an app token. Such a 403 is not retried and names the way out.
 */
export function httpFailure(status: number, url: string, socrata: boolean): { message: string; retry: boolean } {
  const base = `HTTP ${status} for ${url}`;
  const retry = status >= 500 || status === 408 || status === 429;
  if (status === 403 && socrata) {
    return {
      retry,
      message: `${base}: the Socrata edge refused this network (regional block, not a missing app token). `
        + 'Use the sfgis-* ArcGIS sources, or fetch through an egress outside mainland China '
        + '(NODE_USE_ENV_PROXY=1 HTTPS_PROXY=<proxy> on Node 24).',
    };
  }
  return { message: base, retry };
}

class HttpError extends Error {
  constructor(message: string, readonly retry: boolean) { super(message); }
}

async function getText(url: string): Promise<string> {
  return new TextDecoder().decode(await getBytes(url));
}

async function getBytes(url: string, range?: [number, number]): Promise<Uint8Array> {
  for (let attempt = 1; ; attempt++) {
    try {
      const headers: Record<string, string> = { Accept: range ? '*/*' : 'application/json', 'User-Agent': 'sensen-dynamic-farm-gen/1' };
      if (range) headers.Range = `bytes=${range[0]}-${range[1]}`;
      const res = await fetch(url, { headers });
      const body = new Uint8Array(await res.arrayBuffer());
      if (!res.ok) {
        const f = httpFailure(res.status, url, res.headers.has('x-socrata-requestid'));
        throw new HttpError(f.message, f.retry);
      }
      if (range && res.status !== 206) throw new HttpError(`HTTP ${res.status} for a byte range of ${url}: ranges not served`, false);
      if (range && body.length !== range[1] - range[0] + 1) throw new HttpError(`short byte range of ${url}`, true);
      return body;
    } catch (error) {
      if (attempt >= 4 || (error instanceof HttpError && !error.retry)) throw error;
      await new Promise(r => setTimeout(r, 1000 * 2 ** attempt));
    }
  }
}

/**
 * A large file in 1 MiB ranges, 16 at a time: from our network one connection to the extract host
 * runs at about 15 KB/s (34 MB in ~40 min), parallel ranges in a few minutes.
 */
async function getLargeFile(url: string): Promise<Uint8Array> {
  const head = await fetch(url, { method: 'HEAD', headers: { 'User-Agent': 'sensen-dynamic-farm-gen/1' } });
  const size = Number(head.headers.get('content-length'));
  if (!head.ok || !Number.isSafeInteger(size) || size <= 0) throw new Error(`HTTP ${head.status} for ${url} (no size)`);
  const chunk = 1 << 20;
  const out = new Uint8Array(size);
  let next = 0;
  const worker = async () => {
    for (let at = next; at < size; at = next) {
      next += chunk;
      out.set(await getBytes(url, [at, Math.min(size, at + chunk) - 1]), at);
    }
  };
  await Promise.all(Array.from({ length: 16 }, worker));
  return out;
}

/** `md5 file` lines of a BBBike CHECKSUM.txt. */
export function checksumFor(text: string, file: string): string | null {
  for (const line of text.split('\n')) {
    const m = /^([0-9a-f]{32})\s+(\S+)$/.exec(line.trim());
    if (m && m[2] === file) return m[1];
  }
  return null;
}

/**
 * OSM buildings: downloads the extract and checks it against the extract's CHECKSUM.txt (or takes
 * an already downloaded `extract` file, so a rebuild elsewhere uses the same OSM data), keeps it in
 * raw/ and writes the buildings meeting the bbox (or SF_BBOX) as GeoJSON pages of 20,000.
 */
async function fetchOsmExtract(def: SourceDef, dir: string, bbox: number[] | null, log: (s: string) => void, extract?: string): Promise<SnapshotSource> {
  const name = path.posix.basename(new URL(def.url).pathname);
  const bytes = extract ? new Uint8Array(readFileSync(extract)) : await getLargeFile(def.url);
  const md5 = createHash('md5').update(bytes).digest('hex');
  if (!extract) {
    const listed = checksumFor(await getText(new URL('CHECKSUM.txt', def.url).href), name);
    if (listed !== md5) throw new Error(`${def.label}: ${name} md5 ${md5} does not match CHECKSUM.txt (${listed ?? 'not listed'})`);
  }
  mkdirSync(path.join(dir, 'raw'), { recursive: true });
  mkdirSync(path.join(dir, def.role), { recursive: true });
  writeFileSync(path.join(dir, 'raw', name), bytes);
  const { header, features } = osmBuildings(bytes, bbox ?? SF_BBOX);
  const files: SnapshotFile[] = [];
  const page = 20000;
  for (let n = 0; n * page < features.length; n++) {
    const body = JSON.stringify({ type: 'FeatureCollection', features: features.slice(n * page, (n + 1) * page) });
    const file = `${def.role}/${def.label}-${String(n).padStart(4, '0')}.geojson`;
    writeFileSync(path.join(dir, file), body);
    files.push({ file, sha256: sha256(body), count: Math.min(page, features.length - n * page) });
    log(`${def.label}: ${file} ${files.at(-1)!.count} buildings`);
  }
  const metadata = {
    extract_file: `raw/${name}`, extract_bytes: bytes.length, extract_sha256: sha256(bytes), extract_md5: md5,
    extract_from: extract ? 'local file (--extract)' : def.url,
    osm_replication_timestamp: header.replication_timestamp, osm_writing_program: header.writing_program,
    clip_bbox: bbox ?? SF_BBOX, buildings: features.length,
  };
  return { ...def, metadata, files, bbox };
}

async function metadata(def: SourceDef): Promise<Record<string, unknown>> {
  if (def.kind === 'arcgis') {
    const layer = JSON.parse(await getText(`${def.url}?f=json`));
    const item = def.arcgis_item ? JSON.parse(await getText(`https://www.arcgis.com/sharing/rest/content/items/${def.arcgis_item}?f=json`)) : {};
    return {
      layer_name: layer.name, data_last_edit_ms: layer.editingInfo?.dataLastEditDate ?? null,
      item_owner: item.owner ?? null, item_modified_ms: item.modified ?? null,
      item_license: typeof item.licenseInfo === 'string' ? item.licenseInfo.replace(/<[^>]+>/g, '').trim() : null,
    };
  }
  const domain = new URL(def.url).origin;
  const view = JSON.parse(await getText(`${domain}/api/views/${def.datasf_dataset}.json`));
  return { name: view.name, rows_updated_at_s: view.rowsUpdatedAt ?? null, license: view.license?.name ?? null };
}

/** bbox = [minLon, minLat, maxLon, maxLat] or null for the whole city. */
export async function fetchSource(def: SourceDef, dir: string, bbox: number[] | null, log = console.log, extract?: string): Promise<SnapshotSource> {
  if (def.kind === 'osm-pbf') return fetchOsmExtract(def, dir, bbox, log, extract);
  if (extract) throw new Error(`${def.label}: --extract only applies to an OSM extract source`);
  mkdirSync(path.join(dir, def.role), { recursive: true });
  const files: SnapshotFile[] = [];
  const page = def.kind === 'arcgis' ? 2000 : 50000;
  const oid = def.kind === 'arcgis' ? JSON.parse(await getText(`${def.url}?f=json`)).objectIdField ?? 'ObjectId' : '';
  for (let offset = 0, n = 0; ; offset += page, n++) {
    let url: string;
    if (def.kind === 'arcgis') {
      const q = new URLSearchParams({
        where: '1=1', outFields: def.fields.join(','), outSR: '4326', f: 'geojson',
        orderByFields: `${oid} ASC`, resultOffset: String(offset), resultRecordCount: String(page),
      });
      if (bbox) {
        q.set('geometry', bbox.join(',')); q.set('geometryType', 'esriGeometryEnvelope'); q.set('inSR', '4326');
        q.set('spatialRel', 'esriSpatialRelIntersects');
      }
      url = `${def.url}/query?${q}`;
    } else {
      const q = new URLSearchParams({ $limit: String(page), $offset: String(offset), $order: ':id' });
      if (bbox) {
        const [x0, y0, x1, y1] = bbox;
        q.set('$where', `intersects(${def.geometry_field}, 'POLYGON((${x0} ${y0}, ${x1} ${y0}, ${x1} ${y1}, ${x0} ${y1}, ${x0} ${y0}))')`);
      }
      url = `${def.url}?${q}`;
    }
    const body = await getText(url);
    const json = JSON.parse(body);
    if (json.error || !Array.isArray(json.features)) throw new Error(`${def.label}: ${JSON.stringify(json.error ?? 'no features array').slice(0, 300)}`);
    const count = Array.isArray(json.features) ? json.features.length : 0;
    const file = `${def.role}/${def.label}-${String(n).padStart(4, '0')}.geojson`;
    writeFileSync(path.join(dir, file), body);
    files.push({ file, sha256: sha256(body), count });
    log(`${def.label}: ${file} ${count} features`);
    const more = def.kind === 'arcgis' ? json.exceededTransferLimit === true || json.properties?.exceededTransferLimit === true : count === page;
    if (!more || count === 0) break;
  }
  return { ...def, metadata: await metadata(def), files, bbox };
}

export interface FetchOptions {
  /** A local copy of the OSM extract instead of downloading it. */
  extract?: string;
  /** Add the sources to the snapshot already in `dir` (same bbox), e.g. OSM buildings to the snapshot an earlier dataset was built from. */
  append?: boolean;
}

export async function fetchSnapshot(dir: string, labels: string[], bbox: number[] | null, log = console.log, opts: FetchOptions = {}): Promise<SnapshotManifest> {
  const manifestFile = path.join(dir, 'source-manifest.json');
  const base: SnapshotManifest | null = opts.append ? JSON.parse(readFileSync(manifestFile, 'utf8')) : null;
  if (!base && existsSync(manifestFile)) throw new Error(`${dir} already holds a snapshot; use --append to add sources to it`);
  if (base && JSON.stringify(base.bbox) !== JSON.stringify(bbox)) throw new Error(`--bbox must equal the snapshot's (${JSON.stringify(base.bbox)})`);
  mkdirSync(dir, { recursive: true });
  const sources: SnapshotSource[] = [];
  for (const label of labels) {
    const def = SOURCES[label];
    if (!def) throw new Error(`unknown source ${label}; known: ${Object.keys(SOURCES).join(', ')}`);
    if (base?.sources.some(s => s.label === label)) throw new Error(`the snapshot already has ${label}`);
    const src = await fetchSource(def, dir, bbox, log, opts.extract);
    sources.push(base ? { ...src, fetched_at: new Date().toISOString() } : src);
  }
  const manifest: SnapshotManifest = base
    ? { ...base, sources: [...base.sources, ...sources] }
    : { snapshot_schema: 1, fetched_at: new Date().toISOString(), bbox, sources };
  writeFileSync(manifestFile, `${JSON.stringify(manifest, null, 2)}\n`);
  return manifest;
}
