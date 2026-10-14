#!/usr/bin/env python3
"""Rebuild SGODOT-284, using exact existing GLB vertex colors and 290 helpers.

Run: blender --background --factory-startup --python "$PWD/tools/art/build_notice_board.py"
Godot metres, Y up, +Z front; editable source parts keep descriptive names.
"""
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_decor_assets as kit
from verify_chef_sign import load_glb, accessor

SOURCE = kit.ROOT / "tools/art/source/notice_board_284"
FACE_Z = .060
# Hex values select existing samples only. Materials receive the original float
# vertex values, not re-created sRGB approximations or newly adjusted shades.
COLOR_SOURCES = {
    "post_wood": ("deco_bench", "a87948"),
    "frame_wood": ("deco_bench", "675139"),
    "cork_wood": ("storage", "cba067"),
    "roof_green": ("storage", "437d64"),
    "roof_edge": ("storage", "356551"),
    "paper_ivory": ("sign", "fff4d2"),
    "paper_milk": ("chef_sign_a", "fff3dd"),
    "paper_yellow": ("sign", "f1ce58"),
    "pin_red": ("chef_sign_a", "80382f"),
    "pin_gold": ("chef_sign_a", "e6b954"),
}
PAPERS = [
    (-.125, 1.263, .140, .155, -5, "paper_ivory", "pin_red"),
    (.120, 1.268, .120, .140, 6, "paper_yellow", "pin_gold"),
    (-.105, 1.080, .110, .125, 7, "paper_milk", "roof_green"),
    (.120, 1.090, .135, .145, -4, "paper_ivory", "pin_red"),
]


def source_palette():
    records = {}
    for name, (asset, approximate_hex) in COLOR_SOURCES.items():
        path = kit.OUT / (asset + ".glb")
        doc, binary = load_glb(path)
        prim = doc["meshes"][0]["primitives"][0]
        colors = accessor(doc, binary, prim["attributes"]["COLOR_0"])
        target = kit.rgb(approximate_hex)
        sample = min(colors, key=lambda c: sum((c[i]-target[i])**2 for i in range(3)))
        rgba = tuple(sample[:3]) + (1.0,)
        records[name] = {"asset": str(path.relative_to(kit.ROOT)),
                         "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                         "source_vertex": colors.index(sample), "linear_rgba": rgba,
                         "approximate_srgb_hex": approximate_hex}
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = rgba
        mat.use_nodes = True
        shader = mat.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = rgba
        shader.inputs["Roughness"].default_value = .9
        kit.MATS[name] = mat
    (SOURCE / "palette-provenance.json").write_text(json.dumps(records, indent=2) + "\n")


def outline(w, h, r):
    points = []
    for x, y, start in [(w/2-r,h/2-r,0),(-w/2+r,h/2-r,90),
                         (-w/2+r,-h/2+r,180),(w/2-r,-h/2+r,270)]:
        for i in range(3):
            a = math.radians(start+i*45)
            points.append((x+r*math.cos(a), y+r*math.sin(a)))
    return points


def board():
    # Solid rounded annulus: outside 0.56 x 0.44, rim 0.035, depth 0.050.
    outer = outline(.56, .44, .014)
    inner = outline(.49, .37, .009)
    n = len(outer)
    rings = [(outer,.020),(outer,.066),(outline(.554,.434,.013),.070),
             (inner,.070),(inner,.020)]
    verts = [(x,1.17+y,z) for shape,z in rings for x,y in shape]
    faces = []
    for j in range(len(rings)):
        k = (j+1) % len(rings)
        for i in range(n):
            q = (i+1) % n
            faces.append((j*n+i,j*n+q,k*n+q,k*n+i))
    kit.mesh("Board / solid dark wood frame", verts, faces, "frame_wood")
    kit.box("Board / plain recessed cork face",(0,1.17,.0395),(.495,.375,.041),"cork_wood",.004)
    for i,(x,y,w,h,degrees,paper_color,pin_color) in enumerate(PAPERS):
        a = math.radians(degrees)
        paper = kit.box("Paper %d / blank %s"%(i+1,paper_color),
                        (x,y,FACE_Z+.003), (w,h,.005),paper_color,.0013)
        paper.rotation_euler.y = -a
        # 20 mm round head sits into the paper; maximum relief = 12 mm.
        dx,dy = 0,h/2-.013
        pin_x,pin_y = x+dx*math.cos(a)-dy*math.sin(a),y+dx*math.sin(a)+dy*math.cos(a)
        kit.ellipsoid("Pin %d / small round %s"%(i+1,pin_color),
                      (pin_x,pin_y,.068),(.020,.020,.008),pin_color,10,5)


def roof():
    # Ridge along X; front and rear slopes, no texture or tile seams.
    # Eave underside 1.470; roof face extends 0.070 m past recessed board face.
    for sign in [-1,1]:
        z = sign*.13
        verts = [(x,y,zv) for x in [-.35,.35]
                 for y,zv in [(1.562,0),(1.470,z),(1.493,z),(1.586,0)]]
        faces = [(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
        obj = kit.mesh("Canopy / front slope" if sign==1 else "Canopy / rear slope",
                       verts,faces,"roof_green")
        kit.bevel(obj,.004)
    kit.box("Canopy / dark rounded ridge cap",(0,1.583,0),(.70,.024,.030),"roof_edge",.005)


def build():
    kit.begin("notice_board",[1,1],1200,generator="tools/art/build_notice_board.py",
              pivot="ground midpoint between posts",front="+Z",footprint=.65,
              board_bottom=.95,board_top=1.39,board_size=[.56,.44,.05],
              board_face_z=FACE_Z,board_center=[0,1.17,FACE_Z],
              collider={"shape":"box","at":[0,.80,0],"size":[.62,1.60,.14]},
              placement={"anchor_cell":[15,15],"storage_cell":[14,15],"well_cell":[15,13],
                         "storage_relative_position":[-.65,0,0],"well_relative_position":[0,0,1.30]},
              paper_count=4,paper_angles_degrees=[row[4] for row in PAPERS])
    for side,x in [("left",-.25),("right",.25)]:
        kit.box("Structure / %s square post"%side,(x,.80,0),(.07,1.51,.07),"post_wood",.006)
        kit.box("Foot / %s square plinth"%side,(x,.025,0),(.10,.05,.10),"post_wood",.007)
    # Chosen optional rail: joins the narrow pair visually without widening feet.
    kit.box("Structure / low connecting rail",(0,.30,0),(.50,.035,.045),"post_wood",.005)
    board()
    roof()
    kit.socket("board_center",(0,1.17,FACE_Z))
    kit.socket("mark",(0,1.75,0))


def main():
    SOURCE.mkdir(parents=True,exist_ok=True)
    (SOURCE/".gdignore").touch()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for col in list(bpy.data.collections): bpy.data.collections.remove(col)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.unit_settings.system="METRIC"
    source_palette()
    material=bpy.data.materials.new("Farm vertex paint")
    material.use_nodes=True
    shader=material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value=.9
    shader.inputs["Specular IOR Level"].default_value=.18
    color=material.node_tree.nodes.new("ShaderNodeVertexColor")
    color.layer_name="Color"
    material.node_tree.links.new(color.outputs["Color"],shader.inputs["Base Color"])
    build()
    manifest=json.loads((kit.OUT/"manifest.json").read_text())
    entry=kit.export_asset("notice_board",kit.ASSETS["notice_board"],material)
    manifest["assets"]["notice_board"]=entry
    (kit.OUT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/"notice_board.blend"))
    print("NOTICE_BOARD",entry["triangles"],entry["bounds"],flush=True)


if __name__ == "__main__": main()
