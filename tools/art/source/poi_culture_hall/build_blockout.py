"""Owned gray proxies, glass envelopes and an editable N3 white layout."""
from pathlib import Path
import json
import math
import struct
import bpy
import bmesh
from mathutils import Vector,Matrix

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];KIT=ROOT/"assets/rooms/poi_culture_hall"
def vec(p):return Vector((p[0],-p[2],p[1]))
def box(name,at,size,mat):
    bpy.ops.mesh.primitive_cube_add(size=1,location=vec(at));obj=bpy.context.object
    obj.name=name;obj.scale=(size[0],size[2],size[1]);obj.data.materials.append(mat)
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);return obj
def cyl(name,at,r,h,mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=r,depth=h,location=vec(at));obj=bpy.context.object
    obj.name=name;obj.data.materials.append(mat);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);return obj
def ball(name,at,size,mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=.5,location=vec(at));obj=bpy.context.object
    obj.name=name;obj.scale=(size[0],size[2],size[1]);obj.data.materials.append(mat)
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);return obj
def material(name,rgb,alpha=1):
    mat=bpy.data.materials.new(name);mat.diffuse_color=(*rgb,alpha);mat.use_nodes=True
    shader=mat.node_tree.nodes.get("Principled BSDF");shader.inputs["Base Color"].default_value=(*rgb,1)
    shader.inputs["Alpha"].default_value=alpha;shader.inputs["Roughness"].default_value=.88;shader.inputs["Specular IOR Level"].default_value=.18
    return mat
def export(name,parts):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:obj.select_set(True)
    bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();obj=bpy.context.object
    obj.name=name+"_mobile";obj.data.name=obj.name;bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    obj.data.calc_loop_triangles();triangles=len(obj.data.loop_triangles)
    path=KIT/(name+".glb")
    bpy.ops.export_scene.gltf(filepath=str(path),export_format="GLB",use_selection=True,export_yup=True,
        export_materials="EXPORT",export_normals=True,export_cameras=False,export_lights=False)
    raw=path.read_bytes();n=struct.unpack_from("<I",raw,12)[0];doc=json.loads(raw[20:20+n]);tail=raw[20+n:]
    for mat in doc.get("materials",[]):
        if mat["name"]=="ProxyGlass":mat.update(alphaMode="BLEND",doubleSided=True)
    encoded=json.dumps(doc,separators=(",",":")).encode();encoded+=b" "*(-len(encoded)%4)
    path.write_bytes(struct.pack("<III",0x46546C67,2,20+len(encoded)+len(tail))+struct.pack("<II",len(encoded),0x4E4F534A)+encoded+tail)
    surfaces=sum(len(m["primitives"]) for m in doc["meshes"])
    obj.hide_render=True;obj.hide_set(True)
    return obj,dict(name=name,file=name+".glb",triangles=triangles,surfaces=surfaces)
