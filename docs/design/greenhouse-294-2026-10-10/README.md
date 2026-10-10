# SGODOT-294 · Greenhouse R2 / v1.4

刘备 · 2026-10-10. Technical review: 上官婉儿; visual review: 不知火舞.
Integration: 刘邦, `p0_farm_facilities.gd`. This PR delivers artwork and isolated
review tooling; it does not change the farm runtime or gameplay.

Three aligned GLBs form an open greenhouse over a 4.55 × 4.55 m, 4×4 plot block.
The frame now has a **4.95 m post-centre span**, moving all four posts and eaves
off the beds into the surrounding walkways. Actual outside bounds, including
0.30 m feet, are **5.25 × 5.25 m**.
Four corner posts and stone plinths support cream-painted timber, one climbing
vine and a hanging watering can. Every side is open: no wall, door, ground beam
or floor mesh. The source uses named editable parts and flat opaque vertex colours,
without wood grain, texture maps, baked reflections or duplicated glass faces.

The supplied [concept](../../../tools/art/source/greenhouse_294/reference.png)
is a shape/colour reference. Its ground beams are deliberately omitted, following
不知火舞's annotation. [The original v1.1 brief](../../../tools/art/source/greenhouse_294/spec-v1.1.md)
is superseded for heights and branch by the [approved v1.3 amendments](../../../tools/art/source/greenhouse_294/spec-amendments-v1.3.md),
and for frame width and foot positions by [v1.4](../../../tools/art/source/greenhouse_294/spec-amendments-v1.4.md):
eave underside **1.80 m**, eave top **1.92 m**, ridge top **2.75 m**. The
0.16 × 0.16 m post section is retained. Nominal eave-to-ridge rise/half-span implies
about 18.5° pitch; the four central 1.3 m entrances clear the 1.745 m avatar.
Roof, glass, vine and hanging can follow the expanded frame, regenerated from
parameters rather than scaled GLBs. The palette, heights and socket are retained.

## Review evidence

- [43° normal view, glass opacity 25%](greenhouse-43deg-normal.png)
- [43° glass opacity 10%, existing character beside it](greenhouse-43deg-glass10.png)
- [Top-down base-only placement preview](greenhouse-top-base.png)
- [Triangle and bounds table](manifest-budget.csv)
- [Godot validation](validation.json)
- [Original farm kit preservation](preservation.json)
- [Repeat export hash verification](reproducibility.json)

Images are actual Godot 4.7.2 / Vulkan Mobile SubViewport captures at 1800×1500
on the Deck's AMD Custom GPU 0405 (RADV VANGOGH). Lighting matches the existing
farm review setup. The default fixture avatar is 1.745 m tall. The soil, simple
plants and green/red placement cells are isolated review fixtures, not greenhouse
geometry or changes to game crops. Plot centres are 1.30 m apart and each bed is
0.65 m wide, matching the specified 4.55 m block envelope. Top view contains only
the base asset plus the 16 soil beds and inset green/red placement cells; no roof,
glass, avatar or crop fixture. The beams no longer cover the outer rows of cells.

61 structural/capture checks passed, including actual imported bounds, one mesh
and surface per export, opaque vertex alpha, outward glass normals, common origin,
roof socket and all four central entry clearances. New projection checks include
**every base triangle**, including eaves, braces, vine and can: zero projected
overlaps with the 16 beds and a **0.055 m** minimum gap. Each post/plinth sits
at X/Z ±2.475 m with a maximum 0.30 m square foot. The outer bounds leave
**0.30 m** before adjacent bed edges at ±2.925 m. Imported centre checks allow
0.1 mm for the retained Godot mesh compression; source GLB centres were also
checked directly. Rebuilding twice produced
byte-identical GLBs. The current target's 35 manifest entries and 103 existing farm art
files are unchanged relative to `04b50480` (which merged decoration PR #283
while this greenhouse was being prepared). This is desktop art/structure validation;
no Android or physical-phone performance result is claimed.

## Runtime parts and dimensions

