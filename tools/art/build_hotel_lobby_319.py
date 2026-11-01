"""SGODOT-319 N1, approved 324 furniture adaptations on the shared hall shell.

Run prepare_hotel_lobby_319.py and make_hotel_atlas_319.py before Blender.
Named parts remain editable; evaluated local-pivot copies alone are exported.
"""
from pathlib import Path
import hashlib
import json
import math
import random
import re
import struct
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/art"))
import scene_room_pipeline as p
from verify_chef_sign import load_glb, accessor

OUT = ROOT / "assets/rooms/poi_hotel_lobby"
SOURCE = ROOT / "tools/art/source/poi_hotel_lobby"
QA = ROOT / "output/hotel-lobby-319"
HALL = ROOT / "assets/rooms/_shared/shell_hall"
DEPS = QA / "deps"
PLAN = json.loads((SOURCE / "layout_plan.json").read_text())
ROWS = {r["name"]: r for r in PLAN["placements"]}
PALETTE = json.loads((HALL / "hall_palette.json").read_text())["slots"]
PROVENANCE = {}
SHARED = []
GROUPS = {}
TEXTURED = {"green_rug", "cowhide_rug", "mirror_reflection", "Artwork"}


def dump(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def begin(name, at=None, yaw=None, source="new", notes=None, colliders=None):
    row = ROWS.get(name, {})
    at = at or row.get("position", [0, .08, 0])
    yaw = row.get("yaw_degrees", 0) if yaw is None else yaw
    if colliders is None and row:
        if row["shape"] == "circle": colliders = [dict(kind="cylinder", at=[0, row["height"] / 2, 0], radius=row["radius"], height=row["height"])]
        else:
            off = row.get("shape_offset", [0, 0, 0])
            colliders = [dict(at=[off[0], row["size"][1] / 2, off[2]], size=row["size"])]
    p.begin(name, at, yaw, colliders or [])
    PROVENANCE[name] = {"task": "SGODOT-319", "author": "ZHAOYUN", "source": source, "changes": notes or []}
    return p.KITS[name]


def role(obj, value, uv_mode="point"):
    obj["hall_role"] = value
    obj["uv_mode"] = uv_mode
    obj.data.materials.clear()
    obj.data.materials.append(p.material(value))
    for face in obj.data.polygons: face.material_index = 0
    return obj


def cube(name, at, size, color, bevel=.015):
    obj = role(p.cube(name, at, size, color, bevel), color)
    if bevel == 0:
        for face in obj.data.polygons: face.use_smooth = False
    elif min(size) < .035:
        for modifier in obj.modifiers:
            if modifier.type == "BEVEL": modifier.segments = 1
    return obj
def cyl(name, at, r, h, color, n=20): return role(p.cylinder(name, at, r, h, color, vertices=n), color)
def lathe(name, at, profile, color, n=40):
    if abs(profile[0][0] - profile[-1][0]) > .00001:
        return role(p.lathe(name, at, profile, color, n), color)
    # A closed annular cross-section must not get full-disc end caps over its hole.
    vertices = [(at[0] + r * math.cos(i * math.tau / n), at[1] + y, at[2] + r * math.sin(i * math.tau / n)) for y, r in profile for i in range(n)]
    count = len(profile)
    faces = [(row * n + i, row * n + (i + 1) % n, ((row + 1) % count) * n + (i + 1) % n, ((row + 1) % count) * n + i)
        for row in range(count) for i in range(n)]
    return role(p.mesh(name, vertices, faces, color, smooth=True), color)
def tube(name, points, r, color, sides=8): return role(p.tube(name, points, r, color, sides), color)
def blob(name, at, size, color, n=12, rings=8): return role(p.ellipsoid(name, at, size, color, n, rings), color)


def source_parts(name, path, collection, at=None, yaw=0, keep=lambda _: True, origin=None, choose=None):
    """Append and evaluate source construction parts at their actual local scale."""
    kit = begin(name, at, yaw, str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path))
    with bpy.data.libraries.load(str(path), link=False) as (src, dst): dst.collections = [collection]
    col = dst.collections[0]
    assert col is not None, (path, collection)
    bpy.context.scene.collection.children.link(col)
    root = next((o for o in col.objects if o.type == "EMPTY"), None)
    bpy.context.view_layer.update()
    inv = root.matrix_world.inverted() if root else Matrix.Identity(4)
    if origin is not None: inv = Matrix.Translation(-p.v(origin)) @ inv
    deps = bpy.context.evaluated_depsgraph_get()
    retained, removed = [], []
    for src in list(col.objects):
        if src.type != "MESH": continue
        if not keep(src.name): removed.append(src.name); continue
        data = bpy.data.meshes.new_from_object(src.evaluated_get(deps), depsgraph=deps)
        data.transform(inv @ src.matrix_world)
        obj = bpy.data.objects.new(src.name, data)
        kit["collection"].objects.link(obj)
        obj.parent = kit["root"]
        obj["source_part"] = src.name
        obj["source_palette_slot"] = src.get("palette_slot", "")
        obj["export_group"] = src.get("export_group", "Body")
        role(obj, choose(src) if choose else "oak")
        kit["objects"].append(obj)
        retained.append(src.name)
    for obj in list(col.objects): bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(col)
    PROVENANCE[name].update(source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(), source_collection=collection,
        retained_parts=retained, removed_parts=removed)
    return kit


