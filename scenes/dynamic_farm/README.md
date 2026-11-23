# Dynamic farm 3D art preview

This scene consumes one verified schema4 payload. It does not fetch data, claim a parcel, call P0Runtime, send farming commands or write a farm save. The host owns map visibility, dataset/identity checks, loading/error panels and navigation.

Instantiate `dynamic_farm.tscn`, call `setup({farm, dataset, block_id, preview_only:true, return_context})`, connect `preview_ready(summary)`, `preview_error(message)` and `back_requested`, then add it to the tree. The ready summary uses `dataset` and `block_id`; it is emitted only after the player mesh and scenery/shadow preparation are ready. The scene has its own ready-state Back button. Back emits once; the host pops its wrapper. `suspend()` / `resume()` yield and restore this scene's input, canvas, camera and environment.

Grid coordinates remain local to the generated orientation. A single origin/centre translation is applied consistently to the ground, props, masks and actor. Normal framing uses the existing 43° pitch / 14.5° yaw / KEEP_WIDTH and player scale. `set_review_overview()` is a diagnostic capture hook, not a replacement for the normal player camera.

Shared `modules/dynamic_farm/farm_data.gd` is byte-identical to the r4 2D integration head `a0b842fe3677c749d7adcd03dba0cb8d9a29214a`. It validates RLE, capabilities, protected corridors, counts and budgets; geometric agreement/IoU against the public source is a producer responsibility. The sparse walker keeps outside cells impassable and checks the full body circle at corners. Full-mesh boxes with body clearance reserve space for layout and connectivity only. Walking uses the fixed 0.3m avatar disc against the final instances’ inventory cylinders, lying capsules or oriented boxes; on contact it keeps the movement along the touched face and drops only the inward part. Tree profiles fit the low trunk (pine_03: the smallest cylinder covering its three buttress roots); flowers and grasses do not block. All scenery layers bind the same profiles through `Scenery.build(plan, walk)`. Adjust `collision_fit_fraction` in the inventory (0.8–1.0 of the fitted primitive). Inspect the actual walker shapes with `--debug-collisions`. Placement rejects blocked connectivity instead of editing masks.

Art comes from the approved inventory/recipe in `assets/dynamic_farm`. Only the 13 listed existing `assets/farm/art/wild_pz_*.glb` files are used, with original pivots, uniform 0.85–1.0 scale, role caps, deterministic xorshift32 seeds and spatial batches. Extension scenery still avoids core/protected cells. Since C-20 it is grouped (`outer_groves` in the recipe): rear-half tree groves with overlapping canopies and young pines, shrub thickets, rock piles with smaller companion stones and flowers, and flower clumps; trees stay in the rear half and solid props use quarter-turn yaw so their reservation stays tight. Group members may share their own group's reserved cells. The placement budget replays the previous approved scatter (`499-v2-schema4`, solid models only) on a separate walker; the new layout never reserves more cells than that layout did on the same parcel. Per Q-19 a previously walkable cell may only be lost under a new blocking prop's own fitted profile; every other cell, the spawn, entry, core and protected corridors stay reachable and the walkable total does not shrink. Placement keeps the full-flood semantics but checks connectivity incrementally (only the clear neighbours of newly reserved cells must still reach one another). The summary reports groups and budget under `outer`. Nothing is harvestable yet. A separate layer places weeds, stones, bushes and saplings inside distinct core cells (12.5% by default), excluding the spawn/entry neighbourhoods. Per Q-16 its stones, bushes and saplings block with the same model-fitted profiles; weeds do not. A blocking one only takes a cell surrounded by open ground whose loss leaves every other cell connected to spawn. Its random stream is keyed by block ID and layer version. The preview summary reports its roles, batches, triangle count and layout hash under `core_obstacles`, separately from the original extension metrics. Cells, farming permissions and saves are unchanged. Ground/grid/skirt meshes are assembled from occupied cells; there are no custom shader changes. Existing meadow and GroundShade shaders are reused, with bounded per-chunk GLES masks and the existing no-real-time-sun-shadow rule. No interior water or new cliff obstacle is inferred from geo hints.

Packaging must include the scene, all `modules/dynamic_farm` scripts, both art JSON files, and the existing dynamically loaded inventory assets/imports plus existing avatar/farm/shader dependencies. Do not export only statically discoverable scene dependencies and accidentally omit JSON-driven GLBs. No new GLB/image bytes were authored.

Offline preparation: `python3 tools/dev/dynamic_farm/prepare_preview.py --output <temporary-directory> --cache-root <existing-imported-worktree>`. This stages an isolated user directory and existing imported resources; it never invokes editor/import. The AppRouter QA stub provides only the avatar loader's sync-load switch, not routing or network behavior. Run Godot only in a registered resource window, with an absolute deadline and per-PID cleanup.

Checks/tools: `tests/dynamic_farm/test_walk.gd`, `preview_probe.gd`, `lifecycle_probe.gd`, `motion_probe.gd`. Render the probe with `--script` after autoload initialization via its runtime `load()`, not a preload of the scene before autoloads exist. Movie Maker output is a fixed-step normal-speed art replay with scripted joystick input; use separate live frame measurements, and do not label it phone touch or GPU performance evidence.

The first review package contains ordinary 328/424 scenes in Mobile and Compatibility, repeatability/permission/placement checks over seven real plus two labelled synthetic samples, a concave-corner negative control, lifecycle checks and a protected-route walk. Complex-parcel rendered captures, Android host/map integration and device acceptance remain separate review gates. Technical art review: Shangguan; visual review: Huowu. No merge to PR-A or the pre-Nov-25 submission candidate is authorized by this scene.

## First house (C-33, Q-40)

With `args.parcel` (the owner's parcel farm save: `enter(done)` and `place_house(x, y, rotation, done)`, replies in
C-31's `farm_state` v1 shape) the scene calls `enter` once on opening; the first entry brings the gift, a reopen does
not. While the bag holds `blueprint_cottage` and no house stands, `Build Cottage` opens placement: a press or drag
moves the see-through `house_cottage` (its middle cell under the finger); its 3×3 cells fill green or red, grid lines
fade over three core cells round it, and the spawn's arrival cells in reach show sand. The bottom is the shared
`UiPlaceBar` (`Cancel · Build`); the main key shows why a spot is refused. The preview starts on the valid spot
nearest the player. Build sends `place_house`; the cottage stands at once (no construction time).

Rules (`modules/dynamic_farm/farm_house.gd`, the save's `house.x/y` is the footprint's lowest cell): every cell
core (`Outside your yard`); none under an uncleared core obstacle (every role, weeds too), a tilled cell or a crop
(`Space taken`); none on the arrival disc round spawn (dx²+dy² <= 4, the protected disc of the data contract), and
every other walk cell still reaching spawn (`Keep the path clear`). Schema 4 lists the whole core as walking reserve,
so on the core those two are the protected ways; the protected ring and entry path lie outside the core anyway.
The walls block through a model-fitted box (walls and plinth below the eaves; C-19's walker), so the player walks
along them and stops at contact; the eaves, bench, woodpile and doorstep are not walls. A player standing where the
walls go steps out to the nearest clear point. Without `args.parcel` (the art preview) nothing of this shows.

`modules/dynamic_farm/parcel_farm_local.gd` stands in for the server save until C-31 is wired (same answers: the gift
once, one house, a blueprint spent, `CELL_OCCUPIED` over tilled cells or crops), kept in `user://dynamic_farm`.
`tools/dev/dynamic_farm/house_probe.gd` drives it through the real scene: entry, a valid and each refused spot,
Build, the wall, reopen (`--headless`: states only).
