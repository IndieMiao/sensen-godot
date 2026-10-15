#!/usr/bin/env python3
"""SGODOT-213: three props only; named Blender source and shared room atlas.
Run Blender --background --factory-startup --python tools/art/build_kitchen_213.py.
Godot metres, Y up, +Z front. Existing room meshes/anchors are not regenerated.
"""
import hashlib,json,math,struct,sys,zlib
from pathlib import Path
import bpy,numpy as np
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_basic_room as k
from verify_chef_sign import load_glb,accessor
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'assets/rooms/basic_room';SRC=ROOT/'tools/art/source/kitchen_213'
SW=json.loads((SRC/'atlas-swatches.json').read_text());GROUP='body'
RANGE_AT=[-2.05,.082,-2.53];COOKBOOK_AT=[-2.96,2.32,-1.38]
SOCKETS={}

def tag(o):o['export_group']=GROUP;return o
def box(n,p,s,c='cream',r=.014):return tag(k.cube(n,p,s,c,r))
def lathe(n,p,profile,c,segments=20):return tag(k.lathe(n,p,profile,c,segments))
def tube(n,points,r,c,sides=10):return tag(k.tube(n,points,r,c,sides))
def sphere(n,p,s,c):return tag(k.ellipsoid(n,p,s,c,12,6))
def socket(n,p):
 o=bpy.data.objects.new(n,None);k.CURRENT['collection'].objects.link(o);o.empty_display_type='ARROWS';o.empty_display_size=.07;o.location=k.v(p);o.parent=k.CURRENT['root'];SOCKETS[n]=list(p)

def range_build():
 global GROUP
 k.begin('kitchen_range_3');GROUP='body'
 box('Continuous cream masonry plinth',(0,.045,0),(1.35,.09,.60),'cream',.025)
 # Separate softly rounded masonry bays; genuine arch cavities, not dark decals.
 for i,x in enumerate([-.45,0,.45],1):
  b=box(f'Stove {i} / rounded cream masonry',(x,.478,0),(.448,.776,.59),'cream',.023)
  cut=k.arch_solid(f'Stove {i} / arched recess cutter',.400,.115,.460,.195,.68,.13,'iron');cut.location.x=x
  k.boolean_cut(b,cut)
  # Shade the actual recess surfaces with the existing iron swatch; avoid
  # pale inside walls filling the silhouette at the default oblique camera.
  b.data.materials.append(k.material('iron'))
  for f in b.data.polygons:
   centre=sum((b.matrix_world @ b.data.vertices[i].co for i in f.vertices),Vector())/len(f.vertices)
   gx,gy,gz=centre.x,centre.z,-centre.y
   if abs(gx-x)<.205 and .112<gy<.66 and -.215<gz<.294:f.material_index=1
  # Enclosed back and bottom are visible through the arch.
  box(f'Stove {i} / dark firebox back',(x,.385,-.196),(.400,.54,.025),'iron',.005)
  box(f'Stove {i} / dark ash floor',(x,.114,.019),(.39,.012,.47),'iron',.004)
  top=box(f'Stove {i} / cream top slab',(x,.849,0),(.448,.07,.60),'cream',.018)
  cut=k.cylinder(f'Stove {i} / real burner well cutter',(x,.89,.035),.050,.20,'iron',vertices=24)
  k.boolean_cut(top,cut)
  # A recessed iron well and thin annular top at exactly local y=.898.
  profile=[(.828,.048),(.894,.048),(.898,.050),(.898,.119),(.888,.126),(.880,.126)]
  lathe(f'Stove {i} / annular iron pot support',(x,0,.035),profile,'iron',24)
  for j,dx in enumerate([-.09,.09]):
   o=tag(k.cylinder(f'Stove {i} / short seasoned log {j+1}',(x+dx,.18,.08),.045,.25,'wood',vertices=10));o.rotation_euler.x=math.pi/2
  socket(f'stove_{i}_top',(x,.898,.035))
  # The reused fire.glb has an asymmetric -0.0275 m visual centre.
  socket(f'fire_{i}',(x+.0275,.15,-.005))
  if i>1:
   GROUP=f'lid_{i}'
   lathe(f'Stove {i} / removable iron burner cap',(x,.898,.035),[(0,.118),(.012,.121),(.021,.112)],'iron',24)
   tube(f'Stove {i} / cap loop',[(x-.025,.919,.035),(x-.022,.947,.035),(x+.022,.947,.035),(x+.025,.919,.035)],.008,'iron',8)
   GROUP='body'
 # Small flue at the left rear, separate from the cooking positions/name labels.
 tube('Left rear / bent dark iron smoke pipe',[(-.555,.89,-.21),(-.555,1.38,-.21),(-.555,1.44,-.27),(-.555,1.44,-.432)],.049,'iron',12)
 lathe('Pipe / base collar',(-.555,.876,-.21),[(0,.065),(.027,.065),(.033,.054)],'iron',16)
 o=tag(k.cylinder('Pipe / rear wall flange',(-.555,1.44,-.435),.074,.016,'iron',vertices=16));o.rotation_euler.x=math.pi/2

