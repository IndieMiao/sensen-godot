"""SGODOT-322: editable Basic Room adaptations and unchanged approved props."""
from pathlib import Path
import hashlib
import json
import math
import struct
import sys
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT/"tools/art"))
import scene_room_pipeline as p

OUT = ROOT/"assets/rooms/poi_classroom"
PALETTE = json.loads((OUT/"atlas_skin.json").read_text())["slots"]
PLAN = json.loads((HERE/"layout_plan.json").read_text())
PROVENANCE = {}
TEMPLATES = {}

def dump(path, data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,indent=2)+"\n")

def begin(name, source, notes):
    p.begin(name,(0,0,0))
    PROVENANCE[name] = dict(author="ZHAOYUN",source=source,changes=notes)
    return p.KITS[name]

def role(obj, key):
    obj["atlas_role"] = key
    obj.data.materials.clear(); obj.data.materials.append(p.material(key))
    for face in obj.data.polygons: face.material_index=0
    return obj

def cube(name,at,size,key,bevel=.008):
    return role(p.cube(name,at,size,key,bevel),key)

def template(path, collection):
    cache_key = (str(path),collection)
    if cache_key in TEMPLATES:return TEMPLATES[cache_key]
    with bpy.data.libraries.load(str(path),link=False) as (src,dst):dst.collections=[collection]
    col=dst.collections[0]; assert col is not None,(path,collection)
    bpy.context.scene.collection.children.link(col);bpy.context.view_layer.update()
    root=next(o for o in col.objects if o.type=="EMPTY")
    inv=root.matrix_world.inverted();deps=bpy.context.evaluated_depsgraph_get();parts=[]
    for obj in col.objects:
        if obj.type!="MESH":continue
        mesh=bpy.data.meshes.new_from_object(obj.evaluated_get(deps),depsgraph=deps)
        mesh.transform(inv@obj.matrix_world)
        parts.append((obj.name,mesh,dict(obj.items())))
    for obj in list(col.objects):bpy.data.objects.remove(obj,do_unlink=True)
    bpy.data.collections.remove(col)
    TEMPLATES[cache_key]=parts
    return parts

def copy_part(part,name,key):
    obj=bpy.data.objects.new(name,part[1].copy());kit=p.b.CURRENT
    kit["collection"].objects.link(obj);obj.parent=kit["root"];kit["objects"].append(obj)
    obj["source_part"]=part[0]
    return role(obj,key)

def fit(obj,at,size):
    points=np.array([v.co[:] for v in obj.data.vertices]);lo,hi=points.min(0),points.max(0)
    target=np.array([size[0],size[2],size[1]])
    center=np.array(p.v(at))
    for vertex in obj.data.vertices:vertex.co=(np.array(vertex.co)-(lo+hi)/2)*target/np.maximum(hi-lo,1e-6)+center
    obj.data.update()

def source_hash(name,path,collection):
    PROVENANCE[name].update(source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),source_collection=collection)

