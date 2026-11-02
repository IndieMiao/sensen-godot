"""Small editable vertex-painted static kits for SGODOT-355."""
from pathlib import Path
import hashlib
import json
import math
import bpy
import bmesh
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[4]
RUNTIME=ROOT/'output/monsters-355/runtime'
SOURCE=Path(__file__).resolve().parent
OUT=ROOT/'output/mine-kit-355'
PARTS=[]
MATERIAL=None


def vector(p):return Vector((p[0],-p[2],p[1]))
def world(p):return (p.x,p.z,-p.y)
def linear(color):
    rgb=[int(color[i:i+2],16)/255 for i in [0,2,4]] if isinstance(color,str) else color
    return tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in rgb)


def start(name,roughness=.72):
    global MATERIAL
    bpy.ops.wm.read_factory_settings(use_empty=True);PARTS.clear()
    MATERIAL=bpy.data.materials.new(name+'_vertex_matte');MATERIAL.use_nodes=True
    bsdf=MATERIAL.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Roughness'].default_value=roughness
    bsdf.inputs['Specular IOR Level'].default_value=.25
    color=MATERIAL.node_tree.nodes.new('ShaderNodeVertexColor');color.layer_name='Color'
    MATERIAL.node_tree.links.new(color.outputs['Color'],bsdf.inputs['Base Color'])


def paint(obj,name,color,smooth=True,vertex_colors=None):
    obj.name=name;obj.data.name=name+'_mesh';bpy.context.view_layer.objects.active=obj
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    obj.data.materials.clear();obj.data.materials.append(MATERIAL)
    for face in obj.data.polygons:face.use_smooth=smooth;face.material_index=0
    colors=obj.data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
    for loop in obj.data.loops:
        colors.data[loop.index].color=(*linear(vertex_colors[loop.vertex_index] if vertex_colors else color),1)
    obj.data.color_attributes.active_color=colors;obj.data.color_attributes.render_color_index=obj.data.color_attributes.find('Color')
    for uv in list(obj.data.uv_layers):obj.data.uv_layers.remove(uv)
    obj['source_colour']=color;PARTS.append(obj)
    return obj


def mesh(name,points,faces,color,smooth=True,vertex_colors=None):
    data=bpy.data.meshes.new(name);data.from_pydata([vector(p) for p in points],[],faces);data.update()
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(data);bm.free()
    obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True)
    return paint(obj,name,color,smooth,vertex_colors)


def ellipsoid(name,at,size,color,segments=8,rings=4):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,radius=1,location=vector(at))
    obj=bpy.context.object;obj.scale=(size[0]/2,size[2]/2,size[1]/2)
    return paint(obj,name,color)


def box(name,at,size,color,bevel=0,segments=1):
    bpy.ops.mesh.primitive_cube_add(size=1,location=vector(at))
    obj=bpy.context.object;obj.scale=(size[0],size[2],size[1])
    paint(obj,name,color)
    if bevel:
        mod=obj.modifiers.new('Rounded edges','BEVEL');mod.width=bevel;mod.segments=segments;mod.harden_normals=True
        normal=obj.modifiers.new('Weighted normals','WEIGHTED_NORMAL');normal.keep_sharp=True
    return obj


def tube(name,points,radius,color,sides=8):
    points=[Vector(p) for p in points];vertices=[];faces=[]
    for i,point in enumerate(points):
        tangent=(points[min(i+1,len(points)-1)]-points[max(i-1,0)]).normalized()
        u=tangent.cross(Vector((0,1,0)))
        if u.length<.01:u=tangent.cross(Vector((1,0,0)))
        u.normalize();v=tangent.cross(u).normalized()
        for j in range(sides):vertices.append(point+radius*(u*math.cos(j*math.tau/sides)+v*math.sin(j*math.tau/sides)))
    for i in range(len(points)-1):
        for j in range(sides):faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces += [tuple(reversed(range(sides))),tuple((len(points)-1)*sides+j for j in range(sides))]
    return mesh(name,vertices,faces,color)


def export(name,directory,source_dir,limit,metadata,anchors=None):
    directory=RUNTIME/directory;source_dir=ROOT/source_dir
    directory.mkdir(parents=True,exist_ok=True);source_dir.mkdir(parents=True,exist_ok=True)
    (source_dir/'.gdignore').touch()
    markers=[]
    for spec in anchors or []:
        marker=bpy.data.objects.new(spec['name'],None);bpy.context.collection.objects.link(marker)
        marker.location=vector(spec['position'])
        marker.empty_display_type='ARROWS';markers.append(marker)
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=str(source_dir/(name+'.blend')))
    copies=[];graph=bpy.context.evaluated_depsgraph_get()
    for part in PARTS:
        data=bpy.data.meshes.new_from_object(part.evaluated_get(graph),preserve_all_data_layers=True,depsgraph=graph)
        data.transform(part.matrix_world)
        obj=bpy.data.objects.new(part.name+'_export',data);bpy.context.collection.objects.link(obj);copies.append(obj)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in copies:obj.select_set(True)
    bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();obj=bpy.context.object
    obj.name='Body';obj.data.name=name+'_mobile'
    obj.data.materials.clear();obj.data.materials.append(MATERIAL)
    for face in obj.data.polygons:face.material_index=0
    obj.data.calc_loop_triangles();triangles=len(obj.data.loop_triangles)
    assert triangles<=limit,(name,triangles,limit)
    positions=[world(v.co) for v in obj.data.vertices]
    bounds=[[min(p[i] for p in positions) for i in range(3)],[max(p[i] for p in positions) for i in range(3)]]
    for marker in markers:marker.select_set(True)
    path=directory/(name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
        export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_texcoords=False,
        export_normals=True,export_animations=False,export_skins=False,export_cameras=False,export_lights=False)
    row={'name':name,'file':str(path.relative_to(RUNTIME)),'triangles':triangles,'surfaces':1,'bounds':bounds,
        'dimensions_m':[bounds[1][i]-bounds[0][i] for i in range(3)],'triangle_limit':limit,
        'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'anchors':anchors or [],**metadata}
    provenance={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
        'task':'SGODOT-355','kind':'original procedural geometry','asset':name,
        'source_blend':str((source_dir/(name+'.blend')).relative_to(ROOT)),
        'runtime_sha256':row['sha256'],'changes':metadata.get('notes',[]),'reference':metadata.get('reference','Director dispatch 2026-11-02')}
    (source_dir/(name+'_reuse_provenance.json')).write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n')
    print('STATIC_EXPORT',name,triangles,bounds,flush=True)
    return row


def save(path,value):
    path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
