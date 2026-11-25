# Dynamic Farm map and preview host

This farm-dev branch adds an independent art entry:
`res://scenes/dynamic_farm/dynamic_farm_map.tscn`.
It leaves existing main scenes, home creation, saves and PR-A unchanged. It does
not claim a parcel or attach a gameplay session. Its action is “Preview in 3D”.
Formal account ownership/creation is a separate server contract, not a demo
installation credential.

The map reads only a pinned client-manifest and the selected schema4 farm. It
uses the shared MapBridge JSON-string API and global generation allocator.
A building hit selects the parcel returned from the same native query and shows
the filled building highlight. Metadata is whitelisted, counts are separate, and
opaque building keys never enter the farm payload. Multi-hit selection is explicit.
Decision 1C hides standing parcel frames. q(336) (C-28, the owner 11-23) removes
the open-ground fallback: a hit on a parcel without a building selects nothing,
draws no rectangular parcel outline and keeps the "Tap a building" prompt.
C-112 (C-103#18) draws no parcel colour or outline and no dark building frames at
all: only buildings are filled (own green, someone else's red, claimable yellow when
selected), and Mapbox's own place icons are hidden. The map camera takes farm-dev's
inertia, double tap, two-finger tilt and flights (`test_map_camera.gd`); details in
`docs/plans/C-112.md`.

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

`modules/dynamic_farm/map/config.json` pins the hosted r6 read-only dataset (C-43#152):
`https://oss2.sensenjoy.cn/sensen/dynamicfarm/data/r6-6c3733e3b025/`,
`sf-dynamic-farm-20261124-r6`, client SHA (of `client-manifest.json`)
`727ff59ae8a94c6af4620dd5ecdf605233f2c5f86ddcc11a98d93f908b9d0cb5`; that
client-manifest names the full `manifest.json` SHA `6c3733e3…9376`. r6 is r5
without its degenerate building rings (V-167); r5 was never shipped. The map uses
the dataset's DataSF buildings (`building_source: datasf`), the same footprints
the farm cores are rasterized from. Claims send the same `dataset_version`, which
`assets/farm/data/dynamic_farm.json` registers on the server.
The service is ready; the complete 3D candidate still requires its own reviewed
scene integration and actual package verification. The packager must take exact source config, not
silently replace URL/hash. Include five native runtime Kotlin files (no *Test),
map/farm code from the same precise integration tree and the build-managed token.
Android first; unsupported platforms show a clear message, without a fake map.

## Tests

CI (C-62): the Cardigan check's `dynamic_farm` step runs `tools/ci/dynamic_farm_tests.sh`.
It runs every `test_*.gd` here with `--headless --script` in the imported project, each
under its own timeout (`DYNAMIC_FARM_TIMEOUT`, default 180 s; a hang is killed and fails),
and passes the four pinned r4 parcels in `fixtures/r4/` after `--`. A file passes only with
exit 0, no `SCRIPT ERROR`, and exactly one summary line with a non-zero check count and no
failures. Only the prefixes listed in the script's `SUMMARY_CHECKS` / `SUMMARY_RATIO` count as
a summary (C-63), so a new test file must add its prefix there. All files share a total
budget (`DYNAMIC_FARM_TOTAL_TIMEOUT`, default 1080 s, inside the step's 20 minutes): the last
file's limit is clipped to what is left, later files are reported as NOT RUN failures, and the
report table still shows which files timed out.
`test_read_retries_https.gd` gets a loopback TLS fixture with throwaway certificates; with
`CI=1` a fixture that cannot start fails that file, locally it is skipped.
`tools/ci/test-dynamic-farm-gate.sh` (run first in the same step) checks these rules with a
fake Godot: summary misreads, fixture failure with and without `CI`, and several hangs.
`test_parcel_farming_server.gd` needs a running C-31 server and an owner token, so the check lists it
under "Skipped"; run it by hand as its header describes.
Anything that cannot run is listed under "Skipped" in the job summary, never as passed
(currently `test_mesh_edges.gd --legacy`, whose old mesh script is not in the repository).
Locally: `tools/run_tests.sh --ci-import` once, then `tools/ci/dynamic_farm_tests.sh [test_name…]`.


Run prepare_isolated.py with a fresh external target. It copies exact scripts and
writes SHA256 records, without autoloads, service config, credentials or tokens.
Any Godot/device/build run needs a new explicit resource window and absolute
deadline cleanup. The tests use a fake scene or fake native/transport API:

- test_preview_host.gd: synchronous ready/error, retries, old callbacks, single Back,
  pause/resume and rejecting gameplay/wrong-parcel inputs (12 checks passed Q44).
- test_selection_controller.gd: same-point IDs, count-preserving farm decode,
  callback invalidation, style changes, cancellation, timeout and read-only paths.
  C-28: open-ground hits select nothing and never set a parcel frame; building
  hits keep their filled highlight (28/28).
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

Any native error or contract-rejected answer gets one automatic re-query of the
same point while "Finding parcel…" stays visible (Q-29 A). Only a second failure
shows "Parcel details could not load. Tap Retry."; Retry then re-queries that
tap without reloading the map. The delay is `query_retry_delay_ms` in
`config.json` (default 600, clamped 0–5000); a camera move or pause cancels it.
The 8 s no-answer timeout is not retried and its Retry still reloads the map.
`building_without_parcel`, `invalid_point` and `too_many_candidates` are definite
answers: no re-query, and the existing "No selectable parcel here." / "Zoom in to
choose a farm." hints instead of a failure.

Offline tiles and service failures reach Godot as `parcel_error` (map load
error), not as query answers. The first one reloads the map automatically after
the same delay; a tap that was in flight or waiting for its re-query keeps
"Finding parcel…" and is queried again once the reloaded map is ready, which
counts as its one retry. Only a further map error (or one after the tap's retry
was already sent) shows "Map details could not load. Tap Retry.". One outage reports once per failed tile or
source: further errors and late ready signals from the map being replaced are
ignored, so the tap resumes only on the reloaded map. The reload
allowance resets on the next tap or Retry. `DYNAMIC_MAP_ERROR` logs the native
code and whether a tap was waiting. `DYNAMIC_QUERY` logs the local request number, native
outcome code, attempt and retry decision only, never the point or parcel.

A DataSF building layer (`building_source=datasf`) that Mapbox cannot parse is
dropped without any source error, so the layer never loads and taps answer
`loading` (C-43 V-167). The controller counts it as a map load error
(`buildings_source_timeout`, same reload-once-then-"Map details could not load.
Tap Retry." path) when the native ready signal has not reported
`buildings_source_ready` within `buildings_load_timeout_ms` of setting the
sources (`config.json`, default 45000, clamped 5000–300000).
The building source is kept and reused while it loads (C-118). After that timeout,
and after the player's Retry, the next map setup sends `refetch_buildings: true`:
native then replaces a copy that is still loading instead of waiting for it again;
a loaded copy is still reused. Each copy has its own Mapbox source id, so a replaced
copy's late load or error events cannot change the new one (C-124).

### Core size and too-small parcels (C-43)

The client no longer requires 760–840 core cells. Farm data and parcel
metadata accept any non-empty core within the 8192-cell total budget; shape and
count come from the dataset (r5 rasterizes DataSF building footprints, C-48).
Choosing a parcel whose `core_cell_count` is below `min_core_cells` in
`config.json` (default 400, clamped 1–8192) keeps the building highlighted,
leaves Preview disabled and shows "This parcel is too small to be your main
farm. Please choose a larger one." (Q-56). The fetched farm is checked again
before opening.

`dataset_version` in `config.json` selects the release; any
`sf-dynamic-farm-YYYYMMDD-rN` name is accepted, and the manifest, farms and
preview host must all carry that same version. Switching to r5 means updating
`base_url`, `dataset_version` and `manifest_sha256` together.
test_core_size.gd covers L-shaped, courtyard and threshold-edge fixtures.

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

### Outer groves (C-20)

Run `--headless --script res://tests/dynamic_farm/test_outer_groves.gd -- <farm1.json>
<farm2.json> <farm3.json>` in the same isolated preview project (review set:
`p-3139010`, `p-3139019`, `p-5402049`). Without payloads it runs only the walker
checks. It compares the incremental connectivity check with a full flood fill over 400
random solid boxes, then per parcel replays the previous approved layout as the
"before": reserved cells may not grow, reservation-reachable cells may not shrink
(audited 1539, 1470, 3962 for the review set), and every core, protected, spawn and
entry cell stays reachable. Per Q-19 it then binds the model-fitted profiles (C-19) of
both layouts, core obstacles included, and floods a 0.2 m walker lattice from spawn:
every cell walkable before and not after must lie under a new blocking prop's own
profile (`OUTER_LOST` lists each one with its model), no open lattice point is sealed
off, the walkable total does not shrink, and spawn, entry, core and protected cells stay
walkable. It also checks the 13-model palette, extension-only footprints, rear-half
trees, that only solid footprints reserve cells, at least one grove/rock pile/flower
clump, and an identical layout on reopening. Walker unit checks cover shared group
cells, the new-cell limit, `release()` and shadow-budget pruning of a group member.

### Outer gathering (C-60)

`test_outer_gather.gd [-- <farm.json> ...]` checks the gather rules against the server's
config and the art recipe, the C-58 object id shape, the local stand-in's `gather` command
(refusals included) and, per parcel, that two openings give the same ids at the same places,
all in the extension and within each kind's cap. Real parcels are compared with the pins in
`fixtures/outer_gather_ids.json` (rewrite with `OUTER_GATHER_WRITE_PINS=1` only when the
outer recipe version changes). `test_outer_gather_scene.gd [-- <farm.json>]` (default
`p-3139010`) gathers a tree, a flower and a rock in the real scene on the local save and
checks the key, the bag, the faded/hidden art, the refusal before 24 h, reopening, regrowth,
and that the walk (reserved cells, bound profiles, walkable 0.2 m lattice) never changes.

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

### First house (C-33)

Run `--headless --script res://tests/dynamic_farm/test_house.gd -- <farm1.json> <farm2.json> <farm3.json>` in the
isolated preview project (review set: `p-3139010`, `p-3139019`, `p-5402049`; without payloads only the fixtures).
It checks the cottage's wall box against the model's cross-sections (wall and plinth points within 3 cm, the model
inside its 3×3), `place_house` on C-34's local save (the house as `dynamic_farm.json` says, the blueprint in the gift
once, one house, a blueprint spent, the house back after reopening, `HOUSE_PLACED`, `CELL_OCCUPIED`), a neck fixture
that a house would seal and the protected path round it, and per parcel every footprint position: outside the core,
over an obstacle, on the protected path (`parcel_space.gd`, shared with tilling) and cutting a walk cell off are each
refused, and an
obstacle frees its cell once cleared; tilled cells and crops refuse it. For a dozen accepted spots per parcel it binds
the real scenery, obstacles and house to the walker and floods a 0.2 m lattice from spawn: no previously reachable
cell outside the footprint is lost. With the walls alone, approaches from 16 directions stop with the body 0–4 cm from
the wall outline (never inside), and a push 6° into each face keeps sliding along it.

## First-home claim (C-32)

`test_claim_controller.gd` runs the claim flow against `fake_parcel_server.gd`, an
in-memory stand-in with the C-31 status codes (201 / 200 retry / 409
`ALREADY_CLAIMED` / 409 `PARCEL_TAKEN` / 403 `RESELECT_DISABLED` / 401), and a fake
native bridge that keeps parcel states the way `ParcelLayerState` does. It checks the
own (green) / claimed (red) / selected bits, the claimer-name rows, that a claimable
selection keeps C-28's yellow building fill while an owned one drops it, reopening on
a new generation, a second account, the one-home rule, give-up only with the internal
setting, and the real map card's buttons. Fake data proves client logic only; it is
not evidence of a real claim, a save or device rendering.

Settings read by the map: `sensen/dynamic_farm/reselect` (internal test packages only;
shows "Give up and choose again"), `sensen/dynamic_farm/own_farm` (internal test packages only;
"Enter my farm" opens the own parcel with `own_parcel=true` for farming, C-34 Q-72; otherwise it
opens the read-only preview), `sensen/dynamic_farm/account_restore` (internal test
packages only; reloads the saved account token through `Net.restore_saved_account()`, which
calls `/users/me` and nothing else), `sensen/dynamic_farm/guest_play` (internal test packages only, C-100:
when no saved account was restored, `Net.dynamic_farm_sign_in()` signs in anonymously with the installation key;
the server's `PARCEL_GUEST_WRITES` decides whether that guest may claim and farm) and `sensen/dynamic_farm/fake_claims` (+ optional
`fake_player`, default `fake-a`) for development without the C-31 server, and
`sensen/dynamic_farm/profile_outfit_wait_seconds` (C-135, default 5: how long a profile tap waits for the saved
outfit's parts before the profile opens all the same; `PARCEL_PROFILE_WAIT` logs `timed_out`). None is
set in `project.godot`, so release builds show no give-up entry and keep the normal
`Net` boot. A signed-out player gets a "Sign in" button that opens the existing
`AccountPanel`; ownership is re-read for the new identity.
