"""Quarry v1: warm depth bands, readable terrace edges and timber supports."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import sys

import bpy
from mathutils import Vector

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[4]
QA=ROOT/"output/quarry-355"
pitch,yaw=map(math.radians,(43,14.5))
R=Vector((math.cos(yaw),0,-math.sin(yaw)))
U=Vector((-math.sin(yaw)*math.sin(pitch),math.cos(pitch),-math.cos(yaw)*math.sin(pitch)))
N=Vector((math.sin(yaw)*math.cos(pitch),math.sin(pitch),math.cos(yaw)*math.cos(pitch)))
PALETTE={"bands":[
    {"from":1,"to":4,"ground":"#dca26e","wall":"#b97941","backdrop_tint":"#664324","fog":"#242125"},
    {"from":5,"to":10,"ground":"#cd925b","wall":"#a06c3b","backdrop_tint":"#583b20","fog":"#242225"},
    {"from":11,"to":20,"ground":"#ba824a","wall":"#885e35","backdrop_tint":"#4b341d","fog":"#222125"},
    {"from":21,"to":30,"ground":"#a07146","wall":"#704e2e","backdrop_tint":"#3e2b19","fog":"#201f23"},
]}

def godot(p): return Vector((p.x,p.z,-p.y))
def blender(p): return Vector((p.x,-p.z,p.y))
def projection(p): return Vector((p.dot(R),p.dot(U)))

def export(target):
    bpy.ops.object.select_all(action="DESELECT")
    copies=[]
    for ob in bpy.data.collections["EDITABLE_RELIEF_PARTS"].objects:
        cp=ob.copy();cp.data=ob.data.copy();bpy.context.scene.collection.objects.link(cp)
        cp.select_set(True);copies.append(cp)
    bpy.context.view_layer.objects.active=copies[0]
    bpy.ops.object.join()
    joined=bpy.context.object;joined.name="QuarryBackdrop";joined.data.name="quarry_backdrop_mobile"
    joined.data.calc_loop_triangles()
    triangles=len(joined.data.loop_triangles)
    assert triangles<=4000,triangles
    bpy.ops.export_scene.gltf(filepath=str(target),export_format="GLB",use_selection=True,
        export_yup=True,export_materials="EXPORT",export_normals=True,export_texcoords=True,
        export_vertex_color="ACTIVE",export_all_vertex_colors=False)
    bpy.data.objects.remove(joined,do_unlink=True)
    return triangles

def main():
    parser=argparse.ArgumentParser();parser.add_argument("--runtime",required=True)
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    runtime=Path(args.runtime).resolve()
    source=runtime/"assets/mine/backdrop/source/mine_backdrop.blend"
    target=runtime/"assets/mine/types/quarry"
    target.mkdir(parents=True,exist_ok=True);QA.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    bpy.context.preferences.filepaths.save_version=0
    contour=json.loads(bpy.data.texts["contour.json"].as_string())
    inner=[Vector(q) for q in contour["inner"]]
    def distance(q):
        result=math.inf
        for a,b in zip(inner,inner[1:]):
            v=b-a;t=max(0,min(1,(q-a).dot(v)/v.length_squared))
            result=min(result,(q-a-t*v).length)
        return result
    def fade(q):
        d=distance(q);t=max(0,min(1,(d-.6)/2.75))
        return max(max(0,1-d/.22)*.85,t*t*(3-2*t))
    collection=bpy.data.collections["EDITABLE_RELIEF_PARTS"]
    base=bpy.data.objects["01_Continuous_Earth_And_Rock_Strata"]
    mat=base.data.materials[0]
    baseline_inner=[]
    for polygon in list(base.data.polygons)[:112]:
        for local in [0,3]:
            baseline_inner.append(list(godot(base.data.vertices[polygon.vertices[local]].co)))
    # Keep ring zero byte-stable; edit only the relief outside that protected edge.
    tones=[.55,.54,.95,.42,.94,.43,.92,.44,.51,.44]
    depths=[-6.93,-6.91,-6.79,-6.91,-6.77,-6.92,-6.79,-6.93,-6.85,-6.94,-6.94]
    gray=base.data.color_attributes["StrataGray"]
    for index,polygon in enumerate(base.data.polygons):
        band=index//112;segment=index%112
        for local,vi in enumerate(polygon.vertices):
            ring=band+(1 if local in [1,2] else 0)
            vertex=base.data.vertices[vi]
            p=godot(vertex.co);q=projection(p)
            if ring>0:
                bias=max(0,min(1.10,.20*(q.x-2.5)))
                depth=max(-6.969,min(-5.601,depths[ring]+bias+.014*math.sin(segment*.58)))
                vertex.co=blender(p+N*(depth-p.dot(N)))
        for li in polygon.loop_indices:
            value=max(.42,min(.96,tones[band]*(1+.018*math.sin(segment*.8))))
            gray.data[li].color=(value,value,value,1)
    for ob in list(collection.objects):
        if ob.name.startswith("04_Dead_Root") or (ob.name.startswith("02_Rock_Mass") and int(ob.name.rsplit("_",1)[1])%4):
            bpy.data.objects.remove(ob,do_unlink=True)
    def beam(name,a,b,width):
        a=Vector(a);b=Vector(b);along=(b-a).normalized();side=Vector((-along.y,along.x))*width/2
        corners=[a-side,b-side,b+side,a+side]
        centre=(a+b)/2
        inset=[centre+(q-centre)*Vector((.91,.91)) for q in corners]
        coords=corners+inset
        vertices=[]
        for i,q in enumerate(coords):
            bias=max(0,min(1.10,.20*(q.x-2.5)))
            depth=-6.73+bias+(.028 if i>=4 else 0)
            depth=min(-5.601,depth)
            vertices.append(blender(R*q.x+U*q.y+N*depth))
        faces=[(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
        ob=bpy.data.objects.new(name,mesh);collection.objects.link(ob);mesh.materials.append(mat)
        c=mesh.color_attributes.new(name="StrataGray",type="FLOAT_COLOR",domain="CORNER")
        mesh.color_attributes.active_color=c
        mesh.uv_layers.new(name="UVMap");uv=mesh.uv_layers.new(name="Fade_UV2")
        for polygon in mesh.polygons:
            g=[.58,.72,.96,.80,.96][polygon.index]
            for li in polygon.loop_indices:
                c.data[li].color=(g,g,g,1)
                uv.data[li].uv=(fade(coords[mesh.loops[li].vertex_index]),1)
        ob["role"]="Shallow timber relief outside the unchanged protection contour; no collision."
    supports=[(4.2,-1.88,1.45,.78),(6.65,-2.40,1.45,.78),(-1.7,2.0,.85,1.1),
        (13.1,2.8,.80,1.0),(5.8,7.25,1.5,.60)]
    for i,(x,y,w,h) in enumerate(supports):
        left=(x-w/2,y-h);right=(x+w/2,y-h)
        beam(f"05_Timber_{i}_left",left,(left[0],y),.24)
        beam(f"05_Timber_{i}_right",right,(right[0],y),.24)
        beam(f"05_Timber_{i}_lintel",(x-w*.61,y),(x+w*.61,y),.28)
        beam(f"05_Timber_{i}_brace",(x-w*.43,y-h*.91),(x+w*.43,y-h*.12),.20)
    for ob in collection.objects:
        # glTF export flips Blender's V: authored 1 becomes the required mask 0.
        for row in ob.data.uv_layers["Fade_UV2"].data: row.uv.y=1
    after_inner=[]
    for polygon in list(base.data.polygons)[:112]:
        for local in [0,3]: after_inner.append(list(godot(base.data.vertices[polygon.vertices[local]].co)))
    assert baseline_inner==after_inner
    bpy.context.scene["quarry_stage"]="v1"
    bpy.context.scene["quarry_runtime_project"]=str(runtime)
    bpy.context.scene["channels"]="COLOR.rgb linear grayscale; alpha1; UV2.x void fade; UV2.y0."
    text=bpy.data.texts["EXPORT_RUNTIME.py"]
    text.clear();text.write('import bpy, os\nfrom pathlib import Path\n'+
        'exec(bpy.data.texts["quarry_export_function.py"].as_string())\n'+
        'runtime=Path(os.environ.get("QUARRY_RUNTIME",bpy.context.scene["quarry_runtime_project"]))\n'+
        'export(runtime/"assets/mine/types/quarry/backdrop.glb")\n')
    import inspect
    name="quarry_export_function.py"
    if name in bpy.data.texts: bpy.data.texts.remove(bpy.data.texts[name])
    bpy.data.texts.new(name).write(inspect.getsource(export))
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/"quarry.blend"))
    triangles=export(target/"backdrop.glb")
    (target/"palette.json").write_text(json.dumps(PALETTE,indent=2)+"\n")
    info={"triangles":triangles,"source":str(source.relative_to(runtime)),"source_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),
        "inner_vertices_unchanged":len(baseline_inner),"inner_vertices":baseline_inner,"contour":contour,
        "basis":{"right":list(R),"up":list(U),"normal":list(N)},"parts":len(collection.objects),
        "runtime_forward_translation_m":1.0,"mesh_forward_translation_m":0.0}
    (QA/"build.json").write_text(json.dumps(info,indent=2)+"\n")
    print("QUARRY_V1",triangles,"triangles",len(collection.objects),"parts; inner unchanged",len(baseline_inner))

if __name__=="__main__": main()
