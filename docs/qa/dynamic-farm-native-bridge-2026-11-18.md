# Dynamic-farm Android bridge integration

This independent branch starts at farm-dev `99a853f7c75e917394a3f1f229bce9a82a38235c`. It brings the r3 native parcel implementation from `b232cfa6b9e548351683b4b0ac02da5fccbea011` into the shared map bridge. It does not add a scene entry, create/claim a farm, modify existing farm data, or enter the submission candidate.

## Integration contract

`MapBridge.supports_parcels()` detects all six native commands, the synchronous lifecycle-watermark getter, and three signals. Unsupported platforms, including the current iOS bridge, report `unsupported`; Android adds:

- `set_parcel_sources(generation, config_json)`
- `query_parcel_at(request_id, generation, normalized_point)`
- `set_parcel_states(generation, batch_json)`
- `set_parcel_claims(generation, claims_json)`
- `set_parcel_building_highlight(generation, opaque_key)`
- `clear_parcel_layers(generation)`

Use `MapBridge.next_parcel_generation()` for each scene entry, source retry, or dataset replacement. Reusing an old generation is rejected. Request IDs increase within that generation. Points are relative to the full native MapView, not the panel or physical display density. Filter UI taps/drags before invoking the bridge.

Signals `parcel_ready`, `parcel_query_result`, and `parcel_error` retain the r3 payloads and are forwarded deferred. The wrapper rejects old scene generations, style epochs, and query IDs. `clear_parcel_layers` invalidates local state before calling native. Hiding the map clears this bridge's active parcel layer; returning requires fresh source setup. Clear the active generation on scene teardown even if the shared map remains visible for another scene.

Native hiding/backgrounding independently retires in-flight queries and clears the opaque building selection; resuming cannot revive a previously queued result. City styling skips parcel-owned layers so it cannot overwrite claim/address labels. The Android template setup copies all five runtime Kotlin sources and all four JVM test sources.

MVT/GeoJSON and `promoteId=block_id` retain r3 semantics, including literal `*` in official IDs. Schema-r4 adds `core_cell_count`, `extension_cell_count`, and `total_cell_count` to the public metadata allowlist. Full grid zones/boundaries and Mapbox geometry never leave native selection through this channel. Server/farm JSON validation remains the integration layer's responsibility.

## Validation

Q1117-36 authorized isolated offline compilation and focused tests; it was released early, after all test processes exited.

- First run: real Mapbox 11.29 Kotlin compilation/link inputs and 31 JVM checks passed (4 plugin, 8 payload, 8 r3, 11 lifecycle).
- Godot 4.7.2 minimal project: 12 tests passed, 0 errors/failures/orphans (4 existing Android bridge, 8 new parcel bridge).
- After schema-r4 arrived, only the three metadata fields and a new no-geometry-leak case changed. The related r3 JVM suite passed 9 tests after a fresh compile. Counts are separate runs, not a combined pass total.
- Final runtime/test sources were hash-compared with the tested copies. Shell syntax and `git diff --check` passed.

Evidence: `/Volumes/ACASIS/tmp/yase-dynamic-native-check-1118`. Original logs, test XML, source hashes, process and cleanup records are retained. The first full JVM result XML was superseded in the Gradle output directory by the targeted metadata run; its suite counts were read before that run and the original Gradle log is preserved. No device, simulator, APK, backend, or real Mapbox rendering was started. Private adb 5085 was used only for the minimal import and immediately stopped; all recorded PIDs exited.

## Remaining integration

Pangu owns r4's parcel visual change and the stage-two entry/route. The supplied r4 paint patch is now integrated as described below; actual transparent-layer hit testing remains pending. Do not delete the query fill/source to hide its outline. Houyi's actual schema-r4 included/MVT samples and hosting are needed for real point selection, and Liubang supplies the 3D scene handoff. Real rendered-query behavior, nickname styling, return-from-3D, foreground recovery, and frame timing require the integrated candidate and a new resource window. iOS parcel support is not implemented by this Android change.

## Deferred delivery lifecycle fix (review 207f2374)

The first implementation invalidated only pending native tickets. A result already emitted into Godot's deferred queue could cross a pause/resume boundary and still reach the scene. `onMainPause`, `setMapVisible(false)`, and `onMainDestroy` now increment an `AtomicLong` synchronously, before any queued UI work. The read-only `getParcelLifecycleEpoch()` exposes that watermark without accessing Mapbox from the Godot thread.

The wrapper snapshots the watermark when submitting each query and compares it again immediately before final deferred delivery. This does not depend on a later deferred invalidation signal. The six commands/three signal signatures are unchanged; the new wrapper deliberately reports unsupported if the watermark getter is absent from the packaged plugin.

Q1117-39 fix validation: real Kotlin compilation and the related 11 lifecycle JVM tests passed. The new Godot test first queues a completed native result, changes only the synchronous watermark (no scene/source/request clear and no invalidation signal), then flushes the queue and issues a fresh query. The previous wrapper fails this one test case with two assertion failures (XML failures=2); the fixed wrapper passes all 13 tests, 0 failures. Old/fixed wrappers, logs and both XML reports are retained under `p2-fix/`. All recorded PIDs exited and 5085 was free at 21:12:44; the window was released. No actual device/background reproduction is claimed by these controlled tests.

## R4 visual patch integration

Cherry-picked Pangu's `e0ca7bef7e7d5968ec4eab8b72a25be170d38deb` with provenance as `afe88a776`. The three zone-count metadata fields were already identical, so the effective code change is only ParcelMapController: parcel fill/line opacity is zero, their layers/source remain present, and the building highlight plus claim nickname/dot layers are unchanged. The previous feature-state-dependent parcel tint expression is removed; business claimed/own/selected state is retained.

Static checks parsed both generated layer JSON shapes, verified opacity/visibility, compared the paint block byte-for-byte with the author commit, and confirmed the lifecycle watermark/guards, payload allowlist and downstream layers/query code are unchanged. No Kotlin build or Mapbox runtime was repeated for this paint-only integration. The author likewise has not yet validated SDK hit testing. Integrated-candidate QA must prove Mapbox 11.29 loads and queries the transparent fill for buildings, empty parcels, style reload and claim updates before this behavior is accepted.
