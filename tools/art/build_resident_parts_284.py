#!/usr/bin/env python3
"""Blender 5.2: replace only Geometry in original SM FBX containers.

The source's Model, Connections, GlobalSettings, units, pre-rotations and bone
frames survive exactly. No FBX scene re-export / guessed socket offset.
Run recolor_resident_parts_284.py first. Never runs the extraction pipeline.
"""
from pathlib import Path
from array import array
import bpy,bmesh,math,json,hashlib,copy
from mathutils import Vector
from io_scene_fbx import parse_fbx,encode_bin
ROOT=Path(__file__).resolve().parents[2];SRC=ROOT/'assets/avatar/source';OUT=ROOT/'tools/art/source/resident_parts_284'
METHODS=dict(zip('BCZYILFDRSilfdbc',['bool','char','int8','int16','int32','int64','float32','float64','bytes','string','int32_array','int64_array','float32_array','float64_array','bool_array','byte_array']))
def encoded(node):
    e=encode_bin.FBXElem(node.id)
    for t,v in zip(node.props_type,node.props):getattr(e,'add_'+METHODS[chr(t)])(v)
    e.elems=[encoded(n) for n in node.elems];return e
def child(node,key):return next(n for n in node.elems if n.id==key)
def element(key,types='',props=(),elems=()):
    return parse_fbx.FBXElem(key,list(props),bytearray(types.encode()),list(elems))
def scalar(key,value):return element(key,'S',[value])
def same(a,b):
    return a.id==b.id and a.props_type==b.props_type and a.props==b.props and len(a.elems)==len(b.elems) and all(same(x,y) for x,y in zip(a.elems,b.elems))
def replace_geometry(src,dst,obj):
    tree,version=parse_fbx.parse(str(src));original=copy.deepcopy(tree)
    geo=next(e for e in child(tree,b'Objects').elems if e.id==b'Geometry')
    me=obj.data;me.calc_loop_triangles();uv=me.uv_layers.active
    positions=array('d',(c for v in me.vertices for c in v.co));indices=array('i');normals=array('d');tex=array('d')
    for face in me.polygons:
        for j,li in enumerate(face.loop_indices):
            vi=me.loops[li].vertex_index;indices.append(vi if j<len(face.loop_indices)-1 else -vi-1)
            normals.extend(me.corner_normals[li].vector);tex.extend(uv.data[li].uv)
    normal=element(b'LayerElementNormal','I',[0],[element(b'Version','I',[101]),scalar(b'Name',b''),scalar(b'MappingInformationType',b'ByPolygonVertex'),scalar(b'ReferenceInformationType',b'Direct'),element(b'Normals','d',[normals])])
    texnode=element(b'LayerElementUV','I',[0],[element(b'Version','I',[101]),scalar(b'Name',b'map1'),scalar(b'MappingInformationType',b'ByPolygonVertex'),scalar(b'ReferenceInformationType',b'Direct'),element(b'UV','d',[tex])])
    material=element(b'LayerElementMaterial','I',[0],[element(b'Version','I',[101]),scalar(b'Name',b''),scalar(b'MappingInformationType',b'AllSame'),scalar(b'ReferenceInformationType',b'IndexToDirect'),element(b'Materials','i',[array('i',[0])])])
    layer=element(b'Layer','I',[0],[element(b'Version','I',[100])]+[element(b'LayerElement',elems=[scalar(b'Type',kind),element(b'TypedIndex','I',[0])]) for kind in [b'LayerElementNormal',b'LayerElementUV',b'LayerElementMaterial']])
    geo.elems[:]=[element(b'Vertices','d',[positions]),element(b'PolygonVertexIndex','i',[indices]),element(b'GeometryVersion','I',[124]),normal,texnode,material,layer]
    dst.parent.mkdir(exist_ok=True);encode_bin.write(str(dst),encoded(tree),version)
    after,v=parse_fbx.parse(str(dst));assert version==v
    # Encoder changes only FileId and CreationTime beyond the intended Geometry.
    checks={}
    for old,new in zip(original.elems,after.elems):
        if old.id in [b'FileId',b'CreationTime']:continue
        if old.id==b'Objects':
            assert len(old.elems)==len(new.elems)
            for a,b in zip(old.elems,new.elems):
                if a.id==b'Geometry':assert a.props==b.props
                else:assert same(a,b),(a.id,a.props[:2])
            checks['all_non_geometry_objects_exact']=True
        else:assert same(old,new),old.id
    checks.update({'version':v,'global_axes_units_exact':True,'model_names_hierarchy_transforms_exact':True,'connections_exact':True,'triangles':len(me.loop_triangles),'vertices':len(me.vertices),'sha256':hashlib.sha256(dst.read_bytes()).hexdigest()})
    return checks

