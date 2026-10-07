"""Shop-series helpers, adapted from the accepted Basic Room without modifying it.
Godot metres / Y-up / +Z front; per-module source collections and local pivots.
"""
from pathlib import Path
import json
import math
import random
import sys
import time

import bpy
import bmesh
import numpy as np
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[4]
OUT = None
SOURCE = None
QA = None
SLUG = None
INSTANCES = []

def configure(slug, source=None):
    global OUT, SOURCE, QA, SLUG
    SLUG=slug
    OUT=ROOT/'assets/rooms'/slug
    SOURCE=Path(source) if source is not None else ROOT/'tools/art/source'/slug
    QA=ROOT/'output'/slug
    for p in (OUT,SOURCE,QA): p.mkdir(parents=True,exist_ok=True)
    (SOURCE/'.gdignore').touch()
    random.seed(71007)
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    KITS.clear();MATS.clear();INSTANCES.clear()

PALETTE = {
    "oak": "BE8747", "oak_light": "D59A53", "oak_edge": "AF7338",
    "oak_end": "CA8F4B", "oak_dark": "976536", "floor": "D39A5D",
    "floor_light": "DDA469", "floor_shade": "C48A50", "joint": "A56F41",
    "plaster": "EAD6BA", "plaster_light": "F0DFC7", "stone": "D4C4AD",
    "sage": "7E8A65", "sage_light": "95A477", "sage_dark": "606C4D",
    "linen": "EFE4CB", "linen_green": "9FAB78", "linen_dark": "708253",
    "porcelain": "F2E7D4", "sink_inside": "DED6C6", "iron": "494137",
    "iron_edge": "675747", "brass": "A8864C", "soil": "57422B",
    "terra": "C68D50", "terra_light": "D6A163", "leaf": "528437",
    "leaf_light": "78A84B", "leaf_dark": "3E6B30", "petal": "FFF2D4",
    "pollen": "EAB74B", "jar_green": "819750", "jar_ochre": "C49455",
    "fire_dark": "EF7224", "fire": "FFBB38", "fire_core": "FFE594",
    "sky": "A3D7DD", "hill": "BED785", "hill_back": "DAE7A8",
}

def lin(x):
    return x / 12.92 if x < .04045 else ((x + .055) / 1.055) ** 2.4

def rgb(name):
    h = PALETTE.get(name, name)
    return tuple(lin(int(h[i:i+2], 16) / 255) for i in (0, 2, 4))

def v(p):
    return Vector((p[0], -p[2], p[1]))

MATS = {}
KITS = {}
CURRENT = None

def material(name, kind="matte", axis="X"):
    key = f"{name}_{kind}_{axis}"
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new(key)
    m.diffuse_color = (*rgb(name), 1)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = m.diffuse_color
    p.inputs["Roughness"].default_value = .82 if kind != "metal" else .52
    p.inputs["Specular IOR Level"].default_value = .26
    if kind in ("wood", "plaster", "cloth"):
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        scale = nt.nodes.new("ShaderNodeVectorMath"); scale.operation = "MULTIPLY"
        stretch = {"X": (.65, 19, 13), "Y": (18, 17, .65), "Z": (19, .65, 13)}
        scale.inputs[1].default_value = stretch[axis] if kind == "wood" else (16, 16, 16)
        nt.links.new(geo.outputs["Position"], scale.inputs[0])
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 2.0 if kind == "wood" else 1.2
        noise.inputs["Detail"].default_value = 2
        noise.inputs["Roughness"].default_value = .65
        nt.links.new(scale.outputs["Vector"], noise.inputs["Vector"])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        factor = .84 if kind == "wood" else .94
        ramp.color_ramp.elements[0].position = .18
        ramp.color_ramp.elements[0].color = tuple(c * factor for c in rgb(name)) + (1,)
        ramp.color_ramp.elements[1].position = .83
        ramp.color_ramp.elements[1].color = tuple(min(1, c * 1.035) for c in rgb(name)) + (1,)
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], p.inputs["Base Color"])
    if kind == "fire":
        p.inputs["Emission Color"].default_value = (*rgb(name), 1)
        p.inputs["Emission Strength"].default_value = 2.5
    MATS[key] = m
    return m

