# SGODOT-284 · Notice Board · v1.1

刘备 · 2026-10-13 · target **after 0.2.6**. Based on `origin/wp-3d-scene`
commit `ec5f9bde`; branch `wp-3d-scene-liubei-notice-284`, PR base `wp-3d-scene`.
Technical review: 上官婉儿. Visual review: 不知火舞. Integration: 苏烈 / #375.

The Homestead Lv5 notice board is a pair of slim wooden posts with small feet,
a dark frame and plain recessed cork panel, four blank tilted paper sheets,
small red/gold/green round pins and a green gable canopy. The low connecting
rail is included to make the two posts read as one frame. The single variant
uses the existing farm palette and unchanged `FarmArt.material()`.

## Review images

- [43° pitch / 14.5° yaw, existing character and actual storage/well](notice-board-43deg.png)
- [Front +Z, blank paper sheets and small round pins](notice-board-front.png)
- [True top view, real 0.65 m grid and specified neighbouring cells](notice-board-top-grid.png)

All three are actual 1800 × 1400 Godot 4.7.2 Vulkan Mobile SubViewport captures
on AMD Custom GPU 0405 (RADV VANGOGH). The scene uses existing farm lighting,
an existing 1.745 m character and unmodified `storage.glb` / `well.glb`, each
at unit scale. The front detail crops the lower posts deliberately. The top
view overlays blue outlines showing the feet underneath the roof.
These are isolated desktop art checks; final UI hit regions, farm integration
and physical-device performance are outside this review fixture.

## Dimensions and integration

| Item | Delivered value, Godot metres |
|---|---|
| Mesh / surface / triangles | 1 / 1 / 1,012 (limit 1,200) |
| Mesh total height | 1.595; name-marker empty at 1.75 excluded |
| Full mesh bounds | (-0.35,0,-0.13) → (0.35,1.595,0.13) |
| Board outer dimensions | 0.56 × 0.44 × 0.05 |
| Board bottom / top | 0.95 / 1.39 |
| Rim width / front bevel | 0.035 / 0.003 |
| Frame back / front Z | 0.02 / 0.07 |
| Cork face Z / recess | 0.06 / 0.01 |
| Post centres / section | X ±0.25 / 0.07 × 0.07 |
| Each square foot | 0.10 × 0.05 × 0.10 |
| Complete post/foot projection | X ±0.30, Z ±0.05 |
| Roof width / depth | 0.70 / 0.26 |
| Lowest imported eave / front overhang from cork | 1.47231 / 0.07 |
| Paper sizes | 0.11–0.14 wide, 0.125–0.155 high, 0.005 thick |
| Paper angles | -5°, +6°, +7°, -4° |
| Pin-head diameter / maximum board relief | about 0.02 / 0.01181 |
| Ground pivot / front | Midpoint between posts / +Z |
| `board_center` / `mark` | (0,1.17,0.06) / (0,1.75,0) |
| Collider centre / size | (0,0.80,0) / (0.62,1.60,0.14) |
| Footprint | 0.65 m; `footprint_cells=[1,1]` |

The notice board remains at anchor `(15,15)`. `Blueprint.cell_to_world()` maps
smaller cell Y to larger world Z, so the specified storage `(14,15)` is
`(-0.65,0,0)` relative to it, and well `(15,13)` is `(0,0,+1.30)`.
No additional scale, mirror, yaw or ground translation is baked into the model.

The left foot clears the storage's right edge by **0.030 m**; the prescribed
collider has **0.020 m** clearance. The roof extends 0.025 m beyond either cell
edge and overlaps the storage silhouette in plan by 0.020 m, but its lowest
surface is 0.955 m above the storage top. There is **no 3D intersection**.
The full notice-board mesh and well have a **0.825 m Z gap**. Exact exported
triangle/BVH checks and independent Godot imported-triangle checks both confirm
zero intersections with each neighbour. The positive control moves storage
15 cm into the post and produces 127 intersecting triangle pairs.

When replacing the #375 placeholder, 苏烈 should use the manifest's narrow
collider and board-centre hook for clicking, retaining the ground anchor and
`mark` above the canopy. `FarmArt.instance()` extracts only the mesh; instantiate
the full PackedScene or reconstruct both empties from the manifest if needed.
Automatic LODs and unused tangents are disabled in the committed import file.

## Specification choices and exact palette

Readability and specification dimensions take priority over concept proportions.
The optional low rail is present at 0.30 m. Four paper sheets are spread over the
cork, with three ivory/milk sheets and one yellow sheet, all blank. No lettering,
numerals, drawings, wood grain, cork spots, edge noise, textures or black outlines
were added.

[Palette provenance](../../../tools/art/source/notice_board_284/palette-provenance.json)
records each copied vertex sample, exact linear RGB values and source file hash.
The exported palette is bit-for-bit the same numeric set as those source samples.
Approximate sRGB values below are labels, not newly calculated material values:

| Part | Actual source | Approximate sRGB |
|---|---|---|
| Posts, feet, low rail | deco_bench middle wood | #A87948 |
| Solid board frame | deco_bench dark wood | #675139 |
| Cork face | storage light wood | #CBA067 |
| Roof slopes / green pin | storage green; exact match also in well | #437D64 |
| Ridge cap | storage dark green sample | #356551 |
| Two ivory papers | sign | #FFF4D2 |
| One milk paper | chef_sign_a | #FFF3DD |
| One yellow paper | sign | #F1CE58 |
| Red / gold pins | chef_sign_a | #80382F / #E6B954 |

The chef sign's actual gold is #E6B954, while the specification's approximate
#F1CE58 exists in sign/storage. To preserve the requested source colors, the
pin copies actual chef gold and the paper copies existing sign yellow; neither
is recolored or lightened. This choice is included in the PR for review.

## Validation and reproduction

[Combined validation](validation.json) includes **70 passed checks**: 34 from
[actual Godot imports](godot-validation.json) and 36 from the independent
[GLB/source audit](glb-validation.json). It records actual bounds, triangle count,
post/foot projection, sockets, neighbour placement, exact intersections and
palette provenance. Twenty cork-face ray samples remain unobstructed by the
actual roof triangles at 43° / 14.5°.

[Two consecutive exports](reproducibility.json) produce byte-identical GLB,
manifest and palette provenance. [Preservation audit](preservation.json) confirms
all 113 existing farm-art/import files and all 40 prior manifest entries match
`ec5f9bde`. Existing shared materials and runtime gameplay scripts are unchanged.

The [editable source](../../../tools/art/source/notice_board_284/) contains the
supplied reference/specification, named Blender parts and exact palette record.
Blender version: 5.2.2 LTS. Reproduce from the repository root:

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_notice_board.py"
blender --background --factory-startup --python "$PWD/tools/art/verify_notice_board.py"
python3 tools/art/prepare_notice_board_review.py
godot --headless --path output/notice-board-284/project --editor --import
godot --path output/notice-board-284/project
```

The last command requires the active display. Results appear under
`output/notice-board-284/`; the project is isolated with its own user-data path.

## Plane delivery

Three PNGs and the combined validation JSON are attached to SGODOT-284 with
prefix `SGODOT-284_Notice-Board_v1.1_`. All writes use 刘备's
`virtual_user_id=0fb1de1f-ead5-443b-9537-54cbac113260`.
[Delivery verification](delivery-verification.json) records each attachment ID,
verified uploader and SHA-256 match after downloading the delivered file.
Technical and visual acceptance are requested from the assigned reviewers.
