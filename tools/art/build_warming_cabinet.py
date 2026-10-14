#!/usr/bin/env python3
"""SGODOT-282 v1.1. Blender background: named source -> two metre-scale GLBs.
Godot Y up / +Z front; origin is the floor centre of the back plane.
A and B share identical cabinet/dish geometry. Only A includes an alpha pane.
"""
import hashlib,json,math,struct,sys,shutil,zlib
from pathlib import Path
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_decor_assets as k
from verify_chef_sign import load_glb
ROOT=k.ROOT
OUT=ROOT/'assets/props/warming_cabinet'
SOURCE=ROOT/'tools/art/source/warming_cabinet_282'
SW=json.loads((SOURCE/'atlas-swatches.json').read_text())
EXTRA={'amber':'E8AD4D','amber_light':'F3C46B','stew':'D98737','bread':'DDB05B'}
GROUP='cabinet'

def tag(o):
    o['export_group']=GROUP
    o['swatch']=o.data.materials[0].name
    return o

def box(name,at,size,color,bevel=.008):return tag(k.box(name,at,size,color,bevel))
def sphere(name,at,size,color,segments=8,rings=3):return tag(k.ellipsoid(name,at,size,color,segments,rings))
def lathe(name,profile,color,at,segments=10):return tag(k.lathe(name,profile,color,segments,at))
def mesh(name,verts,faces,color):return tag(k.mesh(name,verts,faces,color))

def frame():
    from build_fare_board import outline
    # One continuous frame, with softly chamfered outer and inner boundaries.
    outer=outline(.50,.88,.016);inner=outline(.405,.785,.012)
    rings=[(outer,.438),(outline(.49,.87,.015),.478),(inner,.478),(inner,.438)]
    verts=[(x,y+.795,z) for shape,z in rings for x,y in shape]
    faces=[];n=8
    for r in range(len(rings)):
        for i in range(n):faces.append((r*n+i,r*n+(i+1)%n,((r+1)%len(rings))*n+(i+1)%n,((r+1)%len(rings))*n+i))
    mesh('Door / continuous rounded sage frame',verts,faces,'sage')
    box('Door / single vertical mullion',(0,.795,.460),(.022,.793,.034),'sage',0)

