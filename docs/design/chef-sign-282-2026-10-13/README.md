# SGODOT-282 · Chef's Sign · v1.2

刘备 · 2026-10-13 · review candidate for 0.2.5. Technical review: 上官婉儿;
visual acceptance: 不知火舞. PR base is `wp-3d-scene`.

Two freestanding hanging signs use the farm's flat opaque vertex colors and
unmodified `FarmArt.material()`. A has a warm wooden foot; B replaces only the
foot with three pale grey stone blocks. The post, arm, chains and complete board
are shared geometry. The sign shows a cream chef's hat, crossed fork and spoon,
and one small gold star on deep warm red with a thin gold frame. No lettering,
textures, grain, noise, decals, extra material or runtime effects.

## Review images

- [A / wood · 43° pitch, 14.5° yaw, existing character](chef_sign_a-43deg.png)
- [B / stone · same camera and character](chef_sign_b-43deg.png)
- [Board front / +Z · real chain connections](chef-sign-front.png)
- [True top view / actual 0.65 m grid](chef-sign-top-grid.png)

All four are actual 1600 × 1400 Godot 4.7.2 Vulkan Mobile SubViewport captures
on the Deck's AMD Custom GPU 0405 (RADV VANGOGH), with existing farm sun/ambient
settings. Captions, grid, ground and character are isolated review fixtures.
The front detail intentionally crops the lower post. These are desktop art
checks; Android, physical-phone performance and final farm placement are not
claimed. Source concept and amendments are retained in
[the editable source directory](../../../tools/art/source/chef_sign_282/).

## Dimensions and integration

| Item | Delivered value (Godot metres) |
|---|---|
| `chef_sign_a.glb` | 1,362 triangles, 1 mesh, 1 surface |
| `chef_sign_b.glb` | 1,450 triangles, 1 mesh, 1 surface |
| Total height / arm top | 1.74 / 1.70 |
| Board outer width × height × frame depth | 0.60 × 0.45 × 0.05 |
| Board bottom / top | 1.06 / 1.51 |
| `board_center` | (-0.382, 1.285, 0), identity basis |
| Foot A / B XZ projection | 0.26 × 0.26 / 0.28 × 0.28 |
| Pivot / front | Post foot-bottom centre (0,0,0) / +Z |
| Footprint metadata | 0.65 m, one anchor cell |
| Collision box | Centre (0,0.87,0), size (0.28,1.74,0.28) |
| A full bounds | (-0.682,0,-0.13) → (0.13,1.74,0.13) |
| B full bounds | (-0.682,0,-0.14) → (0.14,1.74,0.14) |

The frame itself is 0.05 m thick; raised icon relief reaches Z = +0.038,
for a complete decorated board depth of 0.063 m. The arm extends 0.54 m beyond
the post's left face. Both short hanging chains have a solid eye bolt into the
arm and another into the frame, with an alternating-plane link between them.

`manifest.json` records bounds, triangles, surfaces, footprint, board bottom,
board size/centre, collider and suspended overhang bounds. Only the post/foot
blocks movement; never derive a collider from the whole asset AABB. The 1.06 m
board bottom follows the requested gameplay collision policy; it is not full
head clearance for an H = 1.745 m character.

**v1.2 choice: directly authored left arm.** For anchor `(6,14)`, use normal
positive scale and keep +Z facing the default camera. No additional X mirror or
180° Y turn is needed. The reflection is baked in the source coordinates with
outward winding/normals recalculated, including the eye bolts and chains. The
fork/spoon swap sides; the icon remains readable. Feet and post have no
directional texture or detailing.

**Dimension/footprint choice:** preserve the specified 0.60 m wide side-hanging
board and centred post pivot. Consequently its elevated silhouette extends
0.357 m beyond the anchor cell's left edge (X = -0.325). The one-cell footprint
describes the post anchor, not a false claim that the whole silhouette fits in
that square. The top view shows adjacent clear lawn beneath the overhang and a
separate clear path row. 哪吒 must check this overhang at `(6,14)` against the
actual bench, path, porch eave and occupied cells when replacing the placeholder.
The final upgraded farm layout is not part of this art review fixture.

`FarmArt.instance()` / `mesh_for()` extract only the merged mesh. To retain the
`board_center` empty, instantiate the full GLB PackedScene and assign
`FarmArt.material()` to its single MeshInstance3D, or reconstruct the empty from
the manifest socket transform. Import files disable automatic LODs and unused
tangents to retain the small silhouettes.

## Validation and reproduction

- [Godot validation](validation.json): 46 checks passed, including imported
  bounds, board size/bottom, foot dimensions, pivot, marker, budget, left arm,
  shared material and saved captures. Imported dimension tolerance: 0.1 mm.
- [Independent GLB audit](glb-validation.json): 29 checks passed, including
  actual binary topology, zero degenerate triangles, outward normals after
  reflection, no textures, positive scales and matching A/B non-foot geometry,
  normals and colors at 10 micrometre / 5 decimal precision.
- [Rebuild record](reproducibility.json): two consecutive exports produce
  byte-identical GLBs and manifest.
- [Preservation record](preservation.json): 109 existing farm art files and all
  38 prior manifest entries match art target commit `749f098b`.

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_chef_sign.py"
python3 tools/art/verify_chef_sign.py
python3 tools/art/prepare_chef_sign_review.py
godot --headless --path output/chef-sign-282/project --editor --import
godot --path output/chef-sign-282/project
```

Use an active display for the last command. Captures and Godot checks appear in
`output/chef-sign-282/captures`; the independent binary audit is in
`output/chef-sign-282/glb-validation.json`. The isolated project has only the
Avatar autoload, fixture outfit and a separate user-data directory. No gameplay
rules, production save, farm placement code or shared material were changed.

## Plane delivery

The four screenshots are attached to SGODOT-282 with the prefix
`SGODOT-282_Chef-Sign_v1.2_`. Every upload and completion write supplied 刘备's
`virtual_user_id = 0fb1de1f-ead5-443b-9537-54cbac113260`. All four were downloaded
back and SHA-256 matched; the visible uploader was verified as that identity.
[Delivery receipt](delivery-verification.json) records the attachment IDs and hashes.
Technical/visual approval and integration remain separate review steps.
