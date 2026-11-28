# Dynamic farm 3D art preview

This scene consumes one verified schema4 payload. It does not fetch data, claim a parcel or call P0Runtime. Only with `own_parcel` (below) does it farm and save. The host owns map visibility, dataset/identity checks, loading/error panels and navigation.

Instantiate `dynamic_farm.tscn`, call `setup({farm, dataset, block_id, preview_only:true, return_context})`, connect `preview_ready(summary)`, `preview_error(message)` and `back_requested`, then add it to the tree. The ready summary uses `dataset` and `block_id`; it is emitted only after the player mesh and scenery/shadow preparation are ready. The scene has its own ready-state Back button. Back emits once; the host pops its wrapper. `suspend()` / `resume()` yield and restore this scene's input, canvas, camera and environment.

Grid coordinates remain local to the generated orientation. A single origin/centre translation is applied consistently to the ground, props, masks and actor. Normal framing uses the existing 43° pitch / 14.5° yaw / KEEP_WIDTH and player scale. `set_review_overview()` is a diagnostic capture hook, not a replacement for the normal player camera.

Shared `modules/dynamic_farm/farm_data.gd` is byte-identical to the r4 2D integration head `a0b842fe3677c749d7adcd03dba0cb8d9a29214a`. It validates RLE, capabilities, protected corridors, counts and budgets; geometric agreement/IoU against the public source is a producer responsibility. The sparse walker keeps outside cells impassable and checks the full body circle at corners. Full-mesh boxes with body clearance reserve space for layout and connectivity only. Walking uses the fixed 0.3m avatar disc against the final instances’ inventory cylinders, lying capsules or oriented boxes; on contact it keeps the movement along the touched face and drops only the inward part. Tree profiles fit the low trunk (pine_03: the smallest cylinder covering its three buttress roots); flowers and grasses do not block. All scenery layers bind the same profiles through `Scenery.build(plan, walk)`. Adjust `collision_fit_fraction` in the inventory (0.8–1.0 of the fitted primitive). Inspect the actual walker shapes with `--debug-collisions`. Placement rejects blocked connectivity instead of editing masks.

Art comes from the approved inventory/recipe in `assets/dynamic_farm`. Only the 13 listed existing `assets/farm/art/wild_pz_*.glb` files are used, with original pivots, uniform 0.85–1.0 scale, role caps, deterministic xorshift32 seeds and spatial batches. Extension scenery still avoids core/protected cells. Since C-20 it is grouped (`outer_groves` in the recipe): rear-half tree groves with overlapping canopies and young pines, shrub thickets, rock piles with smaller companion stones and flowers, and flower clumps; trees stay in the rear half and solid props use quarter-turn yaw so their reservation stays tight. Group members may share their own group's reserved cells. The placement budget replays the previous approved scatter (`499-v2-schema4`, solid models only) on a separate walker; the new layout never reserves more cells than that layout did on the same parcel. Per Q-19 a previously walkable cell may only be lost under a new blocking prop's own fitted profile; every other cell, the spawn, entry, core and protected corridors stay reachable and the walkable total does not shrink. Placement keeps the full-flood semantics but checks connectivity incrementally (only the clear neighbours of newly reserved cells must still reach one another). The summary reports groups and budget under `outer`. Nothing is harvestable yet. A separate layer places weeds, stones, bushes and trees inside distinct core cells (12.5% of core cells as instances by default), excluding the spawn/entry neighbourhoods. Since C-44 a core tree (`wild_pz_pine_03`) takes a 2×2 block at the outer grove tree scale (0.85–1.0, quarter-turn yaw), centred on the block; its crown stays over the block and a ring of open core cells that no other prop takes, so it never covers another prop or leaves the core. Per Q-16 its stones, bushes and trees block with the same model-fitted profiles, scaled with the model; weeds do not. A blocking one only takes cells surrounded by open ground whose loss leaves every other cell connected to spawn. Its random stream is keyed by block ID and layer version. The preview summary reports its roles, batches, triangle count and layout hash under `core_obstacles`, separately from the original extension metrics. Cells, farming permissions and saves are unchanged. Ground/grid/skirt meshes are assembled from occupied cells; there are no custom shader changes. Existing meadow and GroundShade shaders are reused; since C-44 the backdrop's cumulus groups drift sideways (`CLOUD_DRIFT`, screen widths per second, advanced by the scene rather than shader `TIME`, so it holds still while the scene is suspended and has no hourly `TIME` rollover jump), each group wrapping while off-screen, with bounded per-chunk GLES masks and the existing no-real-time-sun-shadow rule. No interior water or new cliff obstacle is inferred from geo hints.

