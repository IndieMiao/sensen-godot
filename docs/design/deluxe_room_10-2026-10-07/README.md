# SGODOT-173 · Deluxe Room-10 R2.1 finishing revision

赵云 · revised for **Review** after the director's SGODOT-172 R2 release. Reference: Figma `OMLTC3yw3u2WDjOZhLnhaR`, SceneDesign, node `545:2970`. Basic Room's accepted scale and Liu Bei's shared botanical library are read-only dependencies.

![Reference / revised actual Godot / direct 50% overlay](comparison.png)

[Whole scene](godot.png) · [Kitchen](detail-kitchen.png) · [Loft and stairs](detail-loft.png) · [Living](detail-living.png) · [Editable-model orthographics](orthographic-sheet.png).

| Review requirement | Final implementation |
|---|---|
| Spatial layout | Left-wall sink/prep/range/pantry, island with three reused stools, rear stairs rising to the right-back loft. Under-loft bookcase, rounded hearth, separate wood niche and right door. Front-left long dining table with six instances of one padded chair; front-right sofa, low coffee table and TV console. Both main rugs are pale natural jute. |
| Loft and navigation | Structural posts and heavy crossbeam remain visible. Thirteen visual treads sit over one continuous ramp-to-landing convex collider. Outer stair guard stops before the turning opening; loft front/west guards block falling. The solid wedge closes low-headroom under-stair access. Floor is approximately 2.46m high, underside approximately 2.23m, retaining the 1.7455m fixture's clearance. |
| Kitchen | Broad cream trapezoid hood with an oak lip, four-burner oven and cooking pot; glazed jars, open pantry, utensil crock, fruit bowl and flowers. Green enamel pendant has a long black flex and an unshadowed local warm lamp. Island towel and runner use metric UVs. |
| Loft dressing | Checked duvet follows physical fold length, two pillows, drawer nightstand with warm lamp, a real upper arched aperture with green frame, white tied curtains, botanical print and trailing shared plants. |
| Living and dining | Continuous cream upholstered sofa, green and checked cushions, wicker basket, books and ceramic mug. TV console has drawers, knobs and open cubby. Long dining table has a metric checked runner, daisies, six thick solid chairs and tied green pads. Low coffee table is intentionally a distinct furniture category. |
| Hearth and door | Rounded cream plaster, orange gradient flame, charred logs/embers, matte irregular split-log niche, mantel landscape and candlesticks, warm table/wall lighting, greenery near the entry and striped mat. Mantel projects ahead of the loft beam so it reads in the whole scene. |
| Materials and batching | Warm timber and lightly textured plaster, room-wide static contact AO, one shadowed sun and five short-range unshadowed lights. Editable named parts remain in the Blender source; fittings and soft goods are grouped by zone at export. Repeated chairs/stools share local-pivot GLBs. Supplied double-sided alpha-scissor plant material is retained; foliage/flowers/backgrounds do not cast shadows. |

## Latest R2.1 items and future kitchen hooks

The TV screen is 33% smaller in width/height, and its reduced console moves to the room's front-right area with a 55-degree angle toward the sofa. Main-view sofa, coffee table and fireplace visibility is improved. The back wall changes from salmon to low-saturation cream; the stair wall gains a framed botanical picture, wooden shelf, a local black wall lamp and hanging pothos. A plant beside the stairs and a small loft-entry plant supplement the enlarged window/loft foliage. Shared leaves use the current deeper-green atlas `1ec21f9e`; 172's accepted geometry and source remain unchanged.

![Named future kitchen-module mounts](kitchen-attachment-points.png)

Six named **Blender Empties / Godot Marker3D** mounts are present in `layout.json.attachment_points`: `hob_slot_1..3` point upward over three of the four burners; `prep_area` occupies the cleared 0.50m worktop beside the cooker; `spice_rack` uses the open shelf; `warmer_slot` reserves a 0.56m cabinet below prep for a later replacement. Its dashed box is an x-ray annotation because the island partly occludes the base from this camera. The utensil crock moves beside the sink. No kitchen-module model or gameplay behavior is added (213/218 own integration).

