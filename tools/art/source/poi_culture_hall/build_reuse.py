"""Only the authorized N3 shell skin, seats, lamps and shared Monstera."""
from pathlib import Path
import hashlib
import json
import math
import struct
import sys
import bpy
import numpy as np
from mathutils import Matrix,Vector
from mathutils.bvhtree import BVHTree

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];OUT=ROOT/"assets/rooms/poi_culture_hall"
sys.path.insert(0,str(ROOT/"tools/art"))
import scene_room_pipeline as p
from verify_chef_sign import load_glb,accessor
SKIN=json.loads((OUT/"atlas_skin.json").read_text());PALETTE=SKIN["slots"]
PROVENANCE={};TEMPLATES={}
def dump(path,data):
    path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(data,indent=2)+"\n")
def begin(name,source,notes):
    p.begin(name,(0,0,0));PROVENANCE[name]=dict(author="ZHAOYUN",source=source,changes=notes,retained_parts=[])
def role(obj,key):
    obj["atlas_role"]=key;obj.data.materials.clear();obj.data.materials.append(p.material(key))
    for face in obj.data.polygons:face.material_index=0
    return obj
def cube(name,at,size,key,bevel=.008):return role(p.cube(name,at,size,key,bevel),key)
def cyl(name,at,r,h,key,n=20):return role(p.cylinder(name,at,r,h,key,vertices=n),key)
def template(path,collection):
    key=(str(path),collection)
    if key in TEMPLATES:return TEMPLATES[key]
    with bpy.data.libraries.load(str(path),link=False) as (src,dst):dst.collections=[collection]
    col=dst.collections[0];assert col is not None
    bpy.context.scene.collection.children.link(col);bpy.context.view_layer.update()
    root=next(o for o in col.objects if o.type=="EMPTY");inv=root.matrix_world.inverted();deps=bpy.context.evaluated_depsgraph_get();parts=[]
    for obj in col.objects:
        if obj.type!="MESH":continue
        data=bpy.data.meshes.new_from_object(obj.evaluated_get(deps),depsgraph=deps);data.transform(inv@obj.matrix_world)
        parts.append((obj.name,data,dict(obj.items())))
    for obj in list(col.objects):bpy.data.objects.remove(obj,do_unlink=True)
    bpy.data.collections.remove(col);TEMPLATES[key]=parts;return parts
def copy_part(part,name,key,botanical=False):
    kit=p.b.CURRENT;obj=bpy.data.objects.new(name,part[1].copy());kit["collection"].objects.link(obj)
    obj.parent=kit["root"];kit["objects"].append(obj);obj["source_part"]=part[0]
    PROVENANCE[kit["root"].name]["retained_parts"].append(part[0])
    if botanical:obj["botanical"]=True
    return role(obj,key)
def fit(obj,at,size):
    points=np.array([v.co[:] for v in obj.data.vertices]);lo,hi=points.min(0),points.max(0)
    scale=np.array([size[0],size[2],size[1]])/np.maximum(hi-lo,1e-6)
    xf=Matrix.Translation(p.v(at))@Matrix.Diagonal((*scale,1.0))@Matrix.Translation(Vector(-(lo+hi)/2))
    obj.data.transform(xf);obj.data.update()
def source_info(name,path,collection):
    PROVENANCE[name].update(source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),source_collection=collection)
def seats():
    path=ROOT/"tools/art/source/clothing_store_a/clothing_store_a.blend";parts=template(path,"KIT_black_tufted_bench")
    begin("gallery_bench",str(path.relative_to(ROOT)),["Retain four source legs and base frame; omit steel end runners and tiny stitches.",
        "Source continuous cushion adapted into three olive pads. Footprint .68 x 1.728 m and seat top .715 m match approved blockout."])
    legs=[q for q in parts if q[0].startswith("Black steel bench leg")]
    for part,(x,z) in zip(legs,[(x,z) for x in [-.25,.25] for z in [-.70,.70]]):fit(copy_part(part,"Adapted timber bench leg","wood_dark"),(x,.265,z),(.075,.53,.075))
    frame=next(q for q in parts if q[0]=="Bench black steel frame")
    obj=copy_part(frame,"Adapted bench underframe","wood_dark");obj.data.transform(Matrix.Rotation(math.pi/2,4,"Z"));fit(obj,(0,.535,0),(.66,.08,1.70))
    cushion=next(q for q in parts if q[0]=="Leather continuous cushion")
    for i,z in enumerate([-.579,0,.579]):
        obj=copy_part(cushion,"Olive seat pad %d"%(i+1),"cloth_green");obj.data.transform(Matrix.Rotation(math.pi/2,4,"Z"));fit(obj,(0,.645,z),(.68,.14,.57))
    source_info("gallery_bench",path,"KIT_black_tufted_bench")
    path=ROOT/"tools/art/source/deluxe_room_10/deluxe_room_10.blend";parts=template(path,"KIT_bar_stool")
    begin("round_stool",str(path.relative_to(ROOT)),["Retain the round seat and three splayed legs; normalize full bounds to .48 x .715 x .48 m."])
    vertices=np.concatenate([np.array([v.co[:] for v in q[1].vertices]) for q in parts]);lo,hi=vertices.min(0),vertices.max(0)
    scale=np.array([.48,.48,.715])/(hi-lo)
    xf=Matrix.Diagonal((*scale,1.0))@Matrix.Translation(Vector((-(lo[0]+hi[0])/2,-(lo[1]+hi[1])/2,-lo[2])))
    for part in parts:
        obj=copy_part(part,part[0],"oak_light" if "seat" in part[0].lower() else "oak");obj.data.transform(xf)
    source_info("round_stool",path,"KIT_bar_stool")
