# GeoFarm r3 integration

R3 keeps the farm and claim unit as the whole parcel. A tap first selects a visible
building and uses the **same pixel/query snapshot** to find our parcel; a successful
empty building hit falls back to parcel selection. A building without a selectable
parcel never creates a claim. Mapbox building geometry stays transient inside the
native highlight controller; Godot stores only an opaque UI key, never building
geometry in identity/claim/farm data. `building_source` can be `mapbox` or `datasf`.

Full city: `sf-parcel-20261117-v3`, native vector source / source-layer `parcels`,
promoteId `block_id`, source zoom 15–18, parcel display from 16, addresses from 18.
Above 18 Mapbox overzooms instead of requesting nonexistent tiles. Small fallback:
`sf-parcel-small-20261117-v3`, separate GeoJSON source and claim data.
Manifest schema is 3; individual farms remain schema 2. Phones read a compact
`client-manifest.json`, claims and single farms, never the full catalog/hash table.
The complete deployment manifest remains for server verification.

`config.json` pins full-city URL/client SHA and `config.small.example.json` pins
the fallback. Change URL, dataset AND matching client SHA together. Each version
has its own `geo_farm_identity_<dataset>.json` under user://. Only the installation
credential is reused from earlier files; own/pending claims never migrate between
r1/r2/full-v3/small-v3. Literal official ID `p-4591A011*` stays intact in IDs and
farm paths; separators, traversal, query/fragment characters are refused.

Main scene is still `res://demo/geofarm/geofarm_main.tscn`. Export the same standalone
package `com.sensen.geofarmdemo`, versionCode 2026111703, with the existing custom
user directory `gensen-geofarm-demo-1117`, no game autoloads or location/mic permission.
Copy five Kotlin runtime files from the SAME integration commit:
GodotMapPlugin.kt, ParcelMapController.kt, ParcelLayerState.kt, ParcelPayload.kt,
ParcelBuildingSelection.kt. Do not export *Test.kt or tests/. Include config and
the dynamically loaded farm_view.tscn/farm_*; preserve the build-controlled token.

The two UI fixes are included: the shortcut initializes to its prompt and a
successful query clears Finding parcel…. The shortcut menu moves to 328/424 at
zoom19.5 and preselects its parcel; native building picking must still be tested
by tapping the real building after navigation. Demo area resets to the screenshot
center [-122.45190271843384,37.729419227] /17.5. MapView is SurfaceView, not TextureView.

## Verification boundaries

Get a NEW resource grant before any Godot run; an expired or released grant cannot
be reused. `prepare_isolated.py` creates a separate no-autoload QA project without
real endpoint config/token. Use private adb -P 5113 only and record/clean owned PIDs.

- test_parcel_contract.gd: 20 contract/identity checks, including full/fallback isolation.
- test_r3_map_config.gd: 12 source/provider/version checks. An initial old fixture still
  contained a DataSF URL; correcting that fixture made the missing-source case pass.
- test_parcel_flow.gd: 50 actual-main-scene checks with injected native/HTTP callbacks,
  including building priority, ground fallback, stale results and the two UI fixes.
- test_r3_catalog_ids.gd takes the actual catalog path; 154444/154444 IDs accepted,
  including the literal-star ID, while separators/traversal were rejected.
- test_parcel_public_http.gd takes base URL, dataset and client SHA; it is read-only.
  Small-v3 HTTP passed 8 checks, but that run exceeded the prior resource window;
  its timing correction is retained separately. No full-city Godot HTTP pass is claimed.

Native author separately ran 28 JVM checks, then one targeted star compatibility
check; do not add these to client counts or call them APK acceptance. Native
Streets/whole-city MVT picking, highlight alignment, cross-tile behavior, hardware
keyboard, map performance and final upgrade/two-identity flows require APK smoke.