def remap_positions(obj, transform):
    obj.data.transform(transform)
    obj.data.update()


def ring_sofa():
    begin("ring_sofa", notes=["New 2.43 m outside diameter, six equal 60-degree cushions; seat top .715 m above floor."])
    lathe("Dark timber ring underframe", (0, 0, 0), [(.23, 1.12), (.26, 1.18), (.49, 1.18), (.52, 1.13), (.52, .57), (.23, .57)], "wood_dark", 72)
    for y, r in [(.26, 1.19), (.48, 1.19)]:
        lathe("Thin brass circular binding", (0, y, 0), [(0, r), (.018, r), (.018, r - .015), (0, r - .015)], "accent_gold", 72)
    profile = [(.60, .54), (.60, .77), (.65, .97), (.73, .97), (.78, .715), (1.14, .715),
               (1.215, .675), (1.215, .58), (1.16, .515), (.65, .515)]
    for i in range(6):
        center = math.radians(30 + i * 60)
        angles = [center + math.radians(-29.4 + j * 58.8 / 12) for j in range(13)]
        vertices = [(r * math.sin(a), y, r * math.cos(a)) for a in angles for r, y in profile]
        n = len(profile)
        faces = [(j * n + k, j * n + (k + 1) % n, (j + 1) * n + (k + 1) % n, (j + 1) * n + k)
                 for j in range(len(angles) - 1) for k in range(n)]
        faces += [tuple(reversed(range(n))), tuple((len(angles) - 1) * n + k for k in range(n))]
        obj = role(p.mesh("Upholstered radial seat %02d" % (i + 1), vertices, faces, "cloth_green", smooth=True), "cloth_green")
        bevel = obj.modifiers.new("Soft cushion edge", "BEVEL"); bevel.width = .012; bevel.segments = 2
        obj.modifiers.new("Weighted cushion normals", "WEIGHTED_NORMAL")
        x, z = 1.04 * math.sin(center), 1.04 * math.cos(center)
        cyl("Low timber foot %02d" % i, (x, .13, z), .036, .26, "wood_dark", 10)
    begin("central_planter", colliders=[], notes=["New 1.09 m central planter, separate from two shared floor plants."])
    cyl("Planter concealed floor support", (0, .09, 0), .43, .18, "wood_dark", 40)
    lathe("Circular dark walnut planter", (0, 0, 0), [(.18, .46), (.78, .49), (.87, .525), (.92, .545), (.97, .545),
        (1.00, .52), (1.00, .48), (.92, .47), (.78, .445)], "wood_mid", 64)
    cyl("Planter soil", (0, .90, 0), .475, .025, "soil", 64)
    lathe("Planter narrow brass rim", (0, .963, 0), [(0, .546), (.014, .546), (.014, .532), (0, .532)], "accent_gold", 64)
    at = ROWS["central_planter"]["position"]
    begin("central_foliage", at, notes=["New compact broad-leaf planting; no extra floor pot."])
    random.seed(319)
    for j in range(6):
        a = j * math.tau / 6
        base = Vector((math.sin(a) * .12, .91, math.cos(a) * .12))
        stem_top = Vector((math.sin(a) * .18, 1.5 + .15 * (j % 3), math.cos(a) * .18))
        tube("Central live stem %02d" % j, [base, (base + stem_top) / 2, stem_top], .014, "leaf_dark", 6)
        for k in range(7):
            az = a + (k % 2 * 2 - 1) * (.6 + .16 * k)
            start = base.lerp(stem_top, .25 + k * .10)
            reach = .27 + .035 * (k % 3)
            tip = start + Vector((math.sin(az) * reach, .19 + .075 * (k % 2), math.cos(az) * reach))
            obj = role(p.leaf("Folded broad leaf %02d %02d" % (j, k), start, tip, .21 + .03 * (k % 2),
                ["leaf", "leaf_light", "leaf_dark"][(j + k) % 3]), ["leaf", "leaf_light", "leaf_dark"][(j + k) % 3])
    for i in range(18):
        a = i * math.tau / 18
        obj = role(p.leaf("Planter lower trailing leaf", (.12 * math.sin(a), .94, .12 * math.cos(a)),
            (.45 * math.sin(a), 1.04 + .07 * (i % 3), .45 * math.cos(a)), .085, "leaf"), "leaf")


