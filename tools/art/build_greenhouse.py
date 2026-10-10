"""SGODOT-294: deterministic greenhouse exports, Blender 5.2.

Run: blender --background --factory-startup --python /path/to/build_greenhouse.py
Geometry/export conventions reuse the SGODOT-290 farm kit pipeline; standalone
so this asset does not depend on the still-reviewed decoration PR.
"""
import json
import math
import struct
from pathlib import Path
import bmesh
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/farm/art'
SOURCE=ROOT/'tools/art/source/greenhouse_294'
FOOTPRINT=5.20  # v1.5: post-centre span around the unscaled 0.94 m plot.glb.
COVERED_BLOCK=4.84
EAVE=1.92  # User-approved clearance correction: underside 1.80 m.
RIDGE=2.75  # v1.3: keep a readable gable after raising the eave.
POST=FOOTPRINT/2
FOOT=.26
FRAME_SPAN=FOOTPRINT+.16  # Beam ends flush with the outside of the posts.
ROOF_HALF=POST+.07
PALETTE={
    'cream':'f5efda','cream_shade':'dbd5bf','cream_dark':'c4c0ad',
    'stone':'b4b4a5','stone_light':'d7d4c3',
    'leaf':'6d9a44','leaf_light':'97b75b','leaf_dark':'4e824d',
    'metal':'969b92','metal_light':'c8cac1','metal_dark':'646e68',
    'wood':'a87948','flower':'fff5df','yellow':'e2be59','mint':'abd6bf',
}
MATS,ASSETS,META={},{},{}
CURRENT=None

def begin(name,budget,**metadata):
    global CURRENT
    CURRENT=bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(CURRENT)
    ASSETS[name]=CURRENT
    META[name]={'generator':'tools/art/build_greenhouse.py','triangle_limit':budget,
                'footprint':[FOOTPRINT,FOOTPRINT],'footprint_m':[FOOTPRINT,FOOTPRINT],
                'covered_plots':[4,4],'covered_block_m':COVERED_BLOCK,
                'footprint_note':'Nominal post-centre span; use bounds for physical extents (5.46 m including feet).',
                'eave_height':EAVE,'ridge_height':RIDGE,
                'pivot':'ground / footprint centre; common to all three parts',
                'front':'+Z','sockets':{},**metadata}

def rgb(h):
    values = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c < .04045 else ((c + .055) / 1.055) ** 2.4 for c in values)


def v(p):
    return Vector((p[0], -p[2], p[1]))


def finish(obj, name, color, smooth=False):
    obj.name = name
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    CURRENT.objects.link(obj)
    obj.data.materials.append(MATS[color])
    for face in obj.data.polygons:
        face.use_smooth = smooth
    return obj


def bevel(obj, width):
    if width:
        mod = obj.modifiers.new("Rounded silhouette", "BEVEL")
        mod.width = width
        mod.segments = 1
        mod = obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
        mod.keep_sharp = True
    return obj


def box(name, at, size, color, radius=.012):
    bpy.ops.mesh.primitive_cube_add(size=1, location=v(at))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish(obj, name, color)
    return bevel(obj, min(radius, min(size) * .35))


