# Dynamic Farm r4 integration

The demo selects a parcel through its building or open ground. Mapbox parcel fill
and line opacity are zero; the source and hit layer remain enabled. Only the
selected building has a yellow highlight. Claim names/dots remain visible and
claim ownership semantics do not change. Transparent fill picking requires real
Android Mapbox verification; isolated callbacks do not establish that result.

Dataset: `sf-dynamic-farm-20261118-r4`. Client manifest, catalog and farms use
schema4. Native feature metadata carries `core_cell_count`,
`extension_cell_count`, `total_cell_count`; the legacy `cell_count` equals core.
The shared `modules/dynamic_farm/farm_data.gd` decoder validates RLE, permissions,
counts, budgets and walking reserves. The 2D view shows both zones. Extension is
local walking space, never a change to the geographic parcel or claim boundary.

`config.json` deliberately has no endpoint/client pin until reviewed city data
is deployed. Do not package this intermediate state. Freeze URL, dataset and
client manifest SHA together in source; the packager must not silently replace
them. The compact manifest does not contain files or per-farm cell totals.
No r3 small fallback remains active in r4. Historical versions/services stay intact.

Package/signature/userdir stay `com.sensen.geofarmdemo` and
`gensen-geofarm-demo-1117`; display name is Dynamic Farm DEMO. Reserved version is
2026111801 / 0.0.4-demo, subject to coordinated build-date changes. Identity file
is `user://geo_farm_identity_sf-dynamic-farm-20261118-r4.json`. Only the installation
credential may be read from earlier versions; ownership/pending claims never migrate.

Main scene: `res://demo/geofarm/geofarm_main.tscn`. Export all five runtime Kotlin
sources from the same integration head: GodotMapPlugin, ParcelMapController,
ParcelLayerState, ParcelPayload and ParcelBuildingSelection. Exclude *Test.kt.
Include dynamic farm_data plus dynamically loaded farm_view/farm_* and config;
use the build-controlled Mapbox token and no game autoloads/location permission.

## Verification

A new explicit resource window is required before Godot, device or build work.
`prepare_isolated.py` makes a no-autoload project without real endpoint/token.
Use an absolute window deadline, private adb5113 and recorded-PID cleanup.

- Contract/identity: 22/22.
- Source/provider configuration: 12/12.
- Metadata counts: 10/10.
- Actual main scene with injected HTTP/native callbacks: 53/53.
- Shared decoder/view with seven author samples: 67 checks, zero failures.
  This run omitted the author's two extra synthetic JSON inputs; do not label it 69.
- Public HTTP runner updated for schema4; not run against a real r4 endpoint yet.

The seven author samples are not deployment data. Native transparent-layer hits,
yellow-only highlight, claimant names, A-to-B/B-to-A visits and dataset upgrades
still need actual APK smoke. Separate host lifecycle fixtures passed 12 checks;
that does not validate the 3D scene, navigation, appearance or device performance.
