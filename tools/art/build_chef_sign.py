"""SGODOT-282 Chef's Sign. Blender 5.2; metres, Godot +Y up / +Z front.

blender --background --factory-startup --python "$PWD/tools/art/build_chef_sign.py"
Only the two chef signs and their manifest entries are exported. Source retains
named editable construction parts. Uses the accepted SGODOT-290 export pipeline.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_decor_assets as kit

# v1.2: author the arm to the LEFT directly, with positive runtime scale.
# This coordinate reflection reaches every part, including eye bolts and rings;
# kit.mesh recalculates the reflected winding, rather than exporting -1 scale.
kit.v = lambda p: Vector((-p[0], -p[2], p[1]))

SOURCE = kit.ROOT / "tools/art/source/chef_sign_282"
BOARD = (.382, 1.285, 0)
PALETTE = {
    "chef_red": "983f35", "chef_red_edge": "80382f",
    "chef_gold": "e6b954", "chef_gold_edge": "bb8b3e",
    "chef_white": "fff3dd", "chef_white_shade": "e3d6bc",
    "chef_iron": "655b49", "chef_stone": "b9b9af",
    "chef_stone_light": "d2d0c5",
}


def rounded_rect(w, h, radius, steps=5):
    points = []
    for x, y, start in [(w/2-radius,h/2-radius,0),
                        (-w/2+radius,h/2-radius,90),
                        (-w/2+radius,-h/2+radius,180),
                        (w/2-radius,-h/2+radius,270)]:
        for i in range(steps):
            a = math.radians(start+i*90/(steps-1))
            points.append((x+radius*math.cos(a),y+radius*math.sin(a)))
    return points


def relief(name, points, center, back, front, color, edge=None, inset=.0):
    """Closed extruded silhouette; optional small bevel on its front edge."""
    cx,cy = center
    loops = [(points,back),(points,front-inset)] if inset else [(points,back),(points,front)]
    if inset:
        # About local centre; selected only for convex/soft icon outlines.
        factor = 1-inset/max(max(abs(x),abs(y)) for x,y in points)
        loops.append(([(x*factor,y*factor) for x,y in points],front))
    n = len(points)
    vertices = [(cx+x,cy+y,z) for ring,z in loops for x,y in ring]
    faces = [tuple(reversed(range(n)))]
    for j in range(len(loops)-1):
        faces += [(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for i in range(n)]
    faces.append(tuple(range((len(loops)-1)*n,len(loops)*n)))
    obj = kit.mesh(name,vertices,faces,color)
    if edge:
        obj.data.materials.append(kit.MATS[edge])
        for p in obj.data.polygons[:-1]: p.material_index = 1
    return obj


def ring(name, x, y, plane):
    """8 x 4 low-poly closed oval ring, alternate planes to visibly interlock."""
    vertices = []
    for i in range(8):
        a = math.tau*i/8
        for j in range(4):
            b = math.tau*j/4
            u = (.014+.005*math.cos(b))*math.cos(a)
            v = (.023+.005*math.cos(b))*math.sin(a)
            d = .005*math.sin(b)
            vertices.append((x+(u if plane=="XY" else d),y+v,d if plane=="XY" else u))
    faces = [(i*4+j,((i+1)%8)*4+j,((i+1)%8)*4+(j+1)%4,i*4+(j+1)%4)
             for i in range(8) for j in range(4)]
    return kit.mesh(name,vertices,faces,"chef_iron",True)


def board():
    cx,cy,_ = BOARD
    # The gold frame is a true 0.05 m deep annulus, not a floating line decal.
    outer = rounded_rect(.60,.45,.052)
    inner = rounded_rect(.568,.418,.038)
    n = len(outer)
    rings = [(outer,-.025),(outer,.019),(inner,.025),(inner,-.025)]
    verts = [(cx+x,cy+y,z) for points,z in rings for x,y in points]
    faces = []
    for j in range(4):
        faces += [(j*n+i,j*n+(i+1)%n,((j+1)%4)*n+(i+1)%n,((j+1)%4)*n+i) for i in range(n)]
    obj = kit.mesh("Board / solid warm gold rounded frame",verts,faces,"chef_gold")
    obj.data.materials.append(kit.MATS["chef_gold_edge"])
    for poly in obj.data.polygons:
        if poly.index < n or poly.index >= 3*n: poly.material_index=1
    relief("Board / deep warm red inset",rounded_rect(.570,.420,.039),(cx,cy),-.024,.020,
           "chef_red","chef_red_edge")
    # Single continuous white toque silhouette: no text or fine surface noise.
    hat = [(-.064,-.080),(.064,-.080),(.072,-.015),(.094,-.010),(.116,.006),
           (.128,.030),(.124,.049),(.112,.065),(.094,.075),(.076,.074),
           (.067,.096),(.046,.115),(.022,.122),(-.004,.118),(-.027,.104),
           (-.041,.081),(-.063,.088),(-.086,.083),(-.107,.067),(-.116,.043),
           (-.111,.020),(-.095,.000),(-.071,-.006)]
    hat=[(x*1.05,y*.78) for x,y in hat]
    relief("Emblem / cream chef toque",hat,(cx,1.375),.019,.035,"chef_white","chef_white_shade",.003)
    # Low, broad cuff and two short folds; the silhouette does the recognition work.
    relief("Emblem / toque cuff",rounded_rect(.133,.023,.008,3),(cx,1.324),.034,.038,"chef_white_shade")
    for x in [-.032,.032]:
        relief("Emblem / short toque fold",rounded_rect(.009,.027,.004,3),(cx+x,1.349),.034,.037,"chef_white_shade")
    fork = [(-.010,-.106),(.010,-.106),(.010,.012),(.030,.035),(.038,.056),
            (.038,.105),(.025,.105),(.025,.065),(.009,.065),(.009,.108),
            (-.004,.108),(-.004,.065),(-.020,.065),(-.020,.105),
            (-.033,.105),(-.033,.053),(-.026,.034),(-.010,.012)]
    spoon = [(-.010,-.106),(.010,-.106),(.010,.030),(.027,.043),(.038,.063),
             (.041,.083),(.033,.103),(.015,.118),(-.008,.120),(-.027,.108),
             (-.037,.088),(-.035,.067),(-.025,.046),(-.010,.030)]
    for name,points,degrees,z in [("fork",fork,46,.034),("spoon",spoon,-46,.030)]:
        a = math.radians(degrees)
        points = [(x*math.cos(a)-y*math.sin(a),x*math.sin(a)+y*math.cos(a)) for x,y in points]
        relief("Emblem / crossed gold "+name,points,(cx,1.199),.019,z,"chef_gold","chef_gold_edge",.0015)
    star = []
    for i in range(10):
        a = math.pi/2+i*math.pi/5
        r = .024 if i%2==0 else .011
        star.append((r*math.cos(a),r*math.sin(a)))
    relief("Emblem / one small gold star",star,(cx,1.108),.019,.032,"chef_gold","chef_gold_edge")


def sign(variant):
    name = "chef_sign_"+variant
    kit.begin(name,[1,1],1500,generator="tools/art/build_chef_sign.py",
        pivot="post foot bottom centre",front="+Z",footprint=.65,
        board_bottom=1.06,board_size=[.60,.45,.05],board_center=[-BOARD[0],BOARD[1],BOARD[2]],
        collider={"shape":"box","at":[0,.87,0],"size":[.28,1.74,.28]},
        collision_note="Post and foot only; suspended board/arm have no collision.",
        placement_note="v1.2 anchor (6,14): arm directly to -X / camera-left, +Z front, positive scale. One 0.65 m anchor cell; overhang must avoid path/crop/occupied cells.",
        arm_direction="-X",overhang_bounds=[[-.682,1.06,-.025],[-.082,1.51,.038]],
        variant="warm wood foot" if variant=="a" else "three pale grey stone foot blocks")
    # Join about the identical post in both variants. This also keeps Blender's
    # custom-normal encoding identical when the different feet are merged.
    kit.box("Structure / continuous warm wood post",(0,.93,0),(.13,1.62,.13),"wood_light",.014)
    if variant=="a":
        kit.box("Foot / square warm wood plinth",(0,.07,0),(.26,.14,.26),"wood_light",.018)
    else:
        # Three simple blocks, no texture/stone speckles, maximum width/depth 0.28 m.
        kit.box("Foot / stone front left",(-.071,.10,.057),(.138,.20,.166),"chef_stone_light",.014)
        kit.box("Foot / stone front right",(.071,.10,.057),(.138,.20,.166),"chef_stone",.014)
        kit.box("Foot / stone rear block",(0,.10,-.084),(.28,.20,.112),"chef_stone_light",.014)
    kit.box("Structure / lateral wood arm",(.275,1.65,0),(.66,.10,.11),"wood_light",.012)
    kit.beam("Structure / short supporting knee",(.045,1.49,0),(.145,1.606,0),.046,"wood",depth=.07,radius=.006)
    for i,x in enumerate([.192,.562]):
        kit.rod("Hanger %d / upper eye bolt shank"%i,(x,1.600,0),(x,1.618,0),.009,"chef_iron",6)
        ring("Hanger %d / arm eye"%i,x,1.585,"XY")
        ring("Hanger %d / interlocking short link"%i,x,1.555,"YZ")
        ring("Hanger %d / frame eye"%i,x,1.525,"XY")
        kit.rod("Hanger %d / lower eye bolt shank"%i,(x,1.499,0),(x,1.510,0),.009,"chef_iron",6)
    board()
    kit.socket("board_center",BOARD)
    kit.META[name]["sockets"]["board_center"]["position"]=[-BOARD[0],BOARD[1],BOARD[2]]
    next(obj for obj in kit.CURRENT.objects if obj.type=="EMPTY").name=name+" / board_center"


def main():
    SOURCE.mkdir(parents=True,exist_ok=True)
    (SOURCE/".gdignore").touch()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections): bpy.data.collections.remove(collection)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.unit_settings.system="METRIC"
    for name,value in {**kit.PALETTE,**PALETTE}.items():
        mat=bpy.data.materials.new(name)
        mat.diffuse_color=(*kit.rgb(value),1)
        mat.use_nodes=True
        shader=mat.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value=mat.diffuse_color
        shader.inputs["Roughness"].default_value=.9
        kit.MATS[name]=mat
    material=bpy.data.materials.new("Farm vertex paint")
    material.use_nodes=True
    shader=material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value=.9
    shader.inputs["Specular IOR Level"].default_value=.18
    color=material.node_tree.nodes.new("ShaderNodeVertexColor")
    color.layer_name="Color"
    material.node_tree.links.new(color.outputs["Color"],shader.inputs["Base Color"])
    sign("a")
    sign("b")
    manifest=json.loads((kit.OUT/"manifest.json").read_text())
    for name,collection in kit.ASSETS.items():
        marker=next(obj for obj in collection.objects if obj.type=="EMPTY")
        marker.name="board_center"
        manifest["assets"][name]=kit.export_asset(name,collection,material)
        marker.name=name+" / board_center"
        print("CHEF_SIGN",name,manifest["assets"][name]["triangles"],flush=True)
    (kit.OUT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    # Side-by-side presentation only in source; exports above both use the foot origin.
    for obj in kit.ASSETS["chef_sign_b"].objects: obj.location.x+=1.2
    kit.ASSETS["chef_sign_b"]["source_display_offset_blender"]=[1.2,0,0]
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/"chef_sign_282.blend"))


if __name__=="__main__": main()
