"""SGODOT-401 B: single-post, arched upgrade plaque. Only this asset is rebuilt."""
from pathlib import Path
import hashlib
import json
import math
import struct
import sys
import bpy
from mathutils import Vector

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
sys.path.insert(0,str(HERE))
import build_decor_assets as kit

SOURCE=ROOT/"tools/art/source/upgrade_plaque_401"
OUT=ROOT/"assets/farm/art"
NAME="upgrade_plaque"
FACE_CENTER=(0,.43,.076)
SOCKET=(0,.43,.078)
PALETTE={"wood":"A87948","wood_light":"CBA067","wood_edge":"B88E59",
         "ivory":"FFF0D5","ivory_edge":"E4CBA4","nail":"806747",
         "laurel":"97A45F","laurel_light":"AFBA75","stem":"87944D"}


def rounded_rect(w,h,r,steps=3):
    points=[]
    for x,y,start in [(w/2-r,h/2-r,0),(-w/2+r,h/2-r,90),(-w/2+r,-h/2+r,180),(w/2-r,-h/2+r,270)]:
        for i in range(steps):
            a=math.radians(start+i*90/(steps-1));points.append((x+r*math.cos(a),y+r*math.sin(a)))
    return points


def relief(name,points,back,front,color,edge,bevel=0):
    """Convex closed board with one front bevel; named source remains editable."""
    cx=sum(x for x,y in points)/len(points);cy=(min(y for x,y in points)+max(y for x,y in points))/2
    loops=[(points,back),(points,front-bevel)]
    if bevel:
        w=max(x for x,y in points)-min(x for x,y in points)
        h=max(y for x,y in points)-min(y for x,y in points)
        inset=[(cx+(x-cx)*(1-2*bevel/w),cy+(y-cy)*(1-2*bevel/h)) for x,y in points]
        loops.append((inset,front))
    n=len(points);verts=[(x,y,z) for ring,z in loops for x,y in ring]
    faces=[tuple(reversed(range(n)))]
    for j in range(len(loops)-1):
        faces.extend((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for i in range(n))
    faces.append(tuple(range((len(loops)-1)*n,len(loops)*n)))
    obj=kit.mesh(name,verts,faces,color)
    obj.data.materials.append(kit.MATS[edge])
    for face in obj.data.polygons[:-1]:face.material_index=1
    return obj


def leaf(name,at,angle,color):
    # Small embossed lanceolate leaf, lying in the board plane, never growing above it.
    a=math.radians(angle);ux,uy=math.cos(a),math.sin(a);vx,vy=-uy,ux
    outline=[(-.020,0),(-.006,.008),(.020,0),(-.006,-.008)]
    verts=[(at[0]+u*ux+v*vx,at[1]+u*uy+v*vy,.065) for u,v in outline]
    verts.extend([(at[0],at[1],.072),(at[0],at[1],.064)])
    faces=[(i,(i+1)%4,4) for i in range(4)]+[((i+1)%4,i,5) for i in range(4)]
    return kit.mesh(name,verts,faces,color)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    for name,value in PALETTE.items():
        material=bpy.data.materials.new(name);material.diffuse_color=(*kit.rgb(value),1);material.use_nodes=True
        shader=material.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value=material.diffuse_color
        shader.inputs["Roughness"].default_value=.9;shader.inputs["Specular IOR Level"].default_value=.18
        kit.MATS[name]=material
    kit.begin(NAME,[1,1],600,generator="tools/art/build_upgrade_plaque.py",pivot="post foot bottom centre",front="+Z",
              author="赵云",virtual_user_id="8ea32e40-c0ba-4a31-864f-374a6bcbc554",
              target_size_m=[.50,.70],face_size_m=[.40,.28],face_center=list(FACE_CENTER),
              writable_size_m=[.38,.24],runtime_scale=1.0,placement_cell=[7,14],collision="none; integration must retain the current non-blocking plaque")
    kit.box("Single timber post / grounded foot",(0,.16,0),(.095,.32,.072),"wood_light",.008)
    # Bottom rounded corners, then twelve arch segments. The highest point is exactly .70 m.
    outline=[(-.232,.245),(.232,.245),(.2447,.2503),(.25,.263),(.25,.56)]
    outline.extend((.25*math.cos(math.pi*i/12),.56+.14*math.sin(math.pi*i/12)) for i in range(1,13))
    outline.extend([(-.25,.263),(-.2447,.2503)])
    relief("Arched timber plaque / continuous rounded top",outline,.004,.064,"wood_light","wood_edge",.007)
    face=[(x,y+.43) for x,y in rounded_rect(.40,.28,.012,3)]
    relief("Blank warm ivory face / no lettering",face,.062,.076,"ivory","ivory_edge",.003)
    # Four subdued wood/bronze heads sit in the wood border, outside the clear text panel.
    for x in [-.223,.223]:
        for y in [.281,.576]:
            points=[(x+.009*math.cos(i*math.tau/8),y+.009*math.sin(i*math.tau/8)) for i in range(8)]
            relief("Matte corner nail %s %s"%(x,y),points,.063,.069,"nail","nail",.002)
    for side in [-1,1]:
        # Two 2.8 cm stems and eight 4 cm leaves hug the shallow arched header.
        points=[(side*.055,.604),(side*.062,.606),(side*.084,.648),(side*.079,.652)]
        relief("Laurel %s / short flat stem"%side,points,.064,.067,"stem","stem")
        for i,(x,y,a) in enumerate([(.050,.613,-25),(.080,.624,50),(.063,.637,-20),(.086,.651,70)]):
            leaf("Laurel %s / leaf %d"%(side,i+1),(side*x,y),a if side==1 else 180-a,"laurel_light" if i%2 else "laurel")
    marker=bpy.data.objects.new("PlaqueText",None);kit.CURRENT.objects.link(marker)
    marker.location=kit.v(SOCKET);marker.empty_display_type="ARROWS";marker.empty_display_size=.025
    marker["writable_size_m"]=[.38,.24];marker["surface_offset_m"]=.002
    kit.META[NAME]["sockets"]={"PlaqueText":{"position":list(SOCKET),"front":"+Z","node_type":"Marker3D","size":[.38,.24],"surface_offset_m":.002}}
    material=bpy.data.materials.new("Farm vertex paint");material.use_nodes=True
    shader=material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value=.9;shader.inputs["Specular IOR Level"].default_value=.18
    vc=material.node_tree.nodes.new("ShaderNodeVertexColor");vc.layer_name="Color"
    material.node_tree.links.new(vc.outputs["Color"],shader.inputs["Base Color"])
    entry=kit.export_asset(NAME,kit.CURRENT,material)
    # Keep the runtime mesh name explicit, matching recent farm assets' handoff contract.
    path=OUT/(NAME+".glb");raw=path.read_bytes();size=struct.unpack_from("<I",raw,12)[0]
    doc=json.loads(raw[20:20+size]);tail=raw[20+size:];doc["meshes"][0]["name"]=NAME+"_mobile"
    encoded=json.dumps(doc,separators=(",",":")).encode();encoded+=b" "*(-len(encoded)%4)
    path.write_bytes(struct.pack("<III",0x46546C67,2,20+len(encoded)+len(tail))+struct.pack("<II",len(encoded),0x4E4F534A)+encoded+tail)
    entry.update(bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                 source="tools/art/source/upgrade_plaque_401/upgrade_plaque.blend",palette_srgb=PALETTE,
                 laurel_note="Two shallow sprigs; eight small leaves remain below the timber top and outside the blank panel",
                 material_contract={"vertex_color_is_srgb":False,"roughness":.9,"metallic":0,"specular":.18})
    manifest_path=OUT/"manifest.json";manifest=json.loads(manifest_path.read_text())
    manifest["assets"][NAME]=entry
    manifest_path.write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+"\n")
    SOURCE.mkdir(parents=True,exist_ok=True);(SOURCE/"spec.json").write_text(json.dumps(entry,indent=2,ensure_ascii=False)+"\n")
    bpy.context.scene.unit_settings.system="METRIC"
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/"upgrade_plaque.blend"),compress=True)
    print("UPGRADE_PLAQUE",entry["triangles"],"triangles",entry["bounds"],flush=True)


if __name__=="__main__":main()