def reused_furniture():
    path = DEPS / "tools/art/source/hallkit_324/hallkit_324.blend"
    mapping = {"sky": "linen", "linen": "linen", "sage": "linen", "linen_green": "linen", "oak": "wood_mid", "oak_light": "wood_mid", "oak_edge": "wood_dark"}
    for source, name, at, yaw in [
        ("armchair", "cream_armchair", ROWS["armchair_back"]["position"], 90),
        ("round_side_table", "round_side_table", ROWS["table_sofa_left"]["position"], 0),
        ("frame_landscape", "frame_landscape", [2.55, 2.43, -2.99], 0),
    ]:
        def choose(obj):
            if source == "frame_landscape": return "print_landscape" if obj.get("export_group") == "Artwork" else "accent_gold"
            if source == "round_side_table": return "wood_mid" if obj.get("palette_slot") in ["linen", "porcelain"] else "wood_dark"
            return mapping.get(obj.get("palette_slot", "oak"), obj.get("palette_slot", "oak"))
        kit = source_parts(name, path, "KIT_" + source, at, yaw, choose=choose)
        if source == "armchair": kit["collision"] = [dict(at=[0, .663, 0], size=[1.5, 1.326, .89])]
        elif source == "round_side_table":
            for obj in kit["objects"]: remap_positions(obj, Matrix.Diagonal((.70 / 1.10, .70 / 1.10, .90 / 1.13425, 1)))
            kit["collision"] = [dict(kind="cylinder", at=[0, .45, 0], radius=.35, height=.90)]
        PROVENANCE[name].update(source_commit="104446a2a995c8a0269d12d27308b3d547b29f6e", source_asset=source,
            locked_scale=True, changes=["Geometry, normals and game scale retained; only palette UV/color and scalar local AO added."])
        if source == "round_side_table":
            PROVENANCE[name].update(locked_scale=False, scale_xyz=[.70 / 1.10, .90 / 1.13425, .70 / 1.10],
                changes=["N1-only copy scaled to .70 m diameter and .90 m table height per Huowu 319 1db13376; original 324 files unchanged."])
        for obj in kit["objects"]:
            if obj.get("export_group") == "Artwork": obj["uv_mode"] = "front"
    p.instance("cream_armchair", "armchair_front", ROWS["armchair_front"]["position"], 90)
    for name in ["table_sofa_right", "table_sofa_back", "table_armchair"]:
        p.instance("round_side_table", name, ROWS[name]["position"])
    lamp_source = ROOT / "tools/art/source/post_215/post_215.blend"
    at = ROWS["table_sofa_left"]["position"][:]; at[1] += .90
    kit = source_parts("green_table_lamp", lamp_source, "post_table_lamp", at, choose=lambda o:
        "leaf_light" if "warm shade" in o.name else "wood_dark" if "dark foot" in o.name else "accent_gold")
    PROVENANCE["green_table_lamp"]["changes"] = ["Post Office lamp geometry retained at .493 m high; warm shade recolored green, brass retained."]
    for name in ["table_sofa_right", "table_sofa_back"]:
        at = ROWS[name]["position"][:]; at[1] += .90
        p.instance("green_table_lamp", "lamp_" + name, at)


def hearth():
    path = ROOT / "tools/art/source/deluxe_room_10/deluxe_room_10.blend"
    source_parts("hearth", path, "KIT_hearth", ROWS["hearth"]["position"], 90,
        keep=lambda n: not n.startswith("Underloft rounded plaster breast"), choose=lambda o:
        "wood_dark" if "log" in o.name.lower() else "leather" if "ember" in o.name.lower() or "lining" in o.name.lower() else "stone")
    p.KITS["hearth"]["collision"] = [dict(at=[0, 1.0425, .045], size=[1.13, 2.085, 1.05])]
    p.b.CURRENT = p.KITS["hearth"]
    for obj in p.KITS["hearth"]["objects"]:
        if obj["source_part"].startswith("Hearth rounded cooking ledge"):
            transform = Matrix.Diagonal((1, 1, .5, 1)); transform.translation.z = 1.30 * .5
            remap_positions(obj, transform)
    # Staggered solid stones replace the blank chimney breast, retaining its envelope.
    for row in range(4):
        cuts = [-.36, -.12, .12, .36] if row % 2 == 0 else [-.36, 0, .36]
        for left, right in zip(cuts, cuts[1:]):
            cube("Chimney warm stone course %d" % row, ((left + right) / 2, 1.315 + (row + .5) * .1925, -.22),
                (right - left - .014, .1785, .52), "stone", .014)
    for x in [-.43, .43]:
        for i, y in enumerate([.28, .56, .84]):
            cube("Stone facing jamb block", (x, y, .49), (.215, .245, .15), "stone", .028)
    for x in [-.36, -.12, .12, .36]: cube("Stone facing lintel block", (x, 1.10, .49), (.225, .23, .15), "stone", .025)
    PROVENANCE["hearth"]["changes"] = ["Source footprint and logs retained; replace blank chimney breast with four staggered stone courses, thin cooking ledge to .08 m, warm mid-grey N1 palette.", "Use shared SGODOT-178 fire, not new flames."]
    at = ROWS["hearth"]["position"][:]; at[1] += 1.53
    mantel = source_parts("hearth_mantel", path, "KIT_hearth_mantel_details", at, 90,
        keep=lambda n: n.startswith("Deep oak mantel shelf"), origin=[2.14, 1.53, -1.72], choose=lambda _: "stone")
    for obj in mantel["objects"]:
        transform = Matrix.Diagonal((1, 1, .08 / .15, 1)); transform.translation.z = .075 * (1 - .08 / .15)
        remap_positions(obj, transform)
    decor_at = at[:]; decor_at[1] -= .01
    source_parts("mantel_decor", path, "KIT_hearth_mantel_details", decor_at, 90,
        keep=lambda n: n.startswith(("Brass candlestick", "Cream wax candle")), origin=[2.14, 1.53, -1.72],
        choose=lambda o: "brass" if "candlestick" in o.name else "porcelain")
    p.b.CURRENT = p.KITS["mantel_decor"]
    # A static reflected room impression, not a second camera or realtime mirror pass.
    points = [(math.cos(a) * .34, .72 + math.sin(a) * .51, .12) for a in [i * math.tau / 64 for i in range(65)]]
    tube("Oval gilded mirror frame", points, .024, "accent_gold", 8)
    vertices = [(math.cos(i * math.tau / 64) * .317, .72 + math.sin(i * math.tau / 64) * .487, .125) for i in range(64)]
    mirror = role(p.mesh("mirror_reflection", vertices, [tuple(range(64))], "sky"), "sky", "front")
    face_front(mirror)
    cube("Small mantel picture backing", (-.43, .235, .30), (.20, .28, .025), "linen", .006)
    for x in [-.535, -.325]: cube("Small mantel picture side", (x, .235, .319), (.016, .30, .025), "accent_gold", .004)
    for y in [.093, .377]: cube("Small mantel picture crossbar", (-.43, y, .319), (.22, .016, .025), "accent_gold", .004)
    PROVENANCE["hearth_mantel"]["changes"] = ["Only mantel shelf selected; thin from .15 to .08 m while retaining its top and supported decor; warm mid-grey stone palette."]
    PROVENANCE["mantel_decor"]["changes"] = ["Original two candlesticks and candles retained; new oval mirror and small frame; no original room lamps."]