def mesh(name, verts, faces, color, smooth=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata([v(p) for p in verts], [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    CURRENT.objects.link(obj)
    data.materials.append(MATS[color])
    for face in data.polygons:
        face.use_smooth = smooth
    return obj


def cylinder(name, at, radius, height, color, top=None, segments=12):
    bpy.ops.mesh.primitive_cone_add(vertices=segments, radius1=radius,
        radius2=radius if top is None else top, depth=height, location=v(at))
    return finish(bpy.context.object, name, color, True)


def beam(name, a, b, width, color, depth=None, radius=.008):
    a, b = v(a), v(b)
    obj = box(name, (0, 0, 0), (width, (b-a).length, depth or width), color, radius)
    obj.location = (a+b)/2
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (b-a).to_track_quat("Z", "Y")
    return obj


def rod(name, a, b, radius, color, segments=6, top=None):
    a, b = v(a), v(b)
    obj = cylinder(name, (0, 0, 0), radius, (b-a).length, color, top, segments)
    obj.location = (a+b)/2
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (b-a).to_track_quat("Z", "Y")
    return obj


def lathe(name, profile, color, segments=20, at=(0, 0, 0), depth_ratio=1):
    verts = [(at[0]+r*math.cos(i*math.tau/segments), at[1]+y,
              at[2]+depth_ratio*r*math.sin(i*math.tau/segments)) for r, y in profile for i in range(segments)]
    faces = []
    for j in range(len(profile)-1):
        for i in range(segments):
            a, b = j*segments+i, j*segments+(i+1)%segments
            faces.append((a, b, b+segments, a+segments))
    faces += [tuple(reversed(range(segments))), tuple(range((len(profile)-1)*segments, len(profile)*segments))]
    return mesh(name, verts, faces, color, True)


def leaf(name, at, length, width, color, angle=0, tilt=0):
    # Closed six-sided oval with a raised midrib: 12 triangles, no alpha.
    verts = [(0, 0, -length/2), (-width*.45, .006, -length*.23),
             (-width*.5, .006, length*.16), (0, 0, length/2),
             (width*.5, .006, length*.16), (width*.45, .006, -length*.23),
             (0, .023, 0), (0, -.006, 0)]
    faces = [(6,i,(i+1)%6) for i in range(6)]+[(7,(i+1)%6,i) for i in range(6)]
    obj = mesh(name, verts, faces, color, True)
    obj.location = v(at)
    obj.rotation_euler = (tilt, 0, angle)
    return obj


def socket(name, at):
    obj = bpy.data.objects.new(name, None)
    CURRENT.objects.link(obj)
    obj.empty_display_type = "ARROWS"
    obj.empty_display_size = .10
    obj.location = v(at)
    # Export glTF empties with identity game-space rotation (+Z front).
    obj.rotation_euler = (0, 0, 0)
    META[CURRENT.name]["sockets"][name] = {"position": list(at), "front": "+Z"}


def canonical_triangle_order(path):
    """Blender's triangulator may enumerate identical triangles in a new order.

    Keep the vertices, normals and winding exact; sort the opaque index triples
    so a repeated rebuild produces the same runtime bytes.
    """
    data=bytearray(path.read_bytes())
    json_size=struct.unpack_from("<I",data,12)[0]
    doc=json.loads(data[20:20+json_size])
    primitive=doc["meshes"][0]["primitives"][0]
    accessor=doc["accessors"][primitive["indices"]]
    view=doc["bufferViews"][accessor["bufferView"]]
    offset=28+json_size+view.get("byteOffset",0)+accessor.get("byteOffset",0)
    fmt={5121:"B",5123:"H",5125:"I"}[accessor["componentType"]]
    indices=struct.unpack_from("<"+fmt*accessor["count"],data,offset)
    triangles=sorted(tuple(indices[i:i+3]) for i in range(0,len(indices),3))
    struct.pack_into("<"+fmt*accessor["count"],data,offset,*(v for tri in triangles for v in tri))
    path.write_bytes(data)


def export_asset(name, collection, material):
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    deps=bpy.context.evaluated_depsgraph_get()
    copies=[]
    empties=[]
    for source in collection.objects:
        if source.type=="EMPTY":
            empties.append(source)
            continue
        data=bpy.data.meshes.new_from_object(source.evaluated_get(deps),depsgraph=deps)
        obj=bpy.data.objects.new(source.name+" export",data)
        bpy.context.scene.collection.objects.link(obj)
        obj.matrix_world=source.matrix_world.copy()
        obj.select_set(True)
        copies.append(obj)
    bpy.context.view_layer.objects.active=copies[0]
    if len(copies)>1:
        bpy.ops.object.join()
    obj=bpy.context.object
    obj.name=name
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bpy.context.scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    triangulate=obj.modifiers.new("Fixed reproducible diagonals", "TRIANGULATE")
    triangulate.quad_method="FIXED"
    triangulate.ngon_method="CLIP"
    bpy.ops.object.modifier_apply(modifier=triangulate.name)
    data=obj.data
    colors=data.color_attributes.new(name="Color",type="FLOAT_COLOR",domain="CORNER")
    data.color_attributes.active_color=colors
    data.color_attributes.render_color_index=0
    # Flat palette only: no noise, wood grain, freckles, baked texture or continuous AO.
    for face in data.polygons:
        color=data.materials[face.material_index].diffuse_color
        for loop in face.loop_indices:
            colors.data[loop].color=color
    data.materials.clear()
    data.materials.append(material)
    # No textures: omit unused primitive UVs (Blender bevel UV interpolation has
    # sub-ULP variation between runs) and unnecessary tangent payloads.
    for uv in list(data.uv_layers):
        data.uv_layers.remove(uv)
    for face in data.polygons:
        face.material_index=0
    data.calc_loop_triangles()
    tris=len(data.loop_triangles)
    assert tris<=META[name]["triangle_limit"],(name,tris)
    bounds_blender=[[round(min(p.co[i] for p in data.vertices),6) for i in range(3)],
                    [round(max(p.co[i] for p in data.vertices),6) for i in range(3)]]
    lo,hi=bounds_blender
    bounds=[[lo[0],lo[2],-hi[1]],[hi[0],hi[2],-lo[1]]]
    if name=="greenhouse_base":
        assert abs(bounds[0][1])<.00001,(name,bounds)
    for empty in empties:
        empty.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+".glb")),export_format="GLB",use_selection=True,
        export_yup=True,export_materials="EXPORT",export_attributes=False,export_cameras=False,
        export_lights=False,export_animations=False,export_extras=False,
        export_texcoords=False,export_tangents=False)
    canonical_triangle_order(OUT/(name+".glb"))
    entry={"triangles":tris,"surfaces":1,"bytes":(OUT/(name+".glb")).stat().st_size,
           "bounds_blender":bounds_blender,"bounds":bounds,**META[name]}
    bpy.data.objects.remove(obj,do_unlink=True)
    bpy.data.meshes.remove(data)
    return entry

