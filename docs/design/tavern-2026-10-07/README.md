# Tavern · Liu Bei R2 review candidate

[SGODOT-177](https://plane.sensenjoy.cn/zili/browse/SGODOT-177) · owner 刘备 · submitted for art-director **Review**, not Done. This R2 supersedes the earlier Zhao Yun package. Prior images named `godot.png` and `orthographic-sheet.png` are historical R1 media; use the R2 links below.

Reference: Figma `OMLTC3yw3u2WDjOZhLnhaR`, node 545:2966; [original export](reference.png), inspected at native resolution.

![Reference, actual Godot and unwarped overlay](comparison.png)

Dark wood walls now have three board widths, lower paneling and a dado rail. A wooden wagon wheel with eight spokes and individual chain links supports four lanterns. The framed iron-hung TAVERN sign uses Nunito Black with 4 mm depth. Open backbar shelves carry five bottle silhouettes with varied coloured labels and three mug variants. Round, square and low-backed stools, runners, a ceramic pitcher, copper cookware, a landscape painting, chalk beer board, a horizontal cask and bordered green rug complete the dressing. Shared plants use the accepted atlas; the front Monstera sits inside a reused terracotta sleeve.

There are 12 unshadowed local Omni lights: the four chandelier lanterns share one, the two saloon sconces share one, four other wall lamps have one each, and six table/bar/shelf candles have one each. Ambient energy is 0.27. Small ranges retain separate pools; the on/off control uses identical emission and camera settings.

Furniture sizes retain the Basic Room baseline. The counter top is 1.3167 m above its floor pivot, round tables 1.0915 m, dining seats 0.65 m. Two table groups move 0.26/0.28 m to preserve perimeter traversal, without resizing. Stools intentionally have no blocking collision; tables, bar and barrels do. The 10-waypoint route loops around three tables; the live measured bar-to-table aisle is 1.25 m. The decorative saloon arch is not an operational gameplay door.

The accepted SGODOT-172 R2.1 editable structural meshes supply posts, beams, beam pegs/corbels, feet, skirting and plinth. Only spans and positions adapt to the existing room; cross sections and bevel modifiers are retained. The [reuse ledger](../../../tools/art/source/tavern/structure-reuse.json) records source SHA-256, per-part dimensions/modifiers and retained/removed parts. Basic Room, 172 and the shared plant library remain read-only.

The orthographic camera fits three visible plinth edge intersections and an inferred fourth, following 172 R2. No geometry or comparison image is warped. [Camera evidence](camera-registration.png) / [fit data](camera-registration.json); residuals 15.10, 14.25, 15.80 px. Rounded reference edges are estimated intersections, not calibrated survey points.

| Budget | R2 |
|---|---:|
| Unique room modules / placed room modules | 44 / 114 |
| Unique room triangles | 69,324 |
| Placed triangles including all plants | 105,826 / 200,000 |
| All plants, including incidental room vegetation | 5,448 / 100,000 |
| Runtime static surfaces after grouping | 32 / 60 |
| Individual room GLB bytes | 2,823,544 |
| Room atlas | 2048 × 2048, base colour + contact AO |

Exported groups share material/atlas and preserve unmerged editable parts plus individual local-pivot GLBs. Small leaves do not cast shadows. Godot imports use mipmaps and VRAM compression. Source PNG/GLB bytes are not GPU memory; static surfaces exclude shadow passes and the avatar.

[Whole scene](godot-whole.png), [detail sheet](asset-details.jpg), [orthographic views](orthographic.png), [native-pixel sign check](signage-check.png), [colour patches](colour-patch-comparison.jpg), [local light controls](light-pool-controls.jpg), [budget/import verification](revision-verification.json), [character checks](bench-result.json), [video timeline](bench-video-timeline.jpg).

Actual checks run in Godot 4.7.2 **Mobile / Vulkan**, AMD Custom GPU 0405 / RADV VANGOGH, on this Linux host. Hero renders are 1400×1400. Rendered character/collision/input-fixture checks and a real-time 15 s viewport recording use the existing isolated shared harness; the shared core is unchanged. This is desktop evidence, not Android/physical-phone performance or production gameplay acceptance. No APK, phone install or save operation is included.

Differences retained for art-director review: The reference has denser shelf dressing and more ornate joinery. The landscape and stag emblem are simplified. Round-table shape, pantry layout and lighting falloff are interpreted; the small plant silhouettes are the accepted shared library. [Evaluated source-mesh height audit](dimensions-r2.json) independently measures every worktop and seat against the Basic Room baseline. Representative colour medians test corresponding physical surfaces; they do not establish complete-image fidelity. During inspection, samples accidentally landing on rails/props were rejected before declaring the final surface coordinates.

Editable source: [Blender](../../../tools/art/source/tavern/tavern.blend), [revision generator](../../../tools/art/source/tavern/revision2.py), [layout](../../../assets/rooms/tavern/layout.json), [Godot scene](../../../scenes/tavern/tavern_art.tscn). Coordinates are metres, Godot Y-up/front +Z; source Blender coordinates are `(x,-z,y)`.

```sh
blender -b -t 4 --python tools/art/build_tavern.py
DISPLAY=:0 python tools/art/source/coffee_shop/render_r1.py r2 tavern
DISPLAY=:0 python tools/art/source/coffee_shop/run_bench.py tavern --record
DISPLAY=:0 output/art-tools/bin/python tools/art/source/tavern/light_controls.py tavern
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py tavern r2
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py tavern r2
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py tavern r2
output/art-tools/bin/python tools/art/source/coffee_shop/package_r2_details.py tavern r2
```

Use the host's working display; `-- --geometry-only` skips bake/export. Rebuild replaces this scene's source file. Review attachments and Lark media are hash-readback verified in [delivery record](delivery-verification.json) after sending.
