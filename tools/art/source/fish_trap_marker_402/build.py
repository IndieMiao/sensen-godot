"""SGODOT-402 approved A: a coral/cream buoy tied to a visible woven cage crown."""
from pathlib import Path
import hashlib
import json
import math
import bpy
import bmesh
from mathutils import Vector

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
KIT=ROOT/'assets/props/fish_trap_marker';KIT.mkdir(parents=True,exist_ok=True)
COLORS={'coral':'E07A5F','cream':'FFF2D1','pole':'6E7B74','rope':'EBDCB7',
        'wicker_recess':'805736','wicker_strip':'B98A5E','wicker_band':'C99A6B','wicker_rim':'9A6F47'}
PARTS=[];MATERIALS={}
PROFILE=[(-.05,.215),(0,.2235),(.04,.205),(.075,.145),(.095,.05),(.10,0)]
def linear(value):
    return tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in [x/255 for x in bytes.fromhex(value)])
def v(p):return Vector((p[0],-p[2],p[1]))
def material(role):
    if role not in MATERIALS:
        mat=bpy.data.materials.new(role);mat.use_nodes=True;mat.diffuse_color=(*linear(COLORS[role]),1)
        bsdf=mat.node_tree.nodes['Principled BSDF'];bsdf.inputs['Base Color'].default_value=mat.diffuse_color
        bsdf.inputs['Roughness'].default_value=.9;bsdf.inputs['Specular IOR Level'].default_value=.12
        MATERIALS[role]=mat
    return MATERIALS[role]
def mesh(name,points,faces,role,smooth=True,roles=None):
    data=bpy.data.meshes.new(name);data.from_pydata([v(p) for p in points],[],faces);data.update()
    obj=bpy.data.objects.new(name,data);bpy.context.scene.collection.objects.link(obj);obj.parent=pivot
    names=list(dict.fromkeys(roles or [role]))
    for key in names:data.materials.append(material(key))
    for i,face in enumerate(data.polygons):face.use_smooth=smooth;face.material_index=names.index(roles[i] if roles else role)
    PARTS.append(obj);return obj
def lathe(name,profile,role,n=12,center=(0,0,0),role_by_height=None):
    points=[];rings=[];faces=[];roles=[]
    for y,r in profile:
        indices=[]
        for i in range(1 if r==0 else n):
            a=i*math.tau/n;indices.append(len(points));points.append((center[0]+r*math.cos(a),center[1]+y,center[2]+r*math.sin(a)))
        rings.append(indices)
    for j in range(len(rings)-1):
        a,b=rings[j:j+2]
        for i in range(n):
            k=(i+1)%n
            if len(a)==1:face=(a[0],b[i],b[k])
            elif len(b)==1:face=(a[i],b[0],a[k])
            else:face=(a[i],b[i],b[k],a[k])
            faces.append(face);roles.append(role_by_height((profile[j][0]+profile[j+1][0])/2) if role_by_height else role)
    return mesh(name,points,faces,role,True,roles)
def dome_radius(y):
    for (y0,r0),(y1,r1) in zip(PROFILE,PROFILE[1:]):
        if y0<=y<=y1:return r0+(r1-r0)*(y-y0)/(y1-y0)
    raise ValueError(y)
def ribbon(name,ys,a0,a1,role,offset=.0015):
    pts=[];faces=[]
    for y in ys:
        r=dome_radius(y)+offset
        pts.extend([(r*math.cos(a0),y,r*math.sin(a0)),(r*math.cos(a1),y,r*math.sin(a1))])
    for j in range(len(ys)-1):faces.append((2*j,2*j+2,2*j+3,2*j+1))
    return mesh(name,pts,faces,role)
def tube(name,path,radius,role,sides=4):
    pts=[];faces=[];path=[Vector(p) for p in path]
    for i,p in enumerate(path):
        direction=(path[min(i+1,len(path)-1)]-path[max(0,i-1)]).normalized()
        side=direction.cross(Vector((0,1,0)))
        if side.length<.01:side=direction.cross(Vector((1,0,0)))
        side.normalize();up=direction.cross(side).normalized()
        for j in range(sides):pts.append(tuple(p+radius*(math.cos(j*math.tau/sides)*side+math.sin(j*math.tau/sides)*up)))
    for i in range(len(path)-1):
        for j in range(sides):faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces+=[tuple(reversed(range(sides))),tuple((len(path)-1)*sides+j for j in range(sides))]
    obj=mesh(name,pts,faces,role)
    bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free()
    return obj

bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version=0
pivot=bpy.data.objects.new('Waterline origin / unit scale',None);bpy.context.scene.collection.objects.link(pivot)
pivot['waterline_y_m']=0.;pivot['task']='SGODOT-402';pivot['author']='黄忠'
lathe('Cage recess dome and five-centimetre submerged skirt',PROFILE,'wicker_recess')
for i in range(12):
    a=i*math.tau/12
    ribbon('Woven meridian %02d'%(i+1),[0,.04,.075,.095],a-.065,a+.065,'wicker_strip')
for k,y in enumerate([.027,.066]):
    for i in range(12):
        ribbon('Woven cross band %d segment %02d'%(k+1,i+1),[y-.006,y+.006],i*math.tau/12,(i+1)*math.tau/12,'wicker_band',.0022)
rim_pts=[];rim_faces=[]
for i in range(12):
    a=i*math.tau/12
    rim_pts.extend([(.225*math.cos(a),.004,.225*math.sin(a)),(.212*math.cos(a),.004,.212*math.sin(a))])
