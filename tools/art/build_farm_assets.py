"""Build the reference farm kit in Blender; export single-surface glTF assets.

Run: Blender --background --python tools/art/build_farm_assets.py
Coordinates in the modeling helpers use Godot's Y-up convention (front = +Z).
The editable source retains named component meshes; exports merge by asset.
"""

import json
import math
from pathlib import Path
import random
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/farm/art"
SOURCE = ROOT / "tools/art/source"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
random.seed(910)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
for block in list(bpy.data.collections):
    if block.name != "Collection":
        bpy.data.collections.remove(block)

COLORS = {
    "plaster": "f0edd0", "plaster_shade": "d9d4ae", "cream": "fff4d2",
    "wood": "a87948", "wood_light": "cba067", "wood_dark": "675139",
    "green": "437d64", "green_light": "6a9b6a", "glass": "82c5c6",
    "glass_dark": "548f99", "orange": "e7954e", "orange_light": "f4ad60",
    "red": "ca6452", "red_light": "df7d63", "blue": "4c86dd",
    "roof_dark": "454956", "stone": "a5ad98", "stone_light": "c4c6b1",
    "soil": "96764f", "soil_light": "af906a", "soil_dark": "785c40",
    "path": "dfcb94",
    "leaf": "6d9a44", "leaf_light": "97b75b", "leaf_dark": "4e824d",
    "grass": "afcb6c", "flower": "fff5df", "yellow": "f1ce58",
    "pink": "e68c9e", "lavender": "a7a0d2", "water": "589da5",
}


def linear(c):
    return c / 12.92 if c < 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb(name):
    h = COLORS.get(name, name)
    return tuple(linear(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4))


MATS = {}
for name in COLORS:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb(name), 1)
    mat.use_nodes = True
    p = mat.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = mat.diffuse_color
    p.inputs["Roughness"].default_value = 0.88
    p.inputs["Specular IOR Level"].default_value = 0.18
    MATS[name] = mat


def v(point):
    return Vector((point[0], -point[2], point[1]))


CURRENT = None
ASSETS = {}


def begin(name):
    global CURRENT
    CURRENT = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(CURRENT)
    ASSETS[name] = CURRENT


def finish_obj(obj, name, color, smooth=False):
    obj.name = name
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    CURRENT.objects.link(obj)
    obj.data.materials.append(MATS[color])
    if smooth:
        for face in obj.data.polygons:
            face.use_smooth = True
    return obj


def box(name, center, size, color, bevel=0.02, rotation=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=v(center))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rotation:
        obj.rotation_euler = rotation
    finish_obj(obj, name, color)
    if bevel:
        mod = obj.modifiers.new("Soft painted edges", "BEVEL")
        mod.width = min(bevel, min(size) * 0.45)
        mod.segments = 1 if min(size) < 0.065 else 2
        mod = obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
        mod.keep_sharp = True
    return obj


def ellipsoid(name, center, size, color, segments=12, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=v(center))
    obj = bpy.context.object
    obj.scale = (size[0] / 2, size[2] / 2, size[1] / 2)
    return finish_obj(obj, name, color, True)


def cylinder(name, center, radius, height, color, top=None, segments=12):
    bpy.ops.mesh.primitive_cone_add(vertices=segments, radius1=radius,
        radius2=radius if top is None else top, depth=height, location=v(center))
    return finish_obj(bpy.context.object, name, color, True)


def beam(name, start, end, width, color, depth=None):
    a, b = v(start), v(end)
    obj = box(name, (0, 0, 0), (width, (b-a).length, depth or width), color, width * 0.18 if width >= 0.04 else 0)
    obj.location = (a+b) / 2
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (b-a).to_track_quat("Z", "Y")
    return obj