def build():
    global GROUP
    k.begin('Warming Cabinet / editable parts',[1,1],1500)
    GROUP='cabinet'
    box('Honey top / rounded overhang',(0,1.285,.25),(.56,.07,.50),'honey',.018)
    for s in [-1,1]:
        box(('Left' if s<0 else 'Right')+' sage side',(s*.2425,.675,.229),(.035,1.15,.458),'sage',.008)
        for z in [.075,.412]:
            lathe(('Left' if s<0 else 'Right')+(' back' if z<.2 else ' front')+' rounded foot',[(.035,0),(.046,.015),(.046,.095)],'sage',(s*.205,0,z),6)
    box('Solid sage back',(0,.675,.014),(.454,1.15,.028),'sage',0)
    box('Sage lower rail',(0,.105,.242),(.52,.05,.484),'sage',.008)
    box('Drawer / lower carcass',(0,.24,.234),(.454,.22,.42),'sage',0)
    box('Drawer / rounded honey front',(0,.242,.457),(.438,.165,.038),'honey',.012)
    sphere('Drawer / round brass knob',(0,.242,.483),(.037,.037,.034),'brass')
    # Plain amber lining, no emission or light node. The shelf undersides use
    # the lighter amber swatch so the existing room light remains readable.
    box('Interior / amber back',(0,.798,.030),(.454,.895,.006),'amber',0)
    for i,y in enumerate([.378,.654,.930],1):
        box(f'Shelf {i} / honey ledge',(0,y,.235),(.454,.025,.402),'honey',0)
        mesh(f'Shelf {i} / amber underside',[(-.225,y-.0126,.04),(.225,y-.0126,.04),(.225,y-.0126,.43),(-.225,y-.0126,.43)],[(0,3,2,1)],'amber_light')
    frame()
    for y in [.487,1.105]:
        tag(k.cylinder('Door / brass hinge',( .248,y,.472),.010,.065,'brass',segments=8))
    sphere('Door / small brass latch',(-.232,.77,.484),(.027,.047,.030),'brass')
    # Six independently switchable nodes. Side-by-side bowls clear the single
    # mullion; shelf pitch exposes each serving in the requested 43 degree view.
    for i,(x,y,food) in enumerate([(-.111,.943,'stew'),(.111,.943,'bread'),(-.111,.667,'bread'),(.111,.667,'leaf'),(-.111,.391,'bread'),(.111,.391,'stew')],1):
        GROUP=f'dish_{i}'
        lathe(f'Dish {i} / cream bowl and plate',[(.053,0),(.077,.010),(.088,.060),(.073,.064)],'cream',(x,y,.335),8)
        # Main serving is a rounded dome, with two lobes on bread/vegetables.
        sphere(f'Dish {i} / rounded {food} serving',(x,y+.070,.335),(.139,.086,.132),food,8,4)
        if food=='stew':
            sphere(f'Dish {i} / herb garnish',(x+.016,y+.112,.332),(.038,.022,.033),'leaf',6,4)
        elif food in ['leaf','bread']:
            sphere(f'Dish {i} / second {food} lobe',(x-.033,y+.097,.32),(.071,.056,.066),food,6,4)
    GROUP='highlights'
    # Two narrow opaque diagonal strips float immediately behind the door face.
    # Their ends sit within the inner frame, implying closed glass in option B.
    for label,x,y,length in [('upper left',-.154,1.108,.081),('upper right',.145,.855,.058)]:
        dx=length*.7;dy=length*.7;w=.009
        mesh('Glass cue / '+label,[(x-dx/2-w,y-dy/2,.470),(x-dx/2,y-dy/2,.470),(x+dx/2+w,y+dy/2,.470),(x+dx/2,y+dy/2,.470)],[(0,1,2,3)],'cream')
    GROUP='glass'
    mesh('A only / transparent glass', [(-.206,.396,.462),(.206,.396,.462),(.206,1.194,.462),(-.206,1.194,.462)],[(0,1,2,3)],'glass')
    for name,at in {'top_center':(0,1.32,.25),'door_center':(0,.795,.498),'glow':(0,.795,.25)}.items():k.socket(name,at)

def make_material(name,texture=None,alpha=1):
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    sh=mat.node_tree.nodes.get('Principled BSDF')
    sh.inputs['Base Color'].default_value=(1,1,1,1);sh.inputs['Roughness'].default_value=.8
    sh.inputs['Specular IOR Level'].default_value=.25
    if texture:
        img=mat.node_tree.nodes.new('ShaderNodeTexImage');img.image=texture
        mat.node_tree.links.new(img.outputs['Color'],sh.inputs['Base Color'])
    if alpha<1:
        sh.inputs['Base Color'].default_value=(*k.rgb('E8EEE2'),1)
        sh.inputs['Alpha'].default_value=alpha;sh.inputs['Roughness'].default_value=.35
        mat.surface_render_method='BLENDED';mat.use_transparent_shadow=False
    k.MATS[name]=mat;return mat