def lighting():
    begin("spot_track","new simple fixture",["One continuous 2.80 m rail matching the approved white placement; three lamp heads remain separate instances."])
    cube("Brass rail",(0,.03,0),(2.80,.06,.06),"brass",.009)
    for x in [-1.20,0,1.20]:cube("Ceiling attachment tab",(x,.055,0),(.10,.01,.08),"brass",.004)
    begin("spot_head","new simple fixture",["Low-poly brass gallery spotlight; local -Z points toward the existing light target. No new light behaviour."])
    body=role(p.lathe("Machined spotlight body",(0,0,0),[(-.11,.065),(-.09,.065),(.08,.065),(.10,.057)],"brass",24),"brass")
    body.data.transform(Matrix.Rotation(math.pi/2,4,"X"))
    lens=cyl("Opaque warm lens",(0,0,0),.052,.008,"porcelain",24)
    lens.data.transform(Matrix.Rotation(math.pi/2,4,"X"));lens.data.transform(Matrix.Translation(p.v((0,0,-.115))))
    cube("Track adapter",(0,0,.10),(.09,.06,.04),"brass",.004)
    for x in [-.066,.066]:cube("Tilt yoke",(x,0,.055),(.012,.06,.14),"brass",.004)
    path=ROOT/"tools/art/source/clothing_store_b/clothing_store_b.blend";parts=template(path,"KIT_wall_sconce")
    begin("wall_sconce",str(path.relative_to(ROOT)),["Retain original opal/brass sconce geometry and back-centre pivot; remap to the room atlas."])
    for part in parts:copy_part(part,part[0],"porcelain" if "Opal" in part[0] else "brass")
    source_info("wall_sconce",path,"KIT_wall_sconce")
def botanical():
    path=ROOT/"assets/rooms/_shared/plants/source/plants.blend";parts=template(path,"KIT_monstera")
    begin("monstera",str(path.relative_to(ROOT)),["Uniform .62 scale and 90-degree internal Y rotation retain leaf proportions and keep cards clear of the projecting wainscot.",
        "Original 128px tile RGBA values and split-leaf masks copied exactly into the room atlas; alpha scissor .45, double-sided.",
        "Approved conservative pot collision remains .4864 m diameter / .43 m high; no shared library edits."])
    for part in parts:
        obj=copy_part(part,part[0],"leaf",True);obj.data.transform(Matrix.Rotation(math.pi/2,4,"Z")@Matrix.Scale(.62,4))
    source_info("monstera",path,"KIT_monstera")
def uv_materials():
    atlas=bpy.data.images.load(str(OUT/"room_albedo_ao.png"));atlas.pack()
    mats={}
    for masked in [False,True]:
        mat=bpy.data.materials.new("N3 botanical atlas" if masked else "N3 editable atlas");mat.use_nodes=True
        texture=mat.node_tree.nodes.new("ShaderNodeTexImage");texture.image=atlas
        uvmap=mat.node_tree.nodes.new("ShaderNodeUVMap");uvmap.uv_map="CultureAtlas";mat.node_tree.links.new(uvmap.outputs["UV"],texture.inputs["Vector"])
        bsdf=mat.node_tree.nodes.get("Principled BSDF");mat.node_tree.links.new(texture.outputs["Color"],bsdf.inputs["Base Color"]);bsdf.inputs["Roughness"].default_value=.86
        if masked:mat.node_tree.links.new(texture.outputs["Alpha"],bsdf.inputs["Alpha"])
        mats[masked]=mat
    mapping={tuple(t["source_tile"]):t for t in SKIN["botanical_tiles"]}
    for kit in p.KITS.values():
        for obj in kit["objects"]:
            data=obj.data;bot=bool(obj.get("botanical",False))
            source_uv=[v.uv.copy() for v in data.uv_layers["RoomAtlas"].data] if bot else None
            uv=data.uv_layers.new(name="CultureAtlas")
            for layer in data.uv_layers:layer.active_render=False
            uv.active_render=True;data.uv_layers.active_index=data.uv_layers.find("CultureAtlas")
            for loop in data.loops:
                if bot:
                    u,v=source_uv[loop.index];top=np.array([float(u),1-float(v)])*2048
                    tile=mapping[tuple(np.floor(top/128).astype(int))]
                    new=top-np.array(tile["source_rect_px"][:2])+np.array(tile["target_rect_px"][:2])
                    uv.data[loop.index].uv=(new[0]/2048,1-new[1]/2048)
                else:
                    u0,v0,u1,v1=PALETTE[obj["atlas_role"]]["uv_rect_gltf"]
                    uv.data[loop.index].uv=((u0+u1)/2,1-(v0+v1)/2)
            data.materials.clear();data.materials.append(mats[bot])
            for face in data.polygons:face.material_index=0
