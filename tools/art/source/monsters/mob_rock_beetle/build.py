"""SGODOT-355 rock beetle v1.1, retaining the approved v1 action curves."""
from pathlib import Path
import argparse
import json
import math
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
ID = "mob_rock_beetle"
PARTS = []
FPS = 60
MODEL_SCALE = 1.25
LEG_REACH_SCALE = .35
LEG_LENGTH_RATIOS = []
ANIMS = {
    "idle": {"length": 1.6, "loop": True},
    "move": {"length": .8, "loop": True},
    "windup": {"length": .6, "loop": False},
    "attack": {"length": .4, "loop": False, "hit_at": .18},
    "recover": {"length": .5, "loop": False},
    "hit": {"length": .25, "loop": False},
    "die": {"length": .8, "loop": False},
    "stunned": {"length": 1.0, "loop": True},
}
COLORS = {"shell": "685B59", "belly": "514744", "head": "C9A087", "leg": "7E6A5F",
    "rim": "F2A13C", "bump": "85746B", "horn": "F3E6D5", "eye": "26252D",
    "glint": "FFF8EA", "cheek": "E49AAD", "mouth": "654D48"}
BONES = {"root": ((0, 0, 0), None), "body": ((0, .20, 0), "root"),
    "head": ((0, .24, .38), "body"), "ant_l": ((-.105, .333, .422), "head"),
    "ant_r": ((.105, .333, .422), "head")}
for side, x in [("l", -.275), ("r", .275)]:
    for i, z in enumerate([.25, -.03, -.29], 1): BONES[f"leg_{side}_{i}"] = ((x, .175, z), "body")


def point(p): return Vector((p[0], -p[2], p[1]))
def linear(c):
    v = [int(c[i:i+2], 16) / 255 for i in [0, 2, 4]]
    return tuple(x / 12.92 if x <= .04045 else ((x + .055) / 1.055) ** 2.4 for x in v) + (1,)


def finish(obj, name, bone, color, tint=1):
    obj.name = name
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.data.materials.clear()
    obj.data.materials.append(bpy.data.materials["BeetleClay"])
    for face in obj.data.polygons: face.use_smooth = True
    colors = obj.data.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
    for row in colors.data: row.color = linear(COLORS[color])
    obj.data.color_attributes.active_color = colors
    obj.data.color_attributes.render_color_index = obj.data.color_attributes.find("Color")
    for layer in list(obj.data.uv_layers): obj.data.uv_layers.remove(layer)
    obj.data.uv_layers.new(name="UVMap")
    mask = obj.data.uv_layers.new(name="UV2")
    for row in mask.data: row.uv = (tint, 0)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1, "REPLACE")
    obj["bone"] = bone
    obj["tint_mask"] = tint
    obj["palette"] = color
    PARTS.append(obj)
    obj.select_set(False)
    return obj


def mesh(name, vertices, faces, bone, color, tint=1):
    data = bpy.data.meshes.new(name)
    data.from_pydata([point(p) for p in vertices], [], faces)
    data.update()
    bm = bmesh.new(); bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data); bm.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    return finish(obj, name, bone, color, tint)


def ellipsoid(name, at, scale, bone, color, tint=1, segments=10, rings=6):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=point(at))
    obj = bpy.context.object
    obj.scale = (scale[0], scale[2], scale[1])
    return finish(obj, name, bone, color, tint)


def tube(name, points, radii, bone, color, tint=1, sides=6):
    verts = []
    for i, (p, r) in enumerate(zip(points, radii)):
        tangent = (Vector(points[min(i + 1, len(points)-1)]) - Vector(points[max(0, i-1)])).normalized()
        u = tangent.cross(Vector((0, 0, 1)))
        if u.length < .01: u = tangent.cross(Vector((0, 1, 0)))
        u.normalize()
        v = tangent.cross(u).normalized()
        for j in range(sides):
            q = Vector(p) + r * (math.cos(j * math.tau / sides) * u + math.sin(j * math.tau / sides) * v)
            verts.append(tuple(q))
    faces = [(i*sides+j, i*sides+(j+1)%sides, (i+1)*sides+(j+1)%sides, (i+1)*sides+j)
             for i in range(len(points)-1) for j in range(sides)]
    faces += [tuple(reversed(range(sides))), tuple((len(points)-1)*sides+j for j in range(sides))]
    return mesh(name, verts, faces, bone, color, tint)


