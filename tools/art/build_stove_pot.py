#!/usr/bin/env python3
"""SGODOT-282 v1.1: named hollow pottery, hinged lid, deterministic metre GLB.
Run Blender --background --factory-startup --python /absolute/path/to/this.py.
Input points use Godot Y-up / +Z front. Export copies merge per runtime part;
editable source objects retain names, palette and intended parent hierarchy.
"""
import hashlib,json,math,struct,sys,zlib
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_decor_assets as k
from verify_chef_sign import load_glb
ROOT=k.ROOT;OUT=ROOT/'assets/props/stove_pot';SOURCE=ROOT/'tools/art/source/stove_pot_282'
SW=json.loads((SOURCE/'atlas-swatches.json').read_text());EXTRA=SW['extra_palette']
GROUP='normal';PIVOT=(0,.181,-.107)

def tag(o):o['export_group']=GROUP;return o

def revolve(name,profile,color,n=16,at=(0,0,0),inner_from=None,caps=True):
    # A continuous outside -> rounded lip -> inside profile closes only at its
    # two small bottom circles. There is deliberately no polygon at the mouth.
    o=tag(k.lathe(name,profile,color,n,at))
    if not caps:
        # Band is an open-backed skin: three contiguous strips tuck into body.
        import bmesh
        bm=bmesh.new();bm.from_mesh(o.data);bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm,geom=list(bm.faces)[-2:],context='FACES_ONLY');bm.to_mesh(o.data);bm.free()
    if inner_from is not None:
        o.data.materials.append(k.MATS['inner_clay'])
        for f in o.data.polygons:
            if inner_from*n<=f.index<(len(profile)-1)*n or f.index==len(o.data.polygons)-1:f.material_index=1
    return o

def ring_handle(side):
    # Closed torus, vertical oval. Inboard portion physically enters the wall.
    verts=[];faces=[];major=8;minor=4
    for i in range(major):
        a=i*math.tau/major
        for j in range(minor):
            b=j*math.tau/minor;t=.006
            verts.append((side*(.118+(.016+t*math.cos(b))*math.cos(a)),.148+(.021+t*math.cos(b))*math.sin(a),t*math.sin(b)))
    for i in range(major):
        for j in range(minor):faces.append((i*minor+j,((i+1)%major)*minor+j,((i+1)%major)*minor+(j+1)%minor,i*minor+(j+1)%minor))
    return tag(k.mesh(('Left' if side<0 else 'Right')+' / closed thick ring handle',verts,faces,'deep_clay',True))

def empty(name,at,parent=None):
    o=bpy.data.objects.new(name,None);k.CURRENT.objects.link(o);o.empty_display_type='PLAIN_AXES';o.empty_display_size=.025
    o.location=k.v(at)
    if parent:o.parent=parent
    return o

def build():
    global GROUP
    k.begin('Stove pots / editable named parts',[0,0],1100)
    normal=empty('pot_normal',(0,0,0));big=empty('pot_big',(0,0,0))
    GROUP='normal'
    revolve('Normal / hollow rounded body and rolled rim',[(.063,0),(.083,.008),(.098,.035),(.100,.108),(.106,.127),(.106,.136),(.098,.14),(.090,.134),(.087,.040),(.063,.018)],'terracotta',16,inner_from=7)
    for s in [-1,1]:tag(k.ellipsoid(('Left' if s<0 else 'Right')+' / normal small solid ear',(s*.105,.112,0),(.030,.029,.048),'terracotta',8,3))
    empty('mouth',(0,.14,0),normal)
    GROUP='big_body'
    revolve('Big / hollow tall body and rounded rim',[(.070,0),(.090,.010),(.099,.035),(.101,.142),(.105,.173),(.101,.180),(.094,.176),(.089,.035),(.067,.020)],'deep_clay',14,inner_from=6)
    for s in [-1,1]:ring_handle(s)
    revolve('Big / bright copper belt',[(.0997,.075),(.103,.077),(.1034,.102),(.1003,.104)],'copper',14,caps=False)
    GROUP='lid'
    # Underside is a true shallow dome (not a solid filled pot); rear rim y=.181.
    revolve('Lid / terracotta domed shell',[(.022,.204),(.079,.193),(.103,.181),(.107,.185),(.084,.204),(.025,.219)],'deep_clay',12)
    tag(k.ellipsoid('Lid / round honey wood knob',(0,.226,0),(.036,.032,.036),'honey',8,4))
    # Raised open tube set into dome. Aperture is real, with a dark inner wall.
    revolve('Lid / hollow steam outlet',[(.010,.197),(.010,.213),(.005,.213),(.005,.197)],'deep_clay',6,at=(.062,0,.039),inner_from=2,caps=False)
    lid=empty('lid',PIVOT,big)
    empty('mouth',(0,.180,0),big)
    empty('vent',(.062,.213,.039),big)
    for obj in list(k.CURRENT.objects):
        if obj.type!='MESH':continue
        parent={'normal':normal,'big_body':big,'lid':lid}[obj['export_group']]
        world=obj.matrix_world.copy();obj.parent=parent
        bpy.context.view_layer.update();obj.matrix_world=world
    return normal,big,lid

