"""Five owned proxy meshes and an editable white layout; final prop files are untouched."""
from pathlib import Path
import json
import math
import bpy
from mathutils import Vector,Matrix

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];KIT=ROOT/"assets/rooms/poi_classroom"
def vec(p):return Vector((p[0],-p[2],p[1]))
def box(name,at,size,material):
    bpy.ops.mesh.primitive_cube_add(size=1,location=vec(at));obj=bpy.context.object
    obj.name=name;obj.scale=(size[0],size[2],size[1]);obj.data.materials.append(material)
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    return obj
def cylinder(name,at,radius,height,material):
    bpy.ops.mesh.primitive_cylinder_add(vertices=24,radius=radius,depth=height,location=vec(at))
    obj=bpy.context.object;obj.name=name;obj.data.materials.append(material)
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    return obj
def material(name,value):
    mat=bpy.data.materials.new(name);mat.diffuse_color=(*value,1);mat.use_nodes=True
    shader=mat.node_tree.nodes.get("Principled BSDF");shader.inputs["Base Color"].default_value=(*value,1)
    shader.inputs["Roughness"].default_value=.88;shader.inputs["Specular IOR Level"].default_value=.18
    return mat
def export_parts(name,parts):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:obj.select_set(True)
    bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join()
    obj=bpy.context.object;obj.name=name+"_mobile";obj.data.name=obj.name
    bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    obj.data.calc_loop_triangles();count=len(obj.data.loop_triangles)
    bpy.ops.export_scene.gltf(filepath=str(KIT/(name+".glb")),export_format="GLB",use_selection=True,
        export_yup=True,export_materials="EXPORT",export_normals=True,export_cameras=False,export_lights=False)
    obj.hide_render=True;obj.hide_set(True)
    return obj,count
def main():
    bpy.ops.object.select_all(action="SELECT");bpy.ops.object.delete(use_global=False)
    bpy.context.preferences.filepaths.save_version=0
    plan=json.loads((KIT/"layout.json").read_text())
    desk=material("BlockoutDesk",(.52,.55,.56));seat=material("BlockoutSeat",(.28,.34,.37))
    prop=material("BlockoutProxy",(.43,.47,.49));shell_mat=material("BlockoutShell",(.72,.74,.73))
    models={};counts={}
    h=1.745*.65
    parts=[box("DeskTop",(0,h-.045,0),(1.02,.09,.58),desk)]
    for x in [-.43,.43]:
        for z in [-.22,.22]:parts.append(box("DeskLeg",(x,(h-.09)/2,z),(.075,h-.09,.075),desk))
    models["blockout_student_desk"],counts["blockout_student_desk"]=export_parts("blockout_student_desk",parts)
    parts=[cylinder("RoundSeat",(0,.665,0),.24,.10,seat)]
    for x in [-.14,.14]:
        for z in [-.14,.14]:parts.append(box("StoolLeg",(x,.3075,z),(.055,.615,.055),seat))
    models["blockout_student_stool"],counts["blockout_student_stool"]=export_parts("blockout_student_stool",parts)
    models["blockout_box"],counts["blockout_box"]=export_parts("blockout_box",[box("UnitBox",(0,.5,0),(1,1,1),prop)])
    models["blockout_cylinder"],counts["blockout_cylinder"]=export_parts("blockout_cylinder",[cylinder("UnitCylinder",(0,.5,0),.5,1,prop)])
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=.5,location=vec((0,.5,0)))
    obj=bpy.context.object;obj.data.materials.append(prop)
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    models["blockout_ball"],counts["blockout_ball"]=export_parts("blockout_ball",[obj])
    for row in plan["placements"]:
        original=models[row["model"]];obj=original.copy();obj.data=original.data.copy();bpy.context.scene.collection.objects.link(obj)
        obj.name=row["name"];obj.hide_render=False;obj.hide_set(False);obj.location=vec(row["position"])
        obj.rotation_euler.z=math.radians(row["yaw_degrees"])
        if row["model"] not in ["blockout_student_desk","blockout_student_stool"]:obj.scale=(row["size"][0],row["size"][2],row["size"][1])
        obj["owner"]=row["owner"];obj["role"]=row["role"]
    hall=json.loads((ROOT/"assets/rooms/_shared/shell_hall/layout.json").read_text());assets={a["name"]:a for a in hall["assets"]}
    for row in hall["assets"]+hall["instances"]:
        asset=assets[row.get("asset",row["name"])];before=set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(ROOT/"assets/rooms/_shared/shell_hall"/asset["file"]))
        imported=list(set(bpy.data.objects)-before)
        for obj in imported:
            if obj.type!="MESH":continue
            xf=Matrix.Translation(vec(row["position"]))@Matrix.Rotation(math.radians(row["yaw_degrees"]),4,"Z")
            obj.matrix_world=xf@obj.matrix_world;obj.name=row["name"]+"__"+obj.name
            obj.data.materials.clear();obj.data.materials.append(shell_mat)
        for obj in imported:
            if obj.type!="MESH":bpy.data.objects.remove(obj,do_unlink=True)
    for row in plan["anchors"]:
        obj=bpy.data.objects.new(row["name"],None);bpy.context.scene.collection.objects.link(obj)
        obj.location=vec(row["position"]);obj.rotation_euler.z=math.radians(row.get("yaw_degrees",0))
        obj.empty_display_type="ARROWS";obj.empty_display_size=.14;obj["module"]=row["module"]
    bpy.context.scene["stage"]="white blockout; final models and atlas await approval"
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/"classroom_blockout.blend"))
    shell_stats=json.loads((ROOT/"assets/rooms/_shared/shell_hall/shell_asset_stats.json").read_text())
    stats={"phase":"white blockout","owned_modules":counts,"placed_proxy_triangles":sum(counts[r["model"]] for r in plan["placements"]),
        "placed_proxy_surfaces":len(plan["placements"]),"shared_shell_stats":shell_stats,
        "final_budget":{"triangles":150000,"surfaces":50},"scope":"Proxy cost only; final asset budget must be rechecked after assembly"}
    (KIT/"asset_stats.json").write_text(json.dumps(stats,indent=2)+"\n")
    print("CLASSROOM_WHITE",counts,stats["placed_proxy_triangles"])
if __name__=="__main__":main()
