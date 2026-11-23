# Dynamic farm dataset audit (`dynamic-farm-audit-1`)

An offline check of a dataset produced by `tools/dynamic_farm_gen` (r5, `building-raster-1`), run
before upload. It covers steps 3 and 4 of the r4 process (REPRODUCE-r4): **id reconciliation** and
**source-geometry audit**. The audit never imports generator code and never uses the generator's
own numbers in a calculation. It reads only:

- the source snapshot: `source-manifest.json` and the raw DataSF responses (hashes checked);
- the dataset directory: `manifest.json`, `farms/*.json`, `index.geojson`, `buildings.geojson`,
  `reports/generation-report.json`.

The generator's statistics (`stats.core_iou`, `core_components`, the report totals) are read only so
they can be compared with the audit's own values. A test (`test/audit.test.ts`, "independence") fails
if `src/` imports anything from the generator.

## Usage

```sh
cd tools/dynamic_farm_audit
pnpm cli --snapshot <snapshot dir> --dataset <dataset dir> --out <report dir> [--params audit.json] [--quiet]
# e.g. the C-49 test range:
pnpm cli --snapshot ../dynamic_farm_gen/test/fixtures/sf-test-snapshot --dataset "$TMPDIR/r5" --out "$TMPDIR/r5-audit"
```

Writes `audit-report.json` (everything, one entry per farm) and `audit-summary.md` (also printed).
Exit code: 0 = `pass` or `warn`, 1 = `fail`, 2 = usage error.

## 1. Id reconciliation

The valid input set is derived from the snapshot's parcel source, independently: active features,
grouped by `mapblklot` (or `blklot` when empty), with an id matching `[A-Za-z0-9]{1,40}` and at least
one polygon. It must split exactly into the generator's **generated** and **excluded** parcels, and
these must agree with the files actually present:

| Check | Meaning |
| --- | --- |
| `input_not_accounted` / `accounted_not_input` | valid input = generated ∪ excluded, in both directions |
| `generated_and_excluded`, `*_duplicate` | the sets are disjoint and free of duplicates |
| `generated_without_farm_file` / `farm_file_not_generated` | report rows vs `farms/` on disk |
| `farm_file_not_in_manifest` / `manifest_farm_without_file` | `farms/` on disk vs `manifest.json` |
| `index_without_farm_file` / `farm_file_not_in_index` | `index.geojson` vs `farms/` on disk |
| `excluded_with_farm_file` | an excluded parcel still has a farm |
| `dataset_file_integrity` | every file's SHA-256 against `manifest.json` (tiles included); unlisted or missing files. `manifest.json`, `client-manifest.json` and the host-written `tilejson.json` are not listed by design |
| `snapshot_file_integrity` | raw snapshot files against `source-manifest.json` |
| `invalid_parcel_not_reported_rejected` / reverse | rejected parcel records agree with the audit's own invalid set |
| `count_mismatch …` | report totals and `manifest.parcel_count` against the real counts |
| `snapshot_manifest_sha256` | the dataset was built from this snapshot |

Exclusions are counted by category (`no_building`, `layout`, …) and by full reason. Lot numbers
(aliases) are counted separately: all valid lots = lots under farms + lots under excluded parcels,
and each farm's `parcel_aliases` must equal the snapshot's lots for that parcel.

## 2. Source-geometry audit (per farm)

1. The farm's buildings are `(stats.building_source, area_id)` pairs; their **geometry is always
   taken from the snapshot**, never from the dataset. Two dataset layouts are accepted:
   - from C-55 on, the ids are `building_area_ids` in `reports/generation-report.json`, and
     `buildings.geojson` is a lighter map layer (no `area_id`, 6 decimals, 0.1 m simplification);
   - before that, the ids are the `area_id`s of the farm's features in `buildings.geojson`, whose
     coordinates must then match the snapshot within `coordinate_tolerance_deg`.
   When both carry ids they must agree. In both layouts the farm's map-layer footprints are
   compared with the snapshot footprints by area (IoU ≥ `layer_iou_min`), so rounding and
   simplification are tolerated while a wrong or missing building in the map is listed.
2. Footprints are projected to UTM 10N with **proj4** (not the generator's projection), then moved
   into the farm grid: subtract `source_transform.origin_m`, rotate by `-rotation_deg` (the schema's
   convention), divide by `source_cell_m`. Cell `(x, y)` is then the unit square `[x, x+1] × [y, y+1]`.
3. The footprints are unioned with **polygon-clipping** (exact; overlaps are not counted twice).
   IoU = |S ∩ C| / (|S| + |C| − |S ∩ C|), where C is the core cells from `zones.core.runs` and
   |S ∩ C| is the exact clipped area per run. No supersampling.
4. Topology: source components and holes = polygons and interior rings of the union; core
   components (4-connected cells) and holes (8-connected empty regions not reaching the border).
   Differences are listed, not failed: two buildings closer than a cell merge, and notches can close.
5. Attribution: for each footprint, the share of its area inside its own parcel, the other snapshot
   parcel holding the largest share, and the share inside no parcel (street, or a parcel outside a
   bbox snapshot).

## Defaults (`src/config.ts`; override with `--params file.json`)

| Name | Default | Effect |
| --- | --- | --- |
| `iou_exclude` | 0.85 | audited IoU below it → farm `fail` (r4: excluded below 0.85) |
| `iou_warn` | 0.90 | audited IoU below it → `warn` (r4: 0.85–0.90 needed approximation_warning) |
| `iou_delta_warn` | 0.01 | \|audited − generator IoU\| above it is listed (`iou_differs_from_generator`) |
| `attribution_min_fraction` | 0.5 | a footprint with less of its area in its own parcel is listed |
| `area_rel_warn` | 0.001 | union area vs the farm's `source_area_m2` differing by more is listed |
| `coordinate_tolerance_deg` | 1e-7 | original layout only: `buildings.geojson` coordinates (7 decimals) vs the snapshot |
| `layer_iou_min` | 0.90 | map-layer footprints vs snapshot footprints, per farm; C-49 sample: ≥ 0.9986, C-55 layer: ≥ 0.985 |

Failures: reconciliation discrepancies, IoU below `iou_exclude`, buildings or parcels missing from
the snapshot, core runs that overlap / leave the grid / disagree with `counts.core_cell_count`, and
unreadable farm files. Everything else is a warning and does not change the exit code.

The two flags in C-48#13 are counted on their own: `summary.total_cap_and_too_small` lists farms
carrying both `cell_scaled_for_total_cap` and `too_small`.

## Notes

- The generator estimates IoU from 4 × 4 samples per cell and keeps the best of 16 grid offsets by
  that estimate, so its value is expected to sit slightly above the exact one (C-49 sample: mean
  −0.0044, largest −0.015, on 150-cell farms).
- On a bbox snapshot, parcels just outside the bbox are absent, so `share_outside_parcels` near the
  edge also includes neighbours that were not fetched.
- Not covered here: vector tiles and tile checks (REPRODUCE-r4 steps 5–6, C-55).