def student_furniture():
    path=ROOT/"tools/art/source/basic_room/basic_room.blend"
    parts=template(path,"KIT_dining_table")
    begin("student_desk",str(path.relative_to(ROOT)),["Dining table resized to 1.02 x .58 m; top 1.13425 m.","Original four tapered legs and four aprons retained; one original board widened into a .075 m desk slab, other four boards omitted."])
    points=np.concatenate([np.array([v.co[:] for v in data.vertices]) for _,data,_ in parts])
    lo,hi=points.min(0),points.max(0)
    scale=np.array([1.02,.58,1.13425])/(hi-lo)
    top_used=False
    for part in parts:
        if "tabletop" in part[0] and top_used:continue
        obj=copy_part(part,part[0],"oak_light" if "tabletop" in part[0] else "oak")
        for v in obj.data.vertices:v.co=(np.array(v.co)-np.array([(lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]]))*scale
        if "tabletop" in part[0]:
            fit(obj,(0,1.13425-.075/2,0),(1.02,.075,.58));top_used=True
        elif "apron" in part[0]:obj.data.transform(Matrix.Translation((0,0,.074)))
    source_hash("student_desk",path,"KIT_dining_table")
    parts=template(path,"KIT_chair")
    leg=next(x for x in parts if x[0].startswith("Chair front leg"))
    brace=next(x for x in parts if x[0].startswith("Chair side stretcher"))
    begin("student_stool",str(path.relative_to(ROOT)),["Chair front legs duplicated to four; back and original planked seat omitted.","New softened round seat diameter .48 m, top .715 m; adapted stretchers."])
    for x in [-.13,.13]:
        for z in [-.13,.13]:fit(copy_part(leg,"Adapted chair leg","oak"),(x,.315,z),(.068,.63,.068))
        fit(copy_part(brace,"Adapted chair side stretcher","oak_edge"),(x,.27,0),(.045,.045,.27))
    fit(copy_part(brace,"Adapted chair cross stretcher","oak_edge"),(0,.27,0),(.27,.045,.045))
    role(p.lathe("Rounded circular oak seat",(0,0,0),[(.635,.22),(.642,.237),(.654,.24),(.695,.24),(.710,.232),(.715,.22)],"oak_light",40),"oak_light")
    source_hash("student_stool",path,"KIT_chair")

def book(at,w,h,d,key,index):
    x,y,z=at
    cube("Book %02d pages"%index,(x,y+h/2,z),(w-.012,h-.014,d-.012),"linen",.002)
    for xx in [-w/2+.003,w/2-.003]:cube("Book %02d cover"%index,(x+xx,y+h/2,z),(.006,h,d),key,.001)
    cube("Book %02d spine"%index,(x,y+h/2,z+d/2-.007),(w,h,.014),key,.002)
    for yy in [.12,.82]:cube("Book spine binding",(x,y+h*yy,z+d/2+.001),(w*.72,.008,.004),"linen",0)

def shelving():
    path=ROOT/"tools/art/source/basic_room/basic_room.blend"
    parts=template(path,"KIT_wall_shelf")
    board=next(x for x in parts if x[0].startswith("Oak kitchen shelf"))
    corbel=next(x for x in parts if x[0].startswith("Shelf corbel"))
    def panel(name,at,size,key="oak"):
        obj=copy_part(board,name,key);fit(obj,at,size);return obj
    for name,w,h,d,levels in [("rear_bookcase",.90,2.30,.65,4),("right_storage",1.10,1.16,.50,3),("low_cabinet",.80,.90,.48,1)]:
        begin(name,str(path.relative_to(ROOT)),["Basic Room shelf board rebuilt into named case panels, shelves and back.","Original low-poly book blocks added; no object above tall bookcase top."])
        for x in [-w/2+.035,w/2-.035]:panel("Case side",(x,h/2,0),(.07,h,d))
        panel("Case recessed back",(0,h/2,-d/2+.025),(w-.14,h-.12,.035),"wood_mid")
        ys=[.10+i*(h-.15)/levels for i in range(levels+1)]
        for i,y in enumerate(ys):panel("Adapted oak shelf %02d"%i,(0,y-.025,0),(w-.14,.05,d),"oak_light")
        panel("Top overhanging board",(0,h-.025,0),(w,.05,d),"oak_light")
        panel("Short bottom plinth",(0,.042,0),(w-.12,.084,d-.06),"oak_edge")
        for i,base in enumerate(ys[:-1]):
            count=7 if name=="rear_bookcase" else (8 if name=="right_storage" else 7)
            step=(w-.18)/count
            for j in range(count):
                bh=(ys[i+1]-base-.075)*(1-.12*((j+i)%3))
                book((-w/2+.09+(j+.5)*step,base,.035),step*.79,bh,min(.25,d-.10),["sage","sky","linen_green","petal","oak_edge"][(j+2*i)%5],i*10+j)
        source_hash(name,path,"KIT_wall_shelf")
    for name in ["display_shelf","book_shelf"]:
        begin(name,str(path.relative_to(ROOT)),["Kitchen shelf and corbels resized; upper shelf has two wordless miniature prints, lower shelf has books."])
        panel("Adapted display board",(0,.075,0),(1.12,.05,.32),"oak_light")
        for x in [-.38,.38]:fit(copy_part(corbel,"Shelf corbel","oak_edge"),(x,.015,-.095),(.055,.07,.12))
        if name=="display_shelf":
            for x in [-.32,.08]:
                cube("Display picture backing",(x,.30,-.07),(.30,.40,.018),"oak_edge",.004)
                obj=cube("Wordless landscape print",(x,.30,-.058),(.27,.36,.004),"print_landscape",0);obj["uv_mode"]="front"
        else:
            for i in range(5):book((-.36+i*.105,.10,0),.072,.22+(i%3)*.035,.16,["sky","sage","linen_green"][i%3],i)
        source_hash(name,path,"KIT_wall_shelf")
    begin("reading_books","new accessory",["Three closed books at the visible inner reading edge, outside the .74 m aisle."])
    for i,key in enumerate(["sky","sage","petal"]):
        w=.34-i*.025;d=.26-i*.016;y=i*.055
        cube("Reading book page block",(0,y+.027,0),(w-.012,.041,d-.008),"linen",.002)
        for yy in [.004,.050]:cube("Reading book cloth cover",(0,y+yy,0),(w,.008,d),key,.002)
        cube("Reading book bound spine",(0,y+.027,d/2),(w,.055,.008),key,.002)

