"""Named smooth parts, one rigid bone per vertex, one vertex-colour glTF surface."""
from pathlib import Path
import json
import math
import sys
import bpy
import bmesh
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[4]
SOURCE=Path(__file__).resolve().parent
RUNTIME=ROOT/'output/monsters-355/runtime'
FPS=60
PARTS=[]


def v(p):return Vector((p[0],-p[2],p[1]))


def start(identity):
    bpy.ops.wm.read_factory_settings(use_empty=True);PARTS.clear()
    bpy.context.scene.render.fps=FPS
    mat=bpy.data.materials.new(identity+'_vertex_matte');mat.use_nodes=True
    principled=mat.node_tree.nodes.get('Principled BSDF');principled.inputs['Roughness'].default_value=.72
    principled.inputs['Specular IOR Level'].default_value=.25
    color=mat.node_tree.nodes.new('ShaderNodeVertexColor');color.layer_name='Color'
    mat.node_tree.links.new(color.outputs['Color'],principled.inputs['Base Color'])
    return mat


def paint(obj,name,color,bone,mask,material):
    obj.name=name;obj.data.name=name+'_mesh'
    bpy.context.view_layer.objects.active=obj
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    for face in obj.data.polygons:face.use_smooth=True
    obj.data.materials.clear();obj.data.materials.append(material)
    attr=obj.data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
    srgb=[int(color[i:i+2],16)/255 for i in [0,2,4]]
    linear=[c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in srgb]
    for value in attr.data:value.color=(*linear,1)
    obj.data.color_attributes.active_color=attr;obj.data.color_attributes.render_color_index=obj.data.color_attributes.find('Color')
    for layer in list(obj.data.uv_layers):obj.data.uv_layers.remove(layer)
    obj.data.uv_layers.new(name='UVMap');uv2=obj.data.uv_layers.new(name='TintMask')
    for value in uv2.data:value.uv=(mask,.5)
    obj.data.uv_layers.active_index=0
    group=obj.vertex_groups.new(name=bone);group.add(list(range(len(obj.data.vertices))),1,'REPLACE')
    obj['bone']=bone;obj['tint_mask']=mask;obj['source_colour_srgb']=color;PARTS.append(obj)
    return obj


def ellipsoid(name,at,size,color,bone,mask,material,segments=8,rings=6,roll=0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,radius=1,location=v(at))
    obj=bpy.context.object;obj.scale=(size[0]/2,size[2]/2,size[1]/2);obj.rotation_euler.y=math.radians(-roll)
    return paint(obj,name,color,bone,mask,material)


def pillow(name,outline,depth,color,bone,material):
    points=[Vector(p) for p in outline];center=sum(points,Vector((0,0)))/len(points);n=len(points)
    vertices=[v((p.x,p.y,depth)) for p in points]
    vertices += [v((center.x+(p.x-center.x)*.88,center.y+(p.y-center.y)*.88,depth+.012)) for p in points]
    vertices += [v((center.x+(p.x-center.x)*.88,center.y+(p.y-center.y)*.88,depth-.012)) for p in points]
    vertices += [v((center.x,center.y,depth+.016)),v((center.x,center.y,depth-.016))]
    faces=[]
    for i in range(n):
        j=(i+1)%n;faces += [(i,j,n+j,n+i),(i,2*n+i,2*n+j,j),(n+i,n+j,3*n),(2*n+j,2*n+i,3*n+1)]
    data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.update()
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(data);bm.free()
    obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True)
    return paint(obj,name,color,bone,1,material)


def skeleton(bones):
    data=bpy.data.armatures.new('Skeleton');rig=bpy.data.objects.new('Armature',data)
    bpy.context.collection.objects.link(rig);bpy.context.view_layer.objects.active=rig;rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for name,parent,at in bones:
        bone=data.edit_bones.new(name);bone.head=v(at);bone.tail=bone.head+Vector((0,.08,0))
        if parent:bone.parent=data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    for part in PARTS:
        part.parent=rig;modifier=part.modifiers.new('Rigid skeleton','ARMATURE');modifier.object=rig
    return rig


def animate(rig,specs,pose):
    rig.animation_data_create()
    for name,spec in specs.items():
        rig.animation_data.action=None
        frames=round(spec['length']*FPS)
        for frame in sorted(set(range(0,frames+1,3))|{frames}):
            t=frame/FPS;u=t/spec['length']
            for bone in rig.pose.bones:
                bone.rotation_mode='XYZ';bone.location=(0,0,0);bone.rotation_euler=(0,0,0);bone.scale=(1,1,1)
            pose(name,u,t,rig.pose.bones)
            for bone in rig.pose.bones:
                if bone.name=='root':continue
                bone.keyframe_insert('location',frame=frame,group=bone.name)
                bone.keyframe_insert('rotation_euler',frame=frame,group=bone.name)
                bone.keyframe_insert('scale',frame=frame,group=bone.name)
        action=rig.animation_data.action;action.name=name;action.use_fake_user=True
        action.use_frame_range=True;action.frame_start=0;action.frame_end=frames
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:key.interpolation='LINEAR'
    rig.animation_data.action=None
    for bone in rig.pose.bones:bone.location=(0,0,0);bone.rotation_euler=(0,0,0);bone.scale=(1,1,1)
    bpy.context.scene.frame_set(0)


def export(identity,rig,metadata):
    directory=RUNTIME/'assets/monsters'/identity;directory.mkdir(parents=True,exist_ok=True)
    source=SOURCE/identity;source.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(source/(identity+'.blend')))
    copies=[]
    for part in PARTS:
        obj=part.copy();obj.data=part.data.copy();bpy.context.collection.objects.link(obj);copies.append(obj)
    for part in PARTS:part.hide_set(True)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in copies:obj.select_set(True)
    bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();mesh=bpy.context.object
    mesh.name=identity+'_mesh';mesh.data.name=identity+'_mobile'
    mesh.data.materials.clear();mesh.data.materials.append(PARTS[0].data.materials[0])
    for face in mesh.data.polygons:face.material_index=0
    mesh.data.calc_loop_triangles();triangles=len(mesh.data.loop_triangles)
    assert triangles<=1500,(identity,triangles)
    points=[(p.co.x,p.co.z,-p.co.y) for p in mesh.data.vertices]
    bounds=[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]
    rig.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.export_scene.gltf(filepath=str(directory/(identity+'.glb')),export_format='GLB',use_selection=True,
        export_yup=True,export_materials='EXPORT',export_texcoords=True,export_normals=True,
        export_vertex_color='ACTIVE',export_skins=True,export_animations=True,export_animation_mode='ACTIONS',
        export_nla_strips=True,export_frame_range=False,export_force_sampling=True,export_frame_step=1,
        export_optimize_animation_size=False,export_cameras=False,export_lights=False)
    metadata.update(id=identity,triangles=triangles,surfaces=1,bones=len(rig.data.bones),
        bounds=bounds,height=bounds[1][1],
        tint_mask='UV2.x',cast_shadow=False,root_motion=False,front='+Z',stage='blockout',
        source_concept='Plane 355 c368e7dd',author='黄忠',virtual_user_id='5281cd25-6a49-4df8-9802-f3e534956e80')
    metadata['durations']={name:clip['length'] for name,clip in metadata['anims'].items()}
    metadata['hit_at']=metadata['anims']['attack']['hit_at']
    if 'spore' in metadata['anims']:metadata['spore_at']=metadata['anims']['spore']['emit_at']
    (directory/(identity+'.json')).write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
    print('MONSTER_EXPORT',identity,triangles,len(rig.data.bones),flush=True)
