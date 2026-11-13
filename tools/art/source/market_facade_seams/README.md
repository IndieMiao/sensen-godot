# Market facade recessed liners — SGODOT-218

This is a technical seam correction over approved art `c7a0a4b6a`. It does not change layout, collisions, anchors, navigation, existing roof shapes or any original mesh attribute.

`build.py` opens the original editable `market_plaza.blend`, adds two named liners to each of the twelve facade collections, and saves `market_facade_seams.blend`. Each liner is a closed six-face box (12 triangles); each facade gains 24 triangles and stays a single surface. The GLB append path copies original POSITION / NORMAL / UV / COLOR / indices exactly and packs only the referenced buffers, so it does not rebake approved face colors or duplicate the old binary payload. `manifest.json` records dimensions, colors and file hashes.

Coordinates use the room's Godot metres, front +Z. Each lining starts inside the original wall at |x|=1.94 and ends 0.0301 m outside the original facade's maximum |x| (3 cm plus a 0.1 mm corner welding allowance). Front z=1.228 on the left, 1.230 on the right: about 2 cm behind the wall at z=1.25, with 2 mm separation between adjacent lining fronts. Back z=-1.245, top=eave−0.005; all original roof geometry is retained. Color is the matching wall hue at 80% linear RGB. No collision is added.

```sh
flock ~/gs66-render.lock blender --background --factory-startup --python "$PWD/tools/art/source/market_facade_seams/build.py"
python3 tools/art/source/market_facade_seams/verify.py
flock ~/gs66-render.lock blender --background --factory-startup --python "$PWD/tools/art/source/market_facade_seams/check_joints.py"
```

`verify.py` requires NumPy. It proves all original attributes/indices/materials/nodes and imports exact, each addition ≤40 triangles, normals outward, and every non-target room/scenery file unchanged. `check_joints.py` tests the six linear joints plus the inside corner for each variant, with actual GLB triangles. It checks the common wall below the lower eave; the open skyline above a shorter roof is deliberately excluded. No runtime tests are modified.

The baseline is intentionally pinned: a later visible art redesign must update the baseline and validate the append again. Do not run the older full-room exporter afterward and assume it includes these separate technical liners. The original named room objects and the new liner objects are editable together in the supplementary blend.

`prepare_review.py` prepares an isolated latest-at-start P0 baseline `827720f0a`, with private user data and offline fixtures. It retains before models under review-only names. `review.gd` captures same-camera openings, 720×1600 joint closeups (2× the native portrait dimensions), and the 30 fps camera pan. Only the review runtime's camera driver is paused during the pan; no game script is edited. The 26 s delivered MP4 trims initialization frames [120,900) and resets timestamps; it does not change speed.

Evidence, per-asset triangle budget, approval provenance and reproduction limits: `docs/design/market-facade-seams-218-2026-11-13/README.md`.