def main():
    bpy.ops.object.select_all(action="SELECT");bpy.ops.object.delete(use_global=False);bpy.context.preferences.filepaths.save_version=0
    plan=json.loads((KIT/"layout.json").read_text());models={};assets=[]
    gray=material("ProxyGray",(.43,.47,.49));dark=material("ProxyDark",(.22,.25,.27))
    light=material("ProxyLight",(.65,.67,.67));glass=material("ProxyGlass",(.70,.78,.80),.13)
    shell=material("WhiteShell",(.72,.74,.73))
    def add(name,parts):
        obj,spec=export(name,parts);models[name]=obj;assets.append(spec)
    add("blockout_box",[box("UnitBox",(0,.5,0),(1,1,1),gray)])
    add("blockout_ball",[ball("UnitSphere",(0,.5,0),(1,1,1),gray)])
    add("blockout_cylinder",[cyl("UnitCylinder",(0,.5,0),.5,1,gray)])
    parts=[box("BenchSeat",(0,.665,0),(.68,.10,1.728),dark)]
    for x in [-.25,.25]:
        for z in [-.70,0,.70]:parts.append(box("BenchLeg",(x,.3075,z),(.075,.615,.075),dark))
    add("blockout_bench",parts)
    parts=[cyl("StoolSeat",(0,.665,0),.24,.10,dark)]
    for x in [-.14,.14]:
        for z in [-.14,.14]:parts.append(box("StoolLeg",(x,.3075,z),(.055,.615,.055),dark))
    add("blockout_stool",parts)
    top=1.04/1.46
    parts=[box("DisplayBase",(0,top/2,0),(1,top,1),gray)]
    for x in [-.49,.49]:
        for z in [-.49,.49]:parts.append(box("CasePost",(x,(1+top)/2,z),(.02,1-top,.02),gray))
    for x in [-.495,.495]:parts.append(box("GlassSide",(x,(1+top)/2,0),(.01,1-top,1),glass))
    for z in [-.495,.495]:parts.append(box("GlassEnd",(0,(1+top)/2,z),(1,1-top,.01),glass))
    parts.append(box("GlassLid",(0,.995,0),(1,.01,1),glass));add("blockout_case",parts)
    parts=[box("BlankArtwork",(0,.5,0),(.90,.88,.5),dark)]
    for x in [-.475,.475]:parts.append(box("FrameSide",(x,.5,0),(.05,1,1),light))
    for y in [.025,.975]:parts.append(box("FrameEdge",(0,y,0),(1,.05,1),light))
    add("blockout_frame",parts)
    # One coplanar tessellated top avoids z-fighting at the 2 mm instance scale.
    n=32;vertices=[vec((0,1,0))]
    for radius,y in [(.30,1),(.50,1),(.50,0)]:
        vertices += [vec((radius*math.cos(i*math.tau/n),y,radius*math.sin(i*math.tau/n))) for i in range(n)]
    faces=[]
    for i in range(n):faces.append((0,1+(i+1)%n,1+i))
    for i in range(n):faces.append((1+i,1+(i+1)%n,1+n+(i+1)%n,1+n+i))
    for i in range(n):faces.append((1+n+i,1+n+(i+1)%n,1+2*n+(i+1)%n,1+2*n+i))
    faces.append(tuple(range(1+2*n,1+3*n)))
    data=bpy.data.meshes.new("CoplanarMedallion");data.from_pydata(vertices,[],faces);data.materials.append(gray);data.materials.append(light)
    for face in data.polygons:face.material_index=0 if face.index<n else 1
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
    obj=bpy.data.objects.new("CoplanarMedallion",data);bpy.context.scene.collection.objects.link(obj);add("blockout_mosaic",[obj])
    parts=[cyl("VaseFoot",(0,.08,0),.28,.16,light),ball("VaseBody",(0,.43,0),(1,.8,1),light),cyl("VaseNeck",(0,.83,0),.25,.34,light)]
    add("blockout_vase",parts)
    # Coarse upright disk/rings identify an exhibit; final ammonite belongs to Huangzhong.
    parts=[box("FossilStand",(0,.025,0),(.55,.05,.65),dark)]
    for radius,z in [(.48,0),(.30,.20),(.13,.36)]:
        obj=cyl("FossilDisk",(0,0,0),radius,.18,light)
        obj.data.transform(Matrix.Rotation(math.pi/2,4,"X"));obj.data.transform(Matrix.Translation(vec((0,.52,z))))
        parts.append(obj)
    # Normalize this proxy to bottom-centred unit bounds, including its display stand.
    points=[v.co for o in parts for v in o.data.vertices];lo=Vector([min(v[i] for v in points) for i in range(3)]);hi=Vector([max(v[i] for v in points) for i in range(3)])
    for obj in parts:
        for v in obj.data.vertices:
            v.co=Vector(((v.co.x-(lo.x+hi.x)/2)/(hi.x-lo.x),(v.co.y-(lo.y+hi.y)/2)/(hi.y-lo.y),(v.co.z-lo.z)/(hi.z-lo.z)))
    add("blockout_fossil",parts)
    for row in plan["placements"]:
        src=models[row["model"]];obj=src.copy();obj.data=src.data.copy();bpy.context.scene.collection.objects.link(obj)
        obj.name=row["name"];obj.hide_render=False;obj.hide_set(False);obj.location=vec(row["position"])
        natural=plan["models"].get(row["model"],[1,1,1]);scale=[a/b for a,b in zip(row["size"],natural)]
        obj.scale=(scale[0],scale[2],scale[1]);obj.rotation_euler.z=math.radians(row["yaw_degrees"])
        if "target" in row:obj.rotation_euler=(vec(row["target"])-obj.location).to_track_quat("Y","Z").to_euler()
        obj["owner"]=row["owner"];obj["role"]=row["role"]
    hall=json.loads((ROOT/"assets/rooms/_shared/shell_hall/layout.json").read_text());lookup={a["name"]:a for a in hall["assets"]}
    for row in hall["assets"]+hall["instances"]:
        asset=lookup[row.get("asset",row["name"])];before=set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(ROOT/"assets/rooms/_shared/shell_hall"/asset["file"]))
        for obj in list(set(bpy.data.objects)-before):
            if obj.type!="MESH":continue
            obj.matrix_world=Matrix.Translation(vec(row["position"]))@Matrix.Rotation(math.radians(row["yaw_degrees"]),4,"Z")@obj.matrix_world
            obj.name=row["name"]+"__"+obj.name;obj.data.materials.clear();obj.data.materials.append(shell)
    for row in plan["anchors"]:
        obj=bpy.data.objects.new(row["name"],None);bpy.context.scene.collection.objects.link(obj);obj.location=vec(row["position"])
        obj.empty_display_type="ARROWS";obj.empty_display_size=.15;obj["module"]=row["module"]
    bpy.context.scene["stage"]="SGODOT-323 white blockout; Huangzhong final parts pending"
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/"culture_hall_blockout.blend"),compress=True)
    by={a["name"]:a for a in assets};shell_stats=json.loads((ROOT/"assets/rooms/_shared/shell_hall/shell_asset_stats.json").read_text())
    stats=dict(stage="white_blockout",assets=assets,scene_triangles=shell_stats["scene_triangles"]+sum(by[r["model"]]["triangles"] for r in plan["placements"]),
        static_draw_surfaces=shell_stats["static_draw_surfaces"]+sum(by[r["model"]]["surfaces"] for r in plan["placements"]),shared_shell=shell_stats,
        scope="White proxies only; final geometry and atlas await approval and Huangzhong's assets")
    plan["assets"]=assets
    (KIT/"layout.json").write_text(json.dumps(plan,indent=2)+"\n");(KIT/"asset_stats.json").write_text(json.dumps(stats,indent=2)+"\n")
    print("CULTURE_WHITE",stats["scene_triangles"],stats["static_draw_surfaces"],flush=True)
if __name__=="__main__":main()
