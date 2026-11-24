/**
 * Downloads DataSF parcels and building footprints into a snapshot directory. Raw responses are
 * kept byte-for-byte with their SHA-256; `build` only ever reads a snapshot, never the network.
 */
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

export type Role = 'parcels' | 'buildings';

export interface SourceDef {
  label: string;
  role: Role;
  kind: 'socrata' | 'arcgis';
  title: string;
  /** Canonical DataSF dataset this copy comes from. */
  datasf_dataset: string;
  license: string;
  /** socrata: dataset resource endpoint; arcgis: FeatureServer layer URL. */
  url: string;
  geometry_field?: string;
  arcgis_item?: string;
  fields: string[];
  note?: string;
}

const ARCGIS = 'https://services.arcgis.com/Zs2aNLFN00jrS4gG/arcgis/rest/services';
const PDDL = 'Open Data Commons Public Domain Dedication and License (PDDL) 1.0';

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
};

export interface SnapshotFile { file: string; sha256: string; count: number }
export interface SnapshotSource extends SourceDef { metadata: Record<string, unknown>; files: SnapshotFile[]; bbox: number[] | null }
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
  for (let attempt = 1; ; attempt++) {
    try {
      const res = await fetch(url, { headers: { Accept: 'application/json', 'User-Agent': 'sensen-dynamic-farm-gen/1' } });
      const body = await res.text();
      if (!res.ok) {
        const f = httpFailure(res.status, url, res.headers.has('x-socrata-requestid'));
        throw new HttpError(f.message, f.retry);
      }
      return body;
    } catch (error) {
      if (attempt >= 4 || (error instanceof HttpError && !error.retry)) throw error;
      await new Promise(r => setTimeout(r, 1000 * 2 ** attempt));
    }
  }
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
export async function fetchSource(def: SourceDef, dir: string, bbox: number[] | null, log = console.log): Promise<SnapshotSource> {
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

export async function fetchSnapshot(dir: string, labels: string[], bbox: number[] | null, log = console.log): Promise<SnapshotManifest> {
  mkdirSync(dir, { recursive: true });
  const sources: SnapshotSource[] = [];
  for (const label of labels) {
    const def = SOURCES[label];
    if (!def) throw new Error(`unknown source ${label}; known: ${Object.keys(SOURCES).join(', ')}`);
    sources.push(await fetchSource(def, dir, bbox, log));
  }
  const manifest: SnapshotManifest = { snapshot_schema: 1, fetched_at: new Date().toISOString(), bbox, sources };
  writeFileSync(path.join(dir, 'source-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  return manifest;
}
