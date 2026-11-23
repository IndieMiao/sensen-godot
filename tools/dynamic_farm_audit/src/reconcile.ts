/**
 * Id reconciliation: the valid input parcels (derived here from the snapshot), the farms the
 * generator reports, the parcels it reports as excluded, and the farm files actually present
 * must line up exactly.
 */
import type { Dataset, SourceSnapshot } from './inputs.js';

export interface Discrepancy { check: string; ids: string[] }

export interface Reconciliation {
  counts: {
    input_valid: number;
    input_invalid: number;
    generated: number;
    excluded: number;
    farm_files: number;
    manifest_farm_files: number;
    index_features: number;
    /** Lot numbers (aliases) counted separately: all valid lots, and those under generated / excluded parcels. */
    input_lots: number;
    generated_lots: number;
    excluded_lots: number;
  };
  /** Exclusions by reason category (text before the first ':'), and by full reason. */
  excluded_by_category: Record<string, number>;
  excluded_by_reason: Record<string, number>;
  input_invalid_by_reason: Record<string, number>;
  /** True when every check below is empty. */
  consistent: boolean;
  discrepancies: Discrepancy[];
}

const sorted = (s: Iterable<string>) => [...s].sort();
const minus = (a: Set<string>, b: Set<string>) => sorted([...a].filter(x => !b.has(x)));
function duplicates(list: string[]): string[] {
  const seen = new Set<string>();
  const dup = new Set<string>();
  for (const x of list) (seen.has(x) ? dup : seen).add(x);
  return sorted(dup);
}
const tally = (keys: string[]) => {
  const out: Record<string, number> = {};
  for (const k of [...keys].sort()) out[k] = (out[k] ?? 0) + 1;
  return out;
};

export function reconcile(snapshot: SourceSnapshot, dataset: Dataset): Reconciliation {
  const input = new Set([...snapshot.parcels.keys()].map(id => `p-${id}`));
  const generatedList = dataset.report.parcels.map(p => p.block_id);
  const excludedList = dataset.report.excluded.map(e => e.block_id);
  const generated = new Set(generatedList);
  const excluded = new Set(excludedList);
  const files = new Set(dataset.farm_files);
  const manifestFarms = new Set(Object.keys(dataset.manifest.files)
    .filter(f => /^farms\/[^/]+\.json$/.test(f)).map(f => f.slice('farms/'.length, -'.json'.length)));
  const index = new Set(dataset.index_ids);
  const accounted = new Set([...generated, ...excluded]);

  const checks: Discrepancy[] = [
    { check: 'input_not_accounted (valid input parcel neither generated nor excluded)', ids: minus(input, accounted) },
    { check: 'accounted_not_input (generated or excluded id not a valid input parcel)', ids: minus(accounted, input) },
    { check: 'generated_and_excluded', ids: sorted([...generated].filter(x => excluded.has(x))) },
    { check: 'generated_duplicate', ids: duplicates(generatedList) },
    { check: 'excluded_duplicate', ids: duplicates(excludedList) },
    { check: 'generated_without_farm_file', ids: minus(generated, files) },
    { check: 'farm_file_not_generated', ids: minus(files, generated) },
    { check: 'farm_file_not_in_manifest', ids: minus(files, manifestFarms) },
    { check: 'manifest_farm_without_file', ids: minus(manifestFarms, files) },
    { check: 'index_without_farm_file', ids: minus(index, files) },
    { check: 'farm_file_not_in_index', ids: minus(files, index) },
    { check: 'index_duplicate', ids: duplicates(dataset.index_ids) },
    { check: 'excluded_with_farm_file', ids: sorted([...excluded].filter(x => files.has(x))) },
    { check: 'dataset_file_integrity', ids: [...dataset.file_problems] },
    { check: 'snapshot_file_integrity', ids: [...snapshot.file_problems] },
  ];

  // Parcel-source records the generator says it rejected must be the ones the audit finds invalid.
  const ownInvalid = new Set(snapshot.invalid_parcels.filter(p => p.reason !== 'inactive').map(p => `${p.reason}|${p.id}`));
  const genRejected = new Set(dataset.report.rejected_records
    .filter(r => r.source === snapshot.parcel_source).map(r => `${r.reason}|${r.id}`));
  checks.push({ check: 'invalid_parcel_not_reported_rejected', ids: minus(ownInvalid, genRejected) });
  checks.push({ check: 'reported_rejected_parcel_not_invalid', ids: minus(genRejected, ownInvalid) });

  const totals = dataset.report.totals ?? {};
  const expect = (name: string, actual: number, claimed: number | undefined) => {
    if (claimed !== undefined && claimed !== actual) checks.push({ check: `count_mismatch ${name}`, ids: [`claimed ${claimed}, actual ${actual}`] });
  };
  expect('totals.farms', files.size, totals.farms);
  expect('totals.excluded', excluded.size, totals.excluded);
  expect('totals.parcels_in_snapshot', input.size, totals.parcels_in_snapshot);
  expect('manifest.parcel_count', files.size, dataset.manifest.parcel_count);
  const snapshotSha = dataset.manifest.sources?.snapshot_manifest_sha256;
  if (snapshotSha !== undefined && snapshotSha !== snapshot.manifest_sha256) {
    checks.push({ check: 'snapshot_manifest_sha256 (dataset was built from a different snapshot)', ids: [`dataset ${snapshotSha}`, `snapshot ${snapshot.manifest_sha256}`] });
  }

  const lots = (ids: Set<string>) => [...ids].reduce((n, b) => n + (snapshot.parcels.get(b.slice(2))?.lots.length ?? 0), 0);

  const discrepancies = checks.filter(c => c.ids.length > 0);
  return {
    counts: {
      input_valid: input.size, input_invalid: snapshot.invalid_parcels.length, generated: generated.size, excluded: excluded.size,
      farm_files: files.size, manifest_farm_files: manifestFarms.size, index_features: dataset.index_ids.length,
      input_lots: lots(input), generated_lots: lots(generated), excluded_lots: lots(excluded),
    },
    excluded_by_category: tally(dataset.report.excluded.map(e => e.reason.split(':')[0].trim())),
    excluded_by_reason: tally(dataset.report.excluded.map(e => e.reason)),
    input_invalid_by_reason: tally(snapshot.invalid_parcels.map(p => p.reason)),
    consistent: discrepancies.length === 0,
    discrepancies,
  };
}