def spices_build():
 global GROUP
 GROUP='spice_rack';k.begin('spice_rack')
 box('Rack / rounded honey ledge',(0,0,-.012),(.60,.045,.26),'wood',.012)
 box('Rack / back mounting strip',(0,.065,-.122),(.54,.13,.018),'wood',.009)
 for x in [-.225,.225]:
  tube('Rack / supporting corbel',[(x,-.135,-.12),(x,-.11,-.10),(x,-.023,.08)],.022,'wood',8)
 for i,(x,height,color) in enumerate([(-.215,.155,'pages'),(-.072,.183,'green'),(.072,.163,'red'),(.215,.145,'pages')],1):
  y=.0225;r=.055
  lathe(f'Jar {i} / '+{'pages':'salt','green':'herbs','red':'chilli'}[color],(x,y,.008),[(0,.045),(.012,r),(.105,r),(height-.018,.043),(height,.043)],color,16)
  lathe(f'Jar {i} / wooden lid',(x,y+height,.008),[(0,.046),(.025,.047),(.030,.039)],'wood',16)

def cookbook_build():
 global GROUP
 GROUP='cookbook_wall';k.begin('cookbook_wall')
 box('Book / cream page block',(.003,0,.046),(.339,.444,.074),'pages',.009)
 for z in [.004,.089]:box('Book / plain red cover',(0,0,z),(.35,.45,.010),'red',.012)
 box('Book / rounded red spine',(-.163,0,.047),(.025,.45,.093),'red',.009)
 # Quiet page-edge relief, no writing or symbols.
 for y in [-.12,-.04,.04,.12]:box('Book / page fore-edge',( .173,y,.046),(.0015,.0015,.065),'stone',0)
 for side in [-1,1]:tube('Book / leather hanging loop',[(side*.115,.225,.020),(side*.02,.335,.020),(0,.34,.020)],.009,'wood',8)
 sphere('Book / wooden wall peg',(0,.342,.017),(.043,.043,.034),'wood')

def patch_atlas():
 path=OUT/'room_albedo_ao.png';sha=hashlib.sha256(path.read_bytes()).hexdigest()
 assert sha in [SW['original_atlas_sha256'],SW.get('patched_atlas_sha256')],sha
 if sha==SW.get('patched_atlas_sha256') and not (SRC/'atlas-ao-delta.npz').exists():return
 image=bpy.data.images.load(str(path));w,h=image.size
 # PNG bytes are encoded from sRGB directly, avoiding colour-management round trips.
 import subprocess
 raw=subprocess.check_output(['git','show',SW['baseline']+':assets/rooms/basic_room/room_albedo_ao.png'],cwd=ROOT)
 from tempfile import NamedTemporaryFile
 with NamedTemporaryFile(suffix='.png') as f:
  f.write(raw);f.flush();im=bpy.data.images.load(f.name);pixels=np.array(im.pixels[:]).reshape(h,w,4)[::-1]
 # bpy PNG pixels are sRGB for images loaded without a scene transform.
 a=np.rint(pixels[:,:,:3]*255).astype(np.uint8)
 if (SRC/'atlas-ao-delta.npz').exists():
  factor=np.load(SRC/'atlas-ao-delta.npz')['factor'];f=a.astype(np.float64)/255
  linear=np.where(f<=.04045,f/12.92,((f+.055)/1.055)**2.4)*factor[:,:,None]
  srgb=np.where(linear<=.0031308,linear*12.92,1.055*np.maximum(linear,0)**(1/2.4)-.055)
  a=np.rint(np.clip(srgb,0,1)*255).astype(np.uint8)
 x,y,w0,h0=SW['added_patch']['rect'];a[y:y+h0,x:x+w0]=SW['added_patch']['rgb8']
 def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
 raw=b''.join(b'\0'+row.tobytes() for row in a)
 path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b''))
 SW['patched_atlas_sha256']=hashlib.sha256(path.read_bytes()).hexdigest();(SRC/'atlas-swatches.json').write_text(json.dumps(SW,indent=2)+'\n')
 bpy.data.images.remove(image)

