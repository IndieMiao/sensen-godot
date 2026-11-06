"""Two Alcatraz tree silhouettes, co-designed near/far topology and palette.
Run with flock ~/gs66-render.lock blender --background --python <this file>.
"""
from pathlib import Path
import hashlib, json, math, sys
import bpy, bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/art'))
import build_decor_assets as K
from verify_chef_sign import load_glb,accessor
SRC=ROOT/'tools/art/source/alcatraz_trees_cd_424'
OUT=ROOT/'assets/landmarks/alcatraz_island'
PALETTE=json.loads((SRC/'reference/palette.json').read_text())['colors']
ACTOR='8ea32e40-c0ba-4a31-864f-374a6bcbc554'

def activate(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True);bpy.context.view_layer.objects.active=o

def apply(o):
    activate(o);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bm=bmesh.new();bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free();o.data.update()

def bounds(o):
    return [[min(v.co[k] for v in o.data.vertices) for k in range(3)],
            [max(v.co[k] for v in o.data.vertices) for k in range(3)]]

def fit_bounds(o,source):
    lo,hi=bounds(o);a,b=bounds(source)
    for v in o.data.vertices:
        for k in range(3):v.co[k]=a[k]+(v.co[k]-lo[k])*(b[k]-a[k])/(hi[k]-lo[k])
    o.data.update()

def loft(name,rings,n,color):
    # rings: centre(x,y,z), radius_x, radius_z; all horizontal in Godot.
    vertices=[]
    for (x,y,z),rx,rz in rings:
        for j in range(n):
            t=j*math.tau/n
            vertices.append((x+rx*math.cos(t),y,z+rz*math.sin(t)))
    faces=[tuple(reversed(range(n))),tuple(range((len(rings)-1)*n,len(rings)*n))]
    for ring in range(len(rings)-1):
        for j in range(n):
            a=ring*n+j;b=ring*n+(j+1)%n
            faces.append((a,b,b+n,a+n))
    return K.mesh(name,vertices,faces,color,True)

def branch_tetra(name,a,b,r=.075):
    a,b=Vector(a),Vector(b);axis=(b-a).normalized()
    u=axis.cross(Vector((0,0,1))).normalized();v=axis.cross(u).normalized()
    return K.mesh(name,[a+u*r,a-u*r,b+v*.03,b-v*.03],
                  [(0,1,2),(1,0,3),(1,3,2),(0,2,3)],'wood_light',True)

def cypress(far):
    # A narrow, softly irregular column: no Christmas-tree branch tiers.
    profile=[(1.03,.20),(1.65,.58),(2.65,.78),(3.8,.80),(4.95,.68),
             (5.9,.51),(6.65,.36),(7.3,.20),(7.8,.025)]
    rings=[((.10*math.sin(y*.7),y,.055*math.sin(y*.9)),r,r*.84) for y,r in profile]
    crown=loft('Cypress / continuous tapered column',rings,6 if far else 12,'garden')
    stem=loft('Cypress / upright root and stem',[((0,0,0),.145,.145),((.07,1.7,.02),.07,.07)],4 if far else 8,'wood_dark')
    return [('column',crown,'garden'),('stem',stem,'wood_dark')]