def begin(name, at=(0, 0, 0), yaw=0, collision=None):
    global CURRENT
    c = bpy.data.collections.new("KIT_" + name)
    bpy.context.scene.collection.children.link(c)
    root = bpy.data.objects.new(name, None); c.objects.link(root)
    root.location = v(at); root.rotation_euler.z = math.radians(yaw)
    root["reusable_asset"] = name
    KITS[name] = {"collection": c, "root": root, "at": list(at), "yaw": yaw,
                  "collision": collision or [], "objects": []}
    CURRENT = KITS[name]

def finish(o, name, color, kind="matte", axis="X", smooth=False):
    o.name = name
    for c in list(o.users_collection): c.objects.unlink(o)
    CURRENT["collection"].objects.link(o)
    o.parent = CURRENT["root"]
    o.data.materials.append(material(color, kind, axis))
    for f in o.data.polygons: f.use_smooth = smooth
    CURRENT["objects"].append(o)
    return o

def cube(name, at, size, color, bevel=.025, kind="matte", axis="X"):
    bpy.ops.mesh.primitive_cube_add(size=1, location=v(at))
    o = bpy.context.object
    o.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish(o, name, color, kind, axis, smooth=True)
    if bevel:
        m = o.modifiers.new("Rounded crafted edges", "BEVEL")
        m.width = min(bevel, min(size)*.46); m.segments = 3 if bevel >= .10 else 2
        m = o.modifiers.new("Weighted normals", "WEIGHTED_NORMAL"); m.keep_sharp = True
    return o

def ellipsoid(name, at, size, color, segments=12, rings=8, kind="matte"):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=v(at))
    o = bpy.context.object; o.scale = (size[0]/2, size[2]/2, size[1]/2)
    return finish(o, name, color, kind, smooth=True)

def mesh(name, verts, faces, color, kind="matte", smooth=False):
    d = bpy.data.meshes.new(name); d.from_pydata([v(p) for p in verts], [], faces); d.update()
    bm=bmesh.new();bm.from_mesh(d);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(d);bm.free()
    o = bpy.data.objects.new(name, d); CURRENT["collection"].objects.link(o)
    return finish(o, name, color, kind, smooth=smooth)

def cylinder(name, at, r, height, color, top=None, vertices=16, kind="matte"):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r, radius2=r if top is None else top,
                                  depth=height, location=v(at))
    return finish(bpy.context.object, name, color, kind, smooth=True)

def tube(name, points, radius, color, sides=8, kind="matte"):
    pts = [Vector(p) for p in points]; verts=[]; faces=[]
    for i,p in enumerate(pts):
        t=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized()
        side=t.cross(Vector((0,1,0)))
        if side.length < .01: side=t.cross(Vector((1,0,0)))
        side.normalize(); up=t.cross(side).normalized()
        for j in range(sides):
            a=j*2*math.pi/sides; verts.append(p+radius*(side*math.cos(a)+up*math.sin(a)))
    for i in range(len(pts)-1):
        for j in range(sides): faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces.extend([tuple(reversed(range(sides))),tuple((len(pts)-1)*sides+j for j in range(sides))])
    return mesh(name,verts,faces,color,kind,True)

def lathe(name, at, profile, color, segments=20, kind="matte"):
    verts=[];faces=[]
    for y,r in profile:
        for i in range(segments):
            a=2*math.pi*i/segments;verts.append((at[0]+r*math.cos(a),at[1]+y,at[2]+r*math.sin(a)))
    for j in range(len(profile)-1):
        for i in range(segments):faces.append((j*segments+i,j*segments+(i+1)%segments,(j+1)*segments+(i+1)%segments,(j+1)*segments+i))
    faces.extend([tuple(reversed(range(segments))),tuple((len(profile)-1)*segments+i for i in range(segments))])
    return mesh(name,verts,faces,color,kind,True)

