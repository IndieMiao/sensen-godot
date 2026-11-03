"""Patch only GLB COLOR_0 RGB bytes; optionally sync the editable Blender palette."""
from pathlib import Path
import hashlib
import json
import math
import re
import struct
import sys

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4]
KIT=ROOT/'assets/rooms/poi_culture_hall/props'
palette=json.loads((SRC/'mosaic_palette.json').read_text())
def linear(hex_value):
    rgb=[v/255 for v in bytes.fromhex(hex_value)]
    return [v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]

if '--source' in sys.argv:
    import bpy
    bpy.ops.wm.open_mainfile(filepath=str(SRC/'culture_props.blend'))
    bpy.context.preferences.filepaths.save_version=0
    materials={}
    for role,value in palette['colors'].items():
        name=role+'_matte_X';mat=bpy.data.materials.get(name) or bpy.data.materials.new(name)
        mat.use_nodes=True;mat.diffuse_color=(*linear(value),1)
        bsdf=mat.node_tree.nodes['Principled BSDF'];bsdf.inputs['Base Color'].default_value=mat.diffuse_color
        bsdf.inputs['Roughness'].default_value=.9;materials[role]=mat
    count=0
    for obj in bpy.data.collections['KIT_floor_mosaic'].objects:
        if obj.type!='MESH':continue
        match=re.match(r'Ring (\d+) stone',obj.name)
        role=palette['row_roles'][int(match[1])-1] if match else 'mosaic_grout'
        obj.data.materials.clear();obj.data.materials.append(materials[role]);count+=1
        for face in obj.data.polygons:face.material_index=0
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'culture_props.blend'))
    print('MOSAIC_SOURCE_RECOLORED',count)
else:
    sys.path.insert(0,str(ROOT/'tools/art'))
    from verify_chef_sign import load_glb,accessor
    path=KIT/'floor_mosaic.glb';doc,data=load_glb(path);raw=bytearray(path.read_bytes())
    primitive=doc['meshes'][0]['primitives'][0]
    points=accessor(doc,data,primitive['attributes']['POSITION'])
    attr=doc['accessors'][primitive['attributes']['COLOR_0']];view=doc['bufferViews'][attr['bufferView']]
    assert attr['componentType']==5123 and attr['normalized'] and attr['type']=='VEC4'
    binary_start=28+struct.unpack_from('<I',raw,12)[0]
    start=binary_start+view.get('byteOffset',0)+attr.get('byteOffset',0);stride=view.get('byteStride',8)
    for i,p in enumerate(points):
        role='mosaic_grout'
        if p[1]>.0075:
            radius=math.hypot(p[0],p[2])
            role=next(b['role'] for b in palette['bands'] if radius<=b['radius_max']+.00001)
        encoded=[round(v*65535) for v in linear(palette['colors'][role])]
        struct.pack_into('<HHH',raw,start+i*stride,*encoded)
    path.write_bytes(raw)
    manifest=json.loads((KIT/'prop_manifest.json').read_text());manifest['revision']='v1.2'
    spec=next(s for s in manifest['assets'] if s['name']=='floor_mosaic')
    spec.update(sha256=hashlib.sha256(raw).hexdigest(),color_pattern=palette,
        description='Four alternating warm cream / light terracotta rings and darker center; no collision')
    (KIT/'prop_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    provenance=SRC/'modules/floor_mosaic/reuse_provenance.json'
    info=json.loads(provenance.read_text());info['changes']=[spec['description'],'v1.2 changes only COLOR_0 RGB; all geometry, normals, indices, alpha and material bytes retained']
    provenance.write_text(json.dumps(info,ensure_ascii=False,indent=2)+'\n')
    print('MOSAIC_GLB_COLOR_ONLY',len(points),'vertices;',len(raw),'bytes')