def mat(name,image):
    m=bpy.data.materials.new(name);m.use_nodes=True
    sh=m.node_tree.nodes.get('Principled BSDF');sh.inputs['Roughness'].default_value=.8;sh.inputs['Specular IOR Level'].default_value=.28
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image;m.node_tree.links.new(tex.outputs['Color'],sh.inputs['Base Color'])
    k.MATS[name]=m;return m

def uv_for(color):
    if color in SW['swatches']:u,v=SW['swatches'][color]['gltf_uv'];return u,1-v
    i=list(EXTRA).index(color);return (i%2+.5)/2,1-(i//2+.5)/2

def canonicalize(path):
    d,b=load_glb(path);b=bytearray(b)
    for n in d['nodes']:
        if n.get('name','').startswith('mouth'):n['name']='mouth'
    for mesh in d['meshes']:
        for p in mesh['primitives']:
            a=d['accessors'][p['indices']];view=d['bufferViews'][a['bufferView']];offset=view.get('byteOffset',0)+a.get('byteOffset',0)
            fmt={5121:'B',5123:'H',5125:'I'}[a['componentType']];ids=struct.unpack_from('<'+fmt*a['count'],b,offset)
            tris=sorted(tuple(ids[i:i+3]) for i in range(0,len(ids),3));struct.pack_into('<'+fmt*a['count'],b,offset,*(j for t in tris for j in t))
    d['images']=[{'uri':'../warming_cabinet/room_albedo_ao.png'},{'uri':'pottery_palette.png'}]
    d['samplers']=[{'magFilter':9729,'minFilter':9987,'wrapS':33071,'wrapT':33071}];d['textures']=[{'source':i,'sampler':0} for i in range(2)]
    for m in d['materials']:
        m['pbrMetallicRoughness']['baseColorTexture']={'index':0 if m['name']=='StovePot_SharedRoomAtlas' else 1}
        m['pbrMetallicRoughness']['metallicFactor']=0;m['pbrMetallicRoughness']['roughnessFactor']=.8
        m['alphaMode']='OPAQUE';m['doubleSided']=False
    payload=json.dumps(d,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4);b+=b'\0'*((-len(b))%4)
    path.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(payload)+len(b))+struct.pack('<I4s',len(payload),b'JSON')+payload+struct.pack('<I4s',len(b),b'BIN\0')+b)