def mesh(name, vertices, faces, color, smooth=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata([v(p) for p in vertices], [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    CURRENT.objects.link(obj)
    data.materials.append(MATS[color])
    for polygon in data.polygons:
        polygon.use_smooth = smooth
    return obj


def gable(width, depth, eave, peak, wall="plaster"):
    vertices = [(x, y, z) for z in [-depth/2, depth/2]
                for x, y in [(-width/2, eave), (width/2, eave), (0, peak)]]
    mesh("Solid gable plaster", vertices, [(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)], wall)


def tiled_roof(width=2.14, depth=2.06, eave=1.24, peak=1.96, color="orange", thatch=False):
    half = width / 2
    length = math.hypot(half, peak-eave)
    slope = math.atan2(peak-eave, half)
    for side in [-1, 1]:
        angle = side * slope
        roof = box("Overhanging roof", (side*half/2, (peak+eave)/2, 0),
            (length+0.06, 0.08, depth), color, 0.022)
        roof.rotation_euler.y = angle
        rows, columns = (6, 12) if thatch else (5, 9)
        for row in range(rows):
            t = (row+0.5)/rows
            for column in range(columns):
                z = -depth/2 + (column+0.5)*depth/columns
                x = side * half * t
                y = peak - (peak-eave)*t + 0.057
                shade = "wood_light" if thatch else ("orange_light" if color == "orange" else "red_light")
                tile = box("Thatch bundle" if thatch else "Overlapping clay shingle", (x,y,z),
                    (length/rows+0.038, 0.039, depth/columns-0.009),
                    shade if (row*7+column)%4 == 0 else color, 0.014)
                tile.rotation_euler.y = angle
        for front in [-1, 1]:
            beam("Roof verge", (0,peak+0.035,front*depth/2),
                (side*(half+0.045),eave+0.02,front*depth/2),0.075,
                "wood_dark" if thatch else color)
    beam("Ridge cap", (0,peak+0.08,-depth/2-0.04),(0,peak+0.08,depth/2+0.04),0.11,color)


def window(center, width=0.43, height=0.44, side=False, trim="green", shutters=True):
    x,y,z = center
    def part(name, offset, size, color, bevel=0.008):
        p = (x+offset[2], y+offset[1], z-offset[0]) if side else (x+offset[0],y+offset[1],z+offset[2])
        s = (size[2],size[1],size[0]) if side else size
        return box(name,p,s,color,bevel)
    part("Deep window surround",(0,0,0),(width+0.1,height+0.1,0.07),trim)
    part("Blue window glass",(0,0,0.043),(width,height,0.022),"glass")
    part("Window vertical muntin",(0,0,0.062),(0.027,height,0.018),"cream")
    part("Window horizontal muntin",(0,0,0.064),(width,0.025,0.018),"cream")
    part("Glazing sky reflection",(-width*0.22,height*0.25,0.058),(width*0.27,0.021,0.008),"cream",0)
    part("Window sill",(0,-height/2-0.045,0.045),(width+0.19,0.065,0.17),"wood_light")
    if shutters:
        for sign in [-1,1]:
            part("Painted shutter",(sign*(width/2+0.09),0,0.036),(0.11,height+0.06,0.025),trim)
            for k in range(4):
                part("Shutter louvre",(sign*(width/2+0.09),-height*0.32+k*height*0.21,0.054),(0.09,0.025,0.015),"green_light")


def door(x= -0.35, z=0.795, height=0.84, width=0.45, arch=False):
    box("Door frame",(x,height/2+0.10,z),(width+0.14,height+0.09,0.10),"green",0.035)
    box("Oak door",(x,height/2+0.075,z+0.06),(width,height,0.045),"wood_light",0.025)
    for k in [-1,0,1]:
        box("Door plank groove",(x+k*width*0.23,height/2+0.06,z+0.086),(0.008,height*0.88,0.008),"wood",0)
    ellipsoid("Brass door handle",(x+width*0.30,height*0.47,z+0.105),(0.043,0.043,0.03),"yellow",8,6)
    box("Doorstep",(x,0.066,z+0.16),(width+0.25,0.12,0.35),"stone_light",0.05)
    if arch:
        ellipsoid("Arched door crown",(x,height+0.06,z+0.015),(width+0.14,0.35,0.12),"green")
        ellipsoid("Arched oak inset",(x,height+0.045,z+0.081),(width,0.27,0.035),"wood_light")


def chimney(x=-0.53, z=-0.37, bottom=1.62):
    box("Stone chimney",(x,bottom+0.18,z),(0.23,0.49,0.25),"stone",0.025)
    for level in range(3):
        box("Chimney masonry seam",(x,bottom+level*0.12,z+0.131),(0.215,0.016,0.009),"stone_light",0)
    box("Chimney lip",(x,bottom+0.44,z),(0.31,0.07,0.32),"stone_light",0.018)
    box("Chimney opening",(x,bottom+0.478,z),(0.18,0.008,0.18),"roof_dark",0)


def foundation(width=1.84, depth=1.78, wall="plaster"):
    box("Rounded stone foundation",(0,0.065,0),(width,0.13,depth),"stone",0.055)
    box("Main wall finish",(0,0.665,0),(width-0.13,1.08,depth-0.14),wall,0.045)
    box("Plaster base course",(0,0.205,0),(width-0.09,0.16,depth-0.10),"plaster_shade",0.03)


def cottage():
    begin("house_cottage")
    foundation()
    gable(1.71,1.64,1.2,1.94)
    tiled_roof()
    door()
    window((0.49,0.76,0.83),0.37,0.4)
    window((0.87,0.74,-0.12),0.48,0.44,True)
    for x in [-0.815,0.815]:
        box("Corner timber",(x,0.68,0.835),(0.07,1.04,0.075),"green_light",0.012)
    chimney()


def lathe(name, profile, color, segments=32):
    vertices = []
    for radius,height in profile:
        for i in range(segments):
            a = i*math.tau/segments
            vertices.append((math.cos(a)*radius,height,math.sin(a)*radius))
    faces = []
    for row in range(len(profile)-1):
        for i in range(segments):
            a = row*segments+i
            b = row*segments+(i+1)%segments
            faces.append((a,b,b+segments,a+segments))
    faces.append(tuple(reversed(range(segments))))
    faces.append(tuple((len(profile)-1)*segments+i for i in range(segments)))
    return mesh(name,vertices,faces,color,True)


def mushroom():
    begin("house_mushroom")
    cylinder("Circular stone footing",(0,0.075,0),0.84,0.15,"stone",segments=28)
    cylinder("Round stucco stem",(0,0.64,0),0.73,1.07,"plaster",0.64,28)
    lathe("Sculpted mushroom cap",[(0.04,2.03),(0.26,2.0),(0.57,1.87),(0.86,1.66),(1.04,1.43),(1.06,1.32),(0.99,1.27),(0.74,1.29),(0.01,1.34)],"red",36)
    profile=[(0,2.03),(0.26,2.0),(0.57,1.87),(0.86,1.66),(1.04,1.43),(1.065,1.34)]
    def cap_height(radius):
        for (ra,ha),(rb,hb) in zip(profile,profile[1:]):
            if radius<=rb:
                return ha+(hb-ha)*(radius-ra)/(rb-ra)
        return 1.34
    for i in range(14):
        angle = i*2.399
        r = 0.25+0.67*((i%5)/4)
        cx,cz=math.cos(angle)*r,math.sin(angle)*r
        vertices=[(cx,cap_height(r)+0.014,cz)]
        for k in range(16):
            a=k*math.tau/16
            x=cx+math.cos(a)*(0.09+(i%3)*0.018)
            z=cz+math.sin(a)*(0.10+(i%3)*0.016)
            vertices.append((x,cap_height(math.hypot(x,z))+0.014,z))
        mesh("Painted ivory cap spot",vertices,[(0,(k+1)%16+1,k+1) for k in range(16)],"cream",True)
    door(-0.13,0.72,0.72,0.40,True)
    window((0.66,0.71,-0.11),0.33,0.35,True,shutters=False)
    chimney(-0.46,-0.34,1.73)


def timber():
    begin("house_thatch")
    foundation()
    gable(1.71,1.64,1.2,2.05)
    tiled_roof(2.16,2.12,1.18,2.08,"wood_light",True)
    for x in [-0.81,0,0.81]:
        box("Half timber upright",(x,0.69,0.843),(0.10,1.14,0.08),"wood_dark",0.012)
    for y in [0.26,0.66,1.12]:
        box("Half timber cross rail",(0,y,0.85),(1.74,0.085,0.07),"wood_dark",0.009)
        box("Side timber cross rail",(0.86,y,0),(0.07,0.085,1.63),"wood_dark",0.009)
    for x in [-0.57,-0.28,0.28,0.57]:
        top=2.04-abs(x)*0.98
        beam("Gable timber",(x,1.22,0.837),(x,top,0.837),0.055,"wood_dark")
    for y in [1.35,1.55,1.75]:
        width=(2.04-y)*1.92
        box("Gable horizontal rail",(0,y,0.85),(width,0.07,0.07),"wood_dark",0.008)
    door(-0.39,0.88,0.81,0.42)
    window((0.43,0.79,0.875),0.32,0.33,shutters=False)
    window((0.88,0.77,-0.10),0.43,0.36,True,shutters=False)
    chimney(-0.50,-0.35,1.77)


def dome():
    begin("house_dome")
    foundation(1.83,1.74)
    box("Upper white parapet",(0,1.24,0),(1.78,0.21,1.69),"cream",0.09)
    lathe("Blue ceramic dome",[(0,2.06),(0.23,2.03),(0.43,1.91),(0.59,1.74),(0.68,1.52),(0.69,1.32),(0,1.32)],"blue",36)
    for x in [-0.77,0.77]:
        box("Rounded parapet corner",(x,1.29,0.72),(0.22,0.29,0.23),"cream",0.095)
    door(-0.23,0.83,0.76,0.44,True)
    window((0.51,0.77,0.84),0.27,0.36,trim="blue",shutters=False)
    window((0.87,0.77,-0.14),0.39,0.46,True,trim="blue",shutters=False)
    for i in range(5):
        box("Foundation stone",(-0.65+i*0.31,0.18,0.836),(0.25,0.17,0.045),"stone_light",0.03)
    chimney(-0.57,-0.36,1.76)


def east_asian():
    begin("house_east_asian")
    foundation(1.92,1.83)
    box("Timber porch",(0,0.16,0.85),(2.02,0.16,0.43),"wood",0.026)
    for x in [-0.88,-0.32,0.31,0.88]:
        box("Porch post",(x,0.79,0.88),(0.09,1.28,0.09),"wood_dark",0.016)
    for y in [0.27,0.75,1.20]:
        box("Facade rail",(0,y,0.873),(1.89,0.09,0.075),"wood_dark",0.01)
    door(-0.01,0.90,0.81,0.44)
    for x in [-0.58,0.58]:
        window((x,0.83,0.88),0.32,0.53,trim="wood_dark",shutters=False)
    window((0.94,0.78,-0.17),0.49,0.49,True,trim="wood_dark",shutters=False)
    # Curved slopes rise again at the eaves; rounded ribs carry the silhouette.
    for side in [-1,1]:
        vertices=[]
        rows=8
        for z in [-1.08,1.08]:
            for i in range(rows+1):
                t=i/rows
                y=2.04-1.05*t+0.40*t*t+0.17*t**8
                vertices.append((side*1.17*t,y,z))
        faces=[(i,i+1,i+1+rows+1,i+rows+1) for i in range(rows)]
        if side==1:
            faces=[tuple(reversed(face)) for face in faces]
        roof=mesh("Sweeping tiled roof",vertices,faces,"roof_dark",True)
        solid=roof.modifiers.new("Roof thickness","SOLIDIFY")
        solid.thickness=0.065
        for k in range(15):
            z=-1.07+k*2.14/14
            for i in range(rows):
                a=i/rows
                b=(i+1)/rows
                beam("Glazed tile rib",(side*1.17*a,2.075-1.05*a+0.4*a*a+0.17*a**8,z),
                    (side*1.17*b,2.075-1.05*b+0.4*b*b+0.17*b**8,z),0.025,"roof_dark")
    beam("Roof ridge",(0,2.09,-1.13),(0,2.09,1.13),0.095,"roof_dark")
    for z in [-1.13,1.13]:
        beam("Raised ridge finial",(0,2.09,z*0.86),(0,2.24,z),0.075,"roof_dark")
    chimney(-0.48,-0.34,1.79)


def barn():
    begin("house_barn")
    foundation(2.02,1.85,"wood")
    box("Barn upper storey",(0,1.29,0),(1.90,0.66,1.70),"wood",0.018)
    gable(1.9,1.70,1.53,2.14,"wood")
    tiled_roof(2.29,2.12,1.52,2.18,"red")
    for x in [-0.88,-0.58,-0.28,0,0.28,0.58,0.88]:
        box("Barn weatherboard",(x,0.74,0.866),(0.025,1.35,0.023),"wood_light",0.003)
    for x in [-0.94,0.94]:
        box("White corner post",(x,0.86,0.875),(0.09,1.49,0.09),"cream",0.012)
    for x in [-0.28,0.28]:
        box("Barn door",(x,0.59,0.897),(0.50,0.95,0.035),"wood_dark",0.012)
        for sign in [-1,1]:
            beam("Barn door cross brace",(x-0.22,0.16 if sign==1 else 1.02,0.922),
                (x+0.22,1.02 if sign==1 else 0.16,0.922),0.037,"cream")
    window((0,1.76,0.88),0.27,0.28,trim="cream",shutters=False)
    window((0.965,0.89,-0.13),0.50,0.46,True,shutters=False)
    chimney(-0.57,-0.35,1.98)


def windmill():
    begin("house_windmill")
    foundation(1.91,1.79,"green")
    box("Sage mill siding",(0,0.74,0),(1.79,1.19,1.64),"green",0.025)
    gable(1.79,1.64,1.31,1.98,"green")
    tiled_roof(2.14,2.07,1.26,2.02,"red")
    for x in [-0.84,0.84]:
        box("Mill white corner",(x,0.75,0.85),(0.08,1.25,0.085),"cream",0.01)
    for y in [0.25,0.68,1.19]:
        box("Mill horizontal trim",(0,y,0.852),(1.76,0.05,0.06),"cream",0.008)
    door(-0.34,0.88,0.83,0.45)
    window((0.45,0.87,0.855),0.32,0.35,shutters=False)
    window((0.91,0.85,-0.12),0.44,0.43,True,shutters=False)
    box("Windmill tower",(0,1.91,0.75),(0.75,1.05,0.69),"red",0.035)
    cylinder("Tower cap",(0,2.54,0.75),0.56,0.38,"red",0.04,12)
    cylinder("Rotor axle",(0,2.26,1.19),0.065,0.20,"wood_dark",segments=12).rotation_euler.x=math.pi/2
    chimney(-0.62,-0.35,1.66)

    begin("windmill_sails")
    for k in range(4):
        a=k*math.pi/2+0.35
        def p(r,w=0):
            return (math.sin(a)*r+math.cos(a)*w,math.cos(a)*r-math.sin(a)*w,0)
        beam("Sail spar",p(0.03),p(1.0),0.055,"wood")
        for w in [0,0.30]:
            beam("Sail frame",p(0.37,w),p(1.0,w),0.026,"wood_light")
        for r in [0.38,0.58,0.78,0.98]:
            beam("Sail cross rail",p(r,0),p(r,0.30),0.024,"wood_light")
        canvas=mesh("Canvas sail",[p(0.39,0.035),p(0.99,0.035),p(0.99,0.27),p(0.39,0.27)],[(0,1,2,3)],"cream")
        canvas.modifiers.new("Canvas thickness","SOLIDIFY").thickness=0.006
    ellipsoid("Rotor wooden hub",(0,0,0.015),(0.20,0.20,0.16),"wood_dark")


def props():
    begin("well")
    cylinder("Well footing",(0,0.03,0),0.34,0.06,"stone",segments=20)
    for row in range(2):
        for k in range(12):
            a=(k+row*0.5)*math.tau/12
            obj=box("Well stone block",(math.cos(a)*0.266,0.13+row*0.14,math.sin(a)*0.266),(0.145,0.13,0.115),
                "stone_light" if k%3 else "stone",0.025)
            obj.rotation_euler.z=-a+math.pi/2
    cylinder("Water surface",(0,0.16,0),0.23,0.008,"water",segments=24)
    for x in [-0.26,0.26]:
        box("Well roof post",(x,0.49,-0.025),(0.055,0.77,0.058),"wood",0.01)
    beam("Well spindle",(-0.32,0.56,0),(0.33,0.56,0),0.065,"wood_dark")
    beam("Hanging rope",(0,0.56,0),(0,0.25,0),0.012,"wood_light")
    for side in [-1,1]:
        obj=box("Teal well canopy",(side*0.195,0.87,0),(0.45,0.047,0.69),"green",0.025)
        obj.rotation_euler.y=side*0.37
        for k in range(5):
            beam("Canopy seam",(side*0.015,0.97,-0.28+k*0.14),(side*0.40,0.82,-0.28+k*0.14),0.012,"green_light")
    cylinder("Bucket",(0.39,0.088,0.19),0.07,0.16,"wood",0.085)
    cylinder("Bucket rim",(0.39,0.17,0.19),0.087,0.025,"wood_dark")

    begin("storage")
    box("Seed chest",(0,0.23,0),(0.58,0.43,0.50),"wood_light",0.033)
    box("Chest lid",(0,0.46,0),(0.64,0.085,0.56),"wood_light",0.025)
    for y in [0.12,0.26,0.39]:
        box("Chest board joint",(0,y,0.257),(0.54,0.011,0.011),"wood",0)
    for x in [-0.21,0.21]:
        box("Iron chest band",(x,0.25,0.261),(0.04,0.45,0.022),"green",0.006)
        box("Iron lid band",(x,0.507,0),(0.04,0.02,0.54),"green",0.004)
    box("Chest latch",(0,0.39,0.28),(0.07,0.12,0.035),"yellow",0.009)

    begin("plot")
    # Rounded outlines are modeled in plan, keeping the top exactly at y = 0.15.
    rounded_slab("Soft earthen bed",0.94,0.94,0.15,0.14,"soil")
    rounded_slab("Topsoil",0.86,0.86,0.012,0.12,"soil_light",0.139)
    for k in range(16):
        x=random.uniform(-0.37,0.37)
        z=random.uniform(-0.37,0.37)
        ellipsoid("Soil crumb",(x,0.151,z),(0.016,0.008,0.026),"soil" if k%2 else "soil_dark",6,4)

    begin("path_tile")
    rounded_slab("Garden sand",1.27,1.27,0.009,0.06,"path")

    begin("stepping_stone")
    rounded_slab("Worn stepping stone",0.31,0.24,0.045,0.08,"stone_light")

    begin("fence")
    for x in [-0.62,0.62]:
        box("White fence post",(x,0.34,0),(0.075,0.65,0.075),"cream",0.02)
        cylinder("Fence post cap",(x,0.68,0),0.063,0.11,"cream",0,4)
    for y in [0.27,0.49]:
        beam("Fence rail",(-0.64,y,0),(0.64,y,0),0.043,"cream")

    begin("sign")
    for x in [-0.21,0.21]:
        beam("Noticeboard leg",(x,0,0.12),(x,0.74,-0.02),0.045,"wood_light")
    box("Garden sign frame",(0,0.56,0),(0.57,0.41,0.062),"wood_light",0.028)
    box("Garden sign face",(0,0.56,0.038),(0.49,0.33,0.02),"cream",0.013)
    box("Sign sky",(0,0.605,0.052),(0.39,0.16,0.004),"glass",0)
    ellipsoid("Painted sun",(0.11,0.65,0.06),(0.07,0.07,0.005),"yellow",8,6)
    box("Sign field",(0,0.49,0.056),(0.39,0.07,0.008),"green_light",0.005)
    for x in [-0.1,0,0.1]:
        beam("Painted garden sprout",(x,0.49,0.065),(x+0.025,0.565,0.065),0.015,"leaf")


def rounded_slab(name,width,depth,height,radius,color,base=0):
    outline=[]
    for x,z,a in [(1,1,0),(-1,1,90),(-1,-1,180),(1,-1,270)]:
        for k in range(5):
            angle=math.radians(a+k*90/4)
            outline.append((x*(width/2-radius)+math.cos(angle)*radius,z*(depth/2-radius)+math.sin(angle)*radius))
    vertices=[(x,base+y,z) for y in [0,height] for x,z in outline]
    n=len(outline)
    faces=[tuple(range(n)),tuple(reversed(range(n,n*2)))]
    faces.extend((i,i+n,(i+1)%n+n,(i+1)%n) for i in range(n))
    obj=mesh(name,vertices,faces,color)
    bevel=obj.modifiers.new("Rolled soil edges","BEVEL")
    bevel.width=min(0.035,height*0.35)
    bevel.segments=2
    obj.modifiers.new("Soft normals","WEIGHTED_NORMAL")
    return obj


def vegetation():
    for variant in range(3):
        begin("tree_%d" % variant)
        cylinder("Tapered tree trunk",(0,0.68,0),0.12,1.36,"wood",0.074,10)
        for k in range(3):
            a=k*2.1+variant
            beam("Tree branch",(0,0.78,0),(math.cos(a)*0.42,1.37,math.sin(a)*0.42),0.072,"wood")
        for center,size,color in [((0,1.78,0),(1.44,1.80,1.33),"leaf"),
                ((-0.43,1.52,0.11),(0.94,1.24,0.97),"leaf_light"),
                ((0.44,1.62,-0.17),(0.97,1.40,1.02),"leaf")]:
            ellipsoid("Rounded orchard canopy",center,tuple(s*(1+variant*0.045) for s in size),color,16,10)
        for k in range(4):
            a=k*1.7
            ellipsoid("Grass at tree roots",(math.cos(a)*0.16,0.12,math.sin(a)*0.16),(0.37,0.29,0.35),"leaf_light",10,6)

    begin("bush")
    for k in range(5):
        a=k*2.4
        ellipsoid("Hedge foliage",(math.cos(a)*0.20,0.24+(k%2)*0.08,math.sin(a)*0.16),
            (0.47,0.52,0.46),"leaf_light" if k%2 else "leaf",12,8)

    begin("rock")
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=v((0,0.14,0)))
    obj=finish_obj(bpy.context.object,"Rounded fieldstone","stone")
    obj.scale=(0.24,0.18,0.19)
    bevel=obj.modifiers.new("Worn stone edges","BEVEL")
    bevel.width=0.09
    bevel.segments=2
    obj.modifiers.new("Stone normals","WEIGHTED_NORMAL")

    begin("grass_clump")
    for k in range(6):
        a=k*2.4
        r=Vector((math.cos(a),0,math.sin(a)))
        side=Vector((-math.sin(a),0,math.cos(a)))
        base=r*0.025
        mid=r*0.055+Vector((0,0.10+(k%3)*0.015,0))
        tip=r*0.12+Vector((0,0.18+(k%3)*0.025,0))
        blade=mesh("Curved grass blade",[base-side*0.016,base+side*0.016,mid+side*0.020,tip,mid-side*0.020],
            [(0,1,2,4),(4,2,3)],"leaf_light" if k%2 else "grass")
        blade.modifiers.new("Blade thickness","SOLIDIFY").thickness=0.002

    for variant,color in [("daisy","flower"),("pink_flower","pink"),("blue_flower","lavender")]:
        begin(variant)
        for k in range(3):
            x,z=(k-1)*0.095,((k%2)-0.5)*0.11
            h=0.13+(k%2)*0.075
            beam("Flower stem",(x,0,z),(x,h,z),0.009,"leaf")
            for p in range(5):
                a=p*math.tau/5
                ellipsoid("Flower petal",(x+math.cos(a)*0.037,h,z+math.sin(a)*0.037),(0.052,0.018,0.043),color,6,4)
            ellipsoid("Flower heart",(x,h+0.012,z),(0.031,0.021,0.031),"yellow",8,4)


def export_asset(name, collection):
    bpy.ops.object.select_all(action="DESELECT")
    copies=[]
    depsgraph=bpy.context.evaluated_depsgraph_get()
    for source in collection.objects:
        data=bpy.data.meshes.new_from_object(source.evaluated_get(depsgraph),depsgraph=depsgraph)
        obj=bpy.data.objects.new(source.name+"_export",data)
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
    # Export origins are always the game-space anchor, including the separate rotor.
    bpy.context.scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    data=obj.data
    data.calc_loop_triangles()
    tree=BVHTree.FromPolygons([p.co for p in data.vertices], [list(p.vertices) for p in data.polygons])
    attr=data.color_attributes.new(name="Color",type="FLOAT_COLOR",domain="CORNER")
    data.color_attributes.active_color=attr
    data.color_attributes.render_color_index=0
    # Short deterministic ambient-occlusion rays bake contact depth into vertex color.
    # Runtime needs one opaque material, no SSAO or lightmaps.
    ao={}
    for face in data.polygons:
        color=data.materials[face.material_index].diffuse_color[:3]
        for index in face.loop_indices:
            loop=data.loops[index]
            key=(loop.vertex_index,tuple(round(n,2) for n in data.corner_normals[index].vector))
            if key not in ao:
                normal=data.corner_normals[index].vector.normalized()
                origin=data.vertices[loop.vertex_index].co+normal*0.008
                tangent=normal.cross(Vector((0,0,1)))
                if tangent.length<0.01:
                    tangent=normal.cross(Vector((1,0,0)))
                tangent.normalize()
                bitangent=normal.cross(tangent)
                hits=0.0
                for ray in range(8):
                    a=ray*2.399
                    r=math.sqrt((ray+0.5)/8)*0.88
                    direction=(normal*math.sqrt(1-r*r)+tangent*(math.cos(a)*r)+bitangent*(math.sin(a)*r)).normalized()
                    result=tree.ray_cast(origin,direction,0.38)
                    if result[0] is not None:
                        hits+=1-result[3]/0.38
                ao[key]=1-0.38*hits/8
            shade=ao[key]
            attr.data[index].color=(*(c*shade for c in color),1)
    data.materials.clear()
    material=bpy.data.materials.get("Farm vertex paint")
    if material is None:
        material=bpy.data.materials.new("Farm vertex paint")
        material.use_nodes=True
        nodes=material.node_tree.nodes
        shader=nodes.get("Principled BSDF")
        shader.inputs["Roughness"].default_value=0.9
        shader.inputs["Specular IOR Level"].default_value=0.16
        vertex=nodes.new("ShaderNodeVertexColor")
        vertex.layer_name="Color"
        material.node_tree.links.new(vertex.outputs["Color"],shader.inputs["Base Color"])
    data.materials.append(material)
    for face in data.polygons:
        face.material_index=0
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+".glb")),export_format="GLB",use_selection=True,
        export_yup=True,export_materials="EXPORT",export_attributes=False,
        export_cameras=False,export_lights=False,export_animations=False)
    triangles=len(data.loop_triangles)
    bounds=[min(p.co[i] for p in data.vertices) for i in range(3)], [max(p.co[i] for p in data.vertices) for i in range(3)]
    bpy.data.objects.remove(obj,do_unlink=True)
    bpy.data.meshes.remove(data)
    return {"triangles":triangles,"surfaces":1,"bytes":(OUT/(name+".glb")).stat().st_size,
            "bounds_blender":bounds}


