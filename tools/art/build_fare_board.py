#!/usr/bin/env python3
"""SGODOT-275 Fare Board. Reuse the unchanged Post Office atlas, no atlas bake.

Run in Blender --background --factory-startup --python (absolute script path).
Source coordinates are Godot metres (Y up, +Z front), back-centre pivot at zero.
"""
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_decor_assets as kit

ROOT=kit.ROOT
OUT=ROOT/'assets/rooms/post_office'
SOURCE=ROOT/'tools/art/source/fare_board_275'
FACE_Z=.05
LENGTHS=[.57,.49,.42,.54,.37,.46,.31]


def outline(w,h,r):
    return [(w/2-r,h/2),(-w/2+r,h/2),(-w/2,h/2-r),
            (-w/2,-h/2+r),(-w/2+r,-h/2),(w/2-r,-h/2),
            (w/2,-h/2+r),(w/2,h/2-r)]


def slab(name,shape,at,back,front,swatch):
    x,y=at;n=len(shape)
    verts=[(x+px,y+py,z) for z in [back,front] for px,py in shape]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return kit.mesh(name,verts,faces,swatch)


def stud(name,at,r,swatch,segments=10):
    x,y,z=at
    verts=[(x+r*math.cos(i*math.tau/segments),y+r*math.sin(i*math.tau/segments),zz)
           for zz in [z-.002,z+.001] for i in range(segments)]
    verts.append((x,y,z+.004))
    faces=[tuple(reversed(range(segments)))]
    for i in range(segments):
        j=(i+1)%segments
        faces += [(i,j,j+segments,i+segments),(segments+i,segments+j,2*segments)]
    return kit.mesh(name,verts,faces,swatch,True)


def build():
    kit.begin('fare_board',[0,0],800)
    outer=outline(.90,.65,.018);inner=outline(.80,.55,.010)
    rings=[(outer,0),(outer,.050),(outline(.890,.640,.016),.060),
           (inner,.060),(inner,0)]
    n=len(outer);verts=[(x,y,z) for shape,z in rings for x,y in shape]
    faces=[]
    for row in range(len(rings)):
        for i in range(n):
            j=(i+1)%n;k=(row+1)%len(rings)
            faces.append((row*n+i,row*n+j,k*n+j,k*n+i))
    kit.mesh('Frame / solid dark wood rounded rim',verts,faces,'wood')
    slab('Board / plain recessed blue green',outline(.808,.558,.010),(0,0),0,FACE_Z,'board')
    kit.box('Frame / thin upper cornice',(0,.3025,.0475),(.90,.045,.045),'wood',.007)
    for i,length in enumerate(LENGTHS):
        y=.195-i*.065
        slab('Row %d / blank ivory bar'%(i+1),outline(length,.030,.004),
             (-.265+length/2,y),.049,.054,'cream')
        stud('Row %d / colored round dot'%(i+1),(-.333,y,.054),.021,
             ['red','mustard','teal','cream'][i%4])
    for side in [-1,1]:
        stud('Fixing / %s brass round head'%('left' if side<0 else 'right'),
             (side*.413,.242,.062),.012,'mustard',8)
    kit.socket('board_center',(0,0,FACE_Z))
    # Latest spec explicitly gives local Y ~= 0.45 (0.125 above the board top).
    kit.socket('mark',(0,.45,0))