def components(me):
    adj={v.index:set() for v in me.vertices}
    for e in me.edges:a,b=e.vertices;adj[a].add(b);adj[b].add(a)
    remain=set(adj);out=[]
    while remain:
        todo=[min(remain)];seen=set()
        while todo:
            i=todo.pop()
            if i in seen:continue
            seen.add(i);todo.extend(adj[i]-seen)
        remain-=seen;out.append(seen)
    return out

def load(part):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    path=next((SRC/part).glob('*.fbx'));bpy.ops.import_scene.fbx(filepath=str(path))
    obj=next(o for o in bpy.context.scene.objects if o.type=='MESH')
    assert obj.parent_type=='BONE' and obj.parent_bone=='Head_M'
    return path,obj

def source_material(texture):
    mat=bpy.data.materials.new('NPC atlas');mat.use_nodes=True
    bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.9
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(texture));tex.image.filepath='//'+str(texture.relative_to(ROOT))
    # Source .blend lives four levels under repository root.
    tex.image.filepath='//../../../../'+str(texture.relative_to(ROOT))
    mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color']);return mat

def hat():
    path,obj=load('hairhat51');me=obj.data;keep=components(me)[0]
    allverts=[];faces=[];uvs=[];smooth=[];parts=[]
    def add(name,verts,polys,uvs_in=None,color=(.75,.75),soft=True,native=False):
        offset=len(allverts);first=len(faces)
        allverts.extend(verts if native else [((y-.080)*100,z*100,x*100) for x,y,z in verts])
        faces.extend([tuple(offset+i for i in p) for p in polys]);smooth.extend([soft]*len(polys))
        uvs.extend(uvs_in if uvs_in is not None else [[color]*len(p) for p in polys]);parts.append((name,first,len(faces)))
    ids=sorted(keep);mapping={v:i for i,v in enumerate(ids)};hv=[]
    for i in ids:
        x,y,z=me.vertices[i].co;hv.append((27.93+(x-27.93)*.76,y,z))
    hp=[];hu=[]
    for p in me.polygons:
        if p.vertices[0] in keep:
            hp.append(tuple(mapping[i] for i in p.vertices));hu.append([tuple(me.uv_layers.active.data[i].uv*.5) for i in p.loop_indices])
    add('Short grey hair / derived hairhat51',hv,hp,hu,native=True)
    n=24
    # Smooth dome over the retained hair silhouette.
    rings=[0,.24,.48,.74,1.,1.26];v=[];f=[]
    for a in rings:
        for i in range(n):
            t=i*math.tau/n;v.append((.238*math.cos(a)*math.sin(t),.29+.20*math.sin(a),-.01+.25*math.cos(a)*math.cos(t)))
    for k in range(len(rings)-1):
        for i in range(n):j=(i+1)%n;f.append((k*n+i,k*n+j,(k+1)*n+j,(k+1)*n+i))
    top=len(v);v.append((0,.49,-.01))
    for i in range(n):f.append(((len(rings)-1)*n+i,(len(rings)-1)*n+(i+1)%n,top))
    add('Helmet / mustard round dome',v,f)
    def ellipse_profile(name,profile,color,brim=False):
        v=[];f=[]
        for y,rx,rz in profile:
            for i in range(n):
                t=i*math.tau/n;c=math.cos(t);v.append((rx*math.sin(t),y,-.01+rz*c+(.045*max(c,0)**4 if brim else 0)))
        for k in range(len(profile)):
            for i in range(n):j=(i+1)%n;q=(k+1)%len(profile);f.append((k*n+i,k*n+j,q*n+j,q*n+i))
        add(name,v,f,color=color)
    ellipse_profile('Helmet / short rounded front brim',[(.279,.233,.24),(.284,.258,.258),(.301,.258,.258),(.306,.233,.24)],(.75,.75),True)
    ellipse_profile('Helmet / dark mustard lower band',[(.307,.238,.25),(.308,.242,.254),(.334,.238,.25),(.334,.232,.244)],(.875,.625))
    nlight=20;v=[];f=[]
    for radius,z in [(.062,.220),(.066,.266),(.061,.289),(.047,.289),(.046,.266)]:
        for i in range(nlight):
            t=i*math.tau/nlight;v.append((radius*math.sin(t),.377+radius*math.cos(t),z))
    for k in range(5):
        for i in range(nlight):j=(i+1)%nlight;q=(k+1)%5;f.append((k*nlight+i,k*nlight+j,q*nlight+j,q*nlight+i))
    add('Headlamp / brass housing and rounded ring',v,f,color=(.625,.25))
    v=[(0,.377,.292)]+[(.047*math.sin(i*math.tau/nlight),.377+.047*math.cos(i*math.tau/nlight),.287) for i in range(nlight)]
    f=[(0,i+1,(i+1)%nlight+1) for i in range(nlight)]
    add('Headlamp / matte ivory lens (no emission)',v,f,color=(.875,.25))
    data=bpy.data.meshes.new('Ivo helmet + retained short hair');data.from_pydata(allverts,[],faces);data.update()
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
    uv=data.uv_layers.new(name='map1')
    # bmesh may flip face order, so map UVs by each face's vertex IDs.
    for p,original,coords,soft in zip(data.polygons,faces,uvs,smooth):
        lookup=dict(zip(original,coords));p.use_smooth=soft
        for li in p.loop_indices:uv.data[li].uv=lookup[data.loops[li].vertex_index]
    obj.data=data;obj.data.materials.append(source_material(SRC/'hairhat_npc_ivo/T_ivo_hairHat_D.png'))
    checks=replace_geometry(path,SRC/'hairhat_npc_ivo/SM_hairHat51.fbx',obj)
    # Preserve separately named editable construction groups in the blend.
    for name,start,end in parts:
        group=obj.vertex_groups.new(name=name)
        ids=sorted({i for p in data.polygons[start:end] for i in p.vertices});group.add(ids,1,'REPLACE')
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'ivo-helmet.blend'))
    checks['base']='hairhat51';checks['retained_hair_component']=0;checks['source_texture_size']=[2048,2048]
    return checks