def face_disc(name, at, radii, color, segments, depth=0):
    verts = [(at[0],at[1],at[2]+depth)] + [(at[0]+radii[0]*math.cos(i*math.tau/segments),
        at[1]+radii[1]*math.sin(i*math.tau/segments), at[2]) for i in range(segments)]
    return mesh(name, verts, [(0,i+1,(i+1)%segments+1) for i in range(segments)], "head", color, 0)


def shell():
    # Two dome halves leave a narrow longitudinal seam over the darker abdomen.
    for sign, start in [(1, -math.pi/2), (-1, math.pi/2)]:
        verts = [(sign*.003, .51, -.04)]
        n = 12
        for ring in range(1, 6):
            theta = ring * math.pi / 10
            for j in range(n+1):
                phi = start + j * math.pi / n
                base = .225 + .085*max(0,math.sin(phi))**4
                verts.append((sign*.003 + .37*math.sin(theta)*math.cos(phi),
                    base + (.51-base)*math.cos(theta), -.04 + .455*math.sin(theta)*math.sin(phi)))
        faces = [(0, 1+j, 2+j) for j in range(n)]
        for ring in range(4):
            a = 1 + ring*(n+1); b = a+n+1
            faces += [(a+j,b+j,b+j+1,a+j+1) for j in range(n)]
        mesh("Carapace_" + ("R" if sign > 0 else "L"), verts, faces, "body", "shell")
    seam = []
    for i in range(11):
        a = -math.pi/2+i*math.pi/10
        base = .31 if a>0 else .225
        for x in [-.016,.016]: seam.append((x,base+(.51-base)*math.cos(a)-.003,-.04+.455*math.sin(a)))
    mesh("Recessed brown shell seam",seam,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(10)],"body","belly")
    verts = []
    for i in range(24):
        a = i*math.tau/24
        for j in range(6):
            b = j*math.tau/6
            verts.append(((.375 + .035*math.cos(b))*math.cos(a),
                .225 + .085*max(0,math.sin(a))**4 + .041*math.sin(b), -.04 + (.455 + .035*math.cos(b))*math.sin(a)))
    faces = [(i*6+j, ((i+1)%24)*6+j, ((i+1)%24)*6+(j+1)%6, i*6+(j+1)%6) for i in range(24) for j in range(6)]
    mesh("Bright orange shell rim", verts, faces, "body", "rim", 0)
    shells=[BVHTree.FromPolygons([v.co for v in obj.data.vertices],[list(f.vertices) for f in obj.data.polygons])
        for obj in PARTS if obj.name.startswith("Carapace_")]
    for i, (x,z) in enumerate([(-.205,-.15),(.20,-.12),(.275,.14)]):
        hits=[tree.ray_cast(point((x,1,z)),Vector((0,0,-1)),2)[0] for tree in shells]
        height=max(hit.z for hit in hits if hit is not None)
        ellipsoid("Rounded shell bump %d" % i, (x,height+.007,z), (.047,.022,.053), "body", "bump", segments=8, rings=3)