def arch_path(width, bottom, shoulder, rise, segments=20):
    # Clockwise in the local X/Y plane; front is +Z.
    return [(-width/2,bottom),(-width/2,shoulder)] + [
        (width/2*math.cos(math.pi-i*math.pi/segments), shoulder+rise*math.sin(i*math.pi/segments))
        for i in range(1,segments+1)] + [(width/2,bottom)]

def arch_solid(name, width, bottom, shoulder, rise, depth, z, color):
    p=arch_path(width,bottom,shoulder,rise);n=len(p)
    vs=[(x,y,z+d) for d in (-depth/2,depth/2) for x,y in p]
    fs=[tuple(reversed(range(n))),tuple(n+i for i in range(n))]
    fs += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name,vs,fs,color)

def arch_trim(name, width, bottom, shoulder, rise, trim, depth, z, color="oak_light"):
    inner=arch_path(width,bottom,shoulder,rise)
    outer=arch_path(width+2*trim,bottom-trim,shoulder,rise+trim)
    n=len(inner);vs=[]
    for d in (-depth/2,depth/2):
        vs += [(x,y,z+d) for x,y in inner]+[(x,y,z+d) for x,y in outer]
    fs=[]
    for i in range(n):
        j=(i+1)%n
        fs += [(i,j,n+j,n+i),(2*n+i,3*n+i,3*n+j,2*n+j),
               (i,2*n+i,2*n+j,j),(n+i,n+j,3*n+j,3*n+i)]
    o=mesh(name,vs,fs,color,"wood",smooth=True)
    m=o.modifiers.new("Hand-softened arch", "BEVEL");m.width=.028;m.segments=3
    m=o.modifiers.new("Arch normals", "WEIGHTED_NORMAL");m.keep_sharp=True
    return o

def boolean_cut(target,cutter):
    bpy.context.view_layer.update()
    bpy.context.view_layer.objects.active=target
    m=target.modifiers.new("True opening", "BOOLEAN");m.operation="DIFFERENCE";m.object=cutter
    # Boolean precedes the edge rounding.
    bpy.ops.object.modifier_move_up(modifier=m.name)
    bpy.ops.object.modifier_move_up(modifier=m.name)
    bpy.ops.object.modifier_apply(modifier=m.name)
    CURRENT["objects"].remove(cutter);bpy.data.objects.remove(cutter,do_unlink=True)

def leaf(name, start, end, width, color="leaf"):
    a=Vector(start);b=Vector(end);direction=(b-a).normalized()
    side=direction.cross(Vector((0,1,0))).normalized()
    if side.length<.1:side=Vector((1,0,0))
    normal=side.cross(direction).normalized();verts=[];faces=[];steps=6
    for layer in (0,1):
        for i in range(steps+1):
            t=i/steps;p=a.lerp(b,t);w=max(.003,math.sin(math.pi*t)**.8*width/2)
            for s in (-1,0,1):
                verts.append(p+side*w*s+normal*(math.sin(math.pi*t)*(.032 if s==0 else .014)-layer*.007))
    n=(steps+1)*3
    for layer in range(2):
        k=layer*n
        for i in range(steps):
            for j in range(2):faces.append((k+i*3+j,k+i*3+j+1,k+(i+1)*3+j+1,k+(i+1)*3+j))
    border=[i*3 for i in range(steps+1)]+[steps*3+1]+[i*3+2 for i in reversed(range(steps+1))]+[1]
    for i,u in enumerate(border):
        w=border[(i+1)%len(border)];faces.append((u,w,n+w,n+u))
    return mesh(name,verts,faces,color,smooth=True)

