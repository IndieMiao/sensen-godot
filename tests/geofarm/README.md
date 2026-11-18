# Dynamic Farm r4 integration

The demo selects a parcel through its building or open ground. Mapbox parcel fill
opacity is zero; the source and hit layer remain enabled. Per decision 1C,
parcel line opacity follows selected state: ground/courtyard selection shows
a yellow 2.5px outline, while unselected/claimed/owned parcels have no frame.
Building selection keeps its separate yellow highlight and no parcel frame. Claim names/dots remain visible and
claim ownership semantics do not change. Transparent fill picking requires real
Android Mapbox verification; isolated callbacks do not establish that result.

Dataset: `sf-dynamic-farm-20261118-r4`. Client manifest, catalog and farms use
schema4. Native feature metadata carries `core_cell_count`,
`extension_cell_count`, `total_cell_count`; the legacy `cell_count` equals core.
The shared `modules/dynamic_farm/farm_data.gd` decoder validates RLE, permissions,
counts, budgets and walking reserves. The 2D view shows both zones. Extension is
local walking space, never a change to the geographic parcel or claim boundary.

`config.json` and its example now pin the deployed r4 root, dataset and 918-byte
client manifest together. Deployment receipt: `dynamic-farm/PUBLIC-ENDPOINT-r4.json`.
Client SHA: `645df3530b5617bb7e5a8cfb0d070e0e82b74337db47f83a542df1e90c3ae1cf`.
The compact client binds full deployment manifest
`6559392b147b0f21e97d522d0cdeab428f5ace7eb69a359dc75c19955ed6a88f`.
Do not substitute the author's pre-deployment client hash. The packager must read
exact source config and must not silently replace the URL/hash. Shortcut metadata
for 328, 424 and the literal-star parcel comes from the reviewed catalog; counts
are cross-checked with the deployed farm files. No city geometry is embedded.
Historical r1/r2/r3 services and evidence stay intact.

Package/signature/userdir stay `com.sensen.geofarmdemo` and
`gensen-geofarm-demo-1117`; display name is Dynamic Farm DEMO. The coordinated r4 build version is
2026111901 / 0.0.4-demo (November 19); the earlier 2026111801 reservation is retired. Identity file
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
- Real deployed HTTPS reads: 13/13 in Q1117-53 (pinned client manifest, claims,
  328/424/literal-star schema4 farms and their two-zone views). No POST or device
  rendering was performed.

The seven author samples are not deployment data. Native transparent-layer hits,
yellow-only highlight, claimant names, A-to-B/B-to-A visits and dataset upgrades
still need actual APK smoke. Separate host lifecycle fixtures passed 12 checks;
that does not validate the 3D scene, navigation, appearance or device performance.
