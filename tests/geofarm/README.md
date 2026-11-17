# GeoFarm parcel r2 client

This branch targets only the 1322-parcel screenshot area. Data schema 2,
`sf-parcel-20261117-v2`. Main scene remains
`res://demo/geofarm/geofarm_main.tscn`. `config.json` pins the r2 HTTPS endpoint,
manifest hash and two address shortcuts; no r1 server fallback.

Mapbox owns all map geometry, fill/line/building/address/claim-name layers and
picking. Godot downloads only the manifest, public claims and individual farms;
`geo_native_camera.gd` handles gestures and coalesces camera updates once per frame.
It never scans/reprojects/draws polygons. This version uses native **GeoJSON**,
not MVT or Standard 3D. MapView remains the existing SurfaceView.

Copy the four runtime Kotlin files into Android `src/main/java/com/sensen/map/`:
`GodotMapPlugin.kt`, `ParcelMapController.kt`, `ParcelLayerState.kt`, `ParcelPayload.kt`.
Do not put `*Test.kt` into the app. Preserve SDK android-ndk27 11.29.0 and the
existing build-controlled Mapbox token. Export all demo scripts and dynamically
loaded `scenes/geo_farm_demo/farm_view.tscn`/farm_* dependencies plus config.json.
Use a separate package/user directory, no game autoloads or location/audio
permissions. No production accounts, services, or saves are used.

`block_id` is `p-3139019`; `parcel_id` is canonical `3139019`. Native promoteId,
query results, state updates and claim bodies use **block_id**. Only public
whitelisted metadata crosses the native bridge, never geometry or device IDs.
Callbacks check request ID, scene/data generation, style generation and camera
revision. `source_ready` gates picking on parcel data; building readiness is
separate because buildings are hidden below zoom 18. Failed building/claim
markers show a retry warning; failed parcel data disables picking.

The v2 identity file is `user://geo_farm_identity_sf-parcel-20261117-v2.json`.
On update, it may read the original private 64-hex installation credential from
`user://geo_farm_identity.json`; it never writes that file or migrates its
census ownership/pending claim. New v2 ownership/pending are version checked.
Never log/upload real identity files. Unknown claim results retain the original
ID/nickname for an idempotent retry. A late claims GET cannot erase a committed
claim. The HTTP adapter pins the manifest hash before accepting its JSON.

Find an example parcel… opens a menu with 328 FRIDA KAHLO WAY / 424 STAPLES AVE;
choosing one moves to its center at zoom 19.5 and selects it, without claiming.
Demo area resets to [-122.45190271843384,37.729419227], zoom 17.5.
Parcel layers start at 17; addresses/buildings at 18; pinch range 13–21.

## Verification

Obtain a new Godot resource window before running. Preparation creates an
isolated no-autoload project outside the repository and deliberately omits the
real endpoint config/token. Use a dedicated user directory for r2 QA.

```sh
python3 tests/geofarm/prepare_isolated.py /absolute/temporary/qa
adb -P 5113 start-server
ANDROID_ADB_SERVER_PORT=5113 godot --headless --path /absolute/temporary/qa --editor --import
ANDROID_ADB_SERVER_PORT=5113 godot --headless --path /absolute/temporary/qa --script res://tests/geofarm/test_parcel_contract.gd
ANDROID_ADB_SERVER_PORT=5113 godot --headless --path /absolute/temporary/qa --script res://tests/geofarm/test_parcel_flow.gd
ANDROID_ADB_SERVER_PORT=5113 godot --headless --path /absolute/temporary/qa --script res://tests/geofarm/test_parcel_public_http.gd -- https://approved-r2-endpoint
adb -P 5113 kill-server
```

The first suite checks 14 contract/identity boundaries; the second exercises the
real main scene using injected native/HTTP callbacks (36 checks). The third does
8 **read-only real HTTPS** checks for the pinned manifest, claims and both real
795/809-cell farms. These do not prove native Mapbox drawing, picking alignment,
labels, hardware keyboard behavior or device frame rate. The original r1 map
script is retained only under tests as `baseline_r1_map.gd`; its prior tests and
captures live at git b6b0f6eae. Exclude tests from the product export.

Native bridge author separately compiled Kotlin and ran 21 JVM tests at
606609075731ef93850ec63945c334f3af2a0029. Farm author ran their component suites
at 0ac4b1753131784349a6d5e5bfa4482860323c33. Do not add those numbers to the client
suites or call them combined APK acceptance. Record owned PIDs and release each
window; no extra runs after release without a new grant.