def face_front(obj):
    bm = bmesh.new(); bm.from_mesh(obj.data)
    bmesh.ops.reverse_faces(bm, faces=[f for f in bm.faces if f.normal.y > 0])
    bm.to_mesh(obj.data); bm.free()


def walls_and_luggage():
    begin("elevator", notes=["Closed decorative brass double door, no digits, service or opening."])
    cube("Elevator dark backing", (0, 1.30, 0), (1.4, 2.60, .12), "wood_dark", .012)
    for x in [-.32, .32]: cube("Closed brushed brass elevator panel", (x, 1.29, .063), (.625, 2.42, .022), "brass", .008)
    for x in [-.66, .66]: cube("Elevator bronze jamb", (x, 1.30, .061), (.07, 2.60, .05), "accent_gold", .009)
    for y in [.035, 2.565]: cube("Elevator head and sill", (0, y, .061), (1.33, .07, .05), "accent_gold", .008)
    cube("Elevator central closed seam", (0, 1.29, .077), (.012, 2.42, .006), "wood_mid", .002)
    path = ROOT / "tools/art/source/post_office/post_office.blend"
    kit = source_parts("key_rack", path, "KIT_sorting_cabinet", ROWS["key_rack"]["position"], keep=lambda n:
        n.startswith(("Sorting cabinet back", "Sorting cabinet stile", "Cabinet oak crown", "Mail cubby shelf", "Vertical cubby separator")), choose=lambda _: "wood_dark")
    # Convert a floor sorting cabinet into a shallow wall key rack, retaining its 2.21 m width.
    for obj in kit["objects"]:
        low = np.min([v.co[:] for v in obj.data.vertices], axis=0)
        high = np.max([v.co[:] for v in obj.data.vertices], axis=0)
        if obj.name.startswith("Sorting cabinet back"):
            target_low, target_high = 0.0, 1.27
        elif obj.name.startswith("Sorting cabinet stile"):
            target_low, target_high = 0.0, 1.30
        elif obj.name.startswith("Cabinet oak crown"):
            target_low, target_high = 1.15, 1.30
        elif obj.name.startswith("Mail cubby shelf"):
            center = .5 * (low[2] + high[2]); index = round((center - .91) / .39)
            target_low, target_high = .02 + index * .37, .065 + index * .37
        else: target_low, target_high = .03, 1.17
        sy = (target_high - target_low) / max(high[2] - low[2], .001)
        matrix = Matrix.Diagonal((1, .36 / .61, sy, 1))
        matrix.translation.z = target_low - low[2] * sy
        remap_positions(obj, matrix)
    kit["collision"] = [dict(at=[0, .65, 0], size=[2.21, 1.30, .36])]
    p.b.CURRENT = kit
    for x in [-.76, -.25, .25, .76]:
        for y in [.18, .55, .92]:
            tube("Key peg", [(x, y + .14, -.10), (x, y + .14, .02)], .012, "brass", 6)
            points = [(x + .033 * math.cos(a), y + .09 + .033 * math.sin(a), .04) for a in [i * math.tau / 12 for i in range(13)]]
            tube("Brass key ring", points, .009, "accent_gold", 6)
            cube("Key stem", (x, y + .01, .04), (.015, .12, .018), "brass", .003)
            cube("Key tooth", (x + .016, y - .033, .04), (.038, .018, .018), "brass", .002)
    for x in [-.82, .82]: cube("Key rack concealed wall standoff", (x, .93, -.25), (.08, .22, .18), "wood_dark", .005)
    PROVENANCE["key_rack"]["changes"] = ["Remove floor drawers, labels and handles; retain 2.21 m width, rebuild upper cubbies as 1.30 m high shallow hanging key rack.", "12 keys and wall mounting standoffs added; no letters or transactions."]
    kit = source_parts("wall_clock", path, "KIT_wall_clock", [-.28, 2.61, -2.955], choose=lambda o:
        "wood_dark" if "rim" in o.name else "porcelain" if "dial" in o.name else "iron")
    PROVENANCE["wall_clock"]["changes"] = ["Original .78 m diameter and 592-triangle geometry retained; recolor only; tick marks, no numerals."]
    for i, x in enumerate([.62, 1.52], 2): p.instance("wall_clock", "wall_clock_%d" % i, [x, 2.61, -2.955])
    begin("blank_name_plaque", [.62, 3.20, -2.95])
    cube("Blank cream runtime name plate", (0, 0, 0), (1.68, .30, .035), "porcelain", .008)
    for x in [-.825, .825]: cube("Name plaque end trim", (x, 0, .025), (.03, .30, .025), "accent_gold", .005)
    for y in [-.135, .135]: cube("Name plaque long trim", (0, y, .025), (1.68, .03, .025), "accent_gold", .004)
    PROVENANCE["blank_name_plaque"]["changes"] = ["N1 v1.1: 1.68 x .30 m frame around a 1.60 x .22 m runtime text area; mounting pivot retained."]
    begin("luggage_cart", notes=["New .95 x .77 m cart with three leather cases inside its footprint."])
    cube("Cart wood platform", (0, .21, 0), (.88, .07, .68), "wood_mid", .025)
    for z in [-.35, .35]: cube("Cart brass platform edge", (0, .22, z), (.92, .045, .035), "brass", .012)
    for x in [-.46, .46]: cube("Cart brass side edge", (x, .22, 0), (.03, .045, .72), "brass", .01)
    for x in [-.34, .34]:
        for z in [-.26, .26]:
            obj = cyl("Quiet luggage caster", (x, .08, z), .08, .055, "iron", 16)
            obj.rotation_euler.y = math.pi / 2
            cube("Caster bronze fork", (x, .16, z), (.06, .11, .035), "brass", .007)
    points = [(-.40, .245, -.27), (-.40, 1.38, -.27)]
    points += [(math.cos(a) * .40, 1.38 + math.sin(a) * .29, -.27) for a in [math.pi - i * math.pi / 20 for i in range(21)]]
    points += [(.40, .245, -.27)]
    tube("Bellhop cart arched brass rail", points, .028, "brass", 10)
    blob("Cart crown finial", (0, 1.70, -.27), (.07, .09, .07), "accent_gold", 12, 6)
    for index, (at, size) in enumerate([((-.22, .245, .02), (.35, .53, .43)), ((.20, .245, .02), (.36, .70, .43)), ((-.20, .775, .01), (.39, .22, .38))]):
        x, y, z = at; w, h, d = size
        cube("Leather suitcase %d" % index, (x, y + h / 2, z), (w, h, d), "leather", .035)
        for dx in [-w * .29, w * .29]:
            cube("Suitcase stitched strap", (x + dx, y + h / 2, z + d / 2 + .003), (.025, h * .95, .008), "wood_dark", .003)
            cube("Suitcase brass buckle", (x + dx, y + h * .62, z + d / 2 + .011), (.04, .035, .012), "brass", .004)
        tube("Suitcase carry handle", [(x - .07, y + h, z), (x - .06, y + h + .06, z), (x + .06, y + h + .06, z), (x + .07, y + h, z)], .014, "wood_dark", 8)


