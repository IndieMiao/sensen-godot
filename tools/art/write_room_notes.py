"""Write per-scene factual handoff from measured artifacts and authored notes."""
from pathlib import Path
import json
import sys
ROOT=Path(__file__).resolve().parents[2]
slug,seq,title=sys.argv[1:4]
folder=ROOT/'docs/design'/(slug+'-2026-10-07')
notes=json.loads((folder/'production-notes.json').read_text())
layout=json.loads((ROOT/'assets/rooms'/slug/'layout.json').read_text())
stats=json.loads((ROOT/'assets/rooms'/slug/'asset_stats.json').read_text())
validation=json.loads((ROOT/'output'/(slug+'-2026-10-07')/'godot-validation.json').read_text())
node=layout['reference']['node_id']
text=f'''# {title} · art review candidate

Plane [SGODOT-{seq}](https://plane.sensenjoy.cn/zili/browse/SGODOT-{seq}), owner Zhao Yun / 赵云. **In Progress, awaiting user review.** Produced 2026-10-07 under the user's request to proceed sequentially overnight and send each scene through Lark CLI.

Reference: Figma file `OMLTC3yw3u2WDjOZhLnhaR`, node [{node}](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id={node.replace(':','-')}). The [original export](reference.png) was downloaded and visually inspected before modeling.

![Figma and actual Godot render](comparison.png)

{notes['description']}

## Deliverables

- [Editable Blender model](../../../tools/art/source/{slug}/{slug}.blend), with named objects and module collections.
- [Deterministic scene generator](../../../tools/art/build_{slug}.py), using the [room pipeline](../../../tools/art/scene_room_pipeline.py).
- [GLB placement and collision manifest](../../../assets/rooms/{slug}/layout.json), individual local pivots and a shared external base-color/contact-AO atlas.
- [Reusable Godot art scene](../../../scenes/{slug}/{slug}_art.tscn), without gameplay/account/network dependencies.
- [Whole-scene runtime image](godot.png), [model orthographic views](orthographic-sheet.png), [budget and verification hashes](verification-summary.json).

## Reconstruction and contract

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_{slug}.py" -- --views
python3 tools/art/prepare_room_review.py {slug}
godot --headless --editor --path output/{slug}-2026-10-07/godot-project --import --quit
godot --path output/{slug}-2026-10-07/godot-project \\
  --script res://tools/art/review_room.gd -- {slug} \\
  "$PWD/output/{slug}-2026-10-07"
```

Use the actual host display for rendering. Blender 5.2.0 LTS and Godot 4.7.2 were used here. `--geometry-only` skips bake/export. Rebuilding replaces this scene's `.blend`; preserve manual edits deliberately. Source assets from Basic Room remain read-only.

Coordinates are metres, Godot Y-up/front +Z and Blender `(x,-z,y)`. Modules export about their own floor/mounting pivot; placement is in the manifest. The baked atlas contains procedural surface detail and softened contact AO, with live runtime sunlight. Rebake after major rearrangement. Raw GLBs must bind this atlas. Triangulation occurs before UV bake/export to keep surface interpolation consistent, and empty atlas gutters are extended before mip generation.

## Validation and budget

Actual Godot **Mobile / Vulkan**, {validation['adapter']}, 1440×1080. {validation['mesh_instances']} meshes have atlas materials and finite nonempty bounds; {validation['colliders']} simple collision shapes are present. The imported triangle count matches the export manifest.

| Metric | Measured |
|---|---:|
| Unique GLBs / placed instances | {len(stats['assets'])} / {stats['placed_instances']} |
| Unique / placed triangles | {stats['unique_triangles']:,} / {stats['scene_triangles']:,} |
| Static surfaces | {stats['static_draw_surfaces']} |
| Runtime materials | {validation.get('material_count', stats['materials'])} |
| GLB bytes combined | {stats['glb_bytes']:,} |
| Atlas source PNG bytes | {stats['atlas_bytes']:,} |
| Shared atlas | 2048 × 2048 |

Texture imports enable mipmaps and VRAM compression. Fine geometry keeps uncompressed vertices and disables automatic mesh LODs. Static surface counts exclude renderer shadow passes; PNG bytes are not GPU memory. No physical-phone performance measurement is claimed.

## Inferences and differences

{notes['differences']}

{notes.get('collision','Colliders are simple authored volumes for downstream integration; this art delivery does not establish avatar-controller behavior.')}

This is an art-only candidate awaiting review. No gameplay/map integration, avatar benchmark, Android QA, production build, migration or release is included.
'''
(folder/'README.md').write_text(text)
print(folder/'README.md')
