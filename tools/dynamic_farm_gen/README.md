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

- `datasf-parcels`, `datasf-buildings` – the DataSF (Socrata) API itself, `data.sf.gov` (the old
  `data.sfgov.org` now 301-redirects there). Use these for the real build. From a mainland-China
  egress (cardigan-ci, the control host, the local Mac) the Socrata edge answers **every** request
  with a bare nginx 403 – homepage, metadata and data alike, on every Socrata portal (SF, NYC,
  Seattle, LA), with or without an app token – so this is a regional block, not a rate limit, a
  missing token or a moved endpoint (C-75). The fetch fails at once with a message saying so.
  To use these sources, fetch from an egress outside mainland China, e.g. through a proxy:
  `NODE_USE_ENV_PROXY=1 HTTPS_PROXY=http://<proxy> pnpm cli fetch …` (Node 24's `fetch` honours it).
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
client-manifest.json      what the client pins (manifest SHA, native_map: parcel tiles + datasf buildings)
manifest.json             every file's SHA-256, parameters, sources, map_layer (tile encoder, parameters, tile counts)
tiles/<z>/<x>/<y>.pbf     parcel vector tiles (MVT 2.1, uncompressed), layer "parcels", z15–18
tilejson.template.json    TileJSON for the tiles with a {PUBLIC_BASE} placeholder
index.geojson             parcels with farms, parcel_metadata.gd properties (+ too_small); same outlines/properties as the tiles
buildings.geojson         map layer: the footprints used, one feature each, block_id only, lighter geometry
farms/p-<id>.json         schema-4 farms
reports/generation-report.json   per-parcel area, cell size, counts, IoU, flags, source area_ids; exclusions
```

Not in `manifest.json`: `tilejson.json`, written by the host once the public base URL is known
(`cli tilejson`), because Mapbox needs absolute tile URLs and the base usually contains the
dataset's own hash. Pin it separately when deploying.

## Map layer (C-55)

The client (`modules/dynamic_farm/map/geo_map_config.gd`, Android `ParcelPayload.kt` /
`ParcelMapController.kt`) reads parcels either as one GeoJSON or as a Mapbox vector source through a
TileJSON with source layer `parcels` and promoteId `block_id`; DataSF buildings only as one GeoJSON.
A full city cannot ship as one index.geojson, so the dataset uses the r4 map format:

- **Parcel tiles** (`src/mvt.ts`): real parcel outlines (never farm cells), every index property
  on each feature, z15–18, extent 4096, clipped to the tile plus an 80-unit buffer (r4: tippecanoe
  `--buffer=5`), quantized to tile units, no simplification, no feature or size limit. The encoder
  is built in rather than tippecanoe: no native tool is needed and, using only IEEE-exact
  arithmetic and `src/detmath.ts`, the tiles are byte-identical on every platform. Tiles are not
  gzipped (zlib's bytes depend on platform/build); Mapbox reads both, the CDN may compress.
- **Tile check** (`src/tilecheck.ts`, `cli check-tiles`, also part of `cli validate`): decodes
  every tile with `@mapbox/vector-tile` + `pbf` (independent of the encoder), checks layer, version,
  extent, hashes and unlisted files, compares every feature's properties (block_id, parcel_id, name,
  address, farm_path, counts, …) with index.geojson, checks the farm exists and the geometry is a
  polygon inside the parcel's bounds, lists coverage and missing parcels per zoom and **fails if
  any parcel is missing at the maximum zoom**. `--report` writes the JSON report (decoder and Node
  versions included), `--properties` the decoded maximum-zoom properties for the Godot check.
  `cli validate` on a dataset without `manifest.map_layer` and without tiles (r4, the GeoJSON-only
  r5 of C-49) skips this check and says so; tiles without `map_layer` count as a failure.
- **Client whitelist** (`godot/check_public_keys.sh`, run first by `check_client_decode.sh`):
  `check_decode.gd`'s `PUBLIC_KEYS` must list exactly `ParcelPayload.propertyKeys`
  (`tools/android/overlay/ParcelPayload.kt`), the properties the native map hands to GDScript.
- **Building layer** (`src/buildings.ts`): stays GeoJSON (the only building format the client
  reads), one feature per used footprint so a tap still highlights that building, `block_id` only
  (the source `area_id`s are in the generation report), lon/lat rounded to 6 decimals (~0.1 m) and
  vertices within 0.1 m of the outline dropped (Douglas–Peucker); a ring that would degenerate
  keeps its unsimplified shape, a footprint is never dropped. Test range: 77,147 → 51,817 bytes,
  2,413 → 1,634 vertices.

Map parameters (`src/mvt.ts`, override with `build --map-params file.json`):

| Name | Default | Why |
| --- | --- | --- |
| `tile_minzoom` / `tile_maxzoom` | 15 / 18 | r4 format; client defaults `source_minzoom` 15, `source_maxzoom` 18 |
| `tile_extent` | 4096 | MVT default; ~0.03 m per unit at z18 in SF |
| `tile_buffer` | 80 | r4 tippecanoe `--buffer=5` (5/256 of a tile) |
| `building_decimals` | 6 | ~0.1 m, below a pixel at z20 |
| `building_simplify_m` | 0.1 | removes collinear/noise vertices only |

## Usage

```sh
cd tools/dynamic_farm_gen
# Local sample (test range around 130 SAN RAFAEL WAY / 175 JUNIPERO SERRA BLVD):
pnpm cli fetch --out "$TMPDIR/snap" --sources sfgis-parcels,sfgis-buildings,sfenv-buildings \
  --bbox -122.4718,37.7316,-122.4692,37.7350
pnpm cli build --snapshot "$TMPDIR/snap" --out "$TMPDIR/r5" --dataset-version sf-dynamic-farm-20261123-r5
pnpm cli validate --dataset "$TMPDIR/r5"                       # C-43 rule; --core-range current = today's client
pnpm cli compare --dataset "$TMPDIR/r5" --before <r4 farms dir> --out "$TMPDIR/cmp" --ids p-3250003,p-3250006
pnpm cli check-tiles --dataset "$TMPDIR/r5" --report "$TMPDIR/mvt-validation.json"
godot/check_client_decode.sh "$TMPDIR/r5"                    # the client's own GDScript parsers (also decodes the tiles)
pnpm cli tilejson --dataset "$TMPDIR/r5" --base https://<host>/<prefix>   # on the host, after upload path is known

# Full city: official DataSF sources, no --bbox. Needs an egress outside mainland China (see above).
NODE_USE_ENV_PROXY=1 HTTPS_PROXY=http://<proxy> pnpm cli fetch --out snap-full --sources datasf-parcels,datasf-buildings
pnpm cli build --snapshot snap-full --out r5 --dataset-version sf-dynamic-farm-<YYYYMMDD>-r5
```

`test/fixtures/sf-test-snapshot` is the test-range snapshot fetched 2026-11-23 (sfgis parcels
2026-11-22, sfgis buildings 2026-11-22, sfenv buildings 2025-02-24).

## Known limits

- The local sample uses the City's ArcGIS copies, not DataSF's API (blocked from this network); some
  parcels there lack their main house (e.g. 110/120 SAN LEANDRO WAY get only a garage and are
  `too_small`). The full build must use `datasf-*`.
- `buildings.geojson` is lighter but still one file for the whole city: the native map takes
  DataSF buildings only as GeoJSON (C-43). With `building_source=mapbox` (today's config.json) the
  client does not download it at all.
- z15 tiles of dense blocks can be large (all properties, no size limit, as r4); the parcel layer
  is shown from zoom 16, and `check-tiles` reports the largest tile per zoom.
- DataSF footprints date from 2010–2017 edits; newer buildings may be missing or differ from Mapbox.