def main():
    OUT.mkdir(parents=True,exist_ok=True);SOURCE.mkdir(parents=True,exist_ok=True);(SOURCE/'.gdignore').touch()
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):bpy.data.collections.remove(c)
    bpy.context.preferences.filepaths.save_version=0;bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
    atlas=ROOT/SW['atlas'];assert hashlib.sha256(atlas.read_bytes()).hexdigest()==SW['atlas_sha256']
    def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
    raw=b''.join(b'\0'+b''.join(bytes.fromhex(list(EXTRA.values())[(x//128)+(y//128)*2]) for x in range(256)) for y in range(256))
    (OUT/'pottery_palette.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',256,256,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b''))
    atlas_image=bpy.data.images.load(str(atlas));palette=bpy.data.images.load(str(OUT/'pottery_palette.png'))
    for name in SW['swatches']:mat(name,atlas_image)
    for name in EXTRA:mat(name,palette)
    normal,big,lid=build();bpy.context.view_layer.update()
    original=list(k.CURRENT.objects)
    for obj in original:
        if obj.type=='MESH':
            uv=obj.data.uv_layers.new(name='PaletteUV')
            for f in obj.data.polygons:
                for i in f.loop_indices:uv.data[i].uv=uv_for(obj.data.materials[f.material_index].name)
    deps=bpy.context.evaluated_depsgraph_get();export=[];records={}
    runtime={}
    for key,label in [('honey','StovePot_SharedRoomAtlas'),('terracotta','StovePot_PotteryCopper')]:runtime[label]=k.MATS[key].copy();runtime[label].name=label
    for group,name,parent,pivot in [('normal','normal_body',normal,(0,0,0)),('big_body','big_body',big,(0,0,0)),('lid','lid_mesh',lid,PIVOT)]:
        bpy.ops.object.select_all(action='DESELECT');copies=[]
        for src in original:
            if src.type!='MESH' or src['export_group']!=group:continue
            data=bpy.data.meshes.new_from_object(src.evaluated_get(deps),depsgraph=deps);o=bpy.data.objects.new(src.name+' export',data);bpy.context.scene.collection.objects.link(o)
            o.matrix_world=src.matrix_world.copy();o.select_set(True);copies.append(o)
        bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();o=bpy.context.object;o.name=name
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);bpy.context.scene.cursor.location=k.v(pivot);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        mod=o.modifiers.new('Fixed triangulation','TRIANGULATE');mod.quad_method='FIXED';mod.ngon_method='CLIP';bpy.ops.object.modifier_apply(modifier=mod.name)
        old=list(o.data.materials);keys=[];faces=[]
        for f in o.data.polygons:
            color=old[f.material_index].name;key='StovePot_SharedRoomAtlas' if color=='honey' else 'StovePot_PotteryCopper'
            for i in f.loop_indices:o.data.uv_layers.active.data[i].uv=uv_for(color)
            if key not in keys:keys.append(key)
            faces.append(key)
        o.data.materials.clear()
        for key in keys:o.data.materials.append(runtime[key])
        for f,key in zip(o.data.polygons,faces):f.material_index=keys.index(key)
        o.parent=parent;o.location=Vector((0,0,0));o.data.calc_loop_triangles()
        bpy.context.view_layer.update()
        points=[o.matrix_world@vert.co for vert in o.data.vertices]
        godot_points=[(p.x,p.z,-p.y) for p in points]
        limits=[[round(fn(p[axis] for p in godot_points),6) for axis in range(3)] for fn in [min,max]]
        records[group]={'triangles':len(o.data.loop_triangles),'surfaces':len(keys),'bounds':limits};export.append(o)
    triangles_normal=records['normal']['triangles'];triangles_big=records['big_body']['triangles']+records['lid']['triangles']
    print('STOVE_POT',records,triangles_normal,triangles_big,flush=True)
    assert triangles_normal<=400 and triangles_big<=700 and triangles_normal+triangles_big<=1100
    bpy.ops.object.select_all(action='DESELECT')
    for o in export+[o for o in original if o.type=='EMPTY']:o.select_set(True)
    path=OUT/'stove_pot.glb'
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_normals=True,export_materials='EXPORT',export_image_format='NONE',export_animations=False,export_cameras=False,export_lights=False)
    canonicalize(path)
    for o in export:bpy.data.objects.remove(o,do_unlink=True)
    atlas_image.filepath='//../../../../assets/props/warming_cabinet/room_albedo_ao.png';palette.filepath='//../../../../assets/props/stove_pot/pottery_palette.png'
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'stove_pot.blend'))
    contract={'spec':'SGODOT-282 stove pot / big pot v1.1','units':'metres; Y up; +Z front','pivot':'bottom centre, Y=0','variants':{'pot_normal':{'triangles':triangles_normal,'triangle_limit':400,'mouth':[0,.14,0]},'pot_big':{'triangles':triangles_big,'triangle_limit':700,'mouth':[0,.18,0],'vent':[.062,.213,.039],'lid_pivot':list(PIVOT)}},'triangles':triangles_normal+triangles_big,'groups':records,'lid_open':{'translation_delta':[0,.06,0],'rotation_degrees':[-20,0,0],'note':'Godot local X=-20 raises the +Z front and tilts toward -Z rear. vent is fixed under pot_big: emitter should only run while closed.'},'textures':['../warming_cabinet/room_albedo_ao.png','pottery_palette.png'],'atlas_sha256':SW['atlas_sha256'],'placements':{'basic_room':{'support':'hearth','y':1.377,'xz':[[-2.05,-2.36],[-1.72,-2.36],[-1.885,-2.84]],'hide':['kettle']},'standard_room_5':{'support':'range_cooker','y':1.457,'xz':[[1.28,-2.545],[1.58,-2.545],[1.58,-2.895]],'hide':[],'yaw_degrees':[0,0,45]},'deluxe_room_10':{'support':'range_cooker','y':1.291,'xz':[[-3.915,-.381],[-4.245,-.381],[-3.915,-.859]],'hide':[]}},'generator':'tools/art/build_stove_pot.py'}
    for variant,groups in [('pot_normal',['normal']),('pot_big',['big_body','lid'])]:
        limits=[[fn(records[g]['bounds'][i][axis] for g in groups) for axis in range(3)] for i,fn in enumerate([min,max])]
        contract['variants'][variant]['bounds']=limits;contract['variants'][variant]['size_xyz']=[round(b-a,6) for a,b in zip(*limits)]
    (OUT/'manifest.json').write_text(json.dumps(contract,indent=2)+'\n')
if __name__=='__main__':main()