def olive(far):
    result=[]
    specifications=[((-.65,2.60,0),(2.10,.90,1.80),'garden_dark'),
                    ((.70,2.72,-.10),(2.20,.95,1.95),'garden'),
                    ((.10,3.12,.18),(1.90,.96,1.80),'garden_light')]
    for i,(at,size,color) in enumerate(specifications):
        o=K.ellipsoid('Olive / low spreading lobe '+str(i+1),at,size,color,segments=10,rings=3 if far else 5)
        apply(o)
        if far:
            # Same widest-latitude height as the near model's 5-ring sphere.
            a,b=bounds(o);mid=(a[2]+b[2])/2
            for v in o.data.vertices:
                if a[2]+1e-5<v.co.z<b[2]-1e-5:v.co.z=mid+(v.co.z-mid)*.618033989
        result.append(('lobe_'+str(i+1),o,color))
    trunk=loft('Olive / short bent trunk',[((0,0,0),.155,.155),((.08,1.05,.02),.12,.12),((.18,2.23,.01),.065,.065)],4 if far else 8,'wood')
    result.append(('trunk',trunk,'wood'))
    for i,end in enumerate([(-.65,2.5,0),(.8,2.60,-.1)]):
        start=(.07,1.35,.01)
        o=branch_tetra('Olive / fork '+str(i+1),start,end) if far else K.rod('Olive / fork '+str(i+1),start,end,.075,'wood_light',segments=5,top=.03)
        result.append(('fork_'+str(i+1),o,'wood_light'))
    return result

def palette_paint(o,role,material,gradient=False):
    data=o.data;data.materials.clear();data.materials.append(material)
    attr=data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
    data.color_attributes.active_color=attr;data.color_attributes.render_color_index=0
    for loop in data.loops:
        color=K.rgb(PALETTE[role])
        if gradient:
            y=data.vertices[loop.vertex_index].co.z
            blend=max(0,min(1,(y-1.1)/6.7))
            a=K.rgb(PALETTE['garden_dark']);b=K.rgb(PALETTE['garden_light'])
            color=tuple(x*(1-blend)+z*blend for x,z in zip(a,b))
        attr.data[loop.index].color=(*color,1)

def transfer(o,source,material):
    data=source.data;data.calc_loop_triangles()
    points=[v.co.copy() for v in data.vertices];faces=[tuple(t.vertices) for t in data.loop_triangles]
    bvh=BVHTree.FromPolygons(points,faces,all_triangles=True)
    normals=[v.normal.copy() for v in data.vertices]
    colors={loop.vertex_index:data.color_attributes['Color'].data[loop.index].color[:] for loop in data.loops}
    out=o.data;out.materials.clear();out.materials.append(material)
    attr=out.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER');out.color_attributes.active_color=attr;out.color_attributes.render_color_index=0
    samples={}
    for vertex in out.vertices:
        hit,_,index,_=bvh.find_nearest(vertex.co);ids=faces[index];a,b,c=[points[k] for k in ids]
        u=b-a;v=c-a;w=hit-a;uu=u.dot(u);uv=u.dot(v);vv=v.dot(v);den=uu*vv-uv*uv
        s=(vv*w.dot(u)-uv*w.dot(v))/den if abs(den)>1e-12 else 0
        t=(uu*w.dot(v)-uv*w.dot(u))/den if abs(den)>1e-12 else 0
        weights=[1-s-t,s,t]
        n=sum((normals[j]*x for j,x in zip(ids,weights)),Vector()).normalized()
        color=[sum(colors[j][k]*x for j,x in zip(ids,weights)) for k in range(4)]
        samples[vertex.index]=(n,color)
    ln=[]
    for loop in out.loops:
        n,color=samples[loop.vertex_index];ln.append(n);attr.data[loop.index].color=color
    for p in out.polygons:p.use_smooth=True
    out.normals_split_custom_set(ln)

def trim_hidden_undersides(o):
    # Only a 43-degree island-camera LOD, not intended for underside inspection.
    bm=bmesh.new();bm.from_mesh(o.data);bm.normal_update()
    doomed=[f for f in bm.faces if f.normal.z*math.sin(math.radians(40))+math.hypot(f.normal.x,f.normal.y)*math.cos(math.radians(40)) < -1e-5]
    bmesh.ops.delete(bm,geom=doomed,context='FACES');bm.to_mesh(o.data);bm.free();o.data.update()