def export(name):
    kit=p.KITS[name];bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();copies=[]
    bpy.ops.object.select_all(action="DESELECT")
    for src in kit["objects"]:
        data=bpy.data.meshes.new_from_object(src.evaluated_get(deps),depsgraph=deps);data.transform(kit["root"].matrix_world.inverted()@src.matrix_world)
        for uv in list(data.uv_layers):
            if uv.name!="CultureAtlas":data.uv_layers.remove(uv)
        for color in list(data.color_attributes):data.color_attributes.remove(color)
        obj=bpy.data.objects.new(src.name+" export",data);bpy.context.scene.collection.objects.link(obj);obj.select_set(True);copies.append(obj)
    bpy.context.view_layer.objects.active=copies[0]
    if len(copies)>1:bpy.ops.object.join()
    obj=bpy.context.object;obj.name=name+"_mobile";obj.data.name=obj.name;data=obj.data
    bvh=BVHTree.FromPolygons([v.co for v in data.vertices],[list(f.vertices) for f in data.polygons]);cache={}
    color=data.color_attributes.new(name="Color",type="FLOAT_COLOR",domain="CORNER");data.color_attributes.active_color=color;data.color_attributes.render_color_index=0
    for face in data.polygons:
        for li in face.loop_indices:
            vi=data.loops[li].vertex_index;n=data.corner_normals[li].vector.normalized();key=(vi,tuple(round(c,2) for c in n))
            if key not in cache:
                t=n.cross(Vector((0,0,1)))
                if t.length<.01:t=n.cross(Vector((1,0,0)))
                t.normalize();b=n.cross(t);hits=0
                if name!="monstera":
                    for i in range(8):
                        angle=i*2.399;r=math.sqrt((i+.5)/8)*.88
                        direction=(n*math.sqrt(1-r*r)+t*math.cos(angle)*r+b*math.sin(angle)*r).normalized()
                        hit=bvh.ray_cast(data.vertices[vi].co+n*.004,direction,.25)
                        if hit[0] is not None:hits+=1-hit[3]/.25
                cache[key]=1-.36*hits/8
            shade=cache[key];color.data[li].color=(shade,shade,shade,1)
    mat=bpy.data.materials.get("N3 export AO")
    if mat is None:
        mat=bpy.data.materials.new("N3 export AO");mat.use_nodes=True
        vc=mat.node_tree.nodes.new("ShaderNodeVertexColor");vc.layer_name="Color";mat.node_tree.links.new(vc.outputs["Color"],mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
    data.materials.clear();data.materials.append(mat)
    for face in data.polygons:face.material_index=0
    path=OUT/(name+".glb")
    bpy.ops.export_scene.gltf(filepath=str(path),export_format="GLB",use_selection=True,export_yup=True,export_vertex_color="ACTIVE",export_image_format="NONE",export_animations=False,export_cameras=False,export_lights=False)
    data.calc_loop_triangles();triangles=len(data.loop_triangles);bpy.data.objects.remove(obj,do_unlink=True)
    raw=path.read_bytes();n=struct.unpack_from("<I",raw,12)[0];doc=json.loads(raw[20:20+n]);tail=raw[20+n:]
    doc["images"]=[{"uri":"room_albedo_ao.png"}];doc["textures"]=[{"source":0}]
    material=dict(name="CultureBotanical" if name=="monstera" else "CultureAtlas",pbrMetallicRoughness=dict(baseColorFactor=[1,1,1,1],baseColorTexture=dict(index=0),metallicFactor=0,roughnessFactor=.86),doubleSided=name=="monstera")
    if name=="monstera":material.update(alphaMode="MASK",alphaCutoff=.45)
    doc["materials"]=[material]
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:primitive["material"]=0
    encoded=json.dumps(doc,separators=(",",":")).encode();encoded+=b" "*(-len(encoded)%4)
    path.write_bytes(struct.pack("<III",0x46546C67,2,20+len(encoded)+len(tail))+struct.pack("<II",len(encoded),0x4E4F534A)+encoded+tail)
    accessors=[doc["accessors"][p_["attributes"]["POSITION"]] for m in doc["meshes"] for p_ in m["primitives"]]
    lo=np.min([a["min"] for a in accessors],0);hi=np.max([a["max"] for a in accessors],0)
    result=dict(name=name,file=name+".glb",triangles=triangles,surfaces=1,bounds=[lo.tolist(),hi.tolist()],dimensions_m=(hi-lo).tolist(),sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    PROVENANCE[name].update(result);dump(OUT/"provenance"/name/"reuse_provenance.json",PROVENANCE[name]);print("CULTURE_REUSE_EXPORT",name,triangles,flush=True);return result
def assembly(assets):
    plan=json.loads((HERE/"layout_plan.json").read_text());rows=[];by={a["name"]:a for a in assets}
    for row in plan["placements"]:
        name=row["name"]
        if name=="plant_canopy":continue
        replacement="gallery_bench" if name=="bench" else "round_stool" if name=="stool" else "monstera" if name=="plant_pot" else "spot_track" if name=="spot_track" else "spot_head" if name.startswith("spot_head_") else "wall_sconce" if name.startswith("wall_sconce_") else None
        if replacement:
            row["model"]=replacement;row["model_scale"]=[1,1,1];row["bounds"]=by[replacement]["bounds"]
            if replacement=="wall_sconce":row["position"]=[-3.20,2.25,row["position"][2]];row["yaw_degrees"]=90
        rows.append(row)
    gray=[]
    for name in sorted({r["model"] for r in rows if r["model"].startswith("blockout_")}):
        doc,blob=load_glb(OUT/(name+".glb"));primitives=[p_ for m in doc["meshes"] for p_ in m["primitives"]]
        gray.append(dict(name=name,file=name+".glb",triangles=sum(doc["accessors"][p_["indices"]]["count"]//3 for p_ in primitives),surfaces=len(primitives),stage="unchanged placeholder"))
    plan.update(stage="reuse_preassembly",placements=rows,assets=assets+gray,shell_atlas="res://assets/rooms/poi_culture_hall/room_albedo_ao.png",
        source_ownership=dict(zhaoyun="Hall atlas skin, gallery_bench, round_stool, spot_track, spot_head, wall_sconce, monstera and assembly",huangzhong="All approved gray proxy placements remain unchanged. Final props/ not fetched or modified; wait for technical approval."),
        opening_review="95aed0c2 / 1eb4f28b: approved native opening; no camera offset. Artworks are seen from the viewing area.")
    for row in plan["local_lights"]:row["kind"]="spot"
    for i,z in enumerate([-.55,.55],1):plan["local_lights"].append(dict(name="wall_glow_%d"%i,kind="omni",position=[-2.97,2.25,z],color="FFE0AC",energy=.65,range=1.3))
    dump(OUT/"layout.json",plan);by={a["name"]:a for a in plan["assets"]}
    shell=json.loads((ROOT/"assets/rooms/_shared/shell_hall/shell_asset_stats.json").read_text())
    stats=dict(stage="reuse_preassembly",assets=plan["assets"],scene_triangles=shell["scene_triangles"]+sum(by[r["model"]]["triangles"] for r in rows),
        static_draw_surfaces=shell["static_draw_surfaces"]+sum(by[r["model"]]["surfaces"] for r in rows),shared_shell=shell,
        atlas=dict(file="room_albedo_ao.png",size=[2048,2048],botanical_alpha_scissor=.45),pending="Huangzhong's final display kit; proxy cost is still included")
    assert stats["scene_triangles"]<=150000 and stats["static_draw_surfaces"]<=50
    dump(OUT/"asset_stats.json",stats);dump(OUT/"reuse_provenance.json",PROVENANCE)
    for row in rows:
        if row["model"] not in p.KITS:continue
        p.instance(row["model"],row["name"]+"_placed",row["position"],row["yaw_degrees"])
        if "target" in row:
            root=bpy.data.objects[row["name"]+"_placed"];root.rotation_euler=(p.v(row["target"])-root.location).to_track_quat("Y","Z").to_euler()
    for kit in p.KITS.values():kit["collection"].hide_render=True;kit["collection"].hide_viewport=True
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/"culture_hall_reuse.blend"),compress=True)
    print("CULTURE_REUSE",stats["scene_triangles"],stats["static_draw_surfaces"],flush=True)
def main():
    p.start("poi_culture_hall","SGODOT-318 R3 / approved 323 white / authorized independent reuse subset")
    p.b.PALETTE.update({k:v["hex_srgb"] for k,v in PALETTE.items()})
    seats();lighting();botanical();uv_materials();assets=[export(name) for name in p.KITS];assembly(assets)
if __name__=="__main__":main()