def bookcase_and_lamp():
    begin("low_bookshelf")
    cube("Bookcase backing", (0, .56, -.192), (.90, 1.08, .028), "wood_dark", .008)
    for x in [-.425, .425]: cube("Bookcase upright", (x, .55, 0), (.05, 1.10, .42), "wood_mid", .012)
    for y in [.06, .40, .73, 1.07]: cube("Bookcase shelf", (0, y, 0), (.89, .06, .42), "wood_mid", .012)
    for level, y in enumerate([.09, .43, .76]):
        for i in range(7):
            x = -.345 + i * .113; h = .25 + .025 * ((i + level) % 3)
            c = ["linen", "sage", "wood_mid", "brass", "leather", "porcelain", "sage_dark"][(i + 2 * level) % 7]
            cube("Book pages", (x, y + h / 2, .035), (.077, h, .25), "linen", 0)
            cube("Book cloth spine", (x, y + h / 2, .165), (.088, h + .008, .022), c, .006)
            for yy in [y + .045, y + h - .045]: cube("Book spine gilt band", (x, yy, .178), (.075, .009, .004), "accent_gold", 0)
    begin("floor_lamp")
    lathe("Floor lamp weighted base", (0, 0, 0), [(0, .21), (.045, .21), (.075, .15), (.09, .055)], "brass", 32)
    cyl("Floor lamp slender stem", (0, .80, 0), .023, 1.46, "brass", 16)
    lathe("White linen standing shade", (0, 0, 0), [(1.49, .255), (1.53, .255), (1.84, .14), (1.87, .14), (1.87, .128), (1.83, .128), (1.53, .24), (1.49, .24)], "porcelain", 40)
    lathe("Shade lower seam", (0, 1.49, 0), [(0, .257), (.018, .257), (.018, .25), (0, .25)], "linen", 40)
    blob("Floor lamp finial", (0, 1.884, 0), (.04, .032, .04), "brass", 12, 6)