def plant(at=(0,0,0), scale=1, trailing=False):
    x,y,z=at;s=scale
    lathe("Terracotta pot",at,[(0,.115*s),(.04*s,.135*s),(.27*s,.18*s),(.30*s,.19*s),(.33*s,.19*s),(.33*s,.157*s),(.28*s,.151*s)],"terra",20)
    cylinder("Potting soil",(x,y+.285*s,z),.15*s,.018*s,"soil")
    for i in range(10 if trailing else 7):
        a=i*2.399;h=(.48+(i%3)*.085)*s
        end=(x+math.cos(a)*.30*s,y+h,z+math.sin(a)*.25*s)
        start=(x,y+.31*s,z)
        tube("Plant stem",[start,((start[0]+end[0])*.5,y+.45*s,(start[2]+end[2])*.5),end],.010*s,"leaf_dark",5)
        leaf("Rounded plant leaf",(x+math.cos(a)*.045*s,y+(.38 if not trailing else h/s-.12)*s,z+math.sin(a)*.045*s),end,(.22 if not trailing else .17)*s,"leaf_light" if i%3==0 else "leaf")
    if trailing:
        for j in range(2):
            path=[(x+(.09+j*.09)*s+math.sin(i*.55)*.055*s,y+(.40-i*.105)*s,z+.14*s+.035*i*s) for i in range(10)]
            tube("Trailing vine",path,.008*s,"leaf_dark",5)
            for i,p in enumerate(path[2:]):
                side=-1 if i%2 else 1
                leaf("Vine leaf",p,(p[0]+side*.12*s,p[1]-.045*s,p[2]+.02*s),.095*s,"leaf" if i%2 else "leaf_light")


