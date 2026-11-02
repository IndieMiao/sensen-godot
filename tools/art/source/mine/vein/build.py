"""Copy and edit the accepted relief; preserve its protected inner contour."""
from pathlib import Path
import hashlib
import json
import math
import subprocess
import shutil
import bpy
from mathutils import Vector

SRC=Path(__file__).resolve().parent
ROOT=SRC.parents[4]
OUT=ROOT/'output/mine-vein-355';OUT.mkdir(parents=True,exist_ok=True)
RUNTIME=ROOT/'output/monsters-355/runtime/assets/mine/types/vein';RUNTIME.mkdir(parents=True,exist_ok=True)
pitch=math.radians(43);yaw=math.radians(14.5)
N=Vector((math.sin(yaw)*math.cos(pitch),math.sin(pitch),math.cos(yaw)*math.cos(pitch)))
R=Vector((math.cos(yaw),0,-math.sin(yaw)));U=N.cross(R)

def godot(p):return Vector((p.x,p.z,-p.y))
def blender(p):return Vector((p.x,-p.z,p.y))
def uvn(p):return [p.dot(R),p.dot(U),p.dot(N)]

bpy.ops.wm.open_mainfile(filepath=str(SRC/'base_reference.blend'))
collection=bpy.data.collections['EDITABLE_RELIEF_PARTS']
removed=[]
for obj in list(collection.objects):
    outer_rock=obj.name.startswith('02_Rock_Mass_') and int(obj.name.rsplit('_',1)[1])>=41
    if obj.name.startswith(('03_Embedded_Stone','04_Dead_Root')) or outer_rock:
        removed.append(obj.name);bpy.data.objects.remove(obj,do_unlink=True)

base=collection.objects['01_Continuous_Earth_And_Rock_Strata']
triangles=[]
base.data.calc_loop_triangles()
for triangle in base.data.loop_triangles:
    triangles.append({'uvn':[uvn(godot(base.matrix_world@base.data.vertices[i].co)) for i in triangle.vertices],
        'fade':[base.data.uv_layers['Fade_UV2'].data[i].uv.x for i in triangle.loops]})
(OUT/'original-surface.json').write_text(json.dumps({'triangles':triangles}))
subprocess.run([str(ROOT/'output/art-setup/venv/bin/python'),str(SRC/'plan_seams.py'),
    str(OUT/'original-surface.json'),str(OUT/'seam-plan.json')],check=True)

adjusted=0
for obj in collection.objects:
    for vertex in obj.data.vertices:
        p=godot(obj.matrix_world@vertex.co);depth=p.dot(N)
        if depth< -6.968 or depth> -5.602:
            p+=N*(max(-6.968,min(-5.602,depth))-depth)
            vertex.co=obj.matrix_world.inverted()@blender(p);adjusted+=1
    # Blender exports V as 1-V; the consumer's UV2.y must be zero on grayscale rock.
    for loop in obj.data.uv_layers['Fade_UV2'].data:loop.uv.y=1

material=base.data.materials[0]
for region in json.loads((OUT/'seam-plan.json').read_text()):
    positions=[];faces=[];fades=[];vertex_colours=[]
    for patch in region['triangles']:
        start=len(positions)
        for point,fade in zip(patch['uvn'],patch['fade']):
            positions.append(blender(R*point[0]+U*point[1]+N*point[2]));fades.append(fade)
            vertex_colours.append(patch.get('linear_rgb',[c*patch['shade'] for c in region['color']]))
        faces.append((start,start+1,start+2))
    mesh=bpy.data.meshes.new(region['name']);mesh.from_pydata(positions,[],faces);mesh.update()
    obj=bpy.data.objects.new(region['name'],mesh);collection.objects.link(obj)
    mesh.materials.append(material)
    colors=mesh.color_attributes.new(name='StrataGray',type='FLOAT_COLOR',domain='CORNER')
    uv=mesh.uv_layers.new(name='UVMap');mask=mesh.uv_layers.new(name='Fade_UV2')
    for loop in mesh.loops:
        p=godot(mesh.vertices[loop.vertex_index].co)
        uv.data[loop.index].uv=(p.dot(R)/24,p.dot(U)/24)
        mask.data[loop.index].uv=(fades[loop.vertex_index],0)
        colors.data[loop.index].color=(*vertex_colours[loop.vertex_index],1)
    mesh.color_attributes.active_color=colors;mesh.color_attributes.render_color_index=mesh.color_attributes.find(colors.name)
    obj['mineral_mask']=1

# Keep the editable source independent from obsolete embedded R1 generators.
for text in list(bpy.data.texts):bpy.data.texts.remove(text)
note=bpy.data.texts.new('README_VEIN.txt')
note.write('SGODOT-355 vein v1.1. Named parts copied from accepted mine_backdrop.blend.\nRebuild/export with adjacent build.py. COLOR is linear; Blender Fade_UV2.y is inverted at glTF export.\n')
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'vein.blend'))
bpy.ops.object.select_all(action='DESELECT');copies=[]
for obj in collection.objects:
    copy=obj.copy();copy.data=obj.data.copy();bpy.context.scene.collection.objects.link(copy);copy.select_set(True);copies.append(copy)
bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();export=bpy.context.object
export.name='MineVeinBackdrop';export.data.name='mine_vein_backdrop_mobile'
export.data.calc_loop_triangles();count=len(export.data.loop_triangles)
assert count<=4000,count
path=RUNTIME/'backdrop.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,
    export_materials='EXPORT',export_normals=True,export_texcoords=True,export_vertex_color='ACTIVE',
    export_all_vertex_colors=False,export_animations=False,export_skins=False)
shutil.copy2(SRC/'palette.json',RUNTIME/'palette.json')
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','stage':'v1.1',
    'source':'assets/mine/backdrop/source/mine_backdrop.blend','source_sha256':hashlib.sha256((SRC/'base_reference.blend').read_bytes()).hexdigest(),
    'removed_exterior_details':removed,'depth_only_clamped_vertices':adjusted,'triangles':count,'surfaces':1,
    'runtime_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'axes':{'N':list(N),'R':list(R),'U':list(U)},
    'changes':['Retain protected inner footprint and camera-space alignment; runtime retains the 1m forward offset.',
        'Variable-width kinked mineral vein runs diagonally behind the mine, exposed in upper and lower background.',
        'Mineral geometry is inset 0.08m; quartz is pale lavender sRGB with facet-aligned highlights and darker recesses. Rust retained.',
        'UV2.x retains edge fade; UV2.y is 1 only for un-tinted mineral color; remaining rock is grayscale.']}
(SRC/'reuse_provenance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('VEIN_EXPORT',count,'triangles',adjusted,'depth-only clamped vertices',flush=True)