def lamps_and_plants():
    path=ROOT/"tools/art/source/coffee_shop/coffee_shop.blend"
    parts=template(path,"KIT_pendant")
    begin("pendant",str(path.relative_to(ROOT)),["Catalogue cream bell pendant adapted to .40 m shade; brass cable and stem."])
    for part in parts:
        key="brass" if any(s in part[0] for s in ["cable","lampholder"]) else "porcelain"
        obj=copy_part(part,part[0],key)
        for v in obj.data.vertices:v.co=Vector((v.co.x*.645,v.co.y*.645,(v.co.z+.87)*.80))
    source_hash("pendant",path,"KIT_pendant")
    # Pin the named 324 source, rather than depending on an untracked output path.
    path=HERE/"dependencies/hallkit_324.blend"
    parts=template(path,"KIT_wall_sconce")
    begin("wall_sconce","SGODOT-324 hallkit_324.blend",["Shared opal/brass sconce; unchanged local geometry, room palette mapping."])
    for part in parts:copy_part(part,part[0],"brass" if part[2].get("palette_slot")=="brass" else "porcelain")
    source_hash("wall_sconce",path,"KIT_wall_sconce")
    path=ROOT/"assets/rooms/_shared/plants/source/plants.blend"
    parts=template(path,"KIT_peace_lily")
    begin("small_plant",str(path.relative_to(ROOT)),["Peace lily uniformly scaled .30; geometric leaf outlines retained, no alpha-cut silhouette.","Source botanical colours remapped into classroom atlas; two-sided leaf surface."])
    for i,part in enumerate(parts):
        key="terra" if any(x in part[0] for x in ["planter","flute"]) else "soil" if "soil" in part[0] else "linen" if "spathe" in part[0] else "brass" if "spadix" in part[0] else ["leaf","leaf_light","leaf_dark"][i%3]
        obj=copy_part(part,part[0],key);obj.data.transform(Matrix.Scale(.30,4))
    source_hash("small_plant",path,"KIT_peace_lily")