def external_images(path):
    # One shared external texture per opaque material across both GLBs. Avoid
    # duplicating 2048 atlas bytes in every mesh/variant.
    d,b=load_glb(path);b=bytearray(b)
    # Every primitive needs canonical indices (the older one-mesh helper only
    # handles its first primitive). Blender may reorder equivalent triangles.
    for mesh in d['meshes']:
        for primitive in mesh['primitives']:
            a=d['accessors'][primitive['indices']];v=d['bufferViews'][a['bufferView']]
            offset=v.get('byteOffset',0)+a.get('byteOffset',0);fmt={5121:'B',5123:'H',5125:'I'}[a['componentType']]
            indices=struct.unpack_from('<'+fmt*a['count'],b,offset)
            triangles=sorted(tuple(indices[i:i+3]) for i in range(0,len(indices),3))
            struct.pack_into('<'+fmt*a['count'],b,offset,*(x for t in triangles for x in t))
    d['images']=[{'uri':'room_albedo_ao.png'},{'uri':'interior_food.png'}]
    d['samplers']=[{'magFilter':9729,'minFilter':9987,'wrapS':33071,'wrapT':33071}]
    d['textures']=[{'sampler':0,'source':i} for i in range(2)]
    for m in d['materials']:
        name=m['name'];pbr=m.setdefault('pbrMetallicRoughness',{})
        if name!='Warming_Glass_A':pbr['baseColorTexture']={'index':1 if name=='Warming_InteriorFood' else 0}
        if name=='Warming_Glass_A':m['alphaMode']='BLEND';pbr['baseColorFactor']=[.91,.95,.89,.15];m['doubleSided']=True
    payload=json.dumps(d,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4);b+=b'\0'*((-len(b))%4)
    path.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(payload)+len(b))+struct.pack('<I4s',len(payload),b'JSON')+payload+struct.pack('<I4s',len(b),b'BIN\0')+b)

