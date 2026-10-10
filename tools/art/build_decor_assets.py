"""SGODOT-290: reproducible, untextured farm decorations (Blender 5.2).

blender --background --factory-startup --python /absolute/path/to/this_file.py
Godot coordinates: metres, Y up, +Z front. One merged mesh/surface per GLB.
Source objects remain named and editable; only evaluated export copies join.
No existing farm models/materials are rebuilt. See source/decor_290/README.md.
"""
import json
import math
import struct
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/farm/art"
SOURCE = ROOT / "tools/art/source/decor_290"
PALETTE = {
    "wood": "a87948", "wood_light": "cba067", "wood_dark": "675139",
    "cream": "f5efda", "cream_shade": "dbd5bf",
    "stone": "b4b4a5", "stone_light": "d7d4c3", "stone_shade": "969b92",
    "leaf": "6d9a44", "leaf_light": "97b75b", "leaf_dark": "4e824d",
    "pink": "e68c9e", "pink_light": "f2b6bd", "flower": "fff5df",
    "lavender": "a7a0d2", "yellow": "f1ce58", "straw": "d6af64",
    "straw_light": "ebc982", "soil": "785c40", "metal": "5f5949",
    "glass": "fff1c7", "glass_shade": "e9ddba",
    "shirt": "7e9568", "shirt_shade": "667f59", "burlap": "ceb17d",
    "water": "82bbc5", "water_light": "a5d1d3", "red": "ca6452",
    "red_light": "df7d63", "bird": "7194a9", "bird_shade": "506f85",
}


def rgb(h):
    values = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c < .04045 else ((c + .055) / 1.055) ** 2.4 for c in values)


def v(p):
    return Vector((p[0], -p[2], p[1]))


MATS, ASSETS, META = {}, {}, {}
CURRENT = None


def begin(name, cells, budget, **metadata):
    global CURRENT
    CURRENT = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(CURRENT)
    ASSETS[name] = CURRENT
    META[name] = {"generator": "tools/art/build_decor_assets.py", "footprint_cells": cells,
                  "triangle_limit": budget, "pivot": "floor / footprint centre",
                  "sockets": {}, **metadata}


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


def ellipsoid(name, at, size, color, segments=8, rings=4):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=v(at))
    obj = bpy.context.object
    obj.scale = (size[0]/2, size[2]/2, size[1]/2)
    return finish(obj, name, color, True)


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


def lathe(name, profile, color, segments=20, at=(0, 0, 0)):
    verts = [(at[0]+r*math.cos(i*math.tau/segments), at[1]+y,
              at[2]+r*math.sin(i*math.tau/segments)) for r, y in profile for i in range(segments)]
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


def flower(name, at, radius, color, tilt=.35, yaw=0):
    from mathutils import Euler
    orientation=Euler((tilt,0,yaw)).to_matrix()
    for i in range(5):
        a=i*math.tau/5
        obj=ellipsoid(name+" rounded petal",(0,0,0),(radius*.65,.026,radius*1.05),color,6,3)
        obj.location=v(at)+orientation@v((math.sin(a)*radius*.47,0,math.cos(a)*radius*.47))
        obj.rotation_euler=(orientation@Euler((0,0,a)).to_matrix()).to_euler()
    core = ellipsoid(name+" pollen", (0, 0, 0), (radius*.50, .017, radius*.50), "yellow", 6, 3)
    core.location = v(at)+orientation@v((0,.019,0))
    core.rotation_euler = orientation.to_euler()


def socket(name, at):
    obj = bpy.data.objects.new(name, None)
    CURRENT.objects.link(obj)
    obj.empty_display_type = "ARROWS"
    obj.empty_display_size = .10
    obj.location = v(at)
    # Export glTF empties with identity game-space rotation (+Z front).
    obj.rotation_euler = (0, 0, 0)
    META[CURRENT.name]["sockets"][name] = {"position": list(at), "front": "+Z"}