def bake_and_export(ao_strength=.40, ao_distance=.38, coherent_swatches=False):
    scene=bpy.context.scene;scene.render.engine="CYCLES";scene.cycles.samples=8
    scene.cycles.bake_type="EMIT";scene.render.bake.margin=8;scene.render.bake.use_clear=True
    bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
    all_source=list(scene.objects)
    work=bpy.data.collections.new("TEMP_EXPORT");scene.collection.children.link(work)
    copies=[];names=list(KITS)
    source_id=0
    for ki,name in enumerate(names):
        for source in KITS[name]["objects"]:
            ev=source.evaluated_get(deps)
            d=bpy.data.meshes.new_from_object(ev,depsgraph=deps)
            d.transform(source.matrix_world)
            attr=d.attributes.new("kit_id","INT","FACE")
            for item in attr.data:item.value=ki
            attr=d.attributes.new("source_id","INT","FACE")
            for item in attr.data:item.value=source_id
            source_id+=1
            o=bpy.data.objects.new("Baked_"+source.name,d);work.objects.link(o);copies.append(o)
    for o in all_source:o.hide_render=True;o.hide_set(True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in copies:o.select_set(True)
    bpy.context.view_layer.objects.active=copies[0]
    bpy.ops.object.join();joined=bpy.context.object;joined.name="Atlas working mesh"
    joined.data.uv_layers.new(name="RoomAtlas")
    joined.data.uv_layers.active_index=len(joined.data.uv_layers)-1
    joined.data.uv_layers.active.active_render=True
    bpy.ops.object.mode_set(mode="EDIT");bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.0015,area_weight=.5,correct_aspect=True,scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    joined.data.uv_layers.active.name="RoomAtlas"
    # Reserve a palette strip for subpixel faces: woven reeds and leaf rims must
    # not sample black empty texels when the scene atlas is minified on mobile.
    for item in joined.data.uv_layers.active.data:item.uv.y=.125+.875*item.uv.y
    tex=bpy.data.images.new("Shop_Albedo_AO",width=2048,height=2048,alpha=False)
    tex.colorspace_settings.name="sRGB"
    tex.generated_color=(.5,.5,.5,1)
    for mat in joined.data.materials:
        nt=mat.node_tree;p=nt.nodes.get("Principled BSDF");out=nt.nodes.get("Material Output")
        image=nt.nodes.new("ShaderNodeTexImage");image.image=tex;nt.nodes.active=image
        emission=nt.nodes.new("ShaderNodeEmission")
        ao=nt.nodes.new("ShaderNodeAmbientOcclusion");ao.samples=16 if ao_strength>.4 else 8;ao.inputs["Distance"].default_value=ao_distance
        # Keep occluded surfaces legible; this is contact AO, not baked sun/shadows.
        mix=nt.nodes.new("ShaderNodeMixRGB");mix.blend_type="MIX";mix.inputs[0].default_value=.23 if coherent_swatches and mat.name.startswith(("plaster_","plaster_light_")) else ao_strength
        mix.inputs[1].default_value=(1,1,1,1);nt.links.new(ao.outputs["Color"],mix.inputs[2])
        multiply=nt.nodes.new("ShaderNodeMixRGB");multiply.blend_type="MULTIPLY";multiply.inputs[0].default_value=1
        base=p.inputs["Base Color"]
        if base.is_linked:nt.links.new(base.links[0].from_socket,multiply.inputs[1])
        else:multiply.inputs[1].default_value=base.default_value
        nt.links.new(mix.outputs[0],multiply.inputs[2]);nt.links.new(multiply.outputs[0],emission.inputs[0])
        nt.links.new(emission.outputs[0],out.inputs["Surface"])
    print("BAKING_ATLAS",len(joined.data.polygons),"polygons",flush=True)
    bpy.ops.object.bake(type="EMIT")
    pixels=np.empty(2048*2048*4,dtype=np.float32);tex.pixels.foreach_get(pixels)
    pixels=pixels.reshape((2048,2048,4))
    valid=np.max(pixels[:,:,:3],axis=2)>.001
    for step in range(12):
        old=valid.copy()
        for axis,shift in ((0,1),(0,-1),(1,1),(1,-1)):
            mask=(~valid)&np.roll(old,shift,axis)
            pixels[mask]=np.roll(pixels,shift,axis)[mask];valid[mask]=True
    pixels[~valid]=(*rgb('plaster'),1)
    for mi,mat in enumerate(joined.data.materials):
        col,row=mi%32,mi//32
        assert row<4,'Palette strip capacity exceeded'
        color=mat.diffuse_color[:]
        if coherent_swatches:
            color=tuple(c*12.92 if c<=.0031308 else 1.055*c**(1/2.4)-.055 for c in color[:3])+(color[3],)
        pixels[row*64:(row+1)*64,col*64:(col+1)*64]=color
    # Preserve baked broad surfaces; reuse padded constant swatches for details
    # whose projected UV area cannot retain a stable bake at this resolution.
    uv=joined.data.uv_layers.active.data
    small_sources=set()
    if coherent_swatches:
        areas={}
        ids=joined.data.attributes['source_id'].data
        for f in joined.data.polygons:
            key=ids[f.index].value
            areas[key]=areas.get(key,0)+f.area
        small_sources={key for key,area in areas.items() if area<.006}
    for face in joined.data.polygons:
        pts=[uv[i].uv.copy() for i in face.loop_indices]
        area=abs(sum(p.x*q.y-q.x*p.y for p,q in zip(pts,pts[1:]+pts[:1])))*.5*2048**2
        use_swatch=joined.data.attributes['source_id'].data[face.index].value in small_sources if coherent_swatches else area<12 or face.area<.0007
        if use_swatch:
            mi=face.material_index
            for li in face.loop_indices:uv[li].uv=((mi%32+.5)/32,(mi//32+.5)/32)
    tex.pixels.foreach_set(pixels.ravel());tex.update()
    tex.filepath_raw=str(OUT/"room_albedo_ao.png");tex.file_format="PNG";tex.save()
    runtime=bpy.data.materials.new("Shop_SharedAtlas");runtime.use_nodes=True
    n=runtime.node_tree.nodes.new("ShaderNodeTexImage");n.image=tex
    p=runtime.node_tree.nodes.get("Principled BSDF");runtime.node_tree.links.new(n.outputs["Color"],p.inputs["Base Color"])
    p.inputs["Roughness"].default_value=.80;p.inputs["Specular IOR Level"].default_value=.25
    data=joined.data;data.calc_loop_triangles();uv=data.uv_layers.active.data
    normal=data.corner_normals;kit_attr=data.attributes["kit_id"].data
    stats={"atlas":{"size":[2048,2048],"file":"room_albedo_ao.png","purpose":"base colour + softened contact AO; padded palette swatches for subpixel detail; no baked direct light"},"assets":[]}
    for ki,name in enumerate(names):
        faces=[f for f in data.polygons if kit_attr[f.index].value==ki]
        root=KITS[name]["root"];inv=root.matrix_world.inverted();rot=inv.to_3x3()
        ids=sorted({vi for f in faces for vi in f.vertices});mapping={old:new for new,old in enumerate(ids)}
        d=bpy.data.meshes.new(name+"_mobile")
        d.from_pydata([inv@data.vertices[i].co for i in ids],[],[[mapping[i] for i in f.vertices] for f in faces]);d.update()
        layer=d.uv_layers.new(name="RoomAtlas");normals=[];loop_index=0
        for newface,oldface in zip(d.polygons,faces):
            newface.use_smooth=oldface.use_smooth
            for li in oldface.loop_indices:
                layer.data[loop_index].uv=uv[li].uv
                normals.append((rot@normal[li].vector).normalized());loop_index+=1
        d.normals_split_custom_set(normals);d.materials.append(runtime)
        o=bpy.data.objects.new(name,d);work.objects.link(o)
        bpy.ops.object.select_all(action="DESELECT");o.select_set(True);bpy.context.view_layer.objects.active=o
        bpy.ops.export_scene.gltf(filepath=str(OUT/(name+".glb")),export_format="GLB",use_selection=True,
            export_apply=True,export_yup=True,export_texcoords=True,export_normals=True,export_materials="EXPORT",
            export_image_format="NONE",export_animations=False,export_cameras=False,export_lights=False)
        d.calc_loop_triangles()
        stats["assets"].append({"name":name,"vertices":len(d.vertices),"triangles":len(d.loop_triangles),"surfaces":1,"bytes":(OUT/(name+".glb")).stat().st_size})
        bpy.data.objects.remove(o,do_unlink=True)
    stats["unique_triangles"]=sum(a["triangles"] for a in stats["assets"])
    counts={a['name']:a['triangles'] for a in stats['assets']}
    stats['scene_triangles']=stats['unique_triangles']+sum(counts[i['asset']] for i in INSTANCES)
    stats['static_draw_surfaces']=len(names)+len(INSTANCES)
    stats['unique_assets']=len(names)
    stats['placed_instances']=len(names)+len(INSTANCES)
    stats['atlas']['bytes']=(OUT/'room_albedo_ao.png').stat().st_size
    stats['glb_bytes']=sum(a['bytes'] for a in stats['assets'])
    (OUT/'asset_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
    print('EXPORT_READY',json.dumps({k:stats[k] for k in ['unique_triangles','scene_triangles','static_draw_surfaces']}),flush=True)

def instance(asset, name, at, yaw=0):
    original=KITS[asset]
    root=bpy.data.objects.new(name,None);bpy.context.scene.collection.objects.link(root)
    root.location=v(at);root.rotation_euler.z=math.radians(yaw)
    for source in original['objects']:
        o=source.copy();o.data=source.data;bpy.context.scene.collection.objects.link(o);o.parent=root
    root['linked_asset']=asset
    INSTANCES.append({'name':name,'asset':asset,'position':list(at),'yaw_degrees':yaw})

def text_label(body,at,size,color,align='CENTER'):
    curve=bpy.data.curves.new('Lettering '+body,'FONT');curve.body=body
    curve.align_x=align;curve.size=size;curve.extrude=.0008;curve.resolution_u=3
    o=bpy.data.objects.new('Lettering '+body,curve);bpy.context.scene.collection.objects.link(o)
    o.location=v(at);o.rotation_euler.x=math.pi/2
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
    bpy.ops.object.convert(target='MESH')
    return finish(bpy.context.object,'Lettering '+body,color)

def cup(at=(0,0,0),s=1,color='porcelain',coffee=True):
    x,y,z=at
    lathe('Cup with actual opening',at,[(0,.07*s),(.025*s,.086*s),(.16*s,.106*s),(.175*s,.103*s),(.175*s,.085*s),(.14*s,.077*s),(.03*s,.06*s)],color,16)
    tube('Cup loop handle',[(x+.095*s+math.sin(i*math.pi/10)*.072*s,y+.09*s+math.cos(i*math.pi/10)*.060*s,z) for i in range(11)],.014*s,color,6)
    if coffee:
        cylinder('Coffee surface',(x,y+.145*s,z),.078*s,.006,'oak_dark',vertices=20)
        tube('Latte cream swirl',[(x+math.cos(i*.34)*(.045-i*.0008)*s,y+.150*s,z+math.sin(i*.34)*(.045-i*.0008)*s) for i in range(31)],.006*s,'porcelain',5)

def flower(at,scale=1):
    x,y,z=at
    for j in range(7):
        a=j*math.tau/7
        ellipsoid('Daisy petal',(x+math.cos(a)*.042*scale,y,z+math.sin(a)*.042*scale),(.043*scale,.018*scale,.026*scale),'petal',8,4)
    ellipsoid('Daisy gold heart',at,(.028*scale,.023*scale,.028*scale),'pollen',8,4)

def bouquet(at=(0,0,0),scale=1):
    x,y,z=at;s=scale
    lathe('Celadon bud vase',at,[(0,.10*s),(.05*s,.135*s),(.19*s,.12*s),(.27*s,.062*s),(.31*s,.067*s),(.31*s,.046*s),(.27*s,.040*s)],'jar_green',20)
    for j in range(9):
        a=j*2.399;h=(.42+(j%3)*.065)*s
        end=(x+math.cos(a)*.16*s,y+h,z+math.sin(a)*.14*s)
        tube('Bouquet stem',[(x,y+.25*s,z),end],.005*s,'leaf_dark',5)
        leaf('Bouquet leaf',(x,y+.30*s,z),(end[0],y+.40*s,end[2]),.065*s,'leaf')
        flower(end,.70*s)

def vine(path,density=1):
    tube('Living vine stem',path,.014,'leaf_dark',6)
    for j,p in enumerate(path):
        for side in (-1,1):
            if density<1 and random.random()>density:continue
            end=(p[0]+side*random.uniform(.10,.24),p[1]+random.uniform(-.04,.16),p[2]+random.uniform(.03,.18))
            leaf('Ivy leaf',p,end,random.uniform(.085,.16),random.choice(['leaf','leaf_light','leaf_dark']))
        if j%5==1:flower((p[0],p[1]+.08,p[2]+.08),1.05)

def low_wall(length=2, color='sage'):
    cube('Panel backing',(0,.36,0),(length,.60,.16),color,.025,'plaster')
    n=round(length/.20)
    for j in range(n):
        cube('Tongue and groove panel',(-length/2+(j+.5)*length/n,.38,.10),(length/n-.012,.48,.025),color,.007,'wood','Y')
    cube('Cream coping',(0,.70,0),(length+.07,.14,.25),'plaster_light',.055)
    cube('Cream plinth',(0,.075,0),(length+.02,.15,.23),'plaster',.035)

def chair():
    for x in (-.24,.24):
        for z in (-.23,.23):
            tube('Splayed rattan leg',[(x*1.23,.02,z*1.25),(x,.52,z)],.033,'oak',8,'wood')
    cylinder('Circular seat',(0,.51,0),.32,.075,'oak_light',vertices=32)
    ellipsoid('Cream seat cushion',(0,.57,0),(.62,.12,.57),'linen',24,8)
    for y in (.56,.99):
        tube('Bent rattan back rail',[(.34*math.cos(i*math.pi/24),y,-.32*math.sin(i*math.pi/24)) for i in range(25)],.027,'oak_light',8,'wood')
    for i in range(25):
        a=(i+.5)*math.pi/25
        tube('Cane back upright',[(.335*math.cos(a),.59,-.315*math.sin(a)),(.34*math.cos(a),.965,-.32*math.sin(a))],.009,'linen_green',5)
    for j in range(9):
        tube('Cane woven horizontal',[(.338*math.cos(i*math.pi/24),.605+j*.041,-.318*math.sin(i*math.pi/24)) for i in range(25)],.006,'linen',5)
    for x in (-.29,.29):
        tube('Chair side brace',[(x,.22,-.25),(x,.22,.25)],.018,'oak',6)

def table():
    lathe('Cast pedestal',(0,0,0),[(0,.29),(.035,.30),(.06,.26),(.09,.12),(.13,.055),(.72,.055),(.77,.15)],'iron',24)
    cylinder('Rounded cafe tabletop',(0,.79,0),.56,.09,'oak_light',vertices=48,kind='wood')
    for j in (-1,0,1):
        z=j*.27
        span=math.sqrt(.54**2-z*z)
        tube('Tabletop plank joint',[(-span,.837,z),(span,.837,z)],.0027,'oak_edge',4)

def rug():
    cylinder('Woven jute mat',(0,.011,0),.94,.018,'terra_light',vertices=64,kind='cloth')
    for j in range(20):
        r=.16+j*.039
        tube('Jute spiral ridge',[(r*math.cos(i*math.tau/64),.024,r*math.sin(i*math.tau/64)) for i in range(65)],.007,'oak_light' if j%2 else 'terra',5)

def counter(width=3.4,depth=.90,color='oak_light'):
    cube('Counter carcass',(0,.55,0),(width,1.05,depth),color,.12,'wood','Y')
    for j in range(round(width/.16)):
        x=-width/2+.12+j*(width-.24)/(round(width/.16)-1)
        cube('Counter front plank',(x,.56,depth/2+.004),(.14,.88,.018),color,.008,'wood','Y')
    cube('Stone worktop',(0,1.12,0),(width+.14,.14,depth+.14),'porcelain',.12,'plaster')
    cube('Counter kickboard',(0,.10,0),(width+.025,.14,depth+.025),'oak_edge',.065,'wood')

def save(node_id,camera=None):
    camera=camera or {'position':[10,9,12],'target':[0,1.0,0],'size':9.3}
    layout={'units':'metres','coordinates':'Godot Y up, front +Z; pivots local floor or mounting point',
      'reference':{'file_key':'OMLTC3yw3u2WDjOZhLnhaR','node_id':node_id},
      'assets':[{'name':k,'file':k+'.glb','position':d['at'],'yaw_degrees':d['yaw'],'colliders':d['collision']} for k,d in KITS.items()],
      'instances':INSTANCES,'camera':camera}
    (OUT/'layout.json').write_text(json.dumps(layout,indent=2)+'\n')
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=16
    scene.cycles.use_denoising=True;scene.render.resolution_x=1200;scene.render.resolution_y=1200
    scene.view_settings.view_transform='AgX'
    scene.world=bpy.data.worlds.new('Soft warm daylight');scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value=(*rgb('E9E5D5'),1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value=.8
    light=bpy.data.lights.new('Large softbox','AREA');light.energy=1700;light.shape='DISK';light.size=8
    o=bpy.data.objects.new('Large softbox',light);scene.collection.objects.link(o);o.location=v((-3,9,5))
    o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
    d=bpy.data.cameras.new('Review camera');o=bpy.data.objects.new('Review camera',d);scene.collection.objects.link(o)
    o.location=v(camera['position']);o.rotation_euler=(v(camera['target'])-o.location).to_track_quat('-Z','Y').to_euler()
    d.type='ORTHO';d.ortho_scale=camera['size'];scene.camera=o
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(SLUG+'.blend')))
    print('GEOMETRY_READY',SLUG,len(KITS),sum(len(k['objects']) for k in KITS.values()),flush=True)

def load():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE/(SLUG+'.blend')))
    layout=json.loads((OUT/'layout.json').read_text());INSTANCES[:]=layout['instances']
    for a in layout['assets']:
        c=bpy.data.collections['KIT_'+a['name']]
        KITS[a['name']]={'collection':c,'root':bpy.data.objects[a['name']],
            'objects':[o for o in c.objects if o.type=='MESH'],'at':a['position'],'yaw':a['yaw_degrees']}
