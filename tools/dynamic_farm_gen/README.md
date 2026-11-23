# Dynamic farm dataset generator (r5, `building-raster-1`)

Generates the schema-4 dynamic farm dataset the client reads (`modules/dynamic_farm/farm_data.gd`,
`map/parcel_metadata.gd`, `map/geo_map_config.gd`) from DataSF **building footprints** and
**parcels**. It replaces the r4 generator `dynamic-core-ext-1`, whose source is not available
(C-48#3). Decisions: Q-59 (the farm follows the building outline), Q-58 (regenerate the dataset,
DataSF geometry only, never Mapbox geometry, never on devserver).

The client is not changed here (C-43). The current client still accepts only 760–840 core cells;
r5 farms pass every other check and pass completely once C-43 lifts that one rule
(`godot/check_client_decode.sh` shows both).

## Data sources and licence

| Role | DataSF dataset | Licence |
| --- | --- | --- |
| Parcels | Parcels – Active and Retired, `acdm-wktn` (active parcels) | ODC PDDL 1.0 |
| Buildings | Building Footprints, `ynuv-fyni` | ODC PDDL 1.0 |

Source labels (`src/sources.ts`):

- `datasf-parcels`, `datasf-buildings` – the DataSF (Socrata) API itself. Use these for the real
  build. The local Mac's network gets HTTP 403 from every Socrata domain, so they are untested here.
- `sfgis-parcels`, `sfgis-buildings` – the City and County of San Francisco's ArcGIS Online copies
  ("from DataSF, pulled daily/weekly", owner `vll_sfgis`, licence stated as PDDL 1.0). The building
  copy is **incomplete**: 82,000 of 177,023 rows (area_id 21567–143982; the largest and the
  newest-numbered footprints are missing).
- `sfenv-buildings` – `Buildings_filtered` in the same City organisation (SF Environment,
  2025-02): the same DataSF records, 127,010 rows, about 1.3 m west-north-west of the sfgis copy.
  No licence is stated on the copy; the records are DataSF's PDDL data. Local fallback only.

A parcel never mixes building copies: it uses the copy with the most footprint area for that parcel
(earlier sources win ties), and its farm records which one in `stats.building_source`.

The snapshot (`fetch`) keeps every response byte-for-byte with its SHA-256 and the source's
licence/edit metadata (`source-manifest.json`); `build` reads only a snapshot. The dataset
`manifest.json` repeats the snapshot sources, versions and hashes.

## What a farm is made of

1. **Buildings → parcel.** Every footprint goes to the parcel holding most of its 1 m sample points;
   its `mblr` (a centroid join from a draft basemap) only breaks ties or covers misses. Condominium
   lots share one parcel (`mapblklot`); the other lot numbers are `parcel_aliases`. Parcels with no
   footprint get no farm (`excluded`, reason `no_building`). All of a parcel's buildings form its core.
2. **Grid.** UTM 10N metres (EPSG:32610, own Krüger implementation, matches proj4 to 0.1 mm).
   The grid turns to the buildings' dominant wall direction (always within ±45°, recorded as
   `source_transform.rotation_deg`) and picks the best of 16 sub-cell offsets by IoU.
3. **Core.** A cell is core when ≥ 50% of it lies inside a footprint (4×4 supersampling).
   Islands under 4 cells are dropped. `stats.core_iou` is raster/footprint intersection-over-union.
4. **Cell size.** Fixed `cell_m` (0.5 m, i.e. **0.25 m² per cell**), so cells grow with area. If a
   building would exceed `core_cell_cap`, the cell grows instead (same shape, flag
   `cell_scaled_for_core_cap`); if core + extension would exceed `total_cell_cap` (8192) or a grid
   axis 544, it grows further (`cell_scaled_for_total_cap`).
5. **Walking reserve** (`walk_reserve.no_solid_decor_runs`): the core, the client's 2-cell rounded
   ring around it, 3-wide paths that join separate buildings (`buildings_joined_by_path`) and a
   5-wide entry corridor with a centre path.
6. **Entry.** Toward the street: 3 m outside each parcel side is probed; the side whose probes hit no
   other parcel (right-of-way) wins, then the smaller building setback, then S, W, E, N. The
   corridor leaves from the main (largest) building's most protruding column, the entry is its last
   cell and the spawn is that building's most interior cell nearest the column.
7. **Extension.** Grass within `extension_cells ± extension_jitter` (5 ± 2) of the walking area,
   smooth value noise from the parcel seed. Only ground connected to the core is kept.