def main():
    SOURCE.mkdir(parents=True,exist_ok=True);(SOURCE/'.gdignore').touch()
    swatches=json.loads((SOURCE/'atlas-swatches.json').read_text())
    atlas=ROOT/swatches['atlas']
    assert hashlib.sha256(atlas.read_bytes()).hexdigest()==swatches['atlas_sha256']
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):bpy.data.collections.remove(c)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.unit_settings.system='METRIC'
    tex=bpy.data.images.load(str(atlas));tex.filepath='//../../../../assets/rooms/post_office/room_albedo_ao.png'
    for name,record in swatches['swatches'].items():
        mat=bpy.data.materials.new(name);mat.use_nodes=True
        sh=mat.node_tree.nodes.get('Principled BSDF');sh.inputs['Roughness'].default_value=.8
        sh.inputs['Specular IOR Level'].default_value=.25
        img=mat.node_tree.nodes.new('ShaderNodeTexImage');img.image=tex
        mat.node_tree.links.new(img.outputs['Color'],sh.inputs['Base Color'])
        kit.MATS[name]=mat
    build()
    for obj in kit.CURRENT.objects:
        if obj.type!='MESH':continue
        obj['atlas_swatch']=obj.data.materials[0].name
        u,v=swatches['swatches'][obj['atlas_swatch']]['gltf_uv']
        uv=obj.data.uv_layers.active or obj.data.uv_layers.new(name='RoomAtlas')
        uv.name='RoomAtlas'
        uv.active_render=True
        for loop in uv.data:loop.uv=(u,1-v)
    bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
    bpy.ops.object.select_all(action='DESELECT');copies=[]
    for source in kit.CURRENT.objects:
        if source.type!='MESH':continue
        data=bpy.data.meshes.new_from_object(source.evaluated_get(deps),depsgraph=deps)
        obj=bpy.data.objects.new(source.name+' export',data);bpy.context.scene.collection.objects.link(obj)
        obj.matrix_world=source.matrix_world.copy();obj.select_set(True);copies.append(obj)
    bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();obj=bpy.context.object
    obj.name='fare_board';bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    mod=obj.modifiers.new('Fixed reproducible triangulation','TRIANGULATE');mod.quad_method='FIXED';mod.ngon_method='CLIP'
    bpy.ops.object.modifier_apply(modifier=mod.name)
    data=obj.data
    # Re-assign exact sample-centre UVs after bevel/join interpolation. Each face
    # samples a constant existing atlas color, so wood grain cannot appear.
    while len(data.uv_layers)>1:data.uv_layers.remove(data.uv_layers[-1])
    uv=data.uv_layers.active
    uv.name='RoomAtlas';uv.active_render=True
    for face in data.polygons:
        key=data.materials[face.material_index].name;u,v=swatches['swatches'][key]['gltf_uv']
        for li in face.loop_indices:uv.data[li].uv=(u,1-v)
    runtime=kit.MATS['wood'].copy();runtime.name='RoomKit_SharedAtlas'
    data.materials.clear();data.materials.append(runtime)
    for face in data.polygons:face.material_index=0
    data.calc_loop_triangles();triangles=len(data.loop_triangles);assert triangles<=800,triangles
    for marker in kit.CURRENT.objects:
        if marker.type=='EMPTY':marker.select_set(True)
    # Like scene_room_pipeline: runtime assigns shared external atlas; GLB does
    # not embed a duplicate 2048 texture or depend on an absolute workstation URI.
    bpy.ops.export_scene.gltf(filepath=str(OUT/'fare_board.glb'),export_format='GLB',use_selection=True,
        export_apply=True,export_yup=True,export_texcoords=True,export_normals=True,
        export_materials='EXPORT',export_image_format='NONE',export_animations=False,
        export_cameras=False,export_lights=False,export_tangents=False)
    kit.canonical_triangle_order(OUT/'fare_board.glb')
    lo=[min(v.co[i] for v in data.vertices) for i in range(3)]
    hi=[max(v.co[i] for v in data.vertices) for i in range(3)]
    contract={'asset':'assets/rooms/post_office/fare_board.glb','triangles':triangles,'surfaces':1,
        'bounds':[[lo[0],lo[2],-hi[1]],[hi[0],hi[2],-lo[1]]],
        'pivot':'back face centre','front':'+Z','board_face_z':FACE_Z,
        'sockets':{'board_center':[0,0,FACE_Z],'mark':[0,.45,0]},
        'placement':{'position':[-3.21,1.65,-1.65],'yaw_degrees':90},
        'row_count':7,'row_pitch':.065,'row_height':.030,'row_lengths':LENGTHS,
        'material':'RoomKit_SharedAtlas','atlas':swatches['atlas'],'atlas_sha256':swatches['atlas_sha256']}
    (SOURCE/'asset-contract.json').write_text(json.dumps(contract,indent=2)+'\n')
    bpy.data.objects.remove(obj,do_unlink=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'fare_board.blend'))
    print('FARE_BOARD',triangles,contract['bounds'],flush=True)


if __name__=='__main__':main()