def planter():
    begin("deco_planter", [1, 1], 2000)
    for x in [-.235, .235]:
        for z in [-.235, .235]:
            box("Planter corner foot", (x, .125, z), (.09, .25, .09), "wood_light")
    for level in [.08, .17]:
        for sign in [-1, 1]:
            box("Planter front rear board", (0, level, sign*.237), (.45, .082, .047), "wood")
            box("Planter side board", (sign*.237, level, 0), (.047, .082, .45), "wood_light")
    box("Recessed dark soil", (0, .198, 0), (.43, .026, .43), "soil", .008)
    for i, (x,z) in enumerate([(-.14,-.13),(.13,-.13),(-.16,.11),(.15,.12),(0,0)]):
        ellipsoid("Leaf cushion", (x,.28,z), (.22,.20,.23), "leaf" if i%2 else "leaf_dark")
    for i in range(12):
        a=i*math.tau/12
        leaf("Planter broad leaf", (.19*math.cos(a), .285+.025*(i%3), .19*math.sin(a)), .15,.075,
             "leaf_light" if i%3==0 else "leaf", -a, .2)
    for i, (x,y,z) in enumerate([(-.16,.39,.1),(.13,.39,.12),(-.10,.40,-.1),(.13,.39,-.09),(0,.365,.22)]):
        flower("Pastel flower %d"%i, (x,y,z), .065, ["pink","flower","pink_light","flower","lavender"][i], .45, i*.6)


def lantern():
    begin("deco_lantern", [1,1], 2000)
    box("Lantern grounded post", (-.17,.58,0), (.115,1.16,.115), "wood_light", .022)
    box("Lantern top beam", (.005,1.105,0), (.44,.105,.11), "wood_light", .018)
    beam("Lantern diagonal brace", (-.125,.91,0), (.065,1.06,0), .055,"wood",radius=.008)
    rod("Lantern hanging pin",(.105,1.095,0),(.105,.995,0),.013,"metal",8)
    box("Lantern lower frame",(.105,.721,0),(.235,.04,.215),"metal")
    box("Milk glass body",(.105,.846,0),(.173,.22,.154),"glass",.008)
    for x in [.008,.202]:
        for z in [-.087,.087]:
            box("Lantern metal corner",(x,.85,z),(.019,.25,.019),"metal",.002)
    cap=lathe("Lantern shallow cap",[(.17,.976),(.169,.987),(.060,1.025),(.040,1.025)],"metal",4)
    cap.rotation_euler.z=math.pi/4
    cap.location=v((.105,0,0))
    socket("glow",(.105,.848,0))