def uv_material():
    atlas=bpy.data.images.load(str(OUT/"room_albedo_ao.png"));atlas.pack()
    mat=bpy.data.materials.new("Classroom editable atlas");mat.use_nodes=True
    texture=mat.node_tree.nodes.new("ShaderNodeTexImage");texture.image=atlas
    mat.node_tree.links.new(texture.outputs["Color"],mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
    mat.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value=.82
    for kit in p.KITS.values():
        for obj in kit["objects"]:
            data=obj.data
            for layer in list(data.uv_layers):data.uv_layers.remove(layer)
            for layer in list(data.color_attributes):data.color_attributes.remove(layer)
            uv=data.uv_layers.new(name="ClassroomAtlas")
            u0,v0,u1,v1=PALETTE[obj["atlas_role"]]["uv_rect_gltf"]
            points=np.array([v.co[:] for v in data.vertices]);lo,hi=points.min(0),points.max(0)
            for loop in data.loops:
                if obj.get("uv_mode")=="front":
                    q=data.vertices[loop.vertex_index].co
                    uv.data[loop.index].uv=(u0+(q.x-lo[0])/max(hi[0]-lo[0],1e-6)*(u1-u0),1-v1+(q.z-lo[2])/max(hi[2]-lo[2],1e-6)*(v1-v0))
                else:uv.data[loop.index].uv=((u0+u1)/2,1-(v0+v1)/2)
            data.materials.clear();data.materials.append(mat)
            for face in data.polygons:face.material_index=0

def export(name):
    kit=p.KITS[name];bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
    bpy.ops.object.select_all(action="DESELECT");copies=[]
    for src in kit["objects"]:
        data=bpy.data.meshes.new_from_object(src.evaluated_get(deps),depsgraph=deps)
        data.transform(kit["root"].matrix_world.inverted()@src.matrix_world)
        obj=bpy.data.objects.new(src.name+" export",data);bpy.context.scene.collection.objects.link(obj);obj.select_set(True);copies.append(obj)
    bpy.context.view_layer.objects.active=copies[0]
    if len(copies)>1:bpy.ops.object.join()
    obj=bpy.context.object;obj.name=name+"_mobile";obj.data.name=name+"_mobile"
    data=obj.data
    bvh=BVHTree.FromPolygons([v.co for v in data.vertices],[list(f.vertices) for f in data.polygons])
    color=data.color_attributes.new(name="Color",type="FLOAT_COLOR",domain="CORNER")
    data.color_attributes.active_color=color;data.color_attributes.render_color_index=data.color_attributes.find("Color")
    cache={}
    for face in data.polygons:
        for li in face.loop_indices:
            vi=data.loops[li].vertex_index;n=data.corner_normals[li].vector.normalized();key=(vi,tuple(round(c,2) for c in n))
            if key not in cache:
                tangent=n.cross(Vector((0,0,1)))
                if tangent.length<.01:tangent=n.cross(Vector((1,0,0)))
                tangent.normalize();bitangent=n.cross(tangent);hits=0
                for i in range(8):
                    angle=i*2.399;r=math.sqrt((i+.5)/8)*.88
                    direction=(n*math.sqrt(1-r*r)+tangent*math.cos(angle)*r+bitangent*math.sin(angle)*r).normalized()
                    hit=bvh.ray_cast(data.vertices[vi].co+n*.004,direction,.28)
                    if hit[0] is not None:hits+=1-hit[3]/.28
                cache[key]=1-.42*hits/8
            shade=cache[key];color.data[li].color=(shade,shade,shade,1)
    mat=bpy.data.materials.get("Classroom export AO")
    if mat is None:
        mat=bpy.data.materials.new("Classroom export AO");mat.use_nodes=True
        vc=mat.node_tree.nodes.new("ShaderNodeVertexColor");vc.layer_name="Color"
        mat.node_tree.links.new(vc.outputs["Color"],mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
    data.materials.clear();data.materials.append(mat)
    for face in data.polygons:face.material_index=0
    path=OUT/(name+".glb")
    bpy.ops.export_scene.gltf(filepath=str(path),export_format="GLB",use_selection=True,export_yup=True,
        export_vertex_color="ACTIVE",export_image_format="NONE",export_animations=False,export_cameras=False,export_lights=False)
    data.calc_loop_triangles();triangles=len(data.loop_triangles);bpy.data.objects.remove(obj,do_unlink=True)
    raw=path.read_bytes();length=struct.unpack_from("<I",raw,12)[0];doc=json.loads(raw[20:20+length]);tail=raw[20+length:]
    doc["images"]=[{"uri":"room_albedo_ao.png"}];doc["textures"]=[{"source":0}]
    doc["materials"]=[{"name":"ClassroomAtlas", "pbrMetallicRoughness":{"baseColorFactor":[1,1,1,1],"baseColorTexture":{"index":0},"metallicFactor":0,"roughnessFactor":.82},"doubleSided":name=="small_plant"}]
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:primitive["material"]=0
    encoded=json.dumps(doc,separators=(",",":")).encode();encoded+=b" "*(-len(encoded)%4)
    path.write_bytes(struct.pack("<III",0x46546C67,2,20+len(encoded)+len(tail))+struct.pack("<II",len(encoded),0x4E4F534A)+encoded+tail)
    positions=[doc["accessors"][pr["attributes"]["POSITION"]] for m in doc["meshes"] for pr in m["primitives"]]
    lo=np.min([v["min"] for v in positions],0);hi=np.max([v["max"] for v in positions],0)
    result=dict(name=name,file=name+".glb",triangles=triangles,surfaces=1,bounds=[lo.tolist(),hi.tolist()],dimensions_m=(hi-lo).tolist(),sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    PROVENANCE[name].update(result);dump(OUT/"provenance"/name/"reuse_provenance.json",PROVENANCE[name])
    print("CLASSROOM_EXPORT",name,triangles,flush=True)
    return result

def layout(assets):
    plan=PLAN;plan["stage"]="detail_v1"
    props=json.loads((OUT/"props/prop_manifest.json").read_text());by_prop={a["name"]:a for a in props["assets"]}
    rename={"proxy_teacher_desk":"teacher_desk","proxy_blackboard":"blackboard","proxy_globe":"globe",
        "proxy_stationery_1":"stationery_1","proxy_stationery_6":"stationery_6","proxy_study":"plaster_study",
        "proxy_cushion_1":"reading_cushion_1","proxy_cushion_2":"reading_cushion_2","proxy_sign":"name_sign"}
    prop_models={"teacher_desk":"teacher_desk","blackboard":"blackboard","globe":"globe","stationery_1":"desk_stationery","stationery_6":"desk_stationery","plaster_study":"plaster_study","reading_cushion_1":"reading_cushion","reading_cushion_2":"reading_cushion","name_sign":"name_sign"}
    owned={a["name"]:a for a in assets};rows=[]
    for row in plan["placements"]:
        row["name"]=rename.get(row["name"],row["name"])
        if "support" in row:row["support"]=rename.get(row["support"],row["support"])
        name=row["name"]
        if name in prop_models:
            model=prop_models[name];spec=by_prop[model];row["model"]="props/"+model
            if name=="blackboard":row["position"]=[.38,1.97,-2.99]
            if name=="name_sign":row["position"]=[.38,3.19,-2.99]
            if name=="globe":row["mount"]={"module":"teacher_desk","node":"globe_mount"}
        else:
            model="student_desk" if name.startswith("desk_") else "student_stool" if name.startswith("stool_") else "low_cabinet" if name.startswith("low_cabinet_") else "display_shelf" if name.startswith("display_shelf_") else "pendant" if name.startswith("pendant_") else "wall_sconce" if name.startswith("wall_sconce_") else "small_plant" if name.startswith("plant_") else name
            if name=="display_shelf_1":model="book_shelf"
            row["model"]=model;spec=owned[model]
            if model=="low_cabinet":row["size"]=[.80,.90,.48];row["yaw_degrees"]=90
            if model=="rear_bookcase":row["size"][1]=2.30
            if model in ["display_shelf","book_shelf"]:row["position"][1]=1.74 if name.endswith("1") else 2.40
            if model=="pendant":row["position"][1]=2.73
            if model=="wall_sconce":row["position"][0]=-3.10;row["yaw_degrees"]=90
            if name=="plant_5":continue
            if name=="plant_6":
                row["position"]=[2.96,1.84,-2.82];row["support"]="display_shelf_1"
        row["bounds"]=spec["bounds"]
        row["colliders"]=[]
        if row["collidable"]:
            if "stool" in name or "cushion" in name:
                row["shape"]="circle";row["colliders"]=[dict(kind="cylinder",at=[0,row["size"][1]/2,0],radius=row["size"][0]/2,height=row["size"][1])]
            else:row["colliders"]=[dict(at=[0,row["size"][1]/2,0],size=row["size"])]
        if name=="teacher_desk":row["colliders"]=[dict(at=c["position"],size=c["size"]) for c in spec["colliders"]]
        rows.append(row)
    rows.append(dict(name="reading_books",model="reading_books",position=[-2.48,.08,-.12],size=[.34,.16,.27],bounds=owned["reading_books"]["bounds"],yaw_degrees=0,role="reading corner book stack",collidable=True,owner="zhaoyun",colliders=[dict(at=[0,.08,0],size=[.34,.16,.27])]))
    plan["placements"]=rows
    for anchor in plan["anchors"]:anchor["module"]=rename.get(anchor["module"],anchor["module"])
    plan["shell_atlas"]="res://assets/rooms/poi_classroom/room_albedo_ao.png"
    plan["source_ownership"]["zhaoyun"]=["layout.json","asset_stats.json","root GLBs and atlas","scenes/poi_classroom/*"]
    plan["source_ownership"]["huangzhong"]="props/ copied byte-for-byte from 350bd1f1 / PR #689. No files modified."
    plan["prop_interface"].pop("teacher_proxy_note",None)
    plan.pop("proposed_reuse",None)
    plan["assets"]=assets+[{**a,"name":"props/"+a["name"],"file":"props/"+a["file"]} for a in props["assets"]]
    plan["local_lights"]=[]
    for i,z in enumerate([-.55,.55],1):plan["local_lights"].append(dict(name="wall_warmth_%d"%i,position=[-2.88,2.22,z],color="FFDB9F",energy=.65,range=1.2))
    for i,x in enumerate([-1.35,2.05],1):plan["local_lights"].append(dict(name="pendant_warmth_%d"%i,position=[x,2.71,-1.40],color="FFE2AF",energy=.65,range=2.2))
    for i,z in enumerate([-1.8,1.8],1):plan["local_lights"].append(dict(name="window_fill_%d"%i,position=[-2.80,2.15,z],color="FFF3DA",energy=.50,range=3.2))
    plan["review_lighting"].update(background="E7E3D9",ambient_color="F3EADC",ambient=.52,sun_color="FFF0D4",sun=1.1,shadow_bias=.04,shadow_normal_bias=.12)
    plan["lighting"]={"angular_distance":.4}
    dump(OUT/"layout.json",plan)
    by={a["name"]:a for a in plan["assets"]};shell=json.loads((ROOT/"assets/rooms/_shared/shell_hall/shell_asset_stats.json").read_text())
    stats=dict(assets=plan["assets"],unique_triangles=sum(a["triangles"] for a in plan["assets"]),
        scene_triangles=shell["scene_triangles"]+sum(by[r["model"]]["triangles"] for r in rows),
        static_draw_surfaces=shell["static_draw_surfaces"]+len(rows),shared_shell_stats=shell,
        room_atlas=dict(file="room_albedo_ao.png",size=[2048,2048]),plants_triangles=owned["small_plant"]["triangles"]*5)
    assert stats["scene_triangles"]<=150000 and stats["static_draw_surfaces"]<=50,stats
    dump(OUT/"asset_stats.json",stats);dump(OUT/"reuse_provenance.json",PROVENANCE)
    # Editable furniture, including linked repeats, stays arranged in the source.
    for row in rows:
        if row["model"] not in p.KITS:continue
        p.instance(row["model"],row["name"]+"_placed",row["position"],row["yaw_degrees"])
    for kit in p.KITS.values():
        kit["collection"].hide_render=True;kit["collection"].hide_viewport=True
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/"classroom_detail.blend"),compress=True)
    print("CLASSROOM_DETAIL",stats["scene_triangles"],stats["static_draw_surfaces"],flush=True)

def main():
    p.start("poi_classroom","SGODOT-317 R3 / 322 330d4474")
    p.b.PALETTE.update({key:slot["hex_srgb"] for key,slot in PALETTE.items()})
    student_furniture();shelving();lamps_and_plants();uv_material()
    assets=[export(name) for name in p.KITS]
    layout(assets)

if __name__=="__main__":main()