def main():
    OUT.mkdir(parents=True,exist_ok=True);SOURCE.mkdir(parents=True,exist_ok=True);(SOURCE/'.gdignore').touch()
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):bpy.data.collections.remove(c)
    bpy.context.preferences.filepaths.save_version=0;bpy.context.scene.unit_settings.system='METRIC'
    # Byte-identical copy keeps this standalone prop importable on the art branch,
    # where warming_cabinet_placeholder does not exist. Both options share it.
    atlas=ROOT/SW['source_atlas'];assert hashlib.sha256(atlas.read_bytes()).hexdigest()==SW['atlas_sha256']
    shutil.copyfile(atlas,OUT/'room_albedo_ao.png')
    def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
    raw=b''.join(b'\0'+b''.join(bytes.fromhex(list(EXTRA.values())[(x//128)+(y//128)*2]) for x in range(256)) for y in range(256))
    (OUT/'interior_food.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',256,256,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b''))
    image=bpy.data.images.load(str(OUT/'interior_food.png'))
    atlas_image=bpy.data.images.load(str(OUT/'room_albedo_ao.png'))
    for name in SW['swatches']:make_material(name,atlas_image)
    for name in EXTRA:make_material(name,image)
    make_material('glass',alpha=.15)
    build()
    source_objects=list(k.CURRENT.objects)
    for obj in source_objects:
        if obj.type!='MESH':continue
        uv=obj.data.uv_layers.active or obj.data.uv_layers.new(name='AtlasSwatch')
        color=obj['swatch']
        if color in SW['swatches']:u,v=SW['swatches'][color]['gltf_uv'];sample=(u,1-v)
        elif color in EXTRA:
            i=list(EXTRA).index(color);sample=((i%2+.5)/2,1-(i//2+.5)/2)
        else:sample=(.5,.5)
        for loop in uv.data:loop.uv=sample
    bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
    runtime={}
    for key,label in [('sage','Warming_SharedAtlas'),('amber','Warming_InteriorFood'),('glass','Warming_Glass_A')]:
        runtime[label]=k.MATS[key].copy();runtime[label].name=label
    export=[];records={}
    for group in ['cabinet']+[f'dish_{i}' for i in range(1,7)]+['highlights','glass']:
        bpy.ops.object.select_all(action='DESELECT');copies=[]
        for src in source_objects:
            if src.type!='MESH' or src['export_group']!=group:continue
            data=bpy.data.meshes.new_from_object(src.evaluated_get(deps),depsgraph=deps)
            obj=bpy.data.objects.new(src.name+' export',data);bpy.context.scene.collection.objects.link(obj)
            obj.matrix_world=src.matrix_world.copy();obj.select_set(True);copies.append(obj)
        bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();obj=bpy.context.object
        obj.name=group;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        mod=obj.modifiers.new('Fixed triangulation','TRIANGULATE');mod.quad_method='FIXED';mod.ngon_method='CLIP';bpy.ops.object.modifier_apply(modifier=mod.name)
        data=obj.data;old=list(data.materials);newkeys=[];facekeys=[]
        # Re-set constant UVs after bevel interpolation, then collapse swatch
        # authoring materials into shared runtime materials.
        for face in data.polygons:
            color=old[face.material_index].name
            if color in SW['swatches']:u,v=SW['swatches'][color]['gltf_uv'];sample=(u,1-v);key='Warming_SharedAtlas'
            elif color in EXTRA:i=list(EXTRA).index(color);sample=((i%2+.5)/2,1-(i//2+.5)/2);key='Warming_InteriorFood'
            else:sample=(.5,.5);key='Warming_Glass_A'
            for li in face.loop_indices:data.uv_layers.active.data[li].uv=sample
            if key not in newkeys:newkeys.append(key)
            facekeys.append(key)
        data.materials.clear()
        for key in newkeys:data.materials.append(runtime[key])
        for f,key in zip(data.polygons,facekeys):f.material_index=newkeys.index(key)
        data.calc_loop_triangles();records[group]={'triangles':len(data.loop_triangles),'surfaces':len(newkeys)};export.append(obj)
    sockets=[o for o in source_objects if o.type=='EMPTY']
    for option in ['a','b']:
        bpy.ops.object.select_all(action='DESELECT')
        included=[o for o in export if option=='a' or o.name!='glass']
        for o in included+sockets:o.select_set(True)
        triangles=sum(records[o.name]['triangles'] for o in included)
        print('WARMING',option,triangles,records,flush=True);assert triangles<=1500,triangles
        path=OUT/f'warming_cabinet_{option}.glb'
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_normals=True,export_materials='EXPORT',export_image_format='NONE',export_animations=False,export_cameras=False,export_lights=False)
        external_images(path)
    for o in export:bpy.data.objects.remove(o,do_unlink=True)
    # Portable source uses the output textures, authored objects retain names.
    atlas_image.filepath='//../../../../assets/props/warming_cabinet/room_albedo_ao.png'
    image.filepath='//../../../../assets/props/warming_cabinet/interior_food.png'
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'warming_cabinet.blend'))
    contract={'spec':'SGODOT-282 v1.1','units':'metres, Godot Y-up, +Z front','bounds':[[-.28,0,0],[.28,1.32,.5]],'pivot':'ground, width centre, back plane','collider':{'at':[0,.66,.25],'size':[.56,1.32,.50]},'sockets':{'top_center':[0,1.32,.25],'door_center':[0,.795,.498],'glow':[0,.795,.25]},'groups':records,'glass_alpha':.15,'dish_order':'upper left, upper right, middle left, middle right, bottom left, bottom right','placements':{'basic_room':{'position':[-2.850,.082,-1.69],'yaw_degrees':90},'standard_room_5':{'position':[-2.916,.082,-1.19],'yaw_degrees':90}},'atlas_sha256':SW['atlas_sha256'],'extra_palette':EXTRA,'variants':{}}
    for option in ['a','b']:
        items={n:v for n,v in records.items() if option=='a' or n!='glass'}
        contract['variants'][option]={'file':f'warming_cabinet_{option}.glb','triangles':sum(v['triangles'] for v in items.values()),'surfaces':sum(v['surfaces'] for v in items.values()),'meshes':len(items)}
    (OUT/'manifest.json').write_text(json.dumps(contract,indent=2)+'\n')
if __name__=='__main__':main()