for i in range(12):
    k=(i+1)%12;rim_faces.append((2*i,2*i+1,2*k+1,2*k))
mesh('Waterline wicker rim',rim_pts,rim_faces,'wicker_rim')
lathe('Short sage-green stem',[(.075,.018),(.155,.015)],'pole',6)
ball=[(.11*math.sin(a),.15*math.cos(a)) for a in [-math.pi/2,-math.pi/3,-math.pi/6,0,math.pi/6,math.pi/3,math.pi/2]]
ball[0]=(ball[0][0],0);ball[-1]=(ball[-1][0],0)
lathe('Large coral upper and cream lower buoy',ball,'coral',12,(0,.255,0),lambda y:'coral' if y>=0 else 'cream')
lathe('Small coral top button',[(-.019,0),(0,.018),(.019,0)],'coral',6,(0,.361,0))
coil=[]
for i in range(11):
    a=math.tau*2*i/10;coil.append((.026*math.cos(a),.086+.027*i/10,.026*math.sin(a)))
tube('Two rope turns tying stem to cage crown',coil,.009,'rope')
tube('Short rope tail resting on weave',[(.024,.106,.009),(.052,.092,.031),(.087,.078,.045)],.008,'rope')
bpy.context.view_layer.update()
source_stats={}
for obj in PARTS:
    obj.data.calc_loop_triangles();source_stats[obj.name]=len(obj.data.loop_triangles)
source_scene=bpy.context.scene
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'fish_trap_marker.blend'))

export_scene=bpy.data.scenes.new('Temporary mobile export');copies=[]
flat=bpy.data.materials.new('FishTrapMarkerMatteVertex');flat.use_nodes=True
flat.use_backface_culling=True
bsdf=flat.node_tree.nodes['Principled BSDF'];bsdf.inputs['Base Color'].default_value=(1,1,1,1)
bsdf.inputs['Roughness'].default_value=.9;bsdf.inputs['Metallic'].default_value=0;bsdf.inputs['Specular IOR Level'].default_value=.12
color_node=flat.node_tree.nodes.new('ShaderNodeVertexColor');color_node.layer_name='Color'
flat.node_tree.links.new(color_node.outputs['Color'],bsdf.inputs['Base Color'])
for source in PARTS:
    data=source.data.copy();data.transform(source.matrix_world)
    layer=data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
    for face in data.polygons:
        color=data.materials[face.material_index].diffuse_color
        for corner in face.loop_indices:layer.data[corner].color=color
    data.materials.clear();data.materials.append(flat)
    for face in data.polygons:face.material_index=0
    data.color_attributes.active_color=layer;data.color_attributes.render_color_index=0
    obj=bpy.data.objects.new('Export part',data);export_scene.collection.objects.link(obj);copies.append(obj)
bpy.context.window.scene=export_scene;bpy.ops.object.select_all(action='DESELECT')
for obj in copies:obj.select_set(True)
bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join()
body=bpy.context.object;body.name='Body';body.data.name='fish_trap_marker_mobile'
bm=bmesh.new();bm.from_mesh(body.data);bmesh.ops.triangulate(bm,faces=list(bm.faces))
bm.to_mesh(body.data);bm.free();body.data.calc_loop_triangles()
triangles=len(body.data.loop_triangles);assert triangles<=500,triangles
path=KIT/'fish_trap_marker.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,
    export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,
    export_normals=True,export_texcoords=False,export_animations=False,export_cameras=False,export_lights=False)
points=[Vector((v.co.x,v.co.z,-v.co.y)) for v in body.data.vertices]
lo=[min(v[i] for v in points) for i in range(3)];hi=[max(v[i] for v in points) for i in range(3)]
manifest={'task':'SGODOT-402','revision':'v1','author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
    'file':'fish_trap_marker.glb','mesh':'fish_trap_marker_mobile','units':'metres; Y up; +Z front',
    'origin':'water-surface centre, Y=0','scale':[1,1,1],'waterline_y':0,'bounds':[lo,hi],
    'dimensions_xyz':[hi[i]-lo[i] for i in range(3)],'triangles':triangles,'triangle_limit':500,'surfaces':1,
    'material':'opaque matte linear vertex colour; roughness .9, metallic 0; no textures',
    'cast_shadow':False,'skeleton':False,'animations':[],
    'buoy':{'diameter_m':.30,'body_height_m':.22,'center':[0,.255,0],'coral_srgb':'E07A5F',
        'existing_cast_bobber_width_m':.218383863842247,'width_ratio':.30/.218383863842247,
        'comparison_measurement':'Native Godot SphereMesh vertices at b1 FLOAT_SCALE=1.6; parameter-only diameter .224m is not the final tessellated width'},
    'basket':{'width_m':.45,'crown_y_m':.10,'underwater_depth_m':.05,'visible_crown_at_low_bob_m':.088,
        'weave':'Raised meridian strips and two cross bands over dark recess dome; no separate water mesh'},
    'runtime':{'remove_legacy_trap_float_scale':1.6,'motion':'Consumer bobs origin +/- .012m; no baked animation',
        'water_y_m':.055,'existing_prompt_height_above_origin_m':.6},
    'palette_srgb':COLORS,'source_parts_triangles':source_stats,
    'source':'tools/art/source/fish_trap_marker_402/fish_trap_marker.blend',
    'generator':'tools/art/source/fish_trap_marker_402/build.py','sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
(KIT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
bpy.context.window.scene=source_scene;bpy.data.scenes.remove(export_scene)
print('FISH_TRAP_MARKER_READY',triangles,lo,hi,flush=True)
