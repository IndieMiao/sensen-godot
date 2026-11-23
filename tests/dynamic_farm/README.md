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
Decision 1C hides standing parcel frames but shows a yellow outline for the
selected open-ground parcel. Building selection keeps only its building highlight.
The controller clears an old parcel selection before another tap or style reload.

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

`modules/dynamic_farm/map/config.json` pins the reviewed r4 read-only dataset:
`https://lonely-window-barely-sheriff.trycloudflare.com`,
`sf-dynamic-farm-20261118-r4`, client SHA
`645df3530b5617bb7e5a8cfb0d070e0e82b74337db47f83a542df1e90c3ae1cf`.
The service is ready; the complete 3D candidate still requires its own reviewed
scene integration and actual package verification. The packager must take exact source config, not
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

### First-tap queries (C-27)

The native query used to answer `loading` whenever Mapbox had not reported map
idle since the last camera change, so the first tap after a pan or zoom often
showed "Could not check that location. Tap again." `ParcelMapController` now
keeps that one tap (same pixel and camera revision) and runs it at the next map
idle; after `IDLE_WAIT_MS` (4 s) without idle it still answers `loading`. A
newer tap, camera move, style reload, hide or clear drops the waiting tap.

Any native error answer gets one automatic re-query of the same point while
"Finding parcel…" stays visible. Only a second error shows the message. The
delay is `query_retry_delay_ms` in `config.json` (default 600, clamped 0–5000);
a camera move or pause cancels it. Contract rejections and the 8 s no-answer
timeout are not retried. `DYNAMIC_QUERY` logs the local request number, native
outcome code, attempt and retry decision only, never the point or parcel.

## 1904 read retries

The demo read API allows three total attempts (including the first) for
client-manifest, catalog-shaped JSON paths and individual farms. The current
client does not download the full catalog; the server's private catalog still
returns 404, which is never retried. Existing origins and SHA pins stay fixed.

Only connection/DNS/TLS/no-response/timeout/truncated transport failures and
HTTP 5xx retry. The two delays are 0.5 and 1 second multiplied by independent
0.75–1.25 jitter. Each request retains its 12-second timeout and 2 MiB limit.
Other HTTP codes, redirect/size/decode failures, hash mismatch, malformed JSON
and caller contract rejection are terminal. No response-body field can enable
retries. Exhaustion returns to the existing error/Retry UI.

Pause/cancel retires the epoch, cancels active HTTPRequests and wakes/stops
backoff timers; a cancelled chain cannot send another attempt. Both old request
and timer lists are captured before callbacks wake, so reentrant replacements
are not cancelled with the retired cohort. Retries retain
the original origin/path/pin. DYNAMIC_HTTP_ATTEMPT emits only local request ID,
resource category, attempt, actual HTTPRequest result/status/setup error and
retry delay/decision, never full paths, response bodies, credentials or location.
A JSON transport success is not logged as a domain-contract success.

Q77: test_read_retries.gd 47/47; test_read_retries_https.gd 14/14 using a
loopback-only TLS fixture and a fixture-specific CA, including real production
backoff timing. An unrelated CA intentionally produces three TLS errors and
never disables verification. test_selection_controller.gd 26/26 retained.
These do not establish public Quick Tunnel or device reliability. The fixture
and all tests remain outside the APK; run only in a new registered resource
window with owned-PID and private-adb cleanup.

Q78 final same-source verification: cancellation reentry old 4/6 (two intended
failures) → fixed 6/6; policy 47/47, actual loopback HTTPS 14/14 and selector
26/26 passed again. Earlier rounds are not added to these totals.

1904 follow-up: `test_retry_http_precedence.gd` uses the same eight cases against
20ead and its replacement. Known 301/401/403/404/429 responses stay terminal even
with a body-size mismatch; status 0/200/503 truncation retains the retry budget.
The real TLS suite also sends short Content-Length bodies for four 4xx statuses.

Diagnostic interpretation:
- `DYNAMIC_LOAD request` means the real selector reached the API call; it is not a socket/server ACK.
- `DYNAMIC_HTTP_ATTEMPT phase=start` means an HTTP attempt is about to be started.
  `phase=result` contains the actual HTTPRequest result, HTTP status and setup error,
  fixed outcome label, monotonic `elapsed_ms`, retry decision and backoff delay.
  `cancelled` / `backoff_cancelled` retire old attempts without retrying.
- `DYNAMIC_LOAD validation_accepted/validation_rejected` is the caller's contract
  gate. Pair it with the preceding HTTP result: `json_received` followed by
  rejection distinguishes schema/data mismatch from transport/hash/JSON errors.
  `superseded` marks an old flow, and configuration/bridge rejection means no API call.
- No URL, path, parcel, credentials, coordinates, headers or body are logged.
  Local request sequence, resource category and selector epoch are correlation metadata.
  Elapsed time is per HTTP attempt or caller load, not a claimed server duration.

These logs cannot reconstruct absent HTTP evidence from the old Q76 APK. They
also do not change Mapbox SDK MVT/TileJSON retries or prove device Surface behavior.

### Core obstacles (C-18)

Run `--headless --script res://tests/dynamic_farm/test_core_obstacles.gd` in
an isolated imported preview project. The default fixtures exercise equal
geometry/seed with different block IDs; append `-- <farm1.json> <farm2.json>
<farm3.json>` to also check individual r4 payloads (review set: `p-3139010`,
`p-3139019`, `p-5402049`). The check counts distinct occupied core cells from
the transformed model bounds, validates all four roles, compares the reopened
layout and checks the entire remaining walk mask against extension-only blockers.
With the props built into the walker, stone/bush/sapling centres are blocked,
weed centres stay walkable, and a 0.2 m lattice flooded from spawn still reaches
every previously reachable cell except those holding a blocking prop. A pinch
fixture (two blocks joined by a one-cell neck, five seeds, 20% coverage) checks
that blocking props never seal an area.

## Model-fitted prop contacts

`test_prop_proxies.gd` loads the actual 13 imported meshes (`prop_outline.gd`).
Every full-fit primitive stays inside the model's top-down projection; tree
primitives also stay inside the low trunk/root hull, except pine_03, whose three
splayed roots no inscribed primitive can cover: it gets the smallest cylinder
that does. At the default fit each solid footprint is at least 80% of its outline
(area-equivalent size and widths along its axes). Against the real model, no
trunk/root cross-section point (trees) or vertex (shrubs, rocks) is reachable by
the walker's centre at a translated, rotated and scaled placement; approaches from
16 directions stop within 3 cm of the model (pine_03 stops up to 7.5 cm short of
its root hull between roots), and a command 6° into the touched face keeps
sliding. Flower/grass profiles are non-blocking even when placed in a new
layout; player radius is counted once. `tools/dev/dynamic_farm/fit_prop_proxies.gd`
recomputes the solid profiles from the same meshes.

For review, use the private offline preview project above, an empty output
folder, and read-only farms from the pinned r4 dataset. For example:

```sh
godot --path "$QA" --debug-collisions --fixed-fps 30 --write-movie "$OUT/tree.avi" \
  --script res://tools/dev/dynamic_farm/prop_contact_probe.gd -- \
  "$FARMS/p-5402049.json" "$OUT" tree
```

Use `p-4591A011*` for rock and flower (quote the path), `p-3139019` for shrub,
and `p-5402049` for groundcover. The probe starts the real rig beside a matched
prop, sends scripted movement input, checks contact or passage, saves the
contact frame and walks past it. This is not a trip from spawn or device input.
With `--headless` (omit `--write-movie`), it verifies movement only: no pixels
or recording are generated. All placements keep their ordinary model and pose.
