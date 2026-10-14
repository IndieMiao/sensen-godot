# SGODOT-282 · Chef's Sign · v1.3

> Integration note (farm-dev, SGODOT-282): per the 2026-10-08 art-integration rule, the review images and JSON evidence linked below (43° / top-down captures, validation, reproducibility, preservation, delivery verification, the v1.2 README) stay on the `wp-3d-scene` branch under the same path, as do the generator, review and verify scripts and the Blender source under `tools/art/` (`build_chef_sign.py`, `prepare_chef_sign_review.py`, `review_chef_sign.gd`, `verify_chef_sign.py`, `tools/art/source/chef_sign_282/`); only this README, the two GLBs, their `.import` files and the two `chef_sign_*` manifest entries are merged here. Technical check (上官婉儿) and visual acceptance (不知火舞) passed on SGODOT-282 (summary cfd03baa). Integration: 哪吒 replaces the placeholder at the `chef_sign` anchor (5,14), offset about +0.18 m in X within the cell.

刘备 · 2026-10-13 · target 0.2.5 · [PR #356](https://github.com/IndieMiao/sensen-godot/pull/356), base `wp-3d-scene`.

At final anchor `(5,14)`, the previous 0.60 m board entered the mine path
`(4,14)` by 0.357 m. Per 上官婉儿's v1.3 specification and 不知火舞's option ②,
both variants now have a 0.50 m board, shorter arm and uniformly scaled icons.
The model pivot remains the post foot-bottom centre; 哪吒 applies the requested
approximately +0.18 m X offset during placement.

A retains its warm wooden foot; B uses three pale grey stone blocks. Both share
the same post, arm, chains and red/gold board, with a cream chef's hat, crossed
fork and spoon, and one small gold star. Flat opaque vertex colors use unchanged
`FarmArt.material()`, with no lettering or textures.

## Current review images

- [Both variants / 43° pitch, 14.5° yaw, existing character](v1.3/chef-sign-v1.3-43deg.png)
- [True top view / 0.65 m grid / labelled (4,14) path and (5,14) anchor](v1.3/chef-sign-v1.3-top-grid.png)

These are actual 1800 × 1400 Godot 4.7.2 Vulkan Mobile captures on the Deck's
AMD Custom GPU 0405 (RADV VANGOGH), using existing farm lighting and material.
The top view uses B's larger foot, with a +0.18 m offset in the review fixture.
Labels and dimensions show the remaining 77 mm path intrusion. Final bench
occlusion/click regions require the integrated farm view. These are desktop art
checks, not Android or physical-phone performance measurements.

## Dimensions and integration

| Item | Delivered value (Godot metres) |
|---|---|
| `chef_sign_a.glb` | 1,362 triangles, 1 mesh, 1 surface |
| `chef_sign_b.glb` | 1,450 triangles, 1 mesh, 1 surface |
| Total height / arm top | 1.74 / 1.70 |
| Board outer width × height × frame depth | 0.50 × 0.45 × 0.05 |
| Board bottom / top | 1.06 / 1.51 |
| Board outer / inner X edge | -0.582 / -0.082 |
| `board_center` | (-0.332, 1.285, 0), identity basis |
| Decorated board `overhang_bounds` | (-0.582,1.06,-0.025) → (-0.082,1.51,0.035) |
| Arm X extent | -0.505 → +0.055 |
| Foot A / B XZ projection | 0.26 × 0.26 / 0.28 × 0.28 |
| Pivot / front | Post foot-bottom centre (0,0,0) / +Z |
| Footprint metadata | 0.65 m, one anchor cell |
| Post/foot collision box | Centre (0,0.87,0), size (0.28,1.74,0.28) |
| A full bounds | (-0.582,0,-0.13) → (0.13,1.74,0.13) |
| B full bounds | (-0.582,0,-0.14) → (0.14,1.74,0.14) |

The complete emblem group, including relief depth, is scaled uniformly by 5/6
about the board centre and red front plane. Frame thickness, rim width, corner
radii, board height and bottom remain unchanged. The outer hanger and its
attached eye bolts move inward by 0.10 m with the shortened arm; both short
chains retain real eye-bolt connections into the arm and board.

**Direction choice:** directly authored -X arm, +Z front and positive runtime
scale. No additional mirror or 180° Y turn is needed. Feet and post have no
directional detailing. **Placement choice:** follow the v1.3 width and +0.18 m
runtime offset. The board then reaches X = -0.402 relative to the anchor-cell
centre, or **0.077 m into path (4,14)** past the -0.325 m boundary. B's foot
reaches X = +0.320, leaving 0.005 m before the right cell edge. The remaining
path intrusion is the accepted v1.3 compromise, not a full head-clearance claim.
The board bottom is 1.06 m versus the fixture character's 1.745 m height.

哪吒 must check bench occlusion and click overlap in the actual default farm
camera. If overlap occurs, reduce the rightward offset until the bench is clear,
accepting greater path intrusion as the specification directs. The GLBs contain
no placement translation; the one-cell footprint refers to the post anchor.
Only post/foot collision is used, never the whole suspended asset AABB.

`FarmArt.instance()` / `mesh_for()` extract only the merged mesh. To retain the
`board_center` empty, instantiate the full GLB PackedScene and assign
`FarmArt.material()` to its single MeshInstance3D, or reconstruct the empty from
the manifest socket transform. Import files disable automatic LODs and unused
tangents. Named editable parts and the authoritative specification are in
[the source directory](../../../tools/art/source/chef_sign_282/).

## Validation and reproduction

- [Godot validation](v1.3/validation.json): 48 checks passed; actual imported
  dimensions, marker/pivot, budget, material, fixture path intrusion and foot
  containment, with 0.1 mm dimension tolerance.
- [Independent GLB audit](v1.3/glb-validation.json): 29 checks passed; binary
  topology, zero degenerate triangles, outward normals, no textures, positive
  scale and matching A/B non-foot geometry/colors/normals.
- [Revision audit](v1.3/revision-validation.json): compared against v1.2 commit
  `877beca6`; actual emblem vertices match uniform 5/6 scaling within 1 micrometre,
  foot geometry/pivots retained, 111 existing art/import files and the other 38
  manifest entries unchanged.
- [Rebuild record](v1.3/reproducibility.json): two consecutive exports produce
  byte-identical GLBs and manifest.

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_chef_sign.py"
python3 tools/art/verify_chef_sign.py
python3 tools/art/prepare_chef_sign_review.py
godot --headless --path output/chef-sign-282/project --editor --import
godot --path output/chef-sign-282/project
```

Use an active display for the last command. Captures and Godot checks appear in
`output/chef-sign-282/v1.3/captures`; the independent binary audit appears in
`output/chef-sign-282/glb-validation.json`. The isolated project has only the
Avatar autoload, fixture outfit and a separate user-data directory.

## Delivery history

上官婉儿 confirmed v1.2 technical and visual acceptance before requesting this
placement revision. [The v1.2 record](v1.2-README.md), four screenshots and their
Plane receipts remain archived; their older dimensions/anchor are historical.
The two current screenshots use attachment prefix `SGODOT-282_Chef-Sign_v1.3_`
and 刘备's `virtual_user_id = 0fb1de1f-ead5-443b-9537-54cbac113260`.
The [v1.3 delivery receipt](v1.3/delivery-verification.json) records verified
uploader identity and download SHA-256 matches. Final farm placement is handed
to 哪吒 for the integrated bench/click check and review image.
