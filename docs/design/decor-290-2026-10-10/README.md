# SGODOT-290 · Farm decorations

> Integration note (farm-dev, SGODOT-290): per the 2026-10-08 art-integration rule, the review images and JSON evidence linked below (overviews, contact sheet, validation / preservation JSON) stay on the `wp-3d-scene` branch under the same path; only this README, the GLBs, their `.import` files and the manifest entries are merged here.

刘备 · 2026-10-10. Ten decorations plus one separate windmill rotor, for review by
上官婉儿 (technical) and 不知火舞 (visual). Branch `wp-3d-scene-liubei`; PR target
`wp-3d-scene`. Runtime integration belongs to 苏烈.

The models follow SGODOT-290 v1.1 and the seven concept review corrections.
They use the existing farm wood/leaf/red palette, two or three flat colours per
material family, rounded silhouettes and opaque vertex colours. No wood grain,
stone mottling, water jets, emissive glass, textures or new runtime material.

## Bench R2

The R1 back was too low to read at the 43° review angle. Only `deco_bench` is
revised: two upright broad rails lean 10° backwards and reach 1.048344 m,
0.378344 m above the unchanged 0.67 m seat. Armrests remain at 0.765 m.
The width/depth is 1.110 × 0.563851 m (within 1.24 × 0.59 m); 792 triangles,
one surface. Both seat transforms and the three seat planks are retained.

The [bench 43° close-up](deco_bench-detail.png), both overviews and contact sheet
show R2. [R2 preservation evidence](bench-r2-preservation.json) compares against
R1 commit `bbe4d7b130708ef32ae0e0a49dd54aa171e8d2a4`: the other ten GLBs, all
existing import settings and the other 34 manifest entries are unchanged.
The [rebuild record](reproducibility.json) covers two identical bench exports.

## Godot review

- [43° overview: ten pieces in one row, existing character beside them](overview-43deg.png)
- [R2 bench at 43°](deco_bench-detail.png)
- [Top-down overview: same placement and scale](overview-top.png)
- [Individual views](contact-sheet.jpg)
- [Three fence segments joined at 0.65 m intervals](fence-three-segments.png)
- [Manifest triangle/dimension table](manifest-budget.csv)
- [Godot structural checks](validation.json)
- [Existing farm asset preservation](preservation.json)
- [Deterministic rebuild verification](reproducibility.json)

Screenshots use Godot 4.7.2, Vulkan Mobile on the Deck's AMD Custom GPU 0405
(RADV VANGOGH), through an offline isolated project. Both overview images are
4400 × 1200 actual SubViewport renders. Individual 1100 × 1000 renders use 43°
pitch and 25° yaw; the contact sheet only resizes and labels those captures.
Lighting copies the existing farm sun/ambient settings. The ground and captions
are review fixtures. This is desktop visual/structural validation, not an Android
or physical-phone performance measurement.

## Integration contract

Files: `assets/farm/art/deco_<name>.glb`; manifest keys match file stems and item IDs.
All files contain one MeshInstance3D, one surface, opaque vertex colours and no
images. Floor pivots are `(0,0,0)`, +Z faces forward, one cell is 0.65 m.
`bounds` is `[min,max]` in Godot metres; `bounds_blender` retains the kit convention.
The one explicit origin exception is the separate rotor, whose origin is its axle.

`FarmArt.instance` / `mesh_for` deliberately extract only the mesh. For hooks,
either instantiate the full PackedScene and apply `FarmArt.material()` to its
single mesh, or create the equivalent Node3D hooks from the manifest `sockets`.
Do not expect FarmArt.instance to retain GLB empty nodes automatically.

- **Lantern:** `glow = (0.105, 0.848, 0)`, identity basis; empty node only. Attach
  the nighttime light in gameplay. The glass is opaque cream vertex colour.
- **Bench:** `seat_0 = (-0.275, 0.67, 0.035)`,
  `seat_1 = (0.275, 0.67, 0.035)`, identity bases, +Z forward. Seat top 0.67 m
  matches the actual Basic Room bench mesh (`0.60 + 0.14 / 2`); do not add the
  Basic Room layout's raised room-floor placement to the local socket height.
  The R2 backrest top is 1.048344 m and reclines 10° within the original cells.