8. **Output.** The r4 schema-4 fields unchanged (`zones`, `capabilities`, `counts`, `boundaries`,
   `walk_reserve`, `surface_palette`, `game_cell_m` 0.8, `seed_hex`, …). `source_area_m2` is now the
   footprint area; `source_transform.origin_m` is the UTM position of grid point (0, 0).

`seed_hex` = SHA-256 of `sensen-dynamic-farm|<block_id>|<source_geometry_hash>`: decor stays the
same across dataset versions while the geometry is unchanged.

Determinism: no clock or randomness in `build`; floats are rounded before output. The engine's
`Math.sin/atan/exp/…` and `**` differ in the last bit between platforms (e.g. arm64 Mac vs x86-64
Linux), so the build path uses `src/detmath.ts` (fdlibm ports using only IEEE-exact + − × ÷ and
`Math.sqrt`); areas are summed relative to each ring's first vertex. The same snapshot, parameters
and `--dataset-version` give byte-identical files on any machine: `test/dataset.test.ts` pins the
manifest hash of the test range and fails if the build calls a libm function, and
`test/detmath.test.ts` pins one UTM projection bit for bit.

## Parameters (defaults, `src/config.ts`; override with `--params file.json`)

| Name | Default | Why |
| --- | --- | --- |
| `cell_m` | 0.5 (0.25 m²) | A typical St. Francis Wood house (150–250 m²) gets 600–1000 cells, close to r4's ~800 |
| `core_cell_cap` | 4096 | Half of the 8192 client budget; the extension needs the rest (175 JUNIPERO SERRA: 3972 + 2694) |
| `total_cell_cap` | 8192 | Client `MAX_CELLS`; cannot be raised |
| `min_core_cells` | 400 | Owner's example in C-43#6 (= 100 m² at 0.25 m²); below it the farm is still written but flagged `too_small` (farm `stats` and index) |
| `coverage_threshold` | 0.5 | Half-covered cells count; keeps the raster area equal to the footprint area |
| `min_component_cells` | 4 | Drops slivers from footprint noise |
| `extension_cells` / `extension_jitter` / `extension_noise_period` | 5 / 2 / 8 | Similar to r4's 3–7 cell grass band |
| `align_to_building` | true | Straight edges instead of staircases |
| `samples` | 4 | 16 samples per cell |

## Output layout

```
client-manifest.json      what the client pins (manifest SHA, native_map: geojson + datasf buildings)
manifest.json             every file's SHA-256, parameters, sources
index.geojson             parcels with farms, parcel_metadata.gd properties (+ too_small)
buildings.geojson         the footprints used, block_id per feature (map highlight = farm shape)
farms/p-<id>.json         schema-4 farms
reports/generation-report.json   per-parcel area, cell size, counts, IoU, flags; exclusions
```

## Usage

```sh
cd tools/dynamic_farm_gen
# Local sample (test range around 130 SAN RAFAEL WAY / 175 JUNIPERO SERRA BLVD):
pnpm cli fetch --out "$TMPDIR/snap" --sources sfgis-parcels,sfgis-buildings,sfenv-buildings \
  --bbox -122.4718,37.7316,-122.4692,37.7350
pnpm cli build --snapshot "$TMPDIR/snap" --out "$TMPDIR/r5" --dataset-version sf-dynamic-farm-20261123-r5
pnpm cli validate --dataset "$TMPDIR/r5"                       # C-43 rule; --core-range current = today's client
pnpm cli compare --dataset "$TMPDIR/r5" --before <r4 farms dir> --out "$TMPDIR/cmp" --ids p-3250003,p-3250006
godot/check_client_decode.sh "$TMPDIR/r5"                    # the client's own GDScript parsers

# Full city (planned on cardigan-ci): official DataSF sources, no --bbox.
pnpm cli fetch --out snap-full --sources datasf-parcels,datasf-buildings
pnpm cli build --snapshot snap-full --out r5 --dataset-version sf-dynamic-farm-<YYYYMMDD>-r5
```

`test/fixtures/sf-test-snapshot` is the test-range snapshot fetched 2026-11-23 (sfgis parcels
2026-11-22, sfgis buildings 2026-11-22, sfenv buildings 2025-02-24).

## Known limits

- The local sample uses the City's ArcGIS copies, not DataSF's API (blocked from this network); some
  parcels there lack their main house (e.g. 110/120 SAN LEANDRO WAY get only a garage and are
  `too_small`). The full build must use `datasf-*`.
- `index.geojson` / `buildings.geojson` suit a sample. A full-city map needs vector tiles for
  parcels (r4 used tippecanoe) and a tiled or otherwise lighter building layer; the native map takes
  DataSF buildings only as GeoJSON today (C-43 / C-48).
- DataSF footprints date from 2010–2017 edits; newer buildings may be missing or differ from Mapbox.