def rugs():
    begin("green_rug", [1.05, .081, .65])
    obj = cube("green_rug", (0, .001, 0), (3.85, .002, 3.80), "cloth_green", .001)
    obj["uv_mode"] = "top"
    for x in [-1.905, 1.905]: cube("Rug warm bound edge", (x, .0022, 0), (.025, .001, 3.8), "accent_gold", .0002)
    for z in [-1.88, 1.88]: cube("Rug warm bound edge", (0, .0022, z), (3.85, .001, .025), "accent_gold", .0002)
    begin("cowhide_rug", [-1.43, .081, .10], 90)
    outline = []
    for i in range(80):
        a = i * math.tau / 80
        r = 1 + .14 * math.cos(4 * a) + .07 * math.sin(3 * a + .7) + .025 * math.sin(11 * a)
        outline.append((math.sin(a) * .54 * r, math.cos(a) * .43 * r))
    verts = [(x, y, z) for y in [0, .003] for x, z in outline]
    n = len(outline)
    faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    obj = role(p.mesh("cowhide_rug", verts, faces, "print_portrait"), "print_portrait", "top")
    PROVENANCE["cowhide_rug"]["changes"] = ["New 316-triangle flat contoured hide, not the 7,838-triangle Mine Hut rug."]


def source_uvs(atlas):
    mat = bpy.data.materials.new("N1 editable atlas preview"); mat.use_nodes = True
    texture = mat.node_tree.nodes.new("ShaderNodeTexImage"); texture.image = atlas
    mat.node_tree.links.new(texture.outputs["Color"], mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
    mat.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = .82
    for kit in p.KITS.values():
        for obj in kit["objects"]:
            data = obj.data
            for layer in list(data.uv_layers): data.uv_layers.remove(layer)
            uv = data.uv_layers.new(name="N1Atlas")
            role_ = obj["hall_role"]
            u0, v0, u1, v1 = PALETTE[role_]["uv_rect_gltf"]
            points = np.array([v.co[:] for v in data.vertices]); lo, hi = points.min(0), points.max(0)
            mode = obj.get("uv_mode", "point")
            axes = [0, 1] if mode == "top" else [0, 2]
            for loop in data.loops:
                if mode == "point": coords = ((u0 + u1) / 2, 1 - (v0 + v1) / 2)
                else:
                    q = data.vertices[loop.vertex_index].co
                    u = (q[axes[0]] - lo[axes[0]]) / max(hi[axes[0]] - lo[axes[0]], .0001)
                    v = (q[axes[1]] - lo[axes[1]]) / max(hi[axes[1]] - lo[axes[1]], .0001)
                    coords = (u0 + u * (u1 - u0), 1 - v1 + v * (v1 - v0))
                uv.data[loop.index].uv = coords
            data.materials.clear(); data.materials.append(mat)
            for face in data.polygons: face.material_index = 0


def export_module(name):
    kit = p.KITS[name]
    bpy.context.view_layer.update(); deps = bpy.context.evaluated_depsgraph_get()
    inv = kit["root"].matrix_world.inverted()
    groups = sorted({obj.get("export_group", "Body") for obj in kit["objects"]})
    exports = []
    for group in groups:
        copies = []
        bpy.ops.object.select_all(action="DESELECT")
        for src in kit["objects"]:
            if src.get("export_group", "Body") != group: continue
            data = bpy.data.meshes.new_from_object(src.evaluated_get(deps), depsgraph=deps)
            data.transform(inv @ src.matrix_world)
            obj = bpy.data.objects.new(src.name + " export", data); bpy.context.scene.collection.objects.link(obj)
            obj.select_set(True); copies.append(obj)
        bpy.context.view_layer.objects.active = copies[0]
        if len(copies) > 1: bpy.ops.object.join()
        obj = bpy.context.object; obj.name = group
        obj.data.name = name + ("_artwork" if group == "Artwork" else "") + "_mobile"
        data = obj.data
        # Scalar module-local AO uses the repository's landmark_kit 8-ray recipe.
        # Color remains in the single room atlas; COLOR_0 only modulates contact shade.
        bvh = BVHTree.FromPolygons([v.co for v in data.vertices], [list(f.vertices) for f in data.polygons])
        ao = data.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
        data.color_attributes.active_color = ao; data.color_attributes.render_color_index = data.color_attributes.find("Color")
        cache = {}
        for face in data.polygons:
            for li in face.loop_indices:
                vi = data.loops[li].vertex_index; normal = data.corner_normals[li].vector.normalized()
                key = (vi, tuple(round(c, 2) for c in normal))
                if key not in cache:
                    tangent = normal.cross(Vector((0, 0, 1)))
                    if tangent.length < .01: tangent = normal.cross(Vector((1, 0, 0)))
                    tangent.normalize(); bitangent = normal.cross(tangent)
                    origin = data.vertices[vi].co + normal * .006; hits = 0.0
                    for i in range(8):
                        angle = i * 2.399; r = math.sqrt((i + .5) / 8) * .88
                        direction = (normal * math.sqrt(1 - r * r) + tangent * math.cos(angle) * r + bitangent * math.sin(angle) * r).normalized()
                        hit = bvh.ray_cast(origin, direction, .30)
                        if hit[0] is not None: hits += 1 - hit[3] / .30
                    cache[key] = 1 - .36 * hits / 8
                shade = cache[key] if group != "Artwork" else 1.0
                ao.data[li].color = (shade, shade, shade, 1)
        mat = bpy.data.materials.get("N1 export scalar AO")
        if mat is None:
            mat = bpy.data.materials.new("N1 export scalar AO"); mat.use_nodes = True
            vc = mat.node_tree.nodes.new("ShaderNodeVertexColor"); vc.layer_name = "Color"
            mat.node_tree.links.new(vc.outputs["Color"], mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
        data.materials.clear(); data.materials.append(mat)
        for face in data.polygons: face.material_index = 0
        exports.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in exports: obj.select_set(True)
    path = OUT / (name + ".glb")
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_yup=True,
        export_vertex_color="ACTIVE", export_materials="EXPORT", export_image_format="NONE", export_animations=False,
        export_cameras=False, export_lights=False)
    triangles = 0
    for obj in exports:
        obj.data.calc_loop_triangles(); triangles += len(obj.data.loop_triangles)
        bpy.data.objects.remove(obj, do_unlink=True)
    raw = path.read_bytes(); length = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + length]); tail = raw[20 + length:]
    doc["images"] = [{"uri": "room_albedo_ao.png"}]; doc["textures"] = [{"source": 0}]
    doc["materials"] = [{"name": "HotelHallAtlas", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1],
        "baseColorTexture": {"index": 0}, "metallicFactor": 0, "roughnessFactor": .78}, "alphaMode": "OPAQUE",
        "extensions": {"KHR_materials_specular": {"specularFactor": .48}}}]
    doc["extensionsUsed"] = sorted(set(doc.get("extensionsUsed", [])) | {"KHR_materials_specular"})
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            prim["material"] = 0
            assert "COLOR_0" in prim["attributes"]
    encoded = json.dumps(doc, separators=(",", ":")).encode(); encoded += b" " * (-len(encoded) % 4)
    path.write_bytes(struct.pack("<III", 0x46546C67, 2, 20 + len(encoded) + len(tail)) + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded + tail)
    relative = "res://" + str(path.relative_to(ROOT)); target = "res://.godot/imported/" + path.name + "-" + hashlib.md5(relative.encode()).hexdigest() + ".scn"
    import_path = Path(str(path) + ".import")
    if not import_path.exists():
        template = (HALL / "hall_floor.glb.import").read_text()
        template = re.sub(r'uid="[^\"]+"\n', "", template)
        template = re.sub(r'res://.godot/imported/hall_floor.glb-[^\"]+.scn', target, template)
        template = template.replace("res://assets/rooms/_shared/shell_hall/hall_floor.glb", relative)
        template = template.replace('import_script/path=""', 'import_script/path="res://assets/rooms/poi_hotel_lobby/material_import.gd"')
        import_path.write_text(template)
    else:
        template = import_path.read_text()
        template = re.sub(r'import_script/path="[^\"]*"', 'import_script/path="res://assets/rooms/poi_hotel_lobby/material_import.gd"', template)
        import_path.write_text(template)
    PROVENANCE[name].update(triangles=triangles, surfaces=len(groups), exported_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    dump(OUT / "provenance" / name / "reuse_provenance.json", PROVENANCE[name])
    print("N1_EXPORTED", name, triangles, flush=True)
    return {"name": name, "triangles": triangles, "surfaces": len(groups), "bytes": path.stat().st_size}


def main():
    p.start("poi_hotel_lobby", "SGODOT-315 approved R3 / SGODOT-319 5fe1b06c")
    p.OUT, p.SOURCE, p.QA = OUT, SOURCE, QA
    for path in [OUT, SOURCE, QA]: path.mkdir(parents=True, exist_ok=True)
    (SOURCE / ".gdignore").touch()
    p.b.PALETTE.update({role_: slot["hex_srgb"] for role_, slot in PALETTE.items()})
    ring_sofa(); reused_furniture(); hearth(); walls_and_luggage(); bookcase_and_lamp(); rugs()
    atlas = bpy.data.images.load(str(OUT / "room_albedo_ao.png")); atlas.pack()
    source_uvs(atlas)
    analysis = json.loads((QA / "plan/plan-validation.json").read_text())
    assert analysis["passed"]
    for seat in analysis["seats"]:
        if seat["module"] == "armchair_back": seat["module"] = "cream_armchair"
    seats = [{key: seat[key] for key in ["name", "module", "position", "yaw_degrees", "stand"]} for seat in analysis["seats"]]
    p.MANIFEST_EXTRA.update(floor_y=.08, footprint=[6.8, 6.4], revision="SGODOT-319 N1 v1.1",
        lighting={"angular_distance": .4},
        shared_shell="res://scenes/shell_hall/shell_hall_art.tscn", shell_atlas="res://assets/rooms/poi_hotel_lobby/room_albedo_ao.png",
        anchors=seats + [dict(name="spawn", position=PLAN["spawn"], yaw_degrees=180, module="hall_floor"),
            dict(name="cam_default", position=PLAN["spawn"], yaw_degrees=45, module="hall_floor",
                role="camera_follow_target", pitch_degrees=43, orthographic_width=6.72, near=.1, far=40),
            dict(name="exit", position=PLAN["exit"], yaw_degrees=180, module="hall_floor"),
            dict(name="badge_exit", position=[PLAN["exit"][0], .55, 3.0], yaw_degrees=0, module="hall_floor"),
            dict(name="sign_name", position=[.62, 3.20, -2.92], yaw_degrees=180, module="blank_name_plaque", size=[1.60, .22])],
        standing_16=analysis["standing_16"],
        shared_plants=[dict(name="plant_elevator", file="olive_tree.glb", position=ROWS["plant_elevator"]["position"], yaw_degrees=30, collision_radius=.31),
            dict(name="plant_cart", file="olive_tree.glb", position=ROWS["plant_cart"]["position"], yaw_degrees=125, collision_radius=.31)],
        shared_fire=dict(scene="res://assets/rooms/_shared/fx/fx_hearth_fire.tscn", position=[-2.23, .38, .10], yaw_degrees=90,
            emission_box=[.23, .015, .055], flame_height=.52, flame_count=16, spark_count=4, light_energy=1.4, light_range=1.7))
    lights = []
    for name in ["table_sofa_left", "table_sofa_right", "table_sofa_back"]:
        x, _, z = ROWS[name]["position"]
        lights.append(dict(name="warm_" + name, kind="spot", position=[x, 1.24575, z], target=[x, .97575, z], color="FFD3A0", energy=.35, range=1.1, angle_degrees=65))
    x, _, z = ROWS["floor_lamp"]["position"]
    lights.append(dict(name="floor_lamp_warmth", kind="omni", position=[x, 1.61, z], color="FFD5A6", energy=.65, range=2.1))
    p.MANIFEST_EXTRA["local_lights"] = lights
    p.finalize({"position": [10.3429, 15.64, 10.3429], "target": [0, 2, 0], "size": 11, "pitch_degrees": 43,
        "yaw_degrees": 45, "near": .1, "far": 40}, json.loads((HALL / "layout.json").read_text())["review_lighting"])
    if "--geometry-only" not in sys.argv:
        selected_arg = next((arg.split("=", 1)[1] for arg in sys.argv if arg.startswith("--asset=")), "")
        selected = set(selected_arg.split(",")) if selected_arg else set()
        assert selected.issubset(p.KITS)
        previous_stats = json.loads((OUT / "asset_stats.json").read_text()) if selected else {}
        previous_provenance = json.loads((OUT / "reuse_provenance.json").read_text()) if selected else {}
        assets = []
        for name in p.KITS:
            if selected and name not in selected:
                assets.append(next(row for row in previous_stats["assets"] if row["name"] == name))
                PROVENANCE[name] = previous_provenance[name]
            else:
                assets.append(export_module(name))
        lookup = {a["name"]: a for a in assets}
        stats = {"assets": assets, "unique_triangles": sum(a["triangles"] for a in assets),
            "furniture_scene_triangles": sum(a["triangles"] for a in assets) + sum(lookup[i["asset"]]["triangles"] for i in p.INSTANCES),
            "furniture_surfaces": sum(a["surfaces"] for a in assets) + sum(lookup[i["asset"]]["surfaces"] for i in p.INSTANCES)}
        shell = json.loads((HALL / "shell_asset_stats.json").read_text())
        stats.update(scene_triangles=stats["furniture_scene_triangles"] + shell["scene_triangles"] + 2868 * 2,
            static_draw_surfaces=stats["furniture_surfaces"] + shell["static_draw_surfaces"] + 2,
            shared_fire_draws=2, atlas={"file": "room_albedo_ao.png", "size": [2048, 2048], "shared_plant_and_fx_textures": "unchanged existing library assets"})
        stats.update(dynamic_particle_triangles_max=40, scene_triangles_with_particles_max=stats["scene_triangles"] + 40,
            draw_surfaces_with_fx=stats["static_draw_surfaces"] + 2)
        assert stats["scene_triangles"] <= 150000 and stats["static_draw_surfaces"] + 2 <= 50
        assert lookup["cowhide_rug"]["triangles"] <= 1000
        dump(OUT / "asset_stats.json", stats)
        dump(OUT / "reuse_provenance.json", PROVENANCE)
        print("N1_BUDGET", stats["scene_triangles"], stats["static_draw_surfaces"], flush=True)


if __name__ == "__main__": main()