def beard():
    path,obj=load('mask16_npc_kai');before=[tuple(v.co) for v in obj.data.vertices];bottom=min(p[0] for p in before)
    for v in obj.data.vertices:
        v.co.x=v.co.x/3+2.0
    obj.data.update();obj.data.materials.clear();obj.data.materials.append(source_material(SRC/'mask16_npc_ivo/T_ivo_mask_D.png'))
    checks=replace_geometry(path,SRC/'mask16_npc_ivo/SM_mask16.fbx',obj)
    checks.update({'base':'mask16_npc_kai','hanging_length_before_cm':-bottom,'bottom_below_head_origin_cm':-min(v.co.x for v in obj.data.vertices),'jaw_fit_lift_cm':2.0,'full_height_ratio':(max(v.co.x for v in obj.data.vertices)-min(v.co.x for v in obj.data.vertices))/(max(p[0] for p in before)-bottom)})
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'ivo-short-beard.blend'));return checks

def main():
    bpy.context.preferences.filepaths.save_version=0
    report={'hat':hat(),'beard':beard()}
    # Budget is the largest currently shipped hairHat, from source polygons.
    counts={}
    for p in SRC.glob('hairhat*/*.fbx'):
        if 'npc_ivo' in str(p) or 'granny_wu' in str(p):continue
        tree,_=parse_fbx.parse(str(p));total=0
        for g in child(tree,b'Objects').elems:
            if g.id!=b'Geometry':continue
            idx=next((c for c in g.elems if c.id==b'PolygonVertexIndex'),None)
            if idx:
                sides=0
                for i in idx.props[0]:
                    sides+=1
                    if i<0:total+=sides-2;sides=0
        counts[p.parent.name]=total
    report['existing_hairhat_source_triangles']=counts
    report['hat_budget']=max(counts.values());assert report['hat']['triangles']<=report['hat_budget']
    report['granny_fbx_byte_identical']=(SRC/'hairhat80_npc_ama/SM_hairHat80.fbx').read_bytes()==(SRC/'hairhat80_npc_granny_wu/SM_hairHat80.fbx').read_bytes();assert report['granny_fbx_byte_identical']
    (OUT/'geometry-validation.json').write_text(json.dumps(report,indent=2)+'\n');print('RESIDENT_GEOMETRY',json.dumps(report))
if __name__=='__main__':main()
