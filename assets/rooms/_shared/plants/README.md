# Shared stylized plants · Liu Bei · SGODOT-179 R1

Nine original modules: `monstera` (11 split leaves), `peace_lily` (4 ivory spathes), `pothos`, `ivy_short` (0.65m), `ivy_medium` (1m), `ivy_long` (1.4m), `flower_shrub`, `olive_tree`, `fruit_tree`. The three vine segments have distinct silhouettes and seeded leaf/flower placement. Leaf surfaces are curved, closed meshes; midribs and secondary veins are baked from a separate source UV map into one shared 2048 atlas. No alpha-cutout leaves or duplicate embedded images.

Units: metres; Godot Y up, front +Z. Pots/trees/shrub pivot at their base. Vines pivot at the upper stem and grow along local -Y; rotate about local Z to follow an arch, and yaw to face the wall. Use 0.7–1.0 scale for the cafe vines and stagger/overlap endpoints by 5–12cm. Source objects stay named and editable.

Bind `room_albedo_ao.png` to all GLBs with a shared StandardMaterial3D, roughness 0.86, specular 0.22, mipmapped filtering. Import the atlas with VRAM compression and mipmaps. The GLBs intentionally do not embed the atlas. `layout.json` is a catalogue (all local pivots zero), not a complete room. `asset_stats.json` gives unique costs; multiply by placements to budget a scene.

Editable source: `source/plants.blend`. Reproducible generator:

```sh
blender --background --factory-startup --python "$PWD/assets/rooms/_shared/plants/source/build_plants.py"
```

The generator reuses the existing Liu Bei source helpers in `tools/art/source/coffee_shop/kit.py`; it does not touch Basic Room. It writes this library and ignored `output/_shared/plants/`. It overwrites the generated source; preserve manual edits in the generator before rebuilding.

Consumer example: `assets/rooms/coffee_shop/layout.json` stores `shared_plants` placements with file, position, rotation_degrees, scale, and optional simple pot colliders. `scenes/coffee_shop/coffee_shop_art.gd` shows shared atlas binding and placement. Other agents can consume these GLBs directly in their own assembler. Do not add their geometry into each scene atlas: the library has module-local contact AO and can be rearranged independently. Large room contact shadows should be handled by the room bake/runtime lighting.

Ownership: Liu Bei per SGODOT-171. Other scene owners consume the library; request changes on the parent card. This is an art review candidate, not physical-phone performance acceptance.

![Actual Godot Mobile/Vulkan botanical catalogue](catalogue.jpg)

Validation: all nine modules rendered independently in Godot 4.7.2 Mobile/Vulkan on AMD Custom GPU 0405 (RADV VANGOGH), then checked in the cafe. Single mesh/surface and no embedded image checks passed. The library contains 99,620 unique triangles; per-module costs are in `asset_stats.json`. This is a reusable library cost, not a promise that every scene uses all modules.
