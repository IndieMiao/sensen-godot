"""Build the Basic Room reference as an editable, reusable Blender kit.

blender --background --factory-startup --python tools/art/build_basic_room.py
Optional trailing arguments: -- --geometry-only / --bake-only / --render-only
Model helpers use Godot metres, Y up, front +Z. No downloaded model assets.
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

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/rooms/basic_room"
SOURCE = ROOT / "tools/art/source/basic_room"
QA = ROOT / "output/basic-room-2026-10-06"
for p in (OUT, SOURCE, QA):
    p.mkdir(parents=True, exist_ok=True)
(SOURCE / ".gdignore").touch()
random.seed(61006)
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

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
        m.width = min(bevel, min(size)*.46); m.segments = 3 if bevel >= .06 else 2
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

def flower_vase():
    lathe("Cream jug",(0,0,0),[(0,.11),(.045,.15),(.20,.17),(.29,.14),(.34,.10),(.37,.10),(.37,.074),(.32,.078)],"porcelain",24)
    tube("Jug loop handle",[(.11,.28,0),(.22,.30,0),(.255,.245,0),(.24,.15,0),(.14,.12,0)],.024,"porcelain",8)
    for i in range(9):
        a=i*2.4;r=.08 if i==0 else .16
        head=Vector((math.cos(a)*r,.50+(i%3)*.065,math.sin(a)*r))
        tube("Daisy stem",[(0,.26,0),head],.008,"leaf",5)
        leaf("Daisy leaf",(0,.33,0),(head.x*1.2,.41,head.z*1.2),.055,"leaf")
        normal=Vector((math.cos(a)*.38,1,math.sin(a)*.38)).normalized()
        tangent=normal.cross(Vector((0,0,1))).normalized();other=normal.cross(tangent).normalized()
        for j in range(7):
            b=j*2*math.pi/7;d=tangent*math.cos(b)+other*math.sin(b)
            o=ellipsoid("Daisy ivory petal",head+d*.059,(.047,.020,.092),"petal",8,6)
            o.rotation_mode="QUATERNION";o.rotation_quaternion=v(d).to_track_quat("Y","Z")
        ellipsoid("Daisy golden centre",head+normal*.015,(.049,.036,.049),"pollen",10,6)

def painted_garden():
    """Original soft landscape card, only visible beyond the real window aperture."""
    size=512;y,x=np.mgrid[0:size,0:size].astype(np.float32)/(size-1)
    def col(h):return np.array([int(h[i:i+2],16)/255 for i in (0,2,4)],dtype=np.float32)
    pixels=np.empty((size,size,4),dtype=np.float32)
    pixels[:,:,:3]=col("B8DDD7")+(col("82CCDF")-col("B8DDD7"))*y[:,:,None]
    pixels[:,:,3]=1
    def paint(mask,color):
        a=np.clip(mask,0,1)[:,:,None];pixels[:,:,:3]=pixels[:,:,:3]*(1-a)+col(color)*a
    def disk(cx,cy,rx,ry,color,soft=.10):
        d=np.sqrt(((x-cx)/rx)**2+((y-cy)/ry)**2)
        paint(np.clip((1+soft-d)/(soft*2),0,1),color)
    hill=.38+.045*np.sin(x*6.3+1)
    paint(np.clip((hill-y+.02)/.04,0,1),"D4DE97")
    for cx,cy,s in [(.16,.61,1),(.71,.76,1.25),(.98,.58,.82),(.41,.47,.65)]:
        paint(np.clip((.018*s-np.abs(x-cx))/.006,0,1)*np.clip((y-.22)/.03,0,1)*np.clip((cy-y)/.02,0,1),"BAA66C")
        for ox,oy,rx,ry,c in [(-.06,0,.09,.13,"9EC15F"),(.065,.02,.10,.12,"AAD075"),(0,.09,.095,.14,"BDDC86")]:
            disk(cx+ox*s,cy+oy*s,rx*s,ry*s,c,.18)
    hill=.25+.048*np.sin(x*7.5-1)
    paint(np.clip((hill-y+.015)/.03,0,1),"A9C66D")
    for i in range(22):
        cx=random.random();cy=.03+random.random()*.17
        disk(cx,cy,.006,.013,"E5E6AC",.5)
    im=bpy.data.images.new("Original painted window garden",width=size,height=size,alpha=False)
    im.colorspace_settings.name="sRGB";im.pixels.foreach_set(pixels.ravel());im.pack()
    o=mesh("Soft distant garden beyond the window",[(-1.15,1.18,-.26),(1.15,1.18,-.26),(1.15,3.20,-.26),(-1.15,3.20,-.26)],[(0,1,2,3)],"sky")
    uv=o.data.uv_layers.new(name="GardenUV")
    for i,p in enumerate([(0,0),(1,0),(1,1),(0,1)]):uv.data[i].uv=p
    m=o.data.materials[0];nt=m.node_tree
    texture=nt.nodes.new("ShaderNodeTexImage");texture.image=im
    coords=nt.nodes.new("ShaderNodeUVMap");coords.uv_map="GardenUV"
    nt.links.new(coords.outputs["UV"],texture.inputs["Vector"])
    nt.links.new(texture.outputs["Color"],nt.nodes.get("Principled BSDF").inputs["Base Color"])
    o.visible_shadow=False

def geometry():
    bpy.ops.object.select_all(action="SELECT");bpy.ops.object.delete(use_global=False)
    bpy.context.preferences.filepaths.save_version=0
    # A square 6.2m room, front walls removed as in the reference.
    begin("room_shell",collision=[{"at":[0,-.12,0],"size":[6.45,.24,6.45]},
        {"at":[-3.1,1.8,0],"size":[.25,3.6,6.45]}, {"at":[0,1.8,-3.1],"size":[6.45,3.6,.25]},
        {"at":[3.23,.55,0],"size":[.12,1.1,6.45]}, {"at":[0,.55,3.23],"size":[6.45,1.1,.12]}])
    cube("Rounded wooden foundation",(0,-.16,0),(6.55,.34,6.55),"oak_edge",.13,"wood")
    cube("Dark floor seams",(0,.007,0),(6.15,.07,6.15),"joint",.015)
    for row in range(19):
        z=-2.975+row*.33;start=-3.12
        lengths=[.72,1.55,1.53,1.54,1.0] if row%2 else [1.52,1.56,1.55,1.7]
        for col,length in enumerate(lengths):
            end=min(start+length,3.12)
            if end-start<.05:break
            color=["floor","floor_light","floor","floor_shade"][(row*7+col*3)%4]
            cube("Staggered oak floorboard",((start+end)/2,.043,z),(end-start-.009,.065,.319),color,.009,"wood")
            start=end
    for x in (-3.15,3.15):cube("Floor perimeter long edge",(x,.015,0),(.20,.21,6.50),"oak_light",.045,"wood","Z")
    for z in (-3.15,3.15):cube("Floor perimeter end edge",(0,.015,z),(6.20,.21,.20),"oak",.045,"wood")
    for x in (-3.15,3.15):
        for z in (-3.15,3.15):cube("Rounded floor corner join",(x,-.045,z),(.28,.29,.28),"oak_end",.08,"wood")
    # Plaster wall with a real arched window aperture.
    begin("window_wall",at=(-3.1,0,0),yaw=90,collision=[])
    wall=cube("Warm plaster wall",(0,1.84,0),(6.24,3.55,.17),"plaster",.045,"plaster")
    cutter=arch_solid("Window aperture cutter",1.78,1.32,2.38,.62,.65,0,"plaster")
    cutter.location.x=.10
    boolean_cut(wall,cutter)
    for x in (-3.0,3.0):
        cube("Wall timber post",(x,1.82,.03),(.25,3.70,.29),"oak",.065,"wood","Y")
        cube("Timber join cap",(x,3.61,.035),(.43,.36,.42),"oak_end",.10,"wood")
        cube("Post foot plinth",(x,.14,.04),(.38,.25,.37),"oak_edge",.045,"wood")
    cube("Upper timber beam",(0,3.57,.055),(5.9,.25,.27),"oak_light",.045,"wood")
    cube("Wall skirting",(0,.22,.13),(5.86,.20,.14),"oak",.025,"wood")
    for x in (-1.90,1.8):
        o=cube("Timber peg bracket",(x,3.29,.13),(.21,.30,.16),"oak_edge",.032,"wood","Y")
        o.rotation_euler.x=.13
    begin("back_wall",at=(0,0,-3.1),collision=[])
    wall=cube("Warm plaster back wall",(0,1.84,0),(6.24,3.55,.17),"plaster",.045,"plaster")
    cutter=arch_solid("Door opening cutter",1.04,.075,1.89,.50,.8,0,"plaster");cutter.location.x=2.03
    boolean_cut(wall,cutter)
    # The shared back-left post belongs to the window wall.
    cube("Right timber post",(3.0,1.82,.03),(.25,3.70,.29),"oak",.065,"wood","Y")
    cube("Right join cap",(3.0,3.61,.035),(.43,.36,.42),"oak_end",.10,"wood")
    cube("Right post foot",(3.0,.14,.04),(.38,.25,.37),"oak_edge",.045,"wood")
    cube("Upper back beam",(0,3.57,.055),(5.9,.25,.27),"oak_light",.045,"wood")
    cube("Back skirting left",(-.76,.22,.13),(4.25,.20,.14),"oak",.025,"wood")
    cube("Back skirting right",(2.82,.22,.13),(.25,.20,.14),"oak",.025,"wood")
    for x in (-1.5,.15,1.65):cube("Back timber bracket",(x,3.29,.13),(.20,.30,.16),"oak_edge",.032,"wood","Y")
    begin("arched_window",at=(-3.00,0,-.10),yaw=90)
    arch_trim("Thick arched oak window casing",1.78,1.32,2.38,.62,.15,.19,.035)
    cube("Deep rounded window sill",(0,1.31,.15),(2.12,.14,.49),"oak_light",.045,"wood")
    cube("Sill apron",(0,1.17,.08),(1.83,.14,.14),"oak_edge",.025,"wood")
    cube("Vertical window mullion",(0,2.16,.015),(.074,1.72,.075),"oak",.012,"wood","Y")
    cube("Horizontal window mullion",(0,2.15,.015),(1.80,.074,.078),"oak",.012,"wood")
    begin("window_garden",at=(-3.25,0,-.10),yaw=90)
    painted_garden()
    begin("window_plant",at=(-2.82,1.40,.48),yaw=90)
    plant(scale=.68,trailing=True)
    begin("green_door",at=(2.03,.05,-2.985))
    door=arch_solid("Sage arched door",1.02,0,1.84,.49,.10,0,"sage")
    m=door.modifiers.new("Rounded door edge","BEVEL");m.width=.025;m.segments=2
    arch_trim("Oak arched doorway",1.06,0,1.85,.51,.14,.19,.055)
    for x in (-.31,-.10,.11,.32):
        ytop=1.84+.49*math.sqrt(max(0,1-(x/.51)**2))
        cube("Door board groove",(x,ytop/2,.058),(.009,ytop-.02,.012),"sage_dark",.003)
    glass=arch_solid("Arched glazed door light",.43,1.30,1.79,.22,.023,.066,"hill_back")
    arch_trim("Green glass frame",.45,1.28,1.79,.22,.047,.047,.085,"sage_light")
    cube("Door light vertical muntin",(0,1.63,.12),(.048,.70,.046),"sage_light",.009)
    cube("Door light horizontal muntin",(0,1.66,.12),(.43,.045,.046),"sage_light",.009)
    ellipsoid("Handle round backplate",(-.32,1.02,.115),(.18,.18,.055),"iron",16,8)
    ellipsoid("Iron door knob",(-.32,1.02,.18),(.125,.125,.12),"iron_edge",16,8)
    for y in (.54,1.48):cube("Door hinge",(.47,y,.09),(.055,.14,.04),"iron",.011)
    begin("entry_mat",at=(2.03,.092,-2.40))
    cube("Woven green door mat",(0,0,0),(1.08,.033,.56),"linen_dark",.025,"cloth")
    for x in (-.36,-.12,.12,.36):cube("Cream mat stripe",(x,.021,0),(.102,.013,.54),"linen",.007,"cloth")
    # Hearth and oven: real recessed firebox and separate kettle.
    begin("hearth",at=(-2.05,.082,-2.57),collision=[{"at":[0,.77,0],"size":[1.17,1.54,1.00]}])
    cube("Hearth stone foot",(0,.08,.055),(1.21,.16,1.04),"stone",.075)
    body=cube("Sculpted plaster oven",(0,.65,0),(1.10,1.21,.91),"plaster_light",.14,"plaster")
    cut=arch_solid("Arched firebox cavity",.63,.14,.58,.26,1.5,.13,"iron")
    boolean_cut(body,cut)
    arch_trim("Rounded firebox lip",.63,.14,.58,.26,.067,.09,.46,"stone")
    cube("Firebox dark back",(0,.43,-.40),(.73,.72,.055),"iron",.02)
    cube("Oven top slab",(0,1.22,0),(1.12,.15,.95),"plaster_light",.095,"plaster")
    cube("Rising plaster chimney breast",(0,1.78,-.22),(.77,1.13,.54),"plaster_light",.14,"plaster")
    cylinder("Black chimney pipe",(0,2.61,-.24),.14,.57,"iron",vertices=20,kind="metal")
    cylinder("Chimney base collar",(0,2.35,-.24),.19,.095,"iron_edge",vertices=20,kind="metal")
    cylinder("Chimney upper collar",(0,2.87,-.24),.16,.07,"iron_edge",vertices=20,kind="metal")
    tube("Stove rear elbow",[(0,2.68,-.24),(0,2.73,-.39),(0,2.73,-.53)],.13,"iron",12,"metal")
    cube("Warm chimney cap",(0,2.97,-.24),(.45,.24,.44),"oak",.075,"wood")
    for x,z,a in [(-.13,.25,.22),(.12,.25,-.28),(0,.045,1.3)]:
        o=cylinder("Charred fire log",(x,.235,z),.08,.43,"oak_dark",vertices=10)
        o.rotation_euler.y=math.pi/2;o.rotation_euler.z=a
    begin("kettle",at=(-2.05,1.405,-2.36))
    for x in (-.19,.19):cube("Cast iron hob support",(x,.02,0),(.05,.055,.48),"iron",.012)
    for z in (-.16,.16):cube("Cast iron hob rail",(0,.04,z),(.50,.05,.043),"iron",.01)
    lathe("Rounded cooking pot",(0,.06,0),[(0,.12),(.035,.18),(.15,.205),(.24,.18),(.25,.19)],"iron",24,"metal")
    lathe("Domed kettle lid",(0,.31,0),[(0,.195),(.025,.18),(.055,.11),(.066,.025)],"iron_edge",24,"metal")
    ellipsoid("Kettle lid knob",(0,.405,0),(.077,.06,.077),"iron",12,8)
    for s in (-1,1):tube("Pot side handle",[(s*.17,.22,0),(s*.26,.25,0),(s*.29,.20,0),(s*.19,.16,0)],.020,"iron_edge",8,"metal")
    begin("fire",at=(-2.05,.29,-2.30))
    for x,height,color,z in [(-.13,.32,"fire_dark",.015),(.075,.42,"fire",0),(0,.25,"fire_core",.10)]:
        profile=[(0,.060),(.07,.085),(height*.46,.066),(height*.78,.034),(height,.002)]
        lathe("Sculpted flame",(x,0,z),profile,color,12,"fire")
    # Cabinet and apron-front sink.
    begin("sink_cabinet",at=(-.47,.082,-2.62),collision=[{"at":[0,.60,0],"size":[1.80,1.20,.86]}])
    cube("Sage cabinet carcass",(0,.52,0),(1.80,.95,.74),"sage_dark",.045,"wood","Y")
    cube("Cabinet plinth",(0,.08,.035),(1.86,.16,.80),"sage",.025,"wood")
    for x in (-.85,.85):cube("Oak corner stile",(x,.58,.38),(.105,.93,.075),"oak_edge",.017,"wood","Y")
    for x in (-.405,.405):
        cube("Sage cabinet door",(x,.58,.407),(.73,.79,.08),"sage",.023,"wood","Y")
        for dx in (-.19,0,.19):cube("Cabinet tongue and groove",(x+dx,.58,.453),(.009,.71,.006),"sage_dark",.002)
    for x in (-.085,.085):ellipsoid("Honey oak cabinet knob",(x,.71,.485),(.087,.088,.083),"oak",12,8)
    countertop=cube("Oak countertop",(0,1.075,0),(1.97,.155,.91),"oak_light",.05,"wood")
    cut=cube("Sink counter cutout",(.08,1.08,.13),(.77,.6,.45),"oak",0)
    boolean_cut(countertop,cut)
    cube("Porcelain sink front apron",(.08,1.062,.40),(.90,.37,.13),"porcelain",.063)
    cube("Sink basin bottom",(.08,1.045,.14),(.74,.045,.40),"sink_inside",.035)
    cube("Porcelain inner back wall",(.08,1.135,-.065),(.75,.185,.038),"sink_inside",.012)
    cube("Porcelain inner left wall",(-.28,1.13,.145),(.042,.17,.40),"sink_inside",.012)
    cube("Porcelain inner right wall",(.44,1.13,.145),(.042,.17,.40),"sink_inside",.012)
    cube("Sink left rim",(-.34,1.205,.125),(.13,.21,.60),"porcelain",.036)
    cube("Sink right rim",(.50,1.205,.125),(.13,.21,.60),"porcelain",.036)
    cube("Sink back rim",(.08,1.22,-.135),(.75,.18,.10),"porcelain",.03)
    cube("Sink front rim",(.08,1.22,.405),(.75,.14,.105),"porcelain",.03)
    cylinder("Sink drain",(.08,1.071,.15),.035,.005,"iron_edge",vertices=12)
    tube("Gooseneck faucet",[(.10,1.17,-.23),(.10,1.53,-.23),(.10,1.62,-.18),(.10,1.63,-.08),(.10,1.57,.01),(.10,1.51,.015)],.027,"iron",10,"metal")
    for x in (-.095,.27):
        cylinder("Tap foot",(x,1.18,-.22),.045,.055,"iron_edge",vertices=12)
        ellipsoid("Tap handle",(x,1.25,-.22),(.054,.10,.045),"iron",10,6)
    begin("utensil_crock",at=(-1.11,1.25,-2.70))
    lathe("Honey utensil crock",(0,0,0),[(0,.09),(.03,.11),(.23,.12),(.27,.11),(.27,.085),(.23,.085)],"terra",18)
    for i,(x,z) in enumerate([(-.06,0),(.055,.025),(0,-.04)]):
        top=(x*1.8,.56+i*.03,z*1.7)
        tube("Wooden spoon handle",[(x*.4,.11,z),top],.016,"oak_edge",6)
        o=ellipsoid("Wooden spoon bowl",top,(.105,.15,.035),"oak",10,6)
        o.rotation_euler.y=(i-1)*.20
    begin("wall_shelf",at=(-.48,2.29,-2.87))
    cube("Oak kitchen shelf",(0,0,.13),(1.78,.13,.43),"oak",.045,"wood")
    for x in (-.62,.62):cube("Shelf corbel",(x,-.16,.01),(.13,.29,.19),"oak_edge",.045,"wood","Y")
    for x,r,h,col in [(-.61,.095,.26,"jar_green"),(-.29,.10,.23,"jar_ochre"),(.03,.12,.30,"porcelain")]:
        lathe("Pantry jar",(x,.07,.12),[(0,r*.85),(.025,r),(h*.76,r),(h*.88,r*.78),(h,r*.78)],col,16)
        cylinder("Cork pantry lid",(x,.07+h+.016,.12),r*.83,.065,"oak_edge",vertices=16)
    begin("shelf_plant",at=(.17,2.38,-2.73))
    plant(scale=.69,trailing=True)
    begin("hanging_towel",at=(.72,1.85,-2.925))
    ellipsoid("Wooden towel peg",(0,.10,.07),(.095,.10,.11),"oak",12,8)
    verts=[];faces=[];cols=10;rows=18
    for j in range(rows+1):
        t=j/rows;w=.035+.15*t
        for i in range(cols+1):
            q=i/cols;verts.append(((q-.5)*w*2,-t*.72,.13+math.sin(q*math.pi*6)*.029*t+.018*math.sin(t*5)))
    for j in range(rows):
        for i in range(cols):faces.append((j*(cols+1)+i,j*(cols+1)+i+1,(j+1)*(cols+1)+i+1,(j+1)*(cols+1)+i))
    cloth=mesh("Folded hanging linen towel",verts,faces,"linen","cloth",True)
    cloth.data.materials.append(material("linen_dark","cloth"))
    for p in cloth.data.polygons:
        row=p.index//cols
        if row in (13,15):p.material_index=1
    m=cloth.modifiers.new("Thin cloth thickness","SOLIDIFY");m.thickness=.008
    # Freestanding pieces use pivots on the floor, ready for reuse.
    begin("dining_table",at=(-.12,.082,.62),collision=[{"at":[0,.60,0],"size":[1.88,1.20,1.18]}])
    for x in (-.71,.71):
        for z in (-.40,.40):cube("Square tapered table leg",(x,.51,z),(.14,1.00,.14),"oak",.025,"wood","Y")
    for z in (-.43,.43):cube("Table apron long",(0,.88,z),(1.62,.21,.095),"oak_edge",.018,"wood")
    for x in (-.78,.78):cube("Table apron end",(x,.88,0),(.10,.21,.82),"oak_edge",.018,"wood","Z")
    for i in range(5):cube("Individual tabletop board",(0,1.06,-.47+i*.235),(1.90,.15,.225),"oak_light" if i%3 else "oak",.028,"wood")
    begin("checked_runner",at=(-.12,1.233,.62),yaw=90)
    # Profile follows the tabletop then folds over both edges, leaving oak visible.
    zs=[(-1.08,-.27),(-1.02,-.15),(-.965,-.03),(-.93,0),(-.70,.005),(-.47,.003),(-.24,.005),(0,.003),(.24,.005),(.47,.003),(.70,.005),(.93,0),(.965,-.04),(1.03,-.20)]
    verts=[];faces=[];cols=6
    for j,(z,y) in enumerate(zs):
        for i in range(cols+1):verts.append((-.36+i*.12,y+.005*math.cos(i*2+j),z))
    for j in range(len(zs)-1):
        for i in range(cols):faces.append((j*(cols+1)+i,j*(cols+1)+i+1,(j+1)*(cols+1)+i+1,(j+1)*(cols+1)+i))
    o=mesh("Draped gingham runner",verts,faces,"linen","cloth",True)
    o.data.materials.append(material("linen_green","cloth"));o.data.materials.append(material("linen_dark","cloth"))
    for p in o.data.polygons:
        j=p.index//cols;i=p.index%cols;p.material_index=2 if i%2 and j%2 else 1 if (i+j)%2 else 0
    m=o.modifiers.new("Linen edge","SOLIDIFY");m.thickness=.008
    begin("chair",at=(1.15,.082,.62),yaw=90,collision=[{"at":[0,.66,0],"size":[.63,1.32,.63]}])
    for x in (-.235,.235):
        for z in (-.23,.23):
            h=1.47 if z>.0 else .62
            cube("Chair rear stile" if z>0 else "Chair front leg",(x,h/2,z),(.09,h,.10),"oak",.025,"wood","Y")
    for i in range(3):cube("Chair seat plank",(0,.63,-.19+i*.19),(.63,.11,.18),"oak_light",.028,"wood")
    cube("Chair curved top rail",(0,1.37,.245),(.59,.14,.11),"oak_light",.041,"wood")
    for x in (-.115,.115):cube("Chair back slat",(x,1.05,.245),(.085,.55,.065),"oak",.021,"wood","Y")
    for x in (-.235,.235):cube("Chair side stretcher",(x,.26,0),(.06,.065,.48),"oak_edge",.014,"wood","Z")
    # The second chair is a linked kit instance, never a second baked mesh.
    begin("bench",at=(-2.66,.082,1.18),yaw=90,collision=[{"at":[0,.34,0],"size":[1.08,.68,.45]}])
    cube("Rounded oak bench seat",(0,.60,0),(1.12,.14,.48),"oak_light",.05,"wood")
    for x in (-.39,.39):
        for z in (-.135,.135):cube("Bench leg",(x,.28,z),(.105,.55,.10),"oak",.022,"wood","Y")
    cube("Bench lower brace",(0,.23,0),(.86,.105,.09),"oak_edge",.021,"wood")
    begin("daisy_jug",at=(-.02,1.262,.60));flower_vase()
    begin("floor_plant",at=(2.68,.09,-2.07));plant(scale=1.08)
    # Source instance uses linked mesh data and its own reusable floor pivot.
    inst=bpy.data.objects.new("chair_opposite",None);bpy.context.scene.collection.objects.link(inst)
    inst.location=v((-1.39,.082,.62));inst.rotation_euler.z=-math.pi/2
    for original in KITS["chair"]["objects"]:
        o=original.copy();o.data=original.data;bpy.context.scene.collection.objects.link(o);o.parent=inst
    inst["linked_asset"]="chair"
    layout={"units":"metres", "reference":{"file_key":"5SVgfevrLzZXqD83uyPgmV","node_id":"3:4550"},
        "assets":[{"name":k,"file":k+".glb","position":d["at"],"yaw_degrees":d["yaw"],"colliders":d["collision"]} for k,d in KITS.items()],
        "instances":[{"name":"chair_opposite","asset":"chair","position":[-1.39,.082,.62],"yaw_degrees":-90}],
        "spawn":[1.4,.085,1.65],"camera":{"position":[9.5,8.55,11.2],"target":[0,1.75,0],"size":10.75},
        "sun_direction":[-6,7,1.5],"fire_position":[-2.05,.53,-2.11]}
    (OUT/"layout.json").write_text(json.dumps(layout,indent=2)+"\n")
    setup_render()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/"basic_room.blend"))
    print("GEOMETRY_READY",len(KITS),"kits",sum(len(k["objects"]) for k in KITS.values()),"objects",flush=True)

def setup_render():
    scene=bpy.context.scene;scene.render.engine="CYCLES";scene.cycles.samples=48
    scene.cycles.use_denoising=True
    scene.render.resolution_x=1400;scene.render.resolution_y=1400;scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new("Warm daylight")
    scene.world.use_nodes=True;scene.world.node_tree.nodes["Background"].inputs[0].default_value=(*rgb("E3E7D3"),1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value=.65
    scene.view_settings.view_transform="AgX"
    scene.view_settings.look="AgX - Medium High Contrast"
    def area(name,at,power,size,color,target=(0,1,0)):
        d=bpy.data.lights.new(name,"AREA");d.energy=power;d.shape="DISK";d.size=size;d.color=tuple(int(color[i:i+2],16)/255 for i in (0,2,4))
        o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=v(at)
        o.rotation_euler=(v(target)-o.location).to_track_quat("-Z","Y").to_euler()
    area("Broad soft room fill",(1,7,3),520,7,"FFEDD1")
    d=bpy.data.lights.new("Window afternoon sun","SUN");d.energy=2.0;d.angle=.07;d.color=(1,.86,.66)
    o=bpy.data.objects.new("Window afternoon sun",d);scene.collection.objects.link(o);o.location=v((-6,7,1.5))
    o.rotation_euler=(-o.location).to_track_quat("-Z","Y").to_euler()
    d=bpy.data.lights.new("Hearth warm glow","POINT");d.energy=16;d.color=(1,.32,.04);d.shadow_soft_size=.24
    o=bpy.data.objects.new("Hearth warm glow",d);scene.collection.objects.link(o);o.location=v((-2.05,.54,-2.11))
    d=bpy.data.cameras.new("Reference camera");o=bpy.data.objects.new("Reference camera",d);scene.collection.objects.link(o)
    o.location=v((9.5,8.55,11.2));o.rotation_euler=(v((0,1.75,0))-o.location).to_track_quat("-Z","Y").to_euler()
    d.type="ORTHO";d.ortho_scale=10.75;scene.camera=o
    # A matte cream cyclorama is source-render-only; Godot supplies a matching plane.
    d=bpy.data.meshes.new("Presentation backdrop");d.from_pydata([(-200,-200,-.36),(200,-200,-.36),(200,200,-.36),(-200,200,-.36)],[],[(0,1,2,3)])
    o=bpy.data.objects.new("Presentation backdrop",d);scene.collection.objects.link(o);o.data.materials.append(material("E9E3BC"))

def load_source():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE/"basic_room.blend"))
    for d in json.loads((OUT/"layout.json").read_text())["assets"]:
        c=bpy.data.collections["KIT_"+d["name"]]
        KITS[d["name"]]={"collection":c,"root":bpy.data.objects[d["name"]],"objects":[o for o in c.objects if o.type=="MESH"],"at":d["position"],"yaw":d["yaw_degrees"]}

def bake_and_export():
    scene=bpy.context.scene;scene.render.engine="CYCLES";scene.cycles.samples=16
    scene.cycles.bake_type="EMIT";scene.render.bake.margin=8;scene.render.bake.use_clear=True
    bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
    all_source=list(scene.objects)
    work=bpy.data.collections.new("TEMP_EXPORT");scene.collection.children.link(work)
    copies=[];names=list(KITS)
    for ki,name in enumerate(names):
        for source in KITS[name]["objects"]:
            ev=source.evaluated_get(deps)
            d=bpy.data.meshes.new_from_object(ev,depsgraph=deps)
            d.transform(source.matrix_world)
            attr=d.attributes.new("kit_id","INT","FACE")
            for item in attr.data:item.value=ki
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
    bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.003,area_weight=.5,correct_aspect=True,scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    joined.data.uv_layers.active.name="RoomAtlas"
    tex=bpy.data.images.new("BasicRoom_Albedo_AO",width=2048,height=2048,alpha=False)
    tex.colorspace_settings.name="sRGB"
    tex.generated_color=(.5,.5,.5,1)
    for mat in joined.data.materials:
        nt=mat.node_tree;p=nt.nodes.get("Principled BSDF");out=nt.nodes.get("Material Output")
        image=nt.nodes.new("ShaderNodeTexImage");image.image=tex;nt.nodes.active=image
        emission=nt.nodes.new("ShaderNodeEmission")
        ao=nt.nodes.new("ShaderNodeAmbientOcclusion");ao.samples=16;ao.inputs["Distance"].default_value=.68
        # Keep occluded surfaces legible; this is contact AO, not baked sun/shadows.
        mix=nt.nodes.new("ShaderNodeMixRGB");mix.blend_type="MIX";mix.inputs[0].default_value=.58
        mix.inputs[1].default_value=(1,1,1,1);nt.links.new(ao.outputs["Color"],mix.inputs[2])
        multiply=nt.nodes.new("ShaderNodeMixRGB");multiply.blend_type="MULTIPLY";multiply.inputs[0].default_value=1
        base=p.inputs["Base Color"]
        if base.is_linked:nt.links.new(base.links[0].from_socket,multiply.inputs[1])
        else:multiply.inputs[1].default_value=base.default_value
        nt.links.new(mix.outputs[0],multiply.inputs[2]);nt.links.new(multiply.outputs[0],emission.inputs[0])
        nt.links.new(emission.outputs[0],out.inputs["Surface"])
    print("BAKING_ATLAS",len(joined.data.polygons),"polygons",flush=True)
    bpy.ops.object.bake(type="EMIT")
    tex.filepath_raw=str(OUT/"room_albedo_ao.png");tex.file_format="PNG";tex.save()
    runtime=bpy.data.materials.new("BasicRoom_SharedAtlas");runtime.use_nodes=True
    n=runtime.node_tree.nodes.new("ShaderNodeTexImage");n.image=tex
    p=runtime.node_tree.nodes.get("Principled BSDF");runtime.node_tree.links.new(n.outputs["Color"],p.inputs["Base Color"])
    p.inputs["Roughness"].default_value=.80;p.inputs["Specular IOR Level"].default_value=.25
    data=joined.data;data.calc_loop_triangles();uv=data.uv_layers.active.data
    normal=data.corner_normals;kit_attr=data.attributes["kit_id"].data
    stats={"atlas":{"size":[2048,2048],"file":"room_albedo_ao.png","purpose":"base colour + static contact ambient occlusion; no baked direct light"},"assets":[]}
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
    stats["scene_triangles"]=stats["unique_triangles"]+next(a["triangles"] for a in stats["assets"] if a["name"]=="chair")
    stats["static_draw_surfaces"]=len(names)+1
    (OUT/"asset_stats.json").write_text(json.dumps(stats,indent=2)+"\n")
    print("EXPORT_READY",json.dumps({k:stats[k] for k in ["unique_triangles","scene_triangles","static_draw_surfaces"]}),flush=True)

def render():
    bpy.context.scene.render.filepath=str(QA/"blender-reference-view.png")
    bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    if "--bake-only" in ARGS or "--render-only" in ARGS:load_source()
    else:geometry()
    if "--render-only" in ARGS:render()
    elif "--geometry-only" not in ARGS:bake_and_export()