def lawn_texture():
    size=512
    rng=np.random.default_rng(910)
    noise=np.zeros((size,size))
    ky,kx=np.meshgrid(np.fft.fftfreq(size),np.fft.rfftfreq(size),indexing="ij")
    # Isotropic, tileable color washes avoid the old diagonal sine-wave bands.
    for freq,weight in [(3,0.52),(9,0.28),(28,0.14),(85,0.06)]:
        spectrum=np.fft.rfft2(rng.normal(size=(size,size)))
        field=np.fft.irfft2(spectrum*np.exp(-(kx*kx+ky*ky)*(size/freq)**2),s=(size,size))
        noise+=field/max(field.std(),0.0001)*weight
    base=np.array([0.60,0.74,0.37])
    pixels=np.ones((size,size,4),dtype=np.float32)
    pixels[:,:,:3]=np.clip(base+noise[:,:,None]*np.array([0.048,0.039,0.035]),0,1)
    image=bpy.data.images.new("Meadow painted color",width=size,height=size,alpha=False)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw=str(OUT/"meadow.png")
    image.file_format="PNG"
    image.save()


cottage()
mushroom()
timber()
dome()
east_asian()
barn()
windmill()
props()
vegetation()
lawn_texture()
manifest={"generator":"tools/art/build_farm_assets.py","reference":"20260910-110510.jpeg",
    "units":"meters","front":"+Z in Godot","assets":{}}
only=set(sys.argv[sys.argv.index("--only")+1].split(",")) if "--only" in sys.argv else set()
if only and (OUT/"manifest.json").exists():
    manifest=json.loads((OUT/"manifest.json").read_text())
for name,collection in ASSETS.items():
    if only and name not in only:
        continue
    manifest["assets"][name]=export_asset(name,collection)
    print("FARM_ASSET",name,manifest["assets"][name]["triangles"],flush=True)
(OUT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
# Arrange the source as a contact sheet without baking presentation transforms into exports.
for index,(name,collection) in enumerate(ASSETS.items()):
    for obj in collection.objects:
        obj.location+=Vector(((index%7)*3.3,(index//7)*3.8,0))
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/"farm_reference_kit.blend"))
print("FARM_KIT_DONE",len(ASSETS),flush=True)