def path():
    begin("deco_path",[1,1],500, purchase_instances=5)
    n=12
    outline=[(.268*math.cos(i*math.tau/n)*(1+.045*math.sin(i*2.4)),
              .243*math.sin(i*math.tau/n)*(1+.045*math.cos(i*1.7))) for i in range(n)]
    verts=[(x*s,y,z*s) for s,y in [(.91,0),(1,.009),(1,.021),(.95,.033)] for x,z in outline]
    faces=[tuple(reversed(range(n))),tuple(range(3*n,4*n))]
    for j in range(3):
        faces.extend((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for i in range(n))
    obj=mesh("Single soft irregular stepping stone",verts,faces,"stone")
    obj.data.materials.append(MATS["stone_shade"])
    for p in obj.data.polygons:
        if p.center.z<.021: p.material_index=1


def bench():
    begin("deco_bench",[2,1],2000, seat_height=.67)
    for x in [-.49,.49]:
        for z in [-.22,.22]:
            height=.84 if z<0 else .635
            box("Bench rear upright" if z<0 else "Bench front leg",(x,height/2,z),(.09,height,.09),"wood")
        box("Bench seat bearer",(x,.57,0),(.085,.08,.53),"wood_dark")
        box("Bench armrest",(x,.73,0),(.13,.07,.55),"wood_light")
        beam("Bench front arm support",(x,.62,.20),(x,.715,.20),.065,"wood",radius=.007)
    for z in [-.18,0,.18]:
        box("Bench seat plank",(0,.6325,z),(1.10,.075,.169),"wood_light",.014)
    for y in [.744,.835]:
        box("Bench broad back plank",(0,y,-.24),(1.10,.08,.055),"wood_light",.012)
    box("Bench lower stretcher",(0,.25,-.05),(1.04,.065,.075),"wood",.011)
    socket("seat_0",(-.275,.67,.035))
    socket("seat_1",(.275,.67,.035))


def scarecrow():
    begin("deco_scarecrow",[1,1],2000, silhouette_exception="hands may reach 0.85 m; actual width in bounds")
    box("Scarecrow planting stake",(0,.50,-.028),(.072,1.0,.072),"wood",.011)
    lathe("Sage patchwork shirt",[(.11,.68),(.17,.73),(.18,.86),(.16,1.055),(.12,1.08)],"shirt",12)
    for sign in [-1,1]:
        rod("Downward shirt sleeve",(sign*.12,1.0,0),(sign*.31,.90,0),.085,"shirt",8,top=.07)
        rod("Sleeve cuff",(sign*.292,.908,0),(sign*.322,.893,0),.077,"shirt_shade",8)
        for j in range(3):
            rod("Wrist straw",(sign*.322,.895,(j-1)*.035),(sign*(.39-.009*j),.858+j*.025,(j-1)*.048),.018,"straw_light",5)
    for i in range(7):
        a=i*math.tau/7
        rod("Hem straw",(.11*math.cos(a),.74,.09*math.sin(a)),(.135*math.cos(a),.665,.11*math.sin(a)),.019,"straw",5)
    ellipsoid("Round burlap smile face",(0,1.19,.012),(.28,.29,.252),"burlap",12,6)
    for x in [-.054,.054]:
        ellipsoid("Sewn dark eye",(x,1.219,.130),(.022,.026,.011),"wood_dark",6,3)
    ellipsoid("Little cloth nose",(0,1.181,.146),(.029,.039,.021),"straw",6,3)
    for i in range(5):
        x=(i-2)*.020
        y=1.134+.23*x*x/.05
        rod("Smile stitch",(x-.008,y+.004,.13),(x+.008,y-.003,.13),.0035,"wood_dark",4)
    brim=lathe("Soft straw hat brim",[(.10,1.298),(.234,1.302),(.247,1.322),(.225,1.344),(.135,1.355)],"straw_light",16)
    brim.scale.y=.76  # Shorter front/back brim keeps the sewn smile readable at 43 degrees.
    lathe("Straw hat crown",[(.137,1.33),(.137,1.37),(.108,1.482),(.096,1.495)],"straw",12)
    lathe("Sage hat ribbon",[(.139,1.352),(.135,1.388),(.132,1.395)],"shirt_shade",12)
    box("Pale shirt patch",(.086,.806,.158),(.071,.069,.008),"straw_light",.005)
    rod("Shirt seam",(0,.755,.176),(0,1.0,.168),.003,"shirt_shade",4)
    for y in [.87,.95]:
        ellipsoid("Wood button",(0,y,.179),(.018,.018,.008),"wood_dark",6,3)
    for sign in [-1,1]:
        beam("Ochre neckerchief tail",(0,1.069,.126),(sign*.026,1.005,.168),.028,"straw",depth=.010,radius=.002)


def fence():
    begin("deco_fence",[1,1],500,purchase_instances=6,seam_axis="X",repeat_step=.65)
    # Flat-cut ends: two neighbouring half-posts form one complete square post.
    for sign in [-1,1]:
        x0,x1=((- .325,-.28) if sign<0 else (.28,.325))
        verts=[(x,y,z) for y in [0,.555] for z in [-.045,.045] for x in [x0,x1]]
        verts += [(x0,.59,-.025),(x1,.59,-.025),(x0,.59,.025),(x1,.59,.025)]
        mesh("Fence half end post",verts,[(0,1,3,2),(0,4,5,1),(2,3,7,6),(0,2,6,10,8,4),
             (1,5,9,11,7,3),(4,8,9,5),(6,7,11,10),(8,10,11,9)],"cream_shade")
    for y in [.19,.40]:
        box("Fence horizontal rail",(0,y,-.024),(.65,.055,.04),"cream_shade",.005)
    for x in [-.19,0,.19]:
        points=[(x-.054,.07),(x+.054,.07),(x+.054,.48),(x,.55),(x-.054,.48)]
        verts=[(xx,yy,z) for z in [-.021,.025] for xx,yy in points]
        faces=[tuple(reversed(range(5))),tuple(range(5,10))]
        faces += [(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)]
        bevel(mesh("White pointed fence picket",verts,faces,"cream"),.004)


def birdbath():
    begin("deco_birdbath",[1,1],2000)
    lathe("Birdbath stepped foot",[(.16,0),(.18,.02),(.18,.075),(.14,.10),(.11,.11)],"stone",20)
    lathe("Birdbath slender pedestal",[(.115,.095),(.12,.14),(.078,.22),(.066,.43),(.10,.50),(.13,.52)],"stone_light",16)
    lathe("Birdbath shallow bowl",[(.12,.48),(.18,.50),(.25,.56),(.285,.615),(.289,.65),
          (.272,.668),(.248,.662),(.243,.624),(.19,.572),(.03,.563)],"stone_light",24)
    cylinder("Birdbath still flat water",(0,.612,0),.233,.008,"water",segments=24)
    # Broad tail and distinct wings make the bird readable from above.
    before=set(CURRENT.objects)
    for x in [.17,.205]:
        rod("Bird gold leg",(x,.658,-.097),(x,.691,-.082),.008,"yellow",6)
    ellipsoid("Bird blue body",(.166,.713,-.077),(.132,.12,.17),"bird",10,5)
    ellipsoid("Bird cream breast",(.166,.725,-.010),(.095,.105,.053),"cream",8,4)
    ellipsoid("Bird round head",(.166,.784,-.025),(.107,.112,.102),"bird",10,5)
    for sign in [-1,1]:
        ellipsoid("Bird folded wing",(.166+sign*.058,.73,-.096),(.037,.07,.12),"bird_shade",8,4)
        ellipsoid("Bird bright eye",(.166+sign*.042,.801,.005),(.012,.013,.012),"wood_dark",6,3)
    rod("Bird pointed beak",(.166,.779,.014),(.166,.773,.068),.022,"yellow",6,top=0)
    ellipsoid("Bird fan tail",(.166,.711,-.176),(.079,.025,.108),"bird_shade",8,4)
    for obj in set(CURRENT.objects)-before:
        obj.location+=v((.035,0,-.040))


def windmill():
    begin("deco_windmill",[2,2],4000,rotor_asset="deco_windmill_sails",rotor_position=[0,.985,.273],rotor_axis="+Z")
    for z in [-.31,.31]:
        box("Windmill square foundation rail",(0,.065,z),(.74,.13,.105),"wood_light",.022)
    for x in [-.31,.31]:
        box("Windmill square foundation side",(x,.065,0),(.105,.13,.53),"wood_light",.018)
    for x in [-1,1]:
        for z in [-1,1]:
            box("Windmill pale corner footing",(x*.315,.071,z*.315),(.17,.142,.17),"stone_light",.020)
            beam("Windmill tapered tower leg",(x*.267,.13,z*.267),(x*.11,1.19,z*.11),.073,"wood",radius=.012)
    for z in [-1,1]:
        beam("Windmill front rear X brace",(-.245,.21,z*.25),(.125,1.07,z*.13),.047,"wood_light",radius=.007)
        beam("Windmill front rear X brace",(.245,.21,z*.25),(-.125,1.07,z*.13),.047,"wood_light",radius=.007)
    for x in [-1,1]:
        beam("Windmill side X brace",(x*.24,.25,-.24),(x*.13,1.07,.13),.043,"wood_light",radius=.006)
        for j in range(3):
            z=(j-1)*.105
            beam("Windmill lower wooden slat",(x*.24,.26,z),(x*.18,.67,z*.8),.072,"wood",depth=.035,radius=.005)
    cylinder("Windmill red cone cap",(0,1.23,0),.215,.205,"red",top=.035,segments=12)
    cylinder("Windmill cap lip",(0,1.14,0),.222,.047,"red_light",segments=12)
    rod("Windmill spindle",(0,.985,.09),(0,.985,.273),.051,"wood_dark",12)
    socket("rotor",(0,.985,.273))
    begin("deco_windmill_sails",[2,2],4000,pivot="rotor axle",rotation_axis="+Z",maximum_swept_diameter=1.24)
    rod("Sail round axle boss",(0,0,-.029),(0,0,.038),.084,"wood_dark",12)
    rod("Sail ochre hub face",(0,0,.033),(0,0,.052),.06,"wood",12)
    # Four ladder sails; furthest corner radius < .62 in every animated pose.
    for i in range(4):
        a=math.pi/4+i*math.pi/2
        def p(t,w,z=0):
            return (math.sin(a)*t+math.cos(a)*w,math.cos(a)*t-math.sin(a)*w,z)
        beam("Sail radial spar",p(.05,0),p(.582,0),.029,"wood",depth=.035,radius=.003)
        for w in [-.077,.077]:
            beam("Sail long border",p(.185,w),p(.588,w),.021,"wood_light",depth=.023,radius=.003)
        for j in range(5):
            t=.19+j*.096
            beam("Sail cross slat",p(t,-.082),p(t,.082),.023,"wood_light",depth=.023,radius=.003)


def fountain():
    begin("deco_fountain",[2,2],4000)
    lathe("Fountain lower stepped plinth",[(.48,0),(.555,.035),(.58,.068),(.58,.125),(.55,.15)],"stone",28)
    lathe("Fountain large lower basin",[(.53,.10),(.582,.17),(.603,.25),(.603,.306),(.577,.33),
          (.53,.326),(.516,.29),(.50,.211),(.35,.185),(.055,.185)],"stone_light",28)
    cylinder("Fountain lower still water",(0,.251,0),.511,.008,"water",segments=28)
    lathe("Fountain central turned pedestal",[(.17,.245),(.18,.28),(.14,.32),(.095,.38),(.078,.54),
          (.12,.62),(.14,.65)],"stone_light",20)
    lathe("Fountain distinct upper basin",[(.12,.59),(.20,.61),(.286,.67),(.325,.719),(.325,.761),
          (.30,.785),(.271,.78),(.264,.733),(.22,.685),(.042,.682)],"stone_light",24)
    cylinder("Fountain upper still water",(0,.724,0),.26,.007,"water_light",segments=24)
    lathe("Fountain finial stem",[(.073,.72),(.083,.746),(.055,.775),(.039,.831)],"stone",16)
    ellipsoid("Fountain round stone finial",(0,.902,0),(.176,.184,.176),"stone_light",12,8)


def pergola():
    begin("deco_pergola",[3,2],2000,clearance_height=2.14,
          colliders=[{"at":[x,1.105,z],"size":[.13,2.21,.13]} for x in [-.79,.79] for z in [-.49,.49]],
          collision_note="Four posts only; open passage. No bounding-box collider.")
    for x in [-.79,.79]:
        for z in [-.49,.49]:
            box("Pergola walkable corner post",(x,1.105,z),(.13,2.21,.13),"wood",.018)
    for z in [-.49,.49]:
        box("Pergola long load bearing beam",(0,2.20,z),(1.88,.12,.14),"wood_light",.018)
    for i in range(7):
        box("Pergola short direction roof slat %d"%i,(-.84+i*.28,2.293,0),(.125,.085,1.23),"wood_light",.014)
    # Vines hug the outward faces of posts, then the upper long beams.
    for side in [-1,1]:
        x,z=side*.79,.568
        pts=[(x+.027*math.sin(j*.9),.30+j*.255,z) for j in range(8)]
        for j in range(len(pts)-1):
            rod("Pergola climbing stem",pts[j],pts[j+1],.011,"leaf_dark",5)
        for j,p in enumerate(pts):
            leaf("Pergola attached heart leaf",(p[0]+side*.041,p[1],p[2]),.17,.10,
                 "leaf" if j%3 else "leaf_light",j*.55,math.pi/2)
            if j%2==0:
                leaf("Pergola paired rounded leaf",(p[0]-side*.038,p[1]+.065,p[2]),.14,.10,
                     "leaf_dark",-j*.6,math.pi/2)
        for j in range(5):
            x=side*(.15+j*.145)
            leaf("Pergola roof trailing leaf",(x,2.35,.43-.15*(j%2)),.20,.12,
                 "leaf" if j%2 else "leaf_dark",j*.8,.10)
        for j in range(4):
            a=(side*(.15+j*.145),2.343,.43-.15*(j%2))
            b=(side*(.15+(j+1)*.145),2.343,.43-.15*((j+1)%2))
            rod("Pergola roof creeper",a,b,.010,"leaf_dark",5)
        flower("Pergola roof white flower",(side*.60,2.37,.35),.067,"flower",.05)
        flower("Pergola post flower",(side*.78,1.82,.591),.06,"flower",1.35)


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
    if name!="deco_windmill_sails":
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


def main():
    global MATS
    OUT.mkdir(parents=True,exist_ok=True)
    SOURCE.mkdir(parents=True,exist_ok=True)
    (SOURCE/".gdignore").touch()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)
    bpy.context.preferences.filepaths.save_version=0
    for name,hexcolor in PALETTE.items():
        mat=bpy.data.materials.new(name)
        mat.diffuse_color=(*rgb(hexcolor),1)
        mat.use_nodes=True
        shader=mat.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value=mat.diffuse_color
        shader.inputs["Roughness"].default_value=.9
        MATS[name]=mat
    material=bpy.data.materials.new("Farm vertex paint")
    material.use_nodes=True
    shader=material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value=.9
    shader.inputs["Specular IOR Level"].default_value=.18
    color=material.node_tree.nodes.new("ShaderNodeVertexColor")
    color.layer_name="Color"
    material.node_tree.links.new(color.outputs["Color"],shader.inputs["Base Color"])
    for build in [planter,lantern,path,bench,scarecrow,fence,birdbath,windmill,fountain,pergola]:
        build()
    manifest=json.loads((OUT/"manifest.json").read_text())
    for name,collection in ASSETS.items():
        entry=export_asset(name,collection,material)
        manifest["assets"][name]=entry
        print("DECOR",name,entry["triangles"],entry["bounds"],flush=True)
    total_windmill=sum(manifest["assets"][n]["triangles"] for n in ["deco_windmill","deco_windmill_sails"])
    assert total_windmill<=4000,total_windmill
    (OUT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    # Source inspection layout; collection property records its presentation-only offset.
    for index,(name,collection) in enumerate(ASSETS.items()):
        offset=Vector(((index%6)*2.7,(index//6)*3.1,0))
        collection["source_display_offset_blender"]=list(offset)
        for obj in collection.objects:
            obj.location+=offset
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/"decor_290.blend"))
    print("DECOR_DONE",len(ASSETS),flush=True)


if __name__=="__main__":
    main()