The pendant was raised and shifted forward over the island: measured shade bottom **2.670m**, 0.9245m above the fixture's visual head. The main/detail views show the prep surface unobstructed. Source AABB checks verify the cleared prep area; source Empties and runtime Markers independently verify matching positions and +Y up axes. [Measured hook contract](kitchen-hooks-verification.json).

R2.1 repeats **38/38** actual character checks and records a fresh 15-second route through the loft. Original review remains in Git history and the Plane card; current images/results belong to R2.1.

## Camera and colour evidence

The camera uses the three declared visible plinth-edge intersections, with the hidden fourth inferred. The concept's floor is squarer and its upper back corner is offset relative to a perfect orthographic rectangular room. The retained physical plinth is 9.6×7.8m: edge slopes determine yaw/pitch; mean horizontal scale plus an 8% framing margin keeps the entire ceiling visible. The direct overlay exposes those remaining shape/projection differences; no image warp or pixel-fidelity score is used. [Fit inputs and limits](../../../tools/art/source/deluxe_room_10/camera-review.json).

[Marked surface samples](colour-samples.png) and [full RGB/HSV results](colour-verification.json) record corresponding left plaster, right plaster, front post and horizontal floor. An early supposed floor pixel was on the vertical plinth: its 11.218° result is retained in the private preliminary evidence, and the floor point was then projected from the fixed declared world position `[0.28,0.083,3.25]` before material tuning. Later the fixed back-wall patch rose to 12.925° after hearth placement; the wall material was corrected at the same point. Final hue differences are **3.941° / 9.193° / 1.047° / 2.454°**, all ≤10°. Saturation and brightness remain separately reported.

## Validation and rebuild

**38/38 rendered checks and the unaccelerated 15-second route video pass.** The fixture traverses ten sequential waypoints: door, living, dining, island, sink, stair approach/foot/top, loft entry, bedside. Probes cover furniture, kitchen cabinetry, the closed stair underside, loft guard and open diorama edges. Live measured main aisles are 0.755m between island seating/dining seating and 0.9342m between sofa and coffee table, above the card's 0.70m minimum. Door exit/reentry, diagonal wall sliding, input release and advancing idle/run animation are checked.

[Per-check results](bench-result.json) · [Scale ratios](bench-scale-measurements.json) · [Blender source dimensions](source-scale.json) · [Metric cloth checks](cloth-uv-verification.json) · [Actual colliders](bench-collisions.png) · [Unaccelerated 15-second video frames](video-frames.png).

Measured source heights: door clear 2.33m, island top 1.17m (+1.52%), padded chair .7825m (+14.23%), dining table 1.135m (baseline). All applicable categories stay within ±15% of Basic Room. Three .78m stools serve the higher island; the .613m coffee table is a deliberately lower category, not a replacement for the dining-table baseline.

**159,455 / 200,000 placed triangles**, **33,952 / 100,000 botanical triangles**, **60 / 60 static surfaces**. Exact budgets, delivered GLB UV/normal/image checks and file hashes are in [verification-summary.json](verification-summary.json). Limits are ≤200,000 total / ≤100,000 botanical / ≤60 static surfaces. Character evidence is Godot 4.7.2 Mobile/Vulkan on AMD Custom GPU 0405 (RADV VANGOGH); it is desktop behavioral validation, not physical-phone performance acceptance.

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_deluxe_room_10.py" -- --views
blender --background --factory-startup --python "$PWD/tools/art/source/deluxe_room_10/measure_review.py"
python3 tools/art/create_room_scene.py deluxe_room_10
python3 tools/art/prepare_room_review.py deluxe_room_10
# Import, retain configure_room_imports.py settings, then capture through review_room.gd.
python3 tools/dev/scene_bench/prepare.py deluxe_room_10
# Import the isolated bench, then run on the current real display:
python3 tools/dev/scene_bench/run.py deluxe_room_10 --record --output output/zhaoyun-173-review-2026-10-07/bench
python3 tools/art/check_room_colour.py deluxe_room_10 173
python3 tools/art/package_room_review.py deluxe_room_10 173
```

The builder delegates to `tools/art/source/deluxe_room_10/revision.py`. Source edits belong in that deterministic generator; the `.blend` retains named editable parts and reusable pivots. No gameplay, saves, release presets or another artist's assets are changed.