def export(name,parts,budget):
    bpy.ops.object.select_all(action='DESELECT');copies=[]
    for key,source,color in parts:
        o=source.copy();o.data=source.data.copy();bpy.context.scene.collection.objects.link(o);o.select_set(True);copies.append(o)
    bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();o=bpy.context.object
    o.name=name;o.data.name=name+'_mobile';o.data.calc_loop_triangles();count=len(o.data.loop_triangles)
    assert count<=budget,(name,count,budget)
    path=OUT/(name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_texcoords=False,export_tangents=False,export_animations=False,export_extras=False)
    doc,buf=load_glb(path);primitive=doc['meshes'][0]['primitives'][0];pos=accessor(doc,buf,primitive['attributes']['POSITION'])
    assert len(doc['meshes'])==1 and len(doc['meshes'][0]['primitives'])==1
    box=[[min(v[k] for v in pos) for k in range(3)],[max(v[k] for v in pos) for k in range(3)]]
    entry={'file':name+'.glb','triangles':count,'surfaces':1,'bounds':box,'height_m':box[1][1], 'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,'pivot':'root centre, Y=0','front':'+Z','material_contract':{'vertex_color_is_srgb':False,'roughness':.9,'metallic':0,'specular':.18}}
    bpy.data.objects.remove(o,do_unlink=True)
    print('TREE_CD',name,count,box,flush=True)
    return entry

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
    for role,value in PALETTE.items():
        m=bpy.data.materials.new(role);m.diffuse_color=(*K.rgb(value),1);K.MATS[role]=m
    material=bpy.data.materials.new('Alcatraz matte vertex palette');material.use_nodes=True
    shader=material.node_tree.nodes['Principled BSDF'];shader.inputs['Roughness'].default_value=.9;shader.inputs['Specular IOR Level'].default_value=.18
    vc=material.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';material.node_tree.links.new(vc.outputs['Color'],shader.inputs['Base Color'])
    entries={};groups=[]
    for base,make in [('alc_tree_c',cypress),('alc_tree_d',olive)]:
        near_parts=None
        for far in [False,True]:
            name=base+('_far' if far else '')
            collection=bpy.data.collections.new(name+' editable parts');bpy.context.scene.collection.children.link(collection);K.CURRENT=collection
            parts=make(far)
            for key,o,color in parts:
                apply(o)
                if far:
                    source=next(s for k,s,c in near_parts if k==key)
                    # Shared envelope, including the true root-centred pivot.
                    fit_bounds(o,source)
                    if key.startswith('lobe_'):trim_hidden_undersides(o)
                    # Tetrahedral branch facets use their own outward normals;
                    # a cylindrical source normal can face behind a tetra face.
                    if key.startswith('fork_'):palette_paint(o,color,material)
                    else:transfer(o,source,material)
                else:palette_paint(o,color,material,gradient=key=='column')
            entries[name]=export(name,parts,120 if far else 500)
            if not far:near_parts=parts
        groups.append({'name':base,'near':base,'far':base+'_far','switch_distance_m':40,'margin_m':0,'common_aabb':entries[base]['bounds'],'far_placeholder':False})
    manifest={'author':'赵云','virtual_user_id':ACTOR,'reference_commit':json.loads((SRC/'reference/layout-trees.json').read_text())['commit'],'palette_source':'tools/art/source/alcatraz_island/palette.json','palette_used':{k:PALETTE[k] for k in ['garden','garden_light','garden_dark','wood','wood_dark','wood_light']},'assets':entries,'lod_groups':groups,'far_camera_contract':{'pitch_degrees_min':40,'island_pitch_degrees':43,'rotation':'upright trees, yaw only','note':'D canopy undersides invisible at all yaw above 40 degrees are omitted; C remains closed.'},'source':'tools/art/source/alcatraz_trees_cd_424/trees_cd.blend','generator':'tools/art/build_alcatraz_trees_cd_424.py'}
    for path in [SRC/'asset_stats.json',OUT/'trees_cd_manifest.json']:path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    bpy.context.scene.unit_settings.system='METRIC';bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'trees_cd.blend'),compress=True)

if __name__=='__main__':main()