Colours (C-21) follow the owner's design image (C-43 attachment-210) first and image 1 (C-12 attachment-57) second: warm yellow-green grass, sand-yellow core soil, warm brown cliffs, a slightly warmer sun and a light sky without deep blue, so nothing reads as water. Ground colours, the grass mottle and the core grid colour are in the recipe's `surface`; values are albedos solved for this scene's sun and ambient. The 13 models are recoloured at runtime from the recipe's `prop_palette` (`farm_palette.gd`): only vertex colours change, the shared FarmArt material, geometry, collision profiles and layouts do not. Each placed instance picks a weighted variant (canopies green / yellow-green / gold / orange-red, two pine and shrub greens, pink or cream petals, warm grey rocks) from SHA256(asset|x_cm|z_cm), so a parcel shows the same colours on every opening; variants split batches by about a quarter more. A batch is one model colour variant in one 32-cell chunk (`Scenery.batch_key`); the review-only edge decor (`edge_decor_preview`) budgets its at most 4 new batches with the same key, so its planned count equals what is drawn. `Scenery.build` takes the recipe already read by `Scenery.plan` (`plan.recipe`), so one farm load reads `499-art-recipe.json` once. `tests/dynamic_farm/test_palette.gd` checks the mapping covers every model colour, adds no water blue and leaves layouts unchanged; it always includes the synthetic fixture parcel, and its reopen check compares outer and core props together and requires at least one drawn instance.

Packaging must include the scene, all `modules/dynamic_farm` scripts, both art JSON files, and the existing dynamically loaded inventory assets/imports plus existing avatar/farm/shader dependencies. Do not export only statically discoverable scene dependencies and accidentally omit JSON-driven GLBs. No new GLB/image bytes were authored.

Offline preparation: `python3 tools/dev/dynamic_farm/prepare_preview.py --output <temporary-directory> --cache-root <existing-imported-worktree>`. This stages an isolated user directory and existing imported resources; it never invokes editor/import. The AppRouter QA stub provides only the avatar loader's sync-load switch, not routing or network behavior. Run Godot only in a registered resource window, with an absolute deadline and per-PID cleanup.

Checks/tools: `tests/dynamic_farm/test_walk.gd`, `preview_probe.gd`, `lifecycle_probe.gd`, `motion_probe.gd`. Render the probe with `--script` after autoload initialization via its runtime `load()`, not a preload of the scene before autoloads exist. Movie Maker output is a fixed-step normal-speed art replay with scripted joystick input; use separate live frame measurements, and do not label it phone touch or GPU performance evidence.

The first review package contains ordinary 328/424 scenes in Mobile and Compatibility, repeatability/permission/placement checks over seven real plus two labelled synthetic samples, a concave-corner negative control, lifecycle checks and a protected-route walk. Complex-parcel rendered captures, Android host/map integration and device acceptance remain separate review gates. Technical art review: Shangguan; visual review: Huowu. No merge to PR-A or the pre-Nov-25 submission candidate is authorized by this scene.

## Own parcel farming (C-34)

`setup({..., own_parcel:true, farm_store?})` opens the owner's parcel for farming instead of a preview (the host passes both keys through; `preview_only` is then not required). `ParcelFarming` (`parcel_farming.gd`) adds the main key, the bag row, toasts, tilled soil and carrots (`parcel_crop_art.gd`, C-138, below) and a target-cell marker. The target is the cell in front of the player; a short tap on the ground picks a cell until the player moves. One press clears a core obstacle, tills, sows or harvests (owner decision Q-39, C-34#14): no Energy or coins; carrots ripen 60 s after watering (C-151; after sowing before it) by the store's clock; the first entry grants 1 Starter Hoe and 3 Carrot Seeds once. The scene asks the store to enter only after `preview_ready` (building the scene blocks the main thread for seconds, which timed out a request started earlier, V-123); a lost request is retried once before the key shows Retry. A cleared obstacle leaves the walker and is redrawn out of the core layer (`Scenery.build(..., bind=false)`, `Walk.remove_prop`).

Rules and numbers: `assets/farm/data/dynamic_farm.json` (shared with the C-31 server; separate from the main farm) is read by `modules/dynamic_farm/parcel_farm.gd`, a copy of the server's farm state v1 and its commands. The server holds no parcel geometry, so `parcel_space.gd` keeps the spatial rules on the client: tilling only on core cells, refused outside the core (`Not farmland`), under a building (`House here`) and on the protected path (`On the path`). Schema 4 marks every core cell as reserved, so the protected path inside the core is derived: the shortest walk from the entry to the spawn widened by `PATH_HALF_WIDTH` (1) cell, plus the spawn's `SPAWN_CLEARANCE` (1) ring.

`farm_store` answers `enter()` and `send(base_version, commands)` with the farm, its version and `server_time`. By default the scene uses `parcel_farm_remote_store.gd`: C-31 `POST /parcels/mine/enter` (naming the dataset of the farm being opened, so a claim on an older dataset moves onto it: C-136) and `/parcels/mine/commands` through `Net.client` (it needs a signed-in client; a reply about another parcel is refused). `parcel_farm_local_store.gd` keeps the save in `user://dynamic_farm_local/` with the device clock; it is used only by tests or with the development setting `sensen/dynamic_farm/local_farm_save`, and is not save or server-time evidence.

