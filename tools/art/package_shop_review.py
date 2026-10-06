"""Create a compact review package from actual engine captures; requires Pillow.
python tools/art/package_shop_review.py <slug> <SGODOT-number> <differences>
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, shutil, sys, hashlib, struct

ROOT=Path(__file__).resolve().parents[2]
slug,card,differences=sys.argv[1:4]
out=ROOT/'output'/slug
doc=ROOT/'docs/design'/(slug+'-2026-10-07')
assets=ROOT/'assets/rooms'/slug
layout=json.loads((assets/'layout.json').read_text())
stats=json.loads((assets/'asset_stats.json').read_text())
verification=json.loads((out/'godot-verification.json').read_text())
assert verification['renderer']=='mobile'
assert verification['instances']==stats['placed_instances']
for a in layout['assets']:
    blob=(assets/a['file']).read_bytes()
    magic,version,size=struct.unpack_from('<III',blob)
    assert magic==0x46546c67 and version==2 and size==len(blob)
    n=struct.unpack_from('<I',blob,12)[0]
    gltf=json.loads(blob[20:20+n])
    assert not gltf.get('images'), 'Duplicated embedded atlas'
    assert len(gltf['meshes'])==1
    assert len(gltf['meshes'][0]['primitives'])==1
    assert all(len(c['at'])==3 and all(v>0 for v in c['size']) for c in a['colliders'])
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',24)
def panel(paths,labels,size,dest):
    w,h=size
    image=Image.new('RGB',(w*len(paths),h+64),'#f7f5ee')
    draw=ImageDraw.Draw(image)
    for i,(p,label) in enumerate(zip(paths,labels)):
        source=Image.open(p).convert('RGB');source.thumbnail((w,h))
        image.paste(source,(i*w+(w-source.width)//2,64+(h-source.height)//2))
        draw.text((i*w+24,20),label,fill='#3b493f',font=font)
    image.save(dest,optimize=True)
panel([doc/'reference.png',out/'godot-whole.png'],['Figma reference | '+layout['reference']['node_id'],'Godot Mobile / Vulkan | review draft'],(850,850),doc/'comparison.png')
panel([out/('model-'+s+'.png') for s in ('front','side','top')],['Actual model | front','Actual model | side','Actual model | top'],(640,640),doc/'orthographic.png')
for name in ('godot-whole.png','godot-detail.png','godot-verification.json'):shutil.copy2(out/name,doc/name)
reference_hash=hashlib.sha256((doc/'reference.png').read_bytes()).hexdigest()
node=layout['reference']['node_id']
text=f'''# {slug.replace('_',' ').title()} — SGODOT-{card}

Review draft produced by 刘备 on 2026-10-07. User art approval is pending; Plane remains In Progress.

## Reference and visual scope

Actual Figma export: file `OMLTC3yw3u2WDjOZhLnhaR`, node `{node}`.
[Reference](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id={node.replace(':','-')}). Local export SHA-256: `{reference_hash}`.
The full image was inspected before modeling. Geometry is original; unshown backs, depths and metre dimensions are inferred.

![Reference and runtime comparison](comparison.png)

## Deliverables and rebuild

- Editable named Blender objects/collections: `tools/art/source/{slug}/{slug}.blend`.
- Generator: `tools/art/build_{slug}.py`; shared helpers remain in the Coffee Shop source directory. Basic Room is unchanged.
- Runtime modules, atlas, layout/collisions and budget: `assets/rooms/{slug}/`.
- Reusable art scene: `scenes/{slug}/{slug}_art.tscn`. Contains artwork and simple box collisions only.
- Godot metres, Y up, front +Z; each GLB has its own floor/mount pivot. Repeated objects use the same GLB.

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_{slug}.py"
python3 tools/art/render_shop_review.py {slug}
```

For manual source edits, use `-- --bake-only` to rebake/export the saved source. A full rebuild overwrites the generated `.blend`; preserve intentional edits first.
The renderer needs the current host's legitimate DISPLAY/XAUTHORITY. Pillow is needed only for packaging comparison images.

## Asset budget

| Metric | Value |
|---|---:|
| Unique GLBs / placed instances | {stats['unique_assets']} / {stats['placed_instances']} |
| Unique / placed triangles | {stats['unique_triangles']:,} / {stats['scene_triangles']:,} |
| Static mesh surfaces | {stats['static_draw_surfaces']} |
| Shared atlas | 2048 × 2048, mipmaps + VRAM compression |
| GLB bytes, total | {stats['glb_bytes']:,} |
| Atlas PNG bytes | {stats['atlas']['bytes']:,} |

One shared matte atlas material; separate soft translucent material for glass modules where present. Color/surface detail and softened contact AO are baked; direct lighting remains dynamic. Padded palette swatches protect subpixel detail from black seams. Major rearrangements require rebaking contact AO.

## Verification and limits

Blender 5.2.2 LTS; Godot 4.7.2 Mobile/Vulkan on `{verification['device']}`. All {stats['unique_assets']} GLBs pass container/mesh/surface checks and contain no duplicated embedded images; the assembled render contains all {stats['placed_instances']} instances. Whole/detail/front/side/top images rendered at 1400 × 1400. Source import settings are retained beside the atlas.

The images are real Godot renders of the exported models. No Android, character/movement benchmark, gameplay integration, release or physical-phone performance claim is part of these art-only cards.

Differences / inferred choices: {differences}

![Actual model orthographic views](orthographic.png)

Delivery: Lark self-review messages and downloaded-attachment verification are recorded privately under `output/{slug}/delivery/`; no chat identifiers or credentials are committed.
'''
(doc/'README.md').write_text(text)
print('REVIEW_PACKAGE',slug,stats['unique_assets'],'GLBs',stats['placed_instances'],'instances')