def form():
    shell()
    ellipsoid("Low abdomen", (0,.18,-.035), (.32,.095,.38), "body", "belly", segments=10, rings=6)
    ellipsoid("Tucked forward face", (0,.24,.385), (.172,.118,.13), "head", "head", 0, 12, 6)
    tube("Single upward ivory horn", [(0,.255,.50),(0,.30,.537),(0,.38,.54),(0,.45,.525)],
        [.046,.041,.024,.008], "head", "horn", 0, 10)
    for side, sign in [("l",-1),("r",1)]:
        face_disc("Black eye "+side, (sign*.097,.266,.501), (.026,.032), "eye", 12, .012)
        face_disc("Eye glint "+side, (sign*.097-.005,.276,.512), (.008,.009), "glint", 8)
        face_disc("Pink cheek "+side, (sign*.133,.226,.474), (.027,.014), "cheek", 12)
        tube("Short antenna "+side, [(sign*.105,.333,.422),(sign*.12,.378,.438),(sign*.142,.43,.44)],
            [.015,.014,.012], "ant_"+side, "leg", sides=6)
        ellipsoid("Antenna round tip "+side, (sign*.142,.43,.44), (.028,.028,.028), "ant_"+side, "bump", segments=8, rings=3)
        for i, z in enumerate([.25,-.03,-.29],1):
            sweep = [.025,0,-.025][i-1]
            points = [(sign*.275,.175,z),(sign*.35,.19,z+sweep*.4),(sign*.408,.118,z+sweep),
                 (sign*.438,.038,z+sweep*1.3),(sign*.448,.023,z+sweep*1.35)]
            leg = tube("Jointed leg %s%d"%(side,i), points,
                [.045,.057,.046,.03,.012], f"leg_{side}_{i}", "leg", sides=6)
            # Tuck horizontal reach while retaining hip height for the v1 kicks.
            ground = min(v.co.z for v in leg.data.vertices)
            hip = Vector(points[0])
            shortened = [Vector((hip.x+(p[0]-hip.x)*LEG_REACH_SCALE,min(p[1],hip.y),
                hip.z+(p[2]-hip.z)*LEG_REACH_SCALE)) for p in points]
            length = lambda chain: sum((Vector(b)-Vector(a)).length for a,b in zip(chain,chain[1:]))
            LEG_LENGTH_RATIOS.append(length(shortened)/length(points))
            for ring, (old, new) in enumerate(zip(points, shortened)):
                for vertex in list(leg.data.vertices)[ring*6:(ring+1)*6]:
                    vertex.co += point(new-Vector(old))
            lift = ground-min(v.co.z for v in leg.data.vertices)
            for vertex in leg.data.vertices: vertex.co.z += lift
            pivot = shortened[0]+Vector((0,lift,0))
            BONES[f"leg_{side}_{i}"] = (tuple(pivot), "body")
    tube("Small smile", [(-.027,.207,.505),(0,.199,.513),(.027,.207,.505)],
        [.003,.003,.003], "head", "mouth", 0, 5)