| Part | Triangles | Limit | Surfaces | Purpose |
|---|---:|---:|---:|---|
| `greenhouse_base` | 1,284 | 1,500 | 1 | Posts, plinths, eave ring, corner braces, vine and watering can; placement preview |
| `greenhouse_roof` | 572 | 1,000 | 1 | Ridge, rafters, mid-slope purlins and gable king posts |
| `greenhouse_glass` | 6 | 500 | 1 | Two slope quads and two gable triangles |
| Total | 1,862 | 3,000 | 3 | |

Each file lives at `assets/farm/art/<part>.glb` and has a matching manifest entry.
`bounds` uses Godot coordinates `[min,max]`; `bounds_blender` retains the farm kit
convention. `footprint` / `footprint_m` are `[4.95,4.95]`, `covered_plots` is `[4,4]`,
and `covered_block_m` is `4.55`.
All entries record `eave_height=1.92` and `ridge_height=2.75`. The base also records
`eave_underside=1.80` and a verified central entry width of 1.3 m.

The v1.4 wording calls 4.95 m the outside dimension but also gives post centres
at ±2.475 m. This asset follows the explicit centre coordinates: adding the
0.15 m half-feet produces physical bounds **±2.625 m / 5.25 m total**. Thus
`footprint` is the nominal centre span, not the outside AABB. The manifest's
`footprint_note` documents this distinction; use `bounds` for mesh extents.
Inner edges of the feet are at ±2.325 m, 0.05 m beyond the covered block edge.

All three files use the **same ground-centred origin** and **+Z front**, with
identity root/mesh transforms and authored metre dimensions. Instantiate each at
exactly the same transform, with unit scale. Roof/glass geometry starts above
zero intentionally; do not recenter those meshes or ground them separately.
Glass edges run inside the corresponding ridge/rafter/eave members. The source
file retains the three assembled collections for checking these joins.

`p0_farm_facilities.gd` currently places its placeholder root at `BED_H=0.15`.
These models are authored from terrain ground. Integration must account for that
0.15 m offset once, on the common root, rather than adding it to every part or
rescaling the art to the old placeholder. No placement code is changed here.

## Materials, fading and preview

- Base and roof use the existing **`FarmArt.material()`**. Colour is linear
  vertex paint (alpha 1), matte roughness 0.9, specular 0.18. No new shared shader.
- Glass source is also opaque, with pale mint vertex RGB and alpha 1. Duplicate
  `FarmArt.material()` for a greenhouse glass material, enable alpha blending,
  and set its albedo alpha to **0.25 normally / 0.10 inside**. Do not change the
  singleton's alpha, which would fade other farm objects. The review enables
  `CULL_DISABLED` on this material to see the underside of the single-thickness
  panels; there are no back-face copies in the mesh. Disable glass shadow casting.
- Optional roof fading to 0.50 likewise needs a material duplicate. The requested
  two 43° captures keep the frame fully opaque and change only glass opacity.
- Placement preview loads **only `greenhouse_base`**. Hide/omit both roof and
  glass. The eave ring remains at the perimeter and does not cross the inner grid.
- Optional `roof_center` empty is on the base at **`(0,2.63,0)`**, identity basis.
  `FarmArt.instance()` extracts only the mesh, so use the full PackedScene to
  retain the empty, or create a hook from manifest `sockets.roof_center`.
- Collision, if needed by integration, belongs only at the four corner feet/posts,
  centred at X/Z **±2.475 m**. `post_centres_xz`, `post_section_m` and
  `foot_projection_m` document their positions and maximum horizontal size.
  Do not turn the overall AABB into a solid volume or resize the 4.55 m bed block.

## Reproduce

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_greenhouse.py"
python3 tools/art/prepare_greenhouse_review.py
godot --headless --path output/greenhouse-294/project --editor --import
godot --path output/greenhouse-294/project
```

Use a display for the final command; headless is only for importing/checking.
The offline fixture has its own project and user-data name and loads only the
existing Avatar service. Captures and `validation.json` are written to
`output/greenhouse-294/captures`. There are no network, save, inventory or release
operations. GLB import settings keep the authored normals, disable tangents and
automatic LODs. Source: [greenhouse_294.blend](../../../tools/art/source/greenhouse_294/greenhouse_294.blend).

Branch **`wp-3d-scene-liubei-294` → `wp-3d-scene`** was explicitly approved to keep
this independent of decoration PR #283. No dependency on that PR's art or tooling;
no merge to `farm-dev` and no integration changes are included.