- **Windmill:** position `deco_windmill_sails` at the body's `rotor` empty,
  `(0, 0.985, 0.273)`, and rotate about local +Z. The full animated sweep is
  below 1.24 m diameter. Combined body/rotor cost is below 4,000 triangles.
  The red cap is a cone and the frame has no doors/windows or tiled house roof.
- **Pergola:** four pillar boxes only; `colliders` lists their local centres/sizes.
  No whole-volume collider. Post centres are `(±0.79, 1.105, ±0.49)`, size
  `(0.13, 2.21, 0.13)`. Clear opening is 1.45 × 0.85 m; underside of long beams
  is 2.14 m, leaving 0.395 m over the H = 1.745 m character. Roof/foliage top is
  about 2.40 m. This uses the brief's allowance for a slightly lower opening
  instead of expanding the footprint. All seven roof slats run along short Z.
  Vines remain against the front posts and roof; they are merged in the mesh.
- **Fence:** one 0.65 m segment along X. At each end, a half-width post is cut
  at ±0.325 m; neighbouring halves form one full post. Repeat by 0.65 m without
  an inset/gap at the seam. The six-piece purchase is six program instances.
- **Path:** one flat rounded stone, 0.033 m thick; five-piece purchase is five
  program instances. Use the existing batch API for repeated paths/fences.
- **Scarecrow:** hands span about 0.797 m, within the expressly allowed 0.85 m
  exception to a one-cell outline. Arms angle down; hat, smile and patch remain.
- **Birdbath/Fountain:** the birdbath has a blue bird on the rim; the fountain
  has two distinct basin tiers. All water surfaces are planar vertex-colour
  geometry. No falling water/jet geometry is included.

All other X/Z bounds retain at least approximately 0.03 m clearance inside their
specified footprint. The fence seam and scarecrow hands are the brief's stated
exceptions. No gameplay, slot, avatar, saved outfit or collision code is changed.

## Reproduce

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_decor_assets.py"
python3 tools/art/prepare_decor_review.py
godot --headless --path output/decor-290/project --editor --import
godot --path output/decor-290/project
```

For a bench-only GLB/manifest rebuild, append `-- --only deco_bench` to the
Blender command. Other runtime decorations are left intact.

The staging script copies existing fixture avatar dependencies and artwork into
`output/decor-290/project`; it loads only Avatar, with the default fixture outfit.
Captures and `validation.json` appear in `output/decor-290/captures`. Runtime
files, networking and production user data are not used. Render with a display;
headless mode is only for imports. The review script checks counts, surfaces,
colours, pivots, bounds, socket positions/bases, Basic Room seat height, rotor
sweep and the fence step. Import files disable automatic LOD generation for these
small authored silhouettes. Editable source: [decor_290.blend](../../../tools/art/source/decor_290/decor_290.blend).

## Export budget

| Asset | Triangles | Limit | Godot bounds size X × Y × Z (m) |
|---|---:|---:|---|
| `deco_planter` | 1,676 | 2,000 | 0.560 × 0.427 × 0.560 |
| `deco_lantern` | 452 | 2,000 | 0.453 × 1.160 × 0.240 |
| `deco_path` | 92 | 500 | 0.548 × 0.033 × 0.480 |
| `deco_bench` | 792 | 2,000 | 1.110 × 1.048 × 0.564 |
| `deco_scarecrow` | 1,240 | 2,000 | 0.797 × 1.495 × 0.375 |
| `deco_fence` | 296 | 500 | 0.650 × 0.590 × 0.090 |
| `deco_birdbath` | 1,402 | 2,000 | 0.578 × 0.840 × 0.578 |
| `deco_windmill` | 1,188 | 4,000 | 0.800 × 1.333 × 0.800 |
| `deco_fountain` | 2,076 | 4,000 | 1.206 × 0.994 × 1.206 |
| `deco_pergola` | 1,908 | 2,000 | 1.880 × 2.397 × 1.233 |
| `deco_windmill_sails` | 1,496 | 4,000 | 0.952 × 0.952 × 0.081 |

Total **12,618 triangles**, 11 surfaces in 11 files. Windmill body + sails: **2,684 triangles**. The rotor bound is at its axle; fully assembled rotating height is about 1.59 m.

Godot R2: **123 / 123 checks passed**. Full rotor swept diameter: **1.188378 m**. Original 24 farm manifest entries and existing assets retained. Relative to R1, only the bench GLB/manifest entry changed; two consecutive bench exports were byte-identical.
