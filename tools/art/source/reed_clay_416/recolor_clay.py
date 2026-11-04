"""Repaint only clay RGB words; retain the GLB structure and every other byte.

Run with Python for GLB/manifest; run with Blender for the editable source only.
Both paths are idempotent. No geometry, .import, wood, grass or reed writes.
"""
from pathlib import Path
import hashlib
import json
import struct

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/farm/art'
PATCH=json.loads((SRC/'clay_palette_v11.json').read_text())
def linear(h):
    return tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in [v/255 for v in bytes.fromhex(h)])
try:
    import bpy
except ModuleNotFoundError:
    bpy=None

if bpy:
    bpy.ops.wm.open_mainfile(filepath=str(SRC/'clay_pit.blend'))
    used={slot.material for obj in bpy.context.scene.objects if obj.type=='MESH' for slot in obj.material_slots}
    changed=[]
    for material in used:
        for role,colors in PATCH['changes'].items():
            current=material.diffuse_color[:3]
            if min(max(abs(current[i]-linear(colors[key])[i]) for i in range(3)) for key in ['before','after'])<1e-5:
                rgba=(*linear(colors['after']),1)
                material.diffuse_color=rgba
                material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=rgba
                changed.append(role)
    assert set(changed)==set(PATCH['changes']),changed
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'clay_pit.blend'))
    print('CLAY_SOURCE_RECOLORED',sorted(changed))
else:
    path=KIT/'clay_pit.glb';raw=bytearray(path.read_bytes())
    json_length=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+json_length])
    acc=doc['accessors'][doc['meshes'][0]['primitives'][0]['attributes']['COLOR_0']]
    assert acc['componentType']==5123 and acc['normalized'] and acc['type']=='VEC4'
    view=doc['bufferViews'][acc['bufferView']]
    start=20+json_length+8+view.get('byteOffset',0)+acc.get('byteOffset',0)
    stride=view.get('byteStride',8);counts={k:0 for k in PATCH['changes']}
    for index in range(acc['count']):
        offset=start+index*stride
        current=tuple(v/65535 for v in struct.unpack_from('<3H',raw,offset))
        for role,colors in PATCH['changes'].items():
            if min(max(abs(current[i]-linear(colors[key])[i]) for i in range(3)) for key in ['before','after'])<2e-5:
                struct.pack_into('<3H',raw,offset,*[round(v*65535) for v in linear(colors['after'])])
                counts[role]+=1;break
    assert all(counts.values()),counts
    path.write_bytes(raw)
    manifest_path=KIT/'manifest.json';manifest=json.loads(manifest_path.read_text())
    entry=manifest['assets']['clay_pit'];entry['revision']=PATCH['revision']
    for role,colors in PATCH['changes'].items():entry['palette_srgb'][role]=colors['after']
    entry['sha256']=hashlib.sha256(raw).hexdigest()
    entry['clay_palette_note']='Muted red-ochre; HSV saturation reduced 17.7–18.6%, value reduced 8.7–9.2% from v1. Wood and grass unchanged.'
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print('CLAY_COLOR_WORDS_UPDATED',counts)