def rig():
    ground = min(v.co.z for o in PARTS for v in o.data.vertices)
    for obj in PARTS:
        for v in obj.data.vertices: v.co.z -= ground
    bpy.ops.object.select_all(action="DESELECT")
    data = bpy.data.armatures.new("RockBeetleSkeleton")
    arm = bpy.data.objects.new("RockBeetleRig", data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (at, parent) in BONES.items():
        bone = data.edit_bones.new(name)
        bone.head = point(at) - Vector((0,0,ground if name != "root" else 0))
        bone.tail = bone.head + Vector((0,0,.06))
        if parent: bone.parent = data.edit_bones[parent]
        bone.use_deform = True
    bpy.ops.object.mode_set(mode="OBJECT")
    for obj in PARTS:
        obj.parent = arm
        mod = obj.modifiers.new("Rigid skin", "ARMATURE"); mod.object = arm
    return arm


def pose(arm, name, t):
    for bone in arm.pose.bones:
        bone.location = (0,0,0)
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0,0,0)
        bone.scale = (1,1,1)
    body = arm.pose.bones["body"]
    head = arm.pose.bones["head"]
    phase = t*math.tau
    if name == "idle":
        body.location.y = math.sin(phase)*.007
        body.rotation_euler.y = math.sin(phase)*.022
        for side in ["l","r"]: arm.pose.bones["ant_"+side].rotation_euler.x = math.sin(phase+.7)*.07
    elif name == "move":
        body.location.y = (1-math.cos(phase*2))*.004
        body.rotation_euler.y = math.sin(phase)*.025
        for side, sign in [("l",-1),("r",1)]:
            for i in range(1,4):
                a = phase + (math.pi if (i+(0 if sign<0 else 1))%2 else 0)
                leg = arm.pose.bones[f"leg_{side}_{i}"]
                leg.rotation_euler.y = math.sin(a)*.24*sign
                leg.rotation_euler.z = max(0,math.sin(a))*.13*sign
    elif name == "windup":
        body.location.y = -.026*t
        body.rotation_euler.x = .10*t
        head.rotation_euler.x = .15*t
        for side, sign in [("l",-1),("r",1)]:
            arm.pose.bones["leg_"+side+"_1"].rotation_euler.y = math.sin(t*math.tau*2)*.24*sign
            arm.pose.bones["ant_"+side].rotation_euler.x = -.18*t
            for i,z in enumerate([.25,-.03,-.29],1):
                arm.pose.bones[f"leg_{side}_{i}"].location.y = (.026+max(0,z)*.10)*t
    elif name == "attack":
        body.location.y = -.025*(1-t)
        body.rotation_euler.x = .1*(1-t)
        head.rotation_euler.x = .15*(1-t)+.24*math.sin(t*math.pi)
        for side, sign in [("l",-1),("r",1)]:
            for i,z in enumerate([.25,-.03,-.29],1):
                arm.pose.bones[f"leg_{side}_{i}"].rotation_euler.y = .13*sign*math.sin(t*math.pi)
                arm.pose.bones[f"leg_{side}_{i}"].location.y = (.025+max(0,z)*.10)*(1-t)
    elif name == "recover":
        body.location.y = -.044*(1-t)
        head.rotation_euler.x = .14*(1-t)+.11*math.sin(t*math.pi)
        head.rotation_euler.y = math.sin(.4)*.38*(1-t)
        for side,sign in [("l",-1),("r",1)]:
            arm.pose.bones["ant_"+side].rotation_euler.x = 1.25*(1-t)
            arm.pose.bones["ant_"+side].rotation_euler.z = sign*.30*(1-t)
            for i in range(1,4):
                arm.pose.bones[f"leg_{side}_{i}"].rotation_euler.z = sign*(1.75+.30*math.sin(i*1.2+sign))*(1-t)
                arm.pose.bones[f"leg_{side}_{i}"].rotation_euler.y = .20*math.sin(i+sign)*(1-t)
    elif name == "hit":
        response = math.sin(t*math.pi)
        body.rotation_euler.x = .30*response
        body.rotation_euler.z = .05*response
        body.location.y = .11*response
        body.location.z = -.04*response
        head.rotation_euler.x = .28*response
    elif name == "die":
        ease = min(1,t/.8); ease = ease*ease*(3-2*ease)
        body.rotation_euler.z = -1.35*ease
        body.location.y = .32*ease+.105*math.sin(math.pi*ease)
        for side in ["l","r"]:
            for i in range(1,4): arm.pose.bones[f"leg_{side}_{i}"].rotation_euler.z = .65*ease*(1 if side=="l" else -1)
    elif name == "stunned":
        body.location.y = -.047 + .003*math.cos(phase*2)
        body.rotation_euler.z = math.radians(15)*math.sin(phase)
        head.rotation_euler.y = math.sin(phase+.4)*.38
        head.rotation_euler.x = .14
        for side, sign in [("l",-1),("r",1)]:
            ant = arm.pose.bones["ant_"+side]
            ant.rotation_euler.x = 1.25 + .15*math.sin(phase)
            ant.rotation_euler.z = sign*.30
            for i in range(1,4):
                leg = arm.pose.bones[f"leg_{side}_{i}"]
                leg.rotation_euler.z = sign*(1.75+.30*math.sin(phase*2+i*1.2+sign))
                leg.rotation_euler.y = .20*math.sin(phase*2+i+sign)
    # root never animates: locomotion and knockback belong to gameplay.


def animations(arm):
    arm.animation_data_create()
    for name, spec in ANIMS.items():
        action = bpy.data.actions.new(name)
        arm.animation_data.action = action
        frames = round(spec["length"]*FPS)
        for frame in range(frames+1):
            pose(arm,name,frame/frames)
            for bone in arm.pose.bones:
                if bone.name == "root": continue
                for path in ["location","rotation_euler","scale"]: bone.keyframe_insert(path,frame=frame,group=bone.name)
        action.use_fake_user = True
        track = arm.animation_data.nla_tracks.new(); track.name = name
        strip = track.strips.new(name,0,action); strip.name = name
        track.mute = True
    arm.animation_data.action = None
    pose(arm,"idle",0)


