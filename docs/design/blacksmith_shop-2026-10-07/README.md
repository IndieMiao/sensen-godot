# Blacksmith Shop · Liu Bei R2.1 review candidate

[SGODOT-178](https://plane.sensenjoy.cn/zili/browse/SGODOT-178) · owner 刘备 · submitted for art-director **Review**, not Done. This R2.1 follows the R2 art-director review. Prior images named `godot.png` and `orthographic-sheet.png` are historical R1 media; use the R2.1 links below.

Reference: Figma `OMLTC3yw3u2WDjOZhLnhaR`, node 545:2965; [original export](reference.png), inspected at native resolution.

![Reference, actual Godot and unwarped overlay](comparison.png)

Dark gray lime walls and reddish brown wood replace the pale warm kit colours. The old square yellow post caps are removed. The furnace has staggered red brick courses, a stone hearth, strapped/riveted iron extraction hood, curved emissive flame tongues and readable bark/endgrain logs. R2.1 replaces the bead-like smoke with four fused, irregular cloud volumes: small/darker at the base, progressively larger and paler above, drifting right. Voxel fusion and decimation preserve rounded lobes in 10,296 smoke triangles. These are static art meshes. [R2 / R2.1 changes](r21-changes.jpg).

The wall albedo changes from warm 766D65 to cool 4E565F. Seven closed, curved, thick flame tongues use a read-only copy of the accepted 172 fire gradient in explicit per-tongue height UVs, with restrained emission. The separate coal bed has dark red clinker and brighter glowing fissures. [Gradient reuse record](../../../tools/art/source/blacksmith_shop/fire-gradient-reuse.json).

Three hammer and three tong source variants supply five wall hammers and six wall tongs. The workshop also has three swords, horseshoes, metal mugs, cloth, two crate sizes, a towel over the water barrel, a long coal shovel, corner-braced workbench, corrected tapered anvil horn, hot steel, bench tongs, vise, leather/green aprons and a checked gray-green mat. The FORGE WORKSHOP sign uses Nunito Black with 4 mm depth. Shared pothos plants retain the accepted library atlas.

Three unshadowed local lights cover the furnace, lantern and hot steel. Neutral sun and low ambient preserve gray walls; the forge contributes most of the warm light. On/off screenshots isolate the forge light alone at the anvil, main bench and floor; the lantern and hot-steel lights stay off in both controls. The furnace-to-mainbench aisle is 2.185 m, above 0.8 m. The route stops 0.81 m in front of the furnace mouth, above 0.5 m. Furnace, both benches, water barrel and stump block the avatar. The low stool intentionally has no blocking collision. Main worktop is 1.045 m above its floor pivot, rear worktop 0.9802 m (13.64% below Basic Room), and stool seat 0.6608 m. No human doorway is present in this open-front scene.

The accepted SGODOT-172 R2.1 editable structural meshes supply posts, beams, beam pegs/corbels, feet, skirting and plinth. Only spans and positions adapt to the existing room; cross sections and bevel modifiers are retained. The [reuse ledger](../../../tools/art/source/blacksmith_shop/structure-reuse.json) records source SHA-256, per-part dimensions/modifiers and retained/removed parts. Basic Room, 172 and the shared plant library remain read-only.

The orthographic camera fits three visible plinth edge intersections and an inferred fourth, following 172 R2. No geometry or comparison image is warped. [Camera evidence](camera-registration.png) / [fit data](camera-registration.json); residuals 12.42, 11.85, 13.37 px. Rounded reference edges are estimated intersections, not calibrated survey points.

| Budget | R2.1 |
|---|---:|
| Unique room modules / placed room modules | 46 / 52 |
| Unique room triangles | 93,290 |
| Placed triangles including all plants | 99,674 / 200,000 |
| All plants, including incidental room vegetation | 4,096 / 100,000 |
| Runtime static surfaces after grouping | 19 / 60 |
| Individual room GLB bytes | 3,506,436 |
| Room atlas | 2048 × 2048, base colour + contact AO; flame gradient 32 × 128 |

Exported groups share material/atlas and preserve unmerged editable parts plus individual local-pivot GLBs. Small leaves do not cast shadows. Godot imports use mipmaps and VRAM compression. Source PNG/GLB bytes are not GPU memory; static surfaces exclude shadow passes and the avatar.

[Whole scene](godot-whole.png), [detail sheet](asset-details.jpg), [orthographic views](orthographic.png), [native-pixel sign check](signage-check.png), [colour patches](colour-patch-comparison.jpg), [local light controls](light-pool-controls.jpg), [budget/import verification](revision-verification.json), [character checks](bench-result.json), [video timeline](bench-video-timeline.jpg).

Actual checks run in Godot 4.7.2 **Mobile / Vulkan**, AMD Custom GPU 0405 / RADV VANGOGH, on this Linux host. Hero renders are 1400×1400. Rendered character/collision/input-fixture checks and a real-time 15 s viewport recording use the existing isolated shared harness; the shared core is unchanged. This is desktop evidence, not Android/physical-phone performance or production gameplay acceptance. No APK, phone install or save operation is included.

Differences retained for art-director review: The reference has taller walls relative to its floor, a different furnace/bench spacing and more elaborate metal surface highlights. The original room envelope and Basic Room furniture sizes remain; rigid floor-corner registration exposes the remaining height/composition difference instead of stretching the model. Smoke is static and simplified; no animated fire/smoke acceptance is claimed. [Evaluated source-mesh height audit](dimensions-r2.json) independently measures every worktop and seat against the Basic Room baseline. Representative colour medians test corresponding physical surfaces; they do not establish complete-image fidelity. The R2 gray-wall colour test compared the reference wall below the warm lantern to a runtime point outside that pool. R2.1 retains the reference point and corrects the runtime point to the wall below the lantern; the former cold-wall measurement is retained in [sampling correction](wall-sampling-correction.json), including its failed 163.75-degree hue difference. Unlit walls remain cool gray rather than being warmed to satisfy that mismatched sample.

Editable source: [Blender](../../../tools/art/source/blacksmith_shop/blacksmith_shop.blend), [revision generator](../../../tools/art/source/blacksmith_shop/revision2.py), [layout](../../../assets/rooms/blacksmith_shop/layout.json), [Godot scene](../../../scenes/blacksmith_shop/blacksmith_shop_art.tscn). Coordinates are metres, Godot Y-up/front +Z; source Blender coordinates are `(x,-z,y)`.

```sh
blender -b -t 4 --python tools/art/build_blacksmith_shop.py
DISPLAY=:0 python tools/art/source/coffee_shop/render_r1.py r21 blacksmith_shop
DISPLAY=:0 python tools/art/source/coffee_shop/run_bench.py blacksmith_shop --record
DISPLAY=:0 output/art-tools/bin/python tools/art/source/tavern/light_controls.py blacksmith_shop r21
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py blacksmith_shop r21
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py blacksmith_shop r21
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py blacksmith_shop r21
output/art-tools/bin/python tools/art/source/coffee_shop/package_r2_details.py blacksmith_shop r21
output/art-tools/bin/python tools/art/source/blacksmith_shop/package_r21.py
```

Use the host's working display; `-- --geometry-only` skips bake/export. Rebuild replaces this scene's source file. Review attachments and Lark media are hash-readback verified in [delivery record](delivery-verification.json) after sending.