def curved_tube(name, points, radius, color, sides=6):
    points=[Vector(p) for p in points]
    verts=[]
    for i,p in enumerate(points):
        tangent=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
        u=tangent.cross(Vector((0,0,1))).normalized()
        w=tangent.cross(u).normalized()
        for j in range(sides):
            a=j*math.tau/sides
            verts.append(tuple(p+radius*(math.cos(a)*u+math.sin(a)*w)))
    faces=[]
    for i in range(len(points)-1):
        for j in range(sides):
            a=i*sides+j;b=i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces += [tuple(reversed(range(sides))),tuple(range((len(points)-1)*sides,len(points)*sides))]
    return mesh(name,verts,faces,color,True)


def greenhouse_base():
    begin('greenhouse_base',1500,preview_part=True,post_count=4,ground_beams=False,
          eave_underside=round(EAVE-.12,6),verified_mid_entry_width_m=1.3,
          post_centres_xz=[[sx*POST,sz*POST] for sx in [-1,1] for sz in [-1,1]],
          post_section_m=.16,foot_projection_m=[FOOT,FOOT],
          collision_note='Four corner feet/posts only; no whole-building AABB collider.')
    for sx in [-1,1]:
        for sz in [-1,1]:
            x,z=sx*POST,sz*POST
            foot=box('Corner stone plinth',(x,.11,z),(FOOT,.22,FOOT),'stone',.024)
            foot.data.materials.append(MATS['stone_light'])
            for face in foot.data.polygons:
                if face.normal.z>.5:face.material_index=1
            box('Cream corner post',(x,(EAVE-.11+.20)/2,z),(.16,EAVE-.11-.20,.16),'cream',.014)
            # Short upper diagonal stays at the corner, clear of the middle of each side.
            beam('Corner knee brace',(x,EAVE-.39,z),(x-sx*.35,EAVE-.085,z),.08,'cream_shade',radius=.010)
    for z in [-POST,POST]:
        box('Eave cross beam',(0,EAVE-.06,z),(FRAME_SPAN,.12,.15),'cream',.014)
    for x in [-POST,POST]:
        box('Eave longitudinal beam',(x,EAVE-.06,0),(.15,.12,FRAME_SPAN),'cream',.014)
    # One sparse climbing vine follows the left front post; not across the walkway.
    pts=[(-POST+.025*math.sin(i*1.35),.28+i*(EAVE-.53)/6,POST+.091) for i in range(7)]
    for i in range(len(pts)-1):rod('Vine woody stem',pts[i],pts[i+1],.009,'leaf_dark',5)
    for i,p in enumerate(pts):
        for s in [-1,1]:
            leaf('Rounded vine leaf',(p[0]+s*.055,p[1]+(.04 if s>0 else 0),p[2]),.17,.095,
                 ['leaf','leaf_dark','leaf_light'][(i+(s==1))%3],s*.62,math.pi/2)
    # Follow the expanded corner; keep the entire can outside the covered beds.
    at=(POST-.33,EAVE-.64,POST)
    # 0.2465 m depth fits the real 0.36 m walkway with >0.05 m on both sides.
    lathe('Hollow watering can body',[(.10,0),(.14,.025),(.145,.205),(.129,.24),
           (.109,.24),(.109,.208),(.108,.06),(0,.06)],'metal',8,at,depth_ratio=.85)
    rod('Watering can rising spout',(at[0]-.10,at[1]+.08,at[2]),(at[0]-.28,at[1]+.20,at[2]),.040,'metal',8,top=.031)
    rod('Watering can rose nozzle',(at[0]-.28,at[1]+.20,at[2]),(at[0]-.325,at[1]+.235,at[2]),.033,'metal_light',8,top=.064)
    pts=[(at[0]+.12*math.cos(math.pi*i/6),at[1]+.20+.17*math.sin(math.pi*i/6),at[2]) for i in range(7)]
    curved_tube('Watering can arch handle',pts,.017,'metal_dark')
    rod('Wooden hanging peg',(POST-.025,EAVE-.19,POST),(at[0],EAVE-.19,POST+.09),.030,'wood',6)
    curved_tube('Hanging metal hook',[(at[0]+.01,EAVE-.19,POST+.09),(at[0]+.01,EAVE-.24,POST+.08),
                 (at[0]+.01,EAVE-.28,POST+.02),(at[0]+.01,EAVE-.26,POST-.01)],.011,'metal_dark',5)
    socket('roof_center',(0,RIDGE-.12,0))