def main():
    args = argparse.ArgumentParser()
    args.add_argument("--runtime", required=True)
    parsed = args.parse_args(sys.argv[sys.argv.index("--")+1:])
    out = Path(parsed.runtime).resolve() / "assets/monsters" / ID
    out.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action="SELECT"); bpy.ops.object.delete(use_global=False)
    scene = bpy.context.scene
    scene.render.fps = FPS
    mat = bpy.data.materials.new("BeetleClay"); mat.use_nodes = True
    mat.use_backface_culling = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = .78
    shader.inputs["Specular IOR Level"].default_value = .28
    vertex = mat.node_tree.nodes.new("ShaderNodeVertexColor"); vertex.layer_name = "Color"
    mat.node_tree.links.new(vertex.outputs["Color"],shader.inputs["Base Color"])
    form(); arm = rig(); animations(arm)
    # A static rig transform scales geometry and motion without editing curves.
    arm.scale = (MODEL_SCALE,)*3
    # Preserve named source parts and export one joined mesh with rigid weights.
    originals = list(PARTS)
    bpy.ops.object.select_all(action="DESELECT")
    copies = []
    for src in originals:
        copy = src.copy(); copy.data = src.data.copy(); scene.collection.objects.link(copy)
        copy.select_set(True); copies.append(copy)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = ID; joined.data.name = ID+"_mobile"
    joined.data.calc_loop_triangles()
    count = len(joined.data.loop_triangles)
    assert count <= 1500, count
    for src in originals: src.hide_render = True; src.hide_set(True)
    bounds = [[min(v.co[i] for v in joined.data.vertices)*MODEL_SCALE for i in range(3)],
              [max(v.co[i] for v in joined.data.vertices)*MODEL_SCALE for i in range(3)]]
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/(ID+".blend")))
    bpy.ops.object.select_all(action="DESELECT")
    joined.select_set(True); arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=str(out/(ID+".glb")),export_format="GLB",use_selection=True,
        export_yup=True,export_animations=True,export_animation_mode="ACTIONS",export_skins=True,
        export_force_sampling=True,export_frame_range=False,export_vertex_color="ACTIVE",
        export_materials="EXPORT",export_cameras=False,export_lights=False)
    radius = .58*MODEL_SCALE
    spec = {"id":ID,"radius":radius,"height":round(bounds[1][2]-bounds[0][2],4),
        "hit_point":[0,round(.28*MODEL_SCALE,4),round(.04*MODEL_SCALE,4)],"durations":{name:data["length"] for name,data in ANIMS.items()},
        "hit_at":ANIMS["attack"]["hit_at"],"badge_point":[0,.65*MODEL_SCALE,0],"anims":ANIMS,
        "tint_mask":"UV2.x","source_concept":"Plane 355 c368e7dd / beetle_v3.png",
        "stage":"formal_v1.1","cast_shadow":False,"palette":COLORS}
    (out/(ID+".json")).write_text(json.dumps(spec,indent=2)+"\n")
    info = {"triangles":count,"bones":list(BONES),"parts":len(PARTS),"bounds_blender":bounds,
        "leg_centreline_length_ratios_before_global_scale":LEG_LENGTH_RATIOS,"uniform_scale":MODEL_SCALE,
        "units":"metres","front":"+Z","binding":"one bone, weight 1 per vertex",
        "runtime_files":[str(p.relative_to(Path(parsed.runtime))) for p in out.glob("*")]}
    qa = ROOT/"output/rock-beetle-355"; qa.mkdir(parents=True,exist_ok=True)
    (qa/"build.json").write_text(json.dumps(info,indent=2)+"\n")
    print("ROCK_BEETLE_FORMAL_V1.1", count, "triangles",len(BONES),"bones", len(ANIMS),"animations", flush=True)


if __name__ == "__main__": main()
