# SGODOT-275 · Fare Board · v1.1

刘备 · 2026-10-14 · target 0.2.6 · review base `wp-3d-scene` (`ec5f9bde`).

Adds the San Francisco Post Office's wall-mounted fare board: rounded dark
wood frame, thin cornice, recessed blue-green panel, seven variable-length
ivory bars and seven colored dots. Two brass round heads fix the upper corners.
There are no letters, numbers or symbols on this prop. Named Blender source,
deterministic generator and atlas-swatch provenance are included.

## Actual Godot images

- [43° room view with existing character](fare-board-room-43deg.png)
- [Front: seven blank rows and colored dots](fare-board-front.png)
- [Side: 0.070 m maximum thickness](fare-board-side.png)

All are 1800 × 1400 captures from Godot 4.7.2, Vulkan Mobile, on the Deck's
AMD Custom GPU 0405 (RADV VANGOGH). The room image uses the actual
`post_office_art.tscn`, its shared plants and material, unchanged suite lighting,
43° pitch and suite yaw 45.7063°. Camera target and orthographic width
14.474629 m come from `layout.json`. The existing 1.745 m character stands at
(-2.2,0.08,0.35), facing the left wall on the public side of the counter.

Front/side details retain the kit light colors/direction, with cast shadows
disabled for inspection; this avoids room-scale shadow-map striping at macro
scale. The room image retains the original shadows. The screenshot labels are
review overlays, not geometry. This is desktop art validation, not the P0
portrait UI or a physical-phone/Android performance acceptance.

## Dimensions and integration

| Item | Actual delivered value, Godot metres |
|---|---|
| Runtime asset | `assets/rooms/post_office/fare_board.glb` plus `.import` |
| Mesh / surface / triangles | 1 / 1 / 674, budget 800 |
| Bounds | (-0.45,-0.325,0) → (0.45,0.325,0.07) |
| Width × height × maximum depth | 0.90 × 0.65 × 0.07 |
| Pivot / front | Back centre at zero / +Z |
| Frame width / front plane / board plane | 0.05 / Z=0.06 / Z=0.05 |
| Rows | 7; height 0.03, centre pitch 0.065 |
| Row lengths, top to bottom | 0.57, 0.49, 0.42, 0.54, 0.37, 0.46, 0.31 |
| `board_center` | (0,0,0.05), identity basis |
| `mark` | (0,0.45,0), identity basis |
| Approved placement | (-3.21,1.65,-1.65), yaw 90° |
| Placed bounds | X -3.21…-3.14; Y 1.325…1.975; Z -2.10…-1.20 |
| Gap below actual postal sign | 0.485 |

Arthur adds the GLB through P0 `post.anchors.json` props. Instantiate the full
PackedScene to preserve the two empties, bind the room's shared atlas material
to the single MeshInstance3D, then apply the approved position/yaw. The fixture
uses the **same material object** as the actual sorting cabinet. The raw GLB
contains a named `RoomKit_SharedAtlas` material but no embedded texture, matching
the kit's export convention. Click point and nameplate use `board_center`.
`layout.json` is byte-identical; this PR does not implement gameplay placement.

## Choices under specification priority

1. Seven rows follow v1.1 and 不知火舞's review, overriding the reference's six.
2. Thin upper cornice plus two brass round heads use the permitted fixing option.
3. `mark` follows the authoritative v1.1 **local Y=0.45** coordinate, 0.125 m
   above the board top; the brief's “top +0.45” wording would instead give Y=0.775.
4. The actual world map has no red or mustard regions. Red comes from the
   postal sign, mustard/brass from the door, teal from the map. All are existing
   pixels in the unchanged shared atlas; no replacement colors or atlas edits.

| Swatch | Actual source asset | Atlas pixel (X,Y from top left) | RGB8 |
|---|---|---|---|
| Wood | sorting_cabinet | (789,1031) | 129,66,39 |
| Board | postal_blue_door | (329,455) | 38,71,85 |
| Ivory | post_office_sign letters | (1376,415) | 235,220,192 |
| Red | post_office_sign | (692,1263) | 166,56,48 |
| Mustard/brass | postal_blue_door | (1445,421) | 155,123,70 |
| Teal | world_map | (1208,1086) | 84,138,156 |

Each triangle has a constant UV at one pixel centre, so it samples a flat atlas
color without wood grain. All six centres lie inside source-model UV triangles;
their 7×7 neighborhoods contain neither black nor transparent/blank pixels.
The atlas remains SHA-256
`dbae34e9aaeb7553c7264ef841e939ba43b6d462ad60eb18ba1e2132021ffbd9`.

## Validation and reproduction

[validation.json](validation.json) bundles all evidence: **69 checks passed**
(47 independent binary/source/placement checks and 22 actual Godot checks).
The [binary report](glb-validation.json) checks normals, topology, UVs, named
parts and actual room-triangle intersections. The [Godot report](godot-validation.json)
checks imported dimensions, surfaces, sockets, UVs, shared material and visibility.

Exact triangle testing gives zero penetration against room shell, left wall,
postal sign, counter, magazine rack, computer and sorting cabinet. The left wall
has 48 flush contact pairs at the intended mounting plane, **not penetration**;
nine support rays agree with X=-3.21 within 0.1 mm. A deliberately misplaced
board intersects the actual counter in 129 triangle pairs, verifying detection.
At the required camera angles, all 25 sampled face points are unobstructed by
the real room, plants, counter and monitor. These samples do not certify P0
click regions or nameplate layout.

[Preservation](preservation.json): 102 pre-existing room/scene/pipeline files
match `ec5f9bde` byte-for-byte, including atlas, layout, statistics and imports.
New import parameters match `post_office_sign.glb.import` exactly; staged review
GLB/import bytes match delivery. [Reproducibility](reproducibility.json): two
consecutive builds produce identical GLB, contract and swatch-input hashes.

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_fare_board.py"
blender --background --factory-startup --python "$PWD/tools/art/verify_fare_board.py"
python3 tools/art/prepare_fare_board_review.py
godot --headless --path output/fare-board-275/project --editor --import
godot --path output/fare-board-275/project
```

Use an active display for the last command. Blender reports failures through
its log; also check `output/fare-board-275/glb-validation.json` has no failures.
Godot captures and its report appear under `output/fare-board-275/captures`.
The isolated fixture uses only the existing Avatar autoload and a separate
`SensenFareBoard275QA` user-data directory. Source details and authority copies
are in [fare_board_275](../../../tools/art/source/fare_board_275/README.md).

The three PNGs and combined validation are delivered to SGODOT-275 under
刘备's `virtual_user_id=0fb1de1f-ead5-443b-9537-54cbac113260`.
The [delivery receipt](delivery-verification.json) records uploader identity and
downloaded hash checks for all four attachments.
Technical review belongs to 上官婉儿; visual review belongs to 不知火舞.