Walking up and labour (C-73): a press walks the player beside the target before anything is sent. `modules/dynamic_farm/farm_path.gd` routes on the walker's own grid: a cell is open when the body fits at its centre (`Walk.clear_position`, the same parcel outline and fitted prop profiles the stick collides with) and a step between neighbouring centres, diagonals included, is taken only if the body fits all along it; legs are straightened where it still fits. The player stands on one of the 8 neighbours (sides preferred; for a tree, around its whole 2×2 block), faces the target and plays the main farm's labour clip for the verb (`AnimPlaceholders.clip_for`: `labour_clear`, `labour_till`, `labour_sow`, `labour_harvest`) for `ParcelFarming.LABOUR_S` (1.2 s), holding still. The command is sent as the clip starts and its result is shown as it ends. No route, or a walk that stalls, toasts `Can't reach it` and sends nothing; the stick cancels a walk. The parcel stays under a loading cover (`Loading your farm…`, or `Could not open your farm.` with Retry) until the save is applied, so cleared obstacles never show first. `tests/dynamic_farm/test_farm_path.gd` covers routes on a synthetic grid and on the r4 parcels.

Farming UI (C-74) reuses the main farm's UI kit read-only, without P0Ui, P0Runtime or Energy. The top bar (UI v3 since C-105) is a Ø36 glass Back (`UiGlassButton`, 44 hit area) and a glass capsule with the parcel's name over its status (`UiGlassCapsule`), 12 from the screen's sides at safe top + 8; on one's own parcel the parcel's coins (C-59) follow at its right in the v3 glass coin capsule, updated from each reply. `ParcelFarming` places the main farm's `UiQuickBar` and `UiActionKey` (switch key hidden: one action) exactly as `P0Ui._place_controls`; the key's tool badge shows the hoe while the bag holds it. Item, coin, Bag-end and bag-hero art is C-86's UI v3 art (`UiArt`, `assets/ui/v3`, C-105). The bar lists the bag (hoe, seeds, carrots, then any other named item) with live counts from each reply; Bag or a slot opens the UI v3 bag panel (C-105, `UiModalPanel`): a `Bag` tag, the bag's items in round `UiBagSlot`s three to a row (at least three rows), the tapped one ringed and named under them; the quick bar slides away while it is open (M-16). ✕, a scrim tap or Android Back (the host asks `close_modal()` first) close it (M-05). The bar follows the bag's order; its long-press drag (swap, Pin, Remove) is not supported here — the cells' drag gestures are not passed to the bar (C-74#39) — while taps and a swipe up still work. `announce_gains(gains, from)` shows one v3 `UiGainFloat` line per item (`+3 Carrot Seeds`) and flies each item into the Bag (`UiItemFly`, which bumps as it lands): the first-entry gift from the player, a harvest from its cell, an outer gather (C-60) from the picked object. Later gains in the parcel scene should call it rather than add their own. Items take their names from the P0 content table; parcel-only items are named in C-59's adapter `modules/dynamic_farm/parcel_items.gd` (the blueprints: `Cottage Blueprint`, C-74#33 / #34, and `Coop Blueprint`, with the existing recipe-card icon as a placeholder); icons come from the UI v3 item art where it has the item (`ParcelItems.ART`), else P0's; items with no name anywhere are skipped. While the house is being placed (`held`), the quick bar and the action key are hidden and the bag closes; the C-33 `Build Cottage` button is placed by `place_side_button` at the left on the action key's baseline, clear of the key and the bar. Refusals and errors stay toasts, above the bar.

Packaging must also include `assets/farm/data/dynamic_farm.json` and the P0 content table (`assets/p0/p0_content.json`, item names) with the P0 item icons; JSON is not found by static scene dependencies.

Tests: `tests/dynamic_farm/test_parcel_farming.gd` (rules, commands, spatial rules, local save) and `test_parcel_farming_scene.gd` (the real scene; optional `-- <farm.json>`), both headless in the private preview project. `test_parcel_farming_server.gd -- <base …/v1> <owner token> <farm.json>` runs the scene against a running C-31 server on its real clock (~70 s; the owner has claimed that parcel and not entered it yet).

Soil and carrot stages (C-138): `modules/dynamic_farm/parcel_crop_art.gd` draws every tilled cell as its own 1×1 soil block, dry or wet (wet is darker), and the carrot in seven stages after the owner's reference (C-134 attachment-1052, answer C-134#5 question 3): tilled soil (nothing sown), sowing, emergence, leaf growth, root shoulders, root thickening, maturity. Sowing to root thickening take a fifth of the growing time each (12 s of 60 s); maturity starts at `ripe_at`, exactly when Harvest opens. Stages come from the save's `planted_at` / `ripe_at` only, so the save format is unchanged and a carrot sown before the change lands in its stage. Seeds, growing time, yield and price are unchanged. Since watering (C-151, below) a watered carrot's cell is wet, tilled soil with nothing sown or a carrot not watered yet dry, and a carrot grows from its `watered_at`; the development setting `sensen/dynamic_farm/preview_wet_soil` draws every cell wet (`GATHER_QA_WET_SOIL=1` turns it on in the emulator QA package). The shapes are placeholders from the main farm's carrot meshes until C-139's art. Review captures: `tools/dev/dynamic_farm/crop_stages_probe.gd` (also writes a seeded save for the emulator package); notes in `docs/plans/C-138.md`.

## Well and pail (C-151, 0.4.5)

The owner's SEN-C-137#6 and #15: watering keeps a farm's crops together. A sown carrot sits on dry soil and counts no
time (`watered_at` null, `ripe_at` the server's `NEVER`); watered, it grows from that moment (the carrot's 60 s, the
seven stages of C-138) and its soil turns wet. Every farm gets one Well Blueprint and one Pail once
(`grants.watering` in `assets/farm/data/dynamic_farm.json`): a new player with the first-entry gift, an older farm on
its next entry; the save records it in `grants`. The well is a building type (C-150): 1×1 as P0's well, `well.glb`,
one at level 1 (more with farm levels, SEN-C-152), placed with `Build Well` like the cottage. At the well the key reads
`Fill` · `2 Energy` and draws a full pail (`draw_water`, `watering.pail_uses` 3, the save's `pail_water`; `Pail full`
when full); on a dry carrot it reads `Water` and uses one (`water`, free), `Pail empty` once the pail is spent, until
it is filled at the well again. Only the client knows the player stands at the well (the press walks there); the
server checks the well, the pail, its water, that the cell is sown and not watered, and Energy. A carrot sown before
watering (no `watered_at`) counts as watered and ripens on its own time. Fill and Water play SEN-C-153's
`draw` and `pour` with the pail in the right hand (`bucket_gesture.tscn`, `bucket_actions.tres` as the rig's `pail`
library), for their own lengths; the pail is put away when they end. The guide asks for the well and then
for water while a dry carrot waits. Shared cases: `tests/dynamic_farm/fixtures/watering_cases.json` (server and client).
Notes: `docs/plans/C-151.md`.

## Farm levels (C-152, 0.4.5)

As P0's Homestead levels, Lv1 to Lv5 for now (`farm_levels` in `assets/farm/data/dynamic_farm.json`; Lv2–5 cost 100 /
300 / 600 / 1,000 coins since owner decision SEN-Q-282 (C-198, 0.4.6), materials as on SEN-C-152#14; a farm upgraded at
the earlier 40 / 60 / 70 / 80 keeps its level and coins). Scott's greeting has `Upgrade Farm`, which opens the upgrade
sheet (`parcel_upgrade.gd`, P0's HOME-1 in the kit: NEED-TILEs for Timber, Stone and Coins, What changes, the first gap on
the Upgrade key per LOCK-10); Upgrade sends `upgrade_farm`. The server takes the next level's coins and materials (no
Energy) or refuses the whole batch (`NOT_ENOUGH` naming the first short material, then `NOT_ENOUGH_COINS`; `MAX_LEVEL`
at the top). Each level adds `energy.per_level` (10) to Max Energy; wells are 1 at Lv1, 2 from Lv3 and 3 from Lv5 (a
level's `buildings`), and Lv3 and Lv5 put one Well Blueprint in the bag (`gift`), which `Build Well` uses. Tilled cells
have no cap (owner SEN-C-137#10). The save's `level` is absent on older saves (Lv1) and kept across dataset moves.
Shared cases: `tests/dynamic_farm/fixtures/level_cases.json` (server and client). Notes: `docs/plans/C-152.md`.

## Market and carpenter (C-59)

Jasmine and Scott (`parcel_town.gd`) first opened over the map from two fixed entries, `Market` and `Carpenter`; since C-115 they stand in the Washington Square room (below). Both read and write that home's parcel save through the same store as the parcel scene: `read()` (`GET /parcels/mine`, no welcome gift) and `send()`. Jasmine introduces coins once per parcel on this device (`user://dynamic_farm_local/town.json`), then her `Sell` counter (`parcel_counter.gd`, built from the main counter's kit pieces; the main `P0CounterDrawer` is untouched) sells with the C-58 `sell` command at the rules' prices. Scott gives one Coop Blueprint with `claim_blueprint` once the parcel has sold something. Their looks are existing avatar parts, drawn by `P0KeeperPortraits.register_look`. The parcel's coins show in its top bar (C-74). Details and the copy draft: `docs/plans/C-59.md`; tests: `tests/dynamic_farm/test_parcel_town.gd`; review pictures: `tools/dev/dynamic_farm/town_shots.gd`.

## Outer gathering (C-60)

The outer trees, flowers and rocks of one's own parcel (the C-20 outer groves) can be picked by hand, as the owner answered C-30#29 question 4 (recorded C-30#36): no tool, one Timber (`wood`) per tree, one Wild Herb (`wild_herb`) per flower and one Stone (`stone`) per rock, back after 24 h of server time. Items, amounts, the respawn time and each kind's cap are `economy.gather` in `assets/farm/data/dynamic_farm.json`, which the C-58 server validates; `modules/dynamic_farm/parcel_gather.gd` reads the same block. Names and icons are the main farm's existing materials (`Timber`, `Wild Herb`, `Stone`); no item is new.

When the cell in front has no step to do and no cell was tapped, the main key turns to the outer object nearest the player (within `GATHER_REACH_M`, 1.2 m of its bounds on the ground, about a cell and a half) that the player faces most; a tap whose ray meets an object's bounds picks that object. The key reads `Gather` and the item name, `Gather · Move closer` for a tapped object out of reach, or `Regrowing · Ready in …` until it grows back. A press sends `{type:"gather", object}` without walking (the object is already in reach): with C-73's body the player faces it and plays the main farm's `harvest` labour clip, and the gain (`+1 Timber`) shows as the clip ends. Picked trees and rocks are redrawn faded (same model and pose, `gathered_prop.gdshader` washes out the vertex colours) and picked flowers, which never block, are hidden; the outer layer is redrawn when the picked set changes (`Scenery.build(..., bind=false)`), so the walk, the layout and collision stay exactly as loaded.

Object ids follow C-58's contract (`docs/plans/C-58.md`): `<block id>:<outer_groves.version>:<model>:<x>,<y>:<ordinal>`, the origin's grid cell and the same model's ordinal in that cell in the drawn layout order. The ids lock the recipe's `outer_groves.version` (`outer-groves-v2`); a recipe whose version differs from `economy.gather.recipe_version` offers nothing to gather. `tools/dev/dynamic_farm/gather_qa_apk.sh` builds an emulator QA package (x86_64 or arm64-v8a, default the host architecture, `GATHER_QA_ABI` overrides; also runs on macOS) that opens one r4 parcel straight into one's own farm on the device save (`own_parcel_qa.tscn`); it is never a delivered package.

## First house (C-33, Q-40)

Built on the own-parcel farm above (Q-44: one entry, save and protected path for both). The welcome gift's
`blueprint_cottage` comes with the first entry only. C-150 (0.4.5) makes this any building type: the save keeps a
`buildings` list (type, lowest cell, quarter turns 0–3, the footprint it was built with, an id) and the rules'
`buildings` give each type its model name, blueprint, unturned footprint and limit per parcel; the client's
`modules/dynamic_farm/farm_building.gd` `KINDS` gives each type its model asset, wall profile and name. Only the
cottage (3×3, one per parcel) exists so far. While the bag holds a type's blueprint and the type is under its limit,
`Build <name>` (`Build Cottage`) opens placement (the farming key is held meanwhile): a press or drag moves the
see-through model (its middle cell under the finger); its cells fill green or red, grid lines fade over three core
cells round it, and the protected path's cells in reach show sand. The bottom is the shared `UiPlaceBar`
(`Cancel · Rotate · Build`, the three-key bar P0's Decorate uses); Rotate turns the preview a quarter in place
(0, 90, 180, 270°, the owner's SEN-C-134#22 question 3), a turn swapping the footprint's width and depth; the reason a
spot is refused shows above the bar. The preview starts unturned on the valid spot nearest the player, else turned (C-175). A fresh yard often has no room
for the 7×5 coop until some trees, bushes, rocks and weeds are cleared: with no valid spot the preview starts on the one
needing the fewest of them cleared (`FarmBuilding.start_spot`), and a spot refused only for core obstacles reads
`Clear the plants and rocks here first` instead of `Space taken`. Build sends
`place_building` (type, cell, turn) through `ParcelFarming.send`; it stands at once (no construction time). A refused
Build (`CELL_OCCUPIED`, `BUILDING_OVERLAP`) keeps the preview, judged again on the farm the reply brought. A
successful Build (C-114) pops the building in and puffs dust with the main farm's look-swap effect (`P0Fence.pop_in` /
`P0Fence.dust`, read-only): one puff at the middle and one at each corner and edge middle of the footprint
(`FarmBuilding.rim`), each `HOUSE_DUST_SCALE` (4) times the main farm's size. Buildings that come with the save
(reopening, a refused Build) just stand there.

Rules (`modules/dynamic_farm/farm_building.gd`, a building's `x/y` is the footprint's lowest cell): every cell core
(`Outside your yard`); none under an uncleared core obstacle (`ParcelFarming.obstacle_cells()`, every role, weeds
too), another building, a tilled cell or a crop (`Space taken`); none on `ParcelFarming.protected_path()` (the same
path tilling keeps clear), and every other walk cell still reaching spawn with the standing buildings counted
(`Keep the path clear`). The server (`server/src/parcels/farm.ts`) checks the same buildings, tilled cells and crops
(it has no parcel geometry), with the turned footprint. The walls block through a model-fitted profile per type (the
cottage: walls and plinth below the eaves; C-19's walker), turned with the model, so the player walks along them and
stops at contact; the eaves, bench, woodpile and doorstep are not walls. A player standing where the walls go steps
out to the nearest clear point. Tilling is refused under every building (`House here`). A save from before C-150 has
only `house`: it reads as cottage 1 where it stood and facing as it did, and the server keeps `house` as the cottage's
mirror for 0.4.4 and older clients (their `place_house` is still the cottage). Without `own_parcel` (the art preview)
nothing of this shows.

`tools/dev/dynamic_farm/building_probe.gd` drives the real scene on the local save: entry, a valid spot turned
through the four turns, each refused spot, Build turned (three pop frames), the wall, reopen (`--headless`: states only).

## Coop, feeding and eggs (C-154, 0.4.5)

The coop is a building type of the C-150 rules: 7×5, one per parcel, for Scott's Coop Blueprint only, placed whole in
any of the four turns (`Build Coop`). The rules' `livestock` (in `dynamic_farm.json`, shared with the server) give its
three hens, the feed (one carrot, `energy.costs.feed` 1), the product (an egg `produce_seconds` 120 later), at most
`max_ground` 6 on the ground and the laying spots. The save's `drops` hold every egg, laid or due, with its hen, spot
and `ready_at`; `feed` writes one, `pick_up` takes a laid one into the bag once (ids from `drop_seq`, never reused).
The client's art is `assets/farm/data/dynamic_farm_art.json` (`modules/dynamic_farm/farm_livestock.gd`): the yard's
scene (SEN-C-155's `chicken_yard.tscn`; a placeholder of the parts and fence until it exists), its parts and fence
(walls; the front's opening is the entry, its walls pulled back so the player's centre passes `entry_clear_m`, 0.4 m), the hens' models and clips (SEN-C-156) and the egg's model. The yard's cells
are never farmed. `scenes/dynamic_farm/parcel_livestock.gd` walks the hens on the open floor (walk, peck, idle; they
step away from the player; a fed hen pecks at a feeder; a hen walks to her spot before her egg is due) and draws laid
eggs. Near a feeder the key reads `Feed` · `1 Energy`, unless a tapped cell has a step to do (the well's `Fill`, `Till`;
SEN-C-171, `test_parcel_farming_scene.gd`). An egg within 0.8 m of the player hops into them and flies on
into the Bag (`+1 Egg`). Numbers, the pickup and the copy await the owner (SEN-C-154#19); details in
`docs/plans/C-154.md`. Tests: `tests/dynamic_farm/test_coop.gd` (shared cases `fixtures/coop_cases.json` with the
server, walls, hens, pickup); captures: `tools/dev/dynamic_farm/coop_probe.gd`.

## Request Board (C-191, 0.4.6)

P0's system board at the Washington Square Travel Post: the room's board on the left wall (the kit's Fare Board,
`use_fee_board`) is a facility named `Request Board` (LOCK-07 v2). Tapping it walks there and opens the board drawer
(`parcel_board.gd`, through `parcel_town.gd` with no greeting): the page facts and one P0 `UiBoardCard` per request —
Track (`accept_request`), Deliver (`deliver_request`, tracked or not, once the bag holds enough) or the gap on the key
(LOCK-10) — and the request sheets after P0's BOARD-1 / 3 / DROPPED (`drop_request`). The rules are the `requests` of
`dynamic_farm.json` (server `server/src/parcels/requests.ts`, client `parcel_farm.gd`): 2 slots, refilled at once after
a delivery and 8 h after a drop, an open request swapped after 72 h, at most 6 a player day and 100 coins of completion
bonus; pay is Jasmine's price × count plus the completion bonus (C-197, owner SEN-Q-281 over SEN-Q-278: `floor_percent`
100); count and bonus by item and farm level (Lv3 and below / Lv4 on, `item_tiers`; a template may still carry its own
`tiers`, an item with none takes the shared ones); eggs only with a coop. The save's `board` and `requests_done` (the
sheep pen's unlock). Draws are a shared hash of the slot's own time, so a read and the next command see the same
requests. Copy: SEN-C-191#29; notes in `docs/plans/C-191.md` and `docs/plans/C-197.md`. Tests:
`tests/dynamic_farm/test_parcel_board.gd` (shared cases `fixtures/request_cases.json` with the server); emulator
package: `gather_qa_apk.sh` with `GATHER_QA_ENTRY=board`.

Seed aid (C-197, SEN-Q-281): with too few coins for one carrot seed, no seeds and no crops (bag or ground), opening
Jasmine's greeting sends `claim_seed_aid` once; the server gives 3 Carrot Seeds once a player day (`seed_aid` in
`dynamic_farm.json`, save `seed_aid_day`). Her greeting line says so; Trade stays her one key. Tests:
`tests/dynamic_farm/test_parcel_town.gd` (shared cases `fixtures/seed_aid_cases.json`); emulator package:
`GATHER_QA_ENTRY=aid`.

## First-visit guide (C-35, 0.4.2; C-61, 0.4.3)

`modules/dynamic_farm/parcel_guide.gd` reads the next step of the first ten minutes from the save alone, so a parcel
reopened halfway picks up at the same step: a Cottage Blueprint and no house -> `build`, a house and seeds ->
`till`, tilled soil with nothing on it -> `sow`, a dry carrot -> `well` (while its blueprint waits) or `water` (C-151,
before any other step and on any farm, so older farms hear of it too), a ripe carrot -> `harvest`; nothing while the carrot grows and
nothing once a carrot is in the bag or one has been sold. `ParcelFarming` shows it as the main farm's TipCard
(`UiTipCard`), centred under the top bar; it hides while the house is placed or the bag is open, and a tap closes it
until the next step. On the map, a package that enters one's own farm (`own_farm`) says where to go with nothing
selected (`Tap a building to choose your first home.` / `Tap your green parcel, then Enter my farm.`) and no longer
shows the preview's `Explore and walk. Farming actions come later.` Copy and screenshots: `docs/plans/C-35.md`.

0.4.3 (C-61) goes on from the first carrot, still from the save alone: a carrot in the bag and nothing sold yet ->
`sell` (at the Market); sold once and nothing gathered -> `gather`; something gathered in the bag that the Market buys
-> `sell_gathered`; gathered and sold -> `blueprint` (the Carpenter's coop blueprint); nothing once it is claimed. The
parcel's card says where to go; the map reads the home's save (`GET /parcels/mine`, no gift) on each return, and its
bottom card names the step done off the parcel (`Tap Washington Square to sell your carrot.` … since C-115), with nothing
selected or added under `Your home`. Copy and screenshots: `docs/plans/C-61.md`.

0.4.5 (C-175, the run-through of 0.4.5's content) replaces C-61's gathering loop after the first sale, since selling
what was gathered sold the Timber and Stone the farm upgrade needs: sold -> `blueprint`; the coop blueprint in the bag
-> `coop`; a coop never fed -> `feed` (with no carrot in the bag: `sow` / `till` with seeds, `buy_seeds` without);
a hen fed or an egg in the bag on a Lv1 farm -> `egg` (laid or not) / `sell_egg`; then `gather_upgrade` until the bag
holds Lv2's Timber and Stone, `upgrade` (at Scott's) after; nothing once the farm is past Lv1. A ripe carrot asks for
`harvest` before anything, a dry one with water left in the pail for `water_pail`. `ParcelGuide.stage` is the milestone
the phone's task rows follow (`ParcelTasks`: GET STARTED, TOWN, YOUR FARM). A tap on the coop's floor offers the
nearest feeder's Feed and walks there on the press. Copy: `docs/plans/C-175.md`.

## Blueprint book (C-228, 0.4.7)

The owner's SEN-C-214 (building was linear, one `Build <name>` key at the bottom left, the rules' first type whose
blueprint is in the bag) and design SEN-C-227 D-555, accepted with R1, R2 and D1–D5 (SEN-Q-344). The key in the same
place and size (180 × 48 clay side key) is now `Blueprints` (`blueprint_book.gd` opens from it): the book's rolled
blueprint (`assets/ui/v3/hero/hero_blueprints.png`, also the book's hero) and a cream disc with the blueprints in the
bag, none drawn at 0; a change pops the disc (1 → 1.15 → 1 in 200). It shows on one's own loaded parcel while a
blueprint is in the bag or a building stands (R2), and hides under the book and a placement. The book is the bag's UI v3
modal panel (`Blueprints` tag, the hero, ✕, scrim, Back): one 248 × 128 card per type of the rules' `buildings` in that
order whose blueprint the bag holds (`book_entries()`), the list scrolling past 80 % of the screen. A card shows the
building drawn once at the farm's 43° / 14.5° angle (`blueprint_thumbs.gd`, a SubViewport per type) on blueprint paper with
`×N`, its name, its `materials` as NEED-TILE S and one key: `Place`, `Need N more <item>` (`build_gap`) or `Farm Lv3
needed` (the level whose limit allows one more; a type at a limit no level raises is left out). A grey key shakes and
flashes the short tile, nothing more. `No blueprints` alone when the bag has none. Place fades the book (120) into that
type's placement (`begin_placement(type)`), with the type's name in a dark glass chip under the avatar; Rotate turns
the model over 160 ms ease-out (the spot is judged at once). Build lands back on the farm; Cancel and Android Back in a
preview go back to the book where it was scrolled; Back in the book closes it. The camera and the player stay as they
are while placing (R1). Blueprints are no longer on the quick bar (D4; still in the bag). The guide's build, well and
coop lines point at Blueprints (draft copy, PM finalises it, C-45). The server already took any blueprint in any order;
`server/test/parcels/farm.test.ts` and `parcels.test.ts` pin it and that a missing blueprint, a taken spot and short
materials refuse the whole batch with the save unchanged. The Arrange key, moving and storing: SEN-C-229, below.
Tests: `tests/dynamic_farm/test_blueprint_book.gd`; emulator package `GATHER_QA_ENTRY=book`. Notes: `docs/plans/C-228.md`.

## Moving and storing buildings (C-229, 0.4.7)

Design SEN-C-227 D-555 README §5 (figure 3), accepted with D1–D3 (SEN-Q-344). The server's `move_building {building,
x, y, rotation}` checks the new spot as `place_building` does, the building's own old cells not counting, and keeps its
animals, drops (saved by spot, so they go with it) and timers; `store_building {building}` gives back the blueprint and
the rules' `materials` (D1) and puts its laid drops in the bag; never the cottage (D3, `CANNOT_STORE`), never while a drop
is on its way (D2, `PRODUCING {ready_at}`). Both are free and owner only; `parcel_farm.gd` has the same rules
(`store_refusal`, `store_returns`), with the shared cases in `tests/dynamic_farm/fixtures/arrange_cases.json`
(`tools/dev/dynamic_farm/arrange_cases.ts`). While a building stands the book has a full-width `Arrange` key at the
bottom; it starts the arrange mode (`building_arrange.gd`): the farming UI away (M-16, the phone too), a marker over each
building (LOCK-07 icon button sizes, a four-way arrow, gold while selected), one `Done`; a drag pans. A tap on a marker or
a building's cells slides its card up: its picture, name, `3 Hens` / `1 Egg on the ground`, `Store` and `Move` (the
cottage: `Move`), Store greyed `Ready in …` while a drop is on its way. Store asks `Store <name>?` with what goes back
into the bag; stored, the building shrinks away with dust and a toast says `<name> stored`. Move hides the building and
its yard behind the placement preview (`Cancel · Rotate · Move`, its old outline in white dashes, its own cells free);
moved, it lands with the Build pop. Back folds the card, then ends the mode, as Done does.
Tests: `tests/dynamic_farm/test_building_arrange.gd`; captures `tools/dev/dynamic_farm/arrange_shots.gd`; emulator package
`GATHER_QA_ENTRY=arrange`. Notes: `docs/plans/C-229.md`.

## Washington Square room (C-115)

The owner on C-103#17: no place icons on the map, one fixed 3D space entry in San Francisco, its look and interaction
after farm-dev. The C-59 `Market` and `Carpenter` buttons are gone. `town_entry.gd` draws farm-dev's Travel Post pin at
Washington Square Park in North Beach (37.8008, -122.4103, the park's centre; moved there from farm-dev's own Union
Square spot on C-115#30, beside C-130's starter area; `UiMapDestination` with the post's i-travel glyph and the short
name `Washington Square`), placed each frame through `geo_native_camera.gd`'s `geo_screen` (screen_geo's inverse, tilted too).
The map takes a tap on the pin before its building pick and opens the place card farm-dev opens for an outpost
(P0PlaceSheet's layout from the same kit pieces, without P0Ui): `Washington Square Travel Post`, `Market · Carpenter`, the
Distance from home and `Go`, × above its corner, a tap outside or Back closes it; the pin grows while selected. Without a
home the card says `Claim a home first.` and has no Go. Only in packages with `own_farm`.

Go opens `parcel_outpost.tscn` through AppRouter, as Enter my farm opens the parcel (the map goes opaque only once the
router pushes it). The room extends farm-dev's `P0Outpost` read only, with `use_runtime = false`: the post_office kit, the
post anchors, the door, the room camera and walking are farm-dev's (its top bar names it after the pin); no P0Runtime, P0Ui, session, online room or
voice starts, and no file of the main farm changes. Jasmine stands behind the counter (`npc_keeper`) and Scott where Sam
stands (`npc_sam`), in their C-59 looks; nobody else. The room drives itself: P0Ui's scene touchpad rebuilt on
`GestureArbiter` (stick, tap, double tap recenter, pinch), `p0_frame` each frame and the world prompts (UiNpcNameTag over
the heads, the door's i-door button opening into its `Map` strip; one open at a time, LOCK-07 v2). A tap on Jasmine or her
counter walks to the counter and opens her greeting (LOCK-16), Sell her counter; a tap on Scott walks to him and opens his
greeting; both trade through the home's parcel save as before (`store`). Back closes a greeting first, then walks out
through the door (farm-dev's rule); the door or the top bar's back returns to the map, which reads the save again.
Lock scope (C-115#9): LOCK-07 / 16 as on the main farm; Scott is no resident (no dialogue bar, LOCK-18) and the room
holds both roles (LOCK-19 is the main farm's). Tests: `tests/dynamic_farm/test_parcel_outpost.gd`, the map's pin and card
in `test_claim_controller.gd`, `geo_screen` in `test_map_camera.gd`.
