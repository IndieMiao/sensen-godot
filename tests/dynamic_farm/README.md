# Dynamic Farm map and preview host

This farm-dev branch adds an independent art entry:
`res://scenes/dynamic_farm/dynamic_farm_map.tscn`.
It leaves existing main scenes, home creation, saves and PR-A unchanged. It does
not claim a parcel or attach a gameplay session. Its action is “Preview in 3D”.
Formal account ownership/creation is a separate server contract, not a demo
installation credential.

The map reads only a pinned client-manifest and the selected schema4 farm. It
uses the shared MapBridge JSON-string API and global generation allocator.
A building hit selects the parcel returned from the same native query; open
ground falls back to parcel. Metadata is whitelisted, counts are separate, and
opaque building keys never enter the farm payload. Multi-hit selection is explicit.
The native layer draws no visible parcel frames, retaining building highlights.

Pause/Back retires HTTP and query epochs, clears this generation's native layers
and hides the map. Return gets a new global generation and restores the camera.
No geographic outlines or farms are generated on the client.

`dynamic_farm_host.tscn` receives preview_only=true + matching dataset/block_id
and full farm payload. It connects child signals before setup/add_child, handles
synchronous failures, retries and rejects old ready/Back signals. It expects
Liu Bang's `dynamic_farm.tscn` with preview_ready/preview_error/back_requested and
suspend/resume. The ready child owns its visible Back button; the host owns errors.
AppRouter remains the only system-Back dispatcher.

## Isolated builds

Do not merely change main_scene and boot the normal project. Net's autoload can
start the official Journey endpoint before a main scene runs. The separate QA
build must set `sensen/network/online_qa=true` BEFORE autoload startup, retain
needed Avatar/AppRouter symbols, and use an isolated package/userdir. The scene's
setting check is only an additional guard, not a replacement for build isolation.
No stage-two APK or 3D-scene acceptance is claimed here.

`modules/dynamic_farm/map/config.json` intentionally has blank URL/pin until the
reviewed r4 deployment is ready. The packager must take exact source config, not
silently replace URL/hash. Include five native runtime Kotlin files (no *Test),
map/farm code from the same precise integration tree and the build-managed token.
Android first; unsupported platforms show a clear message, without a fake map.

## Tests

Run prepare_isolated.py with a fresh external target. It copies exact scripts and
writes SHA256 records, without autoloads, service config, credentials or tokens.
Any Godot/device/build run needs a new explicit resource window and absolute
deadline cleanup. The tests use a fake scene or fake native/transport API:

- test_preview_host.gd: synchronous ready/error, retries, old callbacks, single Back,
  pause/resume and rejecting gameplay/wrong-parcel inputs (12 checks passed Q44).
- test_selection_controller.gd: same-point IDs, count-preserving farm decode,
  callback invalidation, style changes, cancellation, timeout and read-only paths.
  21/21 passed Q47; fake callbacks do not prove SDK hit testing.

Real r4 HTTPS, transparent Mapbox picking, UI/3D screenshot review, navigation,
performance and phone input remain distinct verification steps.