def greenhouse_roof():
    begin('greenhouse_roof',1000,preview_part=False,optional_inside_opacity=.5)
    peak=RIDGE-.06
    edge=EAVE-.022
    box('Ridge beam',(0,peak,0),(.12,.12,FRAME_SPAN),'cream',.014)
    for z in [-POST,-POST/3,POST/3,POST]:
        for s in [-1,1]:
            beam('Roof rafter',(s*ROOF_HALF,edge,z),(0,peak,z),.085,'cream',depth=.09,radius=.011)
    for s in [-1,1]:
        box('Mid slope purlin',(s*ROOF_HALF/2,(edge+peak)/2,0),(.070,.065,FOOTPRINT+.06),'cream_shade',.010)
    for z in [-POST,POST]:
        beam('Gable king post',(0,edge,z),(0,peak,z),.075,'cream',depth=.08,radius=.010)


def greenhouse_glass():
    begin('greenhouse_glass',500,preview_part=False,panel_count=4,
          vertex_alpha=1.0,runtime_opacity_normal=.25,runtime_opacity_inside=.10,
          material_note='Duplicate FarmArt.material() for alpha at runtime; single-sided outward geometry. No baked transparency or reflection.')
    edge=EAVE-.022;peak=RIDGE-.06;x=ROOF_HALF;z=POST
    verts=[(-x,edge,-z),(x,edge,-z),(-x,edge,z),(x,edge,z),(0,peak,-z),(0,peak,z)]
    # Four outward-facing panels only: 2 slope quads, 2 gable triangles, no bottom.
    mesh('Four single thickness mint glass panels',verts,[(0,2,5,4),(4,5,3,1),(0,4,1),(2,3,5)],'mint')


def main():
    OUT.mkdir(parents=True,exist_ok=True);SOURCE.mkdir(parents=True,exist_ok=True)
    (SOURCE/'.gdignore').touch()
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):bpy.data.collections.remove(c)
    bpy.context.preferences.filepaths.save_version=0
    for name,h in PALETTE.items():
        m=bpy.data.materials.new(name);m.diffuse_color=(*rgb(h),1);m.use_nodes=True
        p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=m.diffuse_color
        p.inputs['Roughness'].default_value=.9;MATS[name]=m
    material=bpy.data.materials.new('Farm vertex paint');material.use_nodes=True
    material.use_backface_culling=True
    p=material.node_tree.nodes.get('Principled BSDF');p.inputs['Roughness'].default_value=.9
    p.inputs['Specular IOR Level'].default_value=.18
    c=material.node_tree.nodes.new('ShaderNodeVertexColor');c.layer_name='Color'
    material.node_tree.links.new(c.outputs['Color'],p.inputs['Base Color'])
    for build in [greenhouse_base,greenhouse_roof,greenhouse_glass]:build()
    manifest=json.loads((OUT/'manifest.json').read_text())
    for name,collection in ASSETS.items():
        entry=export_asset(name,collection,material)
        manifest['assets'][name]=entry
        print('GREENHOUSE',name,entry['triangles'],entry['bounds'],flush=True)
    assert sum(manifest['assets'][k]['triangles'] for k in ASSETS)<=3000
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    # Source pieces stay assembled on their shared origin, in three named collections.
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'greenhouse_294.blend'))
    print('GREENHOUSE_DONE',flush=True)

if __name__=='__main__':main()