def pack_glb(path):
 d,b=load_glb(path);b=bytearray(b)
 for m in d['meshes']:
  for p in m['primitives']:
   a=d['accessors'][p['indices']];v=d['bufferViews'][a['bufferView']];off=v.get('byteOffset',0)+a.get('byteOffset',0);fmt={5121:'B',5123:'H',5125:'I'}[a['componentType']]
   ids=struct.unpack_from('<'+fmt*a['count'],b,off);ts=sorted(tuple(ids[i:i+3]) for i in range(0,len(ids),3));struct.pack_into('<'+fmt*a['count'],b,off,*(x for t in ts for x in t))
 d['images']=[{'uri':'room_albedo_ao.png'}];d['samplers']=[{'magFilter':9729,'minFilter':9987,'wrapS':33071,'wrapT':33071}];d['textures']=[{'sampler':0,'source':0}]
 for m in d['materials']:m['pbrMetallicRoughness']['baseColorTexture']={'index':0}
 j=json.dumps(d,separators=(',',':')).encode();j+=b' '*((-len(j))%4);b+=b'\0'*((-len(b))%4)
 path.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(j)+len(b))+struct.pack('<I4s',len(j),b'JSON')+j+struct.pack('<I4s',len(b),b'BIN\0')+b)

def export_asset(name,texture):
 kit=k.KITS[name];objects=kit['objects'];runtime=[]
 for o in objects:
  uv=o.data.uv_layers.active or o.data.uv_layers.new(name='RoomAtlas');key=o.data.materials[0].name.split('_matte')[0];u,v=SW['swatches'][key]['gltf_uv']
  for loop in uv.data:loop.uv=(u,1-v)
 bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
 for group in sorted(set(o['export_group'] for o in objects)):
  bpy.ops.object.select_all(action='DESELECT');copies=[]
  for src in objects:
   if src['export_group']!=group:continue
   data=bpy.data.meshes.new_from_object(src.evaluated_get(deps),depsgraph=deps);o=bpy.data.objects.new(src.name+' export',data);bpy.context.scene.collection.objects.link(o);o.matrix_world=src.matrix_world.copy();o.select_set(True);copies.append(o)
  bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();o=bpy.context.object;o.name=group;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
  mod=o.modifiers.new('Fixed triangulation','TRIANGULATE');mod.quad_method='FIXED';mod.ngon_method='CLIP';bpy.ops.object.modifier_apply(modifier=mod.name)
  for f in o.data.polygons:
   key=o.data.materials[f.material_index].name.split('_matte')[0];u,v=SW['swatches'][key]['gltf_uv']
   for li in f.loop_indices:o.data.uv_layers.active.data[li].uv=(u,1-v)
  mat=bpy.data.materials.get('RoomKit_SharedAtlas')
  if mat is None:
   mat=bpy.data.materials.new('RoomKit_SharedAtlas');mat.use_nodes=True;sh=mat.node_tree.nodes.get('Principled BSDF');sh.inputs['Roughness'].default_value=.8;sh.inputs['Specular IOR Level'].default_value=.28;im=mat.node_tree.nodes.new('ShaderNodeTexImage');im.image=texture;mat.node_tree.links.new(im.outputs['Color'],sh.inputs['Base Color'])
  o.data.materials.clear();o.data.materials.append(mat)
  for f in o.data.polygons:f.material_index=0
  o.parent=kit['root'];runtime.append(o)
 bpy.ops.object.select_all(action='DESELECT');kit['root'].select_set(True)
 for o in runtime+[o for o in kit['collection'].objects if o.type=='EMPTY']:o.select_set(True)
 path=OUT/(name+'.glb');bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_image_format='NONE',export_animations=False,export_cameras=False,export_lights=False)
 pack_glb(path)
 for o in runtime:bpy.data.objects.remove(o,do_unlink=True)
 d,b=load_glb(path);return {'name':name,'vertices':sum(d['accessors'][p['attributes']['POSITION']]['count'] for m in d['meshes'] for p in m['primitives']),'triangles':sum(d['accessors'][p['indices']]['count']//3 for m in d['meshes'] for p in m['primitives']),'surfaces':sum(len(m['primitives']) for m in d['meshes']),'bytes':path.stat().st_size}

def layout_and_stats(stats):
 p=OUT/'layout.json';l=json.loads(p.read_text());rows=[]
 for r in l['assets']:
  if r['name']=='kettle':continue
  if r['name']=='hearth':r={'name':'kitchen_range_3','file':'kitchen_range_3.glb','position':RANGE_AT,'yaw_degrees':0,'colliders':[{'at':[0,.449,0],'size':[1.35,.898,.60]}]}
  if r['name']=='fire':r['position']=[round(a+b,6) for a,b in zip(RANGE_AT,SOCKETS['fire_1'])]
  # Idempotent: pin complete original positions instead of repeatedly adding.
  poses={'sink_cabinet':[-.33,.082,-2.62],'utensil_crock':[-.97,1.25,-2.7],'wall_shelf':[-.34,2.29,-2.87],'shelf_plant':[.31,2.38,-2.73]}
  if r['name'] in poses:r['position']=poses[r['name']]
  if r['name'] not in ['spice_rack','cookbook_wall']:rows.append(r)
 rows.extend([{'name':'spice_rack','file':'spice_rack.glb','position':[-2.83,1.72,-1.575],'yaw_degrees':90,'colliders':[]},{'name':'cookbook_wall','file':'cookbook_wall.glb','position':COOKBOOK_AT,'yaw_degrees':90,'colliders':[]}]);l['assets']=rows;l['fire_position']=[-2.5,.48,-2.34];p.write_text(json.dumps(l,indent=2)+'\n')
 p=OUT/'asset_stats.json';s=json.loads(p.read_text());s['assets']=[r for r in s['assets'] if r['name'] not in ['hearth','kettle',*stats]]+list(stats.values());by={r['name']:r for r in s['assets']};s['unique_triangles']=sum(r['triangles'] for r in s['assets']);s['scene_triangles']=s['unique_triangles']+sum(by[r['asset']]['triangles'] for r in l.get('instances',[]));s['static_draw_surfaces']=sum(r['surfaces'] for r in s['assets'])+sum(by[r['asset']]['surfaces'] for r in l.get('instances',[]));s['scope']='Placed Basic Room kit; archived unplaced hearth/kettle files excluded. Review-only warming cabinet, pots and avatar excluded.';p.write_text(json.dumps(s,indent=2)+'\n')

def main():
 SRC.mkdir(parents=True,exist_ok=True);(SRC/'.gdignore').touch();bpy.context.preferences.filepaths.save_version=0
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 for c in list(bpy.data.collections):bpy.data.collections.remove(c)
 bpy.context.scene.unit_settings.system='METRIC';patch_atlas()
 for name,sw in SW['swatches'].items():k.PALETTE[name]=''.join(f'{v:02x}' for v in sw['rgb8'])
 range_build();spices_build();cookbook_build()
 tex=bpy.data.images.load(str(OUT/'room_albedo_ao.png'));stats={n:export_asset(n,tex) for n in ['kitchen_range_3','spice_rack','cookbook_wall']}
 tex.filepath='//../../../../assets/rooms/basic_room/room_albedo_ao.png';bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'kitchen_213.blend'))
 layout_and_stats(stats)
 contract={'placement':{'position':RANGE_AT,'yaw_degrees':0},'stove_top_local_y':.898,'stove_top_world_y':.98,'burner_pitch':.45,'sockets_local':SOCKETS,'sockets_world':{k:[round(a+b,6) for a,b in zip(RANGE_AT,v)] for k,v in SOCKETS.items()},'assets':stats,'cap_semantics':'Top burner caps lid_2/lid_3; hide each when unlocked, never hide the front arch. Default both visible.','atlas':SW}
 (SRC/'contract.json').write_text(json.dumps(contract,indent=2)+'\n');print('KITCHEN_213',json.dumps(stats),flush=True)
if __name__=='__main__':main()
