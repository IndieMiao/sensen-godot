# Geographic farm map / claim QA

This is a standalone demo for `com.sensen.geofarmdemo`. It does not instantiate
P0Runtime, game accounts, Net, or Voice. No source location or POI request is made.
Geometry and cells come from the precomputed public-data dataset; this client only
projects, selects and renders them.

Main scene: `res://demo/geofarm/geofarm_main.tscn`.
Config: `res://demo/geofarm/config.json` (`base_url`, HTTPS root/prefix).
Dependencies: all `demo/geofarm/*`, `scenes/geo_farm_demo/farm_*`,
`scenes/map_poc/map_bridge.gd` and `map_bridge_android.gd`; Android GodotMap plugin
and the existing build-controlled `mapbox_token.txt`. The farm scene is loaded by
string path: explicitly include it if exporting selected resources. Use a separate
application/user directory, no game autoloads, portrait 360×800 canvas_items, and
no location/microphone permission. With no AppRouter the demo handles system Back;
if AppRouter is retained, only the router calls its `is_back_navigation_locked`.

Identity: `user://geo_farm_identity.json`; first startup uses 32 cryptographically
random bytes encoded as 64 lowercase hex characters. This is private installation
data, not a hardware identifier. Clearing only the demo package's data creates B;
A's claim remains on the demo service. Pending claims persist before POST and
retry the same identity/block/nickname after an unknown response. No public output
or logs contain real device credentials. Claim response success is authoritative.

Get a Godot resource window first. Prepare an isolated project outside the repo:

```sh
python3 tests/geofarm/prepare_isolated.py /absolute/temporary/qa
```

Preparation copies exact scripts/view sources, writes their SHA256 manifest,
uses a separate user directory and no autoloads. It deliberately does **not** copy
endpoint config or the Mapbox token. Within the approved single-instance window:

```sh
adb -P 5113 start-server
ANDROID_ADB_SERVER_PORT=5113 godot --headless --path /absolute/temporary/qa --editor --import
ANDROID_ADB_SERVER_PORT=5113 godot --headless --path /absolute/temporary/qa --script res://tests/geofarm/test_geofarm.gd
ANDROID_ADB_SERVER_PORT=5113 godot --path /absolute/temporary/qa --script res://tests/geofarm/capture_geofarm.gd -- /absolute/evidence /absolute/generated
ANDROID_ADB_SERVER_PORT=5113 godot --headless --path /absolute/temporary/qa --script res://tests/geofarm/test_public_http.gd -- https://approved-demo-endpoint
adb -P 5113 kill-server
```

Record/verify each owned PID; do not run parallel Godot instances. The public test
is read-only and uses the real HTTPRequest adapter. Unit claim outcomes use an
injected transport, not real server writes. Screenshot neighbor is an explicit
fixture over genuine generated block geometry. Neither proves native Mapbox
alignment, actual keyboard/touch input or two-installation Android behavior.
Those remain the packaged A-select/claim/farm → clear only demo → B-view-A smoke.
