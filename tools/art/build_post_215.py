#!/usr/bin/env python3
"""SGODOT-215 additions; Blender background. Never rebakes the locked atlas.
Run build_post_215.py, then arrange_post_215.py and prepare_post_215.py.
Editable source collections use metres, Y-up/+Z forward via (x,-z,y).
"""
import hashlib,json,math,re,sys,struct
from pathlib import Path
import bpy
from mathutils import Matrix
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_decor_assets as k
ROOT=k.ROOT;OUT=ROOT/'assets/rooms/post_office';SRC=ROOT/'tools/art/source/post_215'
SW=json.loads((SRC/'atlas-swatches.json').read_text());STATS={}

def tube(name,points,r,color):
 for i,(a,b) in enumerate(zip(points,points[1:])):k.rod(name+' %02d'%i,a,b,r,color,8)

def arc(name,at,rad,r,color,plane='XY',start=0,end=math.tau,n=16):
 x,y,z=at;vs=[];faces=[];sides=8
 for i in range(n+1):
  a=start+(end-start)*i/n
  for j in range(sides):
   b=j*math.tau/sides;rr=rad+r*math.cos(b)
   vs.append((x+rr*math.cos(a),y+rr*math.sin(a),z+r*math.sin(b)) if plane=='XY' else (x+rr*math.cos(a),y+r*math.sin(b),z+rr*math.sin(a)))
 for i in range(n):
  for j in range(sides):faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
 if end-start<math.tau-1e-5:faces.extend([tuple(reversed(range(sides))),tuple(range(n*sides,(n+1)*sides))])
 return k.mesh(name,vs,faces,color,True)

def ring(name,r0,r1,y,color,n=64):
 vs=[(r*math.sin(i*math.tau/n),y,r*math.cos(i*math.tau/n)) for r in [r0,r1] for i in range(n)]
 return k.mesh(name,vs,[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],color)

def rug():
 k.begin('compass_rug',[1,1],2500)
 k.cylinder('Rug / rounded beige hem',(0,.006,0),.95,.012,'beige',segments=96)
 ring('Rug / broad blue grey border',.857,.907,.0125,'bluegray',96)
 ring('Rug / fine inner compass ring',.765,.778,.0126,'gold',96)
 for i in range(8):
  a=i*math.pi/4;length=.64 if i%2==0 else .46
  def p(r,b):return(r*math.sin(b),.0128,r*math.cos(b))
  a0=p(.25,a-math.pi/8);a1=p(.25,a+math.pi/8);tip=p(length,a)
  k.mesh('Compass / blue grey point %d'%i,[(0,.0128,0),a0,tip],[(0,1,2)],'bluegray')
  k.mesh('Compass / honey shadow point %d'%i,[(0,.0128,0),tip,a1],[(0,1,2)],'gold')
 for i in range(4):
  a=i*math.pi/2
  k.mesh('Compass / cardinal arrow %d'%i,[(.82*math.sin(a),.0128,.82*math.cos(a)),(.73*math.sin(a-.055),.0128,.73*math.cos(a-.055)),(.73*math.sin(a+.055),.0128,.73*math.cos(a+.055))],[(0,1,2)],'bluegray')

 # Requested 2.20 m actual diameter; preserve the 12.8 mm sewn height.
 for obj in k.CURRENT.objects:
  if obj.type=='MESH':
   obj.scale.x*=2.2/1.9;obj.scale.y*=2.2/1.9
  if obj.type=='MESH' and 'hem' not in obj.name:
   for f in obj.data.polygons:
    if f.normal.z<0:f.flip()
   obj.data.update()


def desk():
 k.begin('stamp_desk_set',[1,1],6000)
 k.box('Desk / clean sage mat',(.21,-.013,.04),(2.38,.024,1.03),'green',.009)
 # All pieces sit on a common support plane. Local X runs along desk width.
 k.lathe('Coffee / silver white tapered body',[(.083,0),(.095,.014),(.080,.23),(.061,.27)],'silver',24,(-.44,0,-.22))
 k.lathe('Coffee / dark lid',[(.067,.268),(.077,.278),(.069,.293),(.020,.305)],'dark',24,(-.44,0,-.22))
 k.ellipsoid('Coffee / lid knob',(-.44,.319,-.22),(.055,.035,.055),'dark',12,6)
 tube('Coffee / curved handle',[(-.515,.245,-.22),(-.58,.255,-.22),(-.60,.21,-.22),(-.60,.095,-.22),(-.535,.07,-.22)],.014,'dark')
 k.rod('Coffee / tapered silver spout',(-.38,.19,-.22),(-.31,.24,-.22),.026,'silver',12,.016)
 k.rod('Coffee / dark spout opening',(-.31,.24,-.22),(-.308,.242,-.22),.012,'dark',12)
 k.lathe('Cup / white hollow ceramic',[(.047,0),(.054,.012),(.057,.105),(.050,.111),(.046,.03)],'white',24,(-.20,0,-.20))
 arc('Cup / white handle',(-.14,.057,-.20),.035,.010,'white',start=-math.pi*.6,end=math.pi*.6,n=12)
 # Book's shallow bent open pages, blank; no writing or passport symbols.
 k.box('Passport / navy cover',(.05,.008,.13),(.40,.016,.29),'board',.006)
 for side in [-1,1]:
  xs=[.05,.05+side*.18];vs=[(x,y,z) for x,y in [(xs[0],.035),(xs[1],.06)] for z in [-.005,.265]]
  k.mesh('Passport / blank open page '+str(side),vs+[(x,y-.018,z) for x,y,z in vs],[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(1,5,7,3),(0,2,6,4)],'white')
 k.box('Ink pad / dark tray',(.37,.018,.12),(.20,.036,.15),'board',.008)
 k.box('Ink pad / dark ink cushion',(.37,.040,.12),(.17,.012,.12),'dark',.008)
 k.cylinder('Stamp / brass base',(.40,.025,-.10),.059,.05,'gold',segments=16)
 k.lathe('Stamp / warm wood handle',[(.042,.05),(.025,.08),(.022,.145),(.040,.175),(.037,.195)],'wood',16,(.40,0,-.10))
 k.lathe('Plant / red clay pot',[(.062,0),(.079,.14),(.086,.15),(.086,.17),(.072,.17),(.064,.05)],'red',20,(.69,0,-.15))
 k.cylinder('Plant / soil',(.69,.15,-.15),.068,.01,'wood',segments=16)
 for i in range(9):
  a=i*math.tau/9
  o=k.ellipsoid('Plant / rounded leaf %d'%i,(.69+.065*math.sin(a),.21+.035*(i%3),-.15+.065*math.cos(a)),(.075,.035,.16),'green' if i%2 else 'green_light',10,5);o.rotation_euler=(.3,0,a)

def lantern():
 k.begin('post_wall_lantern',[1,1],2500)
 k.box('Lantern / backplate',(0,.12,.02),(.13,.28,.04),'wood',.015)
 k.beam('Lantern / support arm',(0,.22,.04),(0,.22,.26),.045,'wood')
 arc('Lantern / hanging ring',(0,.16,.26),.046,.009,'gold')
 k.lathe('Lantern / cap',[(.035,.105),(.10,.07),(.11,.045),(.095,.03)],'dark',16,(0,0,.26))
 k.lathe('Lantern / base',[(.08,-.24),(.11,-.22),(.11,-.19),(.075,-.17)],'dark',16,(0,0,.26))
 k.lathe('Lantern / warm opaque diffuser',[(.065,-.17),(.082,-.14),(.075,.005),(.055,.035)],'amber',16,(0,0,.26))
 for x in [-.079,.079]:k.beam('Lantern / brass guard',(x,-.19,.26),(x,.04,.26),.014,'gold',radius=.004)
 k.beam('Lantern / rear guard',(0,-.19,.185),(0,.04,.185),.014,'gold',radius=.004)

def table_lamp():
 k.begin('post_table_lamp',[1,1],2000)
 k.lathe('Desk lamp / dark foot',[(.13,0),(.14,.02),(.10,.06),(.055,.10)],'wood',24)
 k.cylinder('Desk lamp / brass stem',(0,.18,0),.028,.22,'gold',segments=16)
 k.lathe('Desk lamp / warm shade',[(.18,.255),(.18,.29),(.085,.44),(.065,.445)],'amber',24)
 k.lathe('Desk lamp / brass shade edge',[(.184,.25),(.184,.27),(.175,.28)],'gold',24)
 k.ellipsoid('Desk lamp / finial',(0,.468,0),(.055,.05,.055),'gold',12,6)

def export_collection(name,col,reused=False):
 bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();bpy.ops.object.select_all(action='DESELECT');copies=[]
 for src in col.objects:
  if src.type!='MESH':continue
  data=bpy.data.meshes.new_from_object(src.evaluated_get(deps),depsgraph=deps)
  o=bpy.data.objects.new(src.name+' export',data);bpy.context.scene.collection.objects.link(o);o.matrix_world=src.matrix_world.copy();o.select_set(True);copies.append(o)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();o=bpy.context.object;o.name=name
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
 mod=o.modifiers.new('Deterministic triangulation','TRIANGULATE');mod.quad_method='FIXED';mod.ngon_method='CLIP';bpy.ops.object.modifier_apply(modifier=mod.name)
 data=o.data
 if not reused:
  while len(data.uv_layers)>0:data.uv_layers.remove(data.uv_layers[0])
  uv=data.uv_layers.new(name='RoomAtlas')
  for face in data.polygons:
   u,v=SW['swatches'][data.materials[face.material_index].name]['gltf_uv']
   for li in face.loop_indices:uv.data[li].uv=(u,1-v)
 runtime=k.MATS['beige'].copy();runtime.name='RoomKit_SharedAtlas';data.materials.clear();data.materials.append(runtime)
 for face in data.polygons:face.material_index=0
 data.calc_loop_triangles();vs=[(v.co.x,v.co.z,-v.co.y) for v in data.vertices]
 lo=[min(v[i] for v in vs) for i in range(3)];hi=[max(v[i] for v in vs) for i in range(3)]
 bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_image_format='NONE',export_animations=False,export_cameras=False,export_lights=False)
 k.canonical_triangle_order(OUT/(name+'.glb'))
 STATS[name]={'name':name,'vertices':len(vs),'triangles':len(data.loop_triangles),'surfaces':1,'bounds':[lo,hi],'bytes':(OUT/(name+'.glb')).stat().st_size}
 bpy.data.objects.remove(o,do_unlink=True)
 rel='res://assets/rooms/post_office/'+name+'.glb';h=hashlib.md5(rel.encode()).hexdigest();t=(OUT/'fare_board.glb.import').read_text();t=re.sub(r'uid="[^"]+"\n','',t);t=re.sub(r'fare_board.glb-[a-f0-9]+',name+'.glb-'+h,t);t=t.replace('post_office/fare_board.glb','post_office/'+name+'.glb');(OUT/(name+'.glb.import')).write_text(t)

def reuse_parcel(name, xmin=0, xmax=0, pivot=(0,0,0), dressing=False, sack=False, ylo=.99, yhi=1.60, auto_pivot=False):
 # Extract unchanged first-row parcel triangles from the accepted packed stock.
 # Positions only translated to a useful bottom pivot; exact UVs/normals retained.
 import numpy as np
 from verify_chef_sign import load_glb,accessor
 d,b=load_glb(OUT/('packing_dressing.glb' if dressing else 'mail_sacks.glb' if sack else 'parcel_shelf_stock.glb'));col=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(col)
 for mesh in d['meshes']:
  for pr in mesh['primitives']:
   vs=np.array(accessor(d,b,pr['attributes']['POSITION']));uv=np.array(accessor(d,b,pr['attributes']['TEXCOORD_0']));ns=np.array(accessor(d,b,pr['attributes']['NORMAL']));ix=np.array(accessor(d,b,pr['indices'])).reshape(-1,3)
   keep=np.all((vs[ix,0]>xmin)&(vs[ix,0]<xmax)&(vs[ix,1]<yhi)&(vs[ix,1]>ylo),axis=1);
   if dressing:
    # Keep complete connected objects, including all parts of tilted envelopes.
    # Weld by position for classification only; exported attributes stay exact.
    ids={};parent=list(range(len(vs)))
    def find(a):
     while parent[a]!=a:parent[a]=parent[parent[a]];a=parent[a]
     return a
    def union(a,b):parent[find(a)]=find(b)
    for i,q in enumerate(vs):
     key=tuple(np.round(q,6))
     if key in ids:union(i,ids[key])
     else:ids[key]=i
    for tri in ix:union(int(tri[0]),int(tri[1]));union(int(tri[0]),int(tri[2]))
    groups={}
    for i in range(len(vs)):groups.setdefault(find(i),[]).append(i)
    chosen=set()
    for key,ii in groups.items():
     pts=vs[ii];center=(pts.min(0)+pts.max(0))/2
     if pts[:,1].max()<1.10 or (.40<center[0]<.92 and 1.80<center[2]<2.20 and center[1]>1.13):chosen.add(key)
    keep=np.array([find(int(tri[0])) in chosen for tri in ix])
   faces=ix[keep]
   used=np.unique(faces)
   if auto_pivot:
    lo=vs[used].min(0);hi=vs[used].max(0);pivot=[(lo[0]+hi[0])/2,lo[1],(lo[2]+hi[2])/2]
   remap={int(q):i for i,q in enumerate(used)}
   data=bpy.data.meshes.new(name);data.from_pydata([k.v(q-np.array(pivot)) for q in vs[used]],[],[[remap[int(q)] for q in tri] for tri in faces]);data.update()
   layer=data.uv_layers.new(name='RoomAtlas')
   for loop in data.loops:layer.data[loop.index].uv=(uv[used[loop.vertex_index],0],1-uv[used[loop.vertex_index],1])
   corners=[k.v(ns[used[loop.vertex_index]]) for loop in data.loops]
   for face in data.polygons:
    if face.normal.dot(sum((corners[i] for i in face.loop_indices),k.v((0,0,0))))<0:
     for i in face.loop_indices:corners[i]=face.normal.copy()
   data.normals_split_custom_set(corners)
   obj=bpy.data.objects.new(name+' / accepted packed parcel',data);col.objects.link(obj);data.materials.append(k.MATS['beige'])
   obj['reuse_source']='packing_dressing.glb' if dressing else 'mail_sacks.glb' if sack else 'parcel_shelf_stock.glb';obj['source_triangles']=len(faces)
 export_collection(name,col,True)


def main():
 assert hashlib.sha256((OUT/'room_albedo_ao.png').read_bytes()).hexdigest()==SW['atlas_sha256']
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 for c in list(bpy.data.collections):bpy.data.collections.remove(c)
 bpy.context.preferences.filepaths.save_version=0;bpy.context.scene.unit_settings.system='METRIC'
 tex=bpy.data.images.load(str(OUT/'room_albedo_ao.png'));tex.filepath='//../../../../assets/rooms/post_office/room_albedo_ao.png'
 # Keep blue board and other selected exact swatches as aliases.
 SW['swatches']['board']=json.loads((ROOT/'tools/art/source/fare_board_275/atlas-swatches.json').read_text())['swatches']['board']
 for name in SW['swatches']:
  m=bpy.data.materials.new(name);m.use_nodes=True;bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.8;bs.inputs['Specular IOR Level'].default_value=.28
  im=m.node_tree.nodes.new('ShaderNodeTexImage');im.image=tex;m.node_tree.links.new(im.outputs['Color'],bs.inputs['Base Color']);k.MATS[name]=m
 rug();desk();lantern();table_lamp()
 for name,col in k.ASSETS.items():
  for o in col.objects:
   if o.type!='MESH':continue
   o['atlas_swatch']=o.data.materials[0].name;u,v=SW['swatches'][o['atlas_swatch']]['gltf_uv'];uv=o.data.uv_layers.active or o.data.uv_layers.new(name='RoomAtlas')
   for loop in uv.data:loop.uv=(u,1-v)
  export_collection(name,col)
 reuse_parcel('brown_parcel_reused',1.48,2.075,(1.78,1.054,-2.51));reuse_parcel('blue_parcel_reused',-.90,0,ylo=2.30,yhi=3.0,auto_pivot=True)
 reuse_parcel('mail_sack_reused',-1,0,sack=True,ylo=-.1,yhi=2,auto_pivot=True)
 reuse_parcel('packing_dressing_215',dressing=True)
 (SRC/'.gdignore').touch();(SRC/'contract.json').write_text(json.dumps({'assets':STATS,'atlas':SW,'base_commit':'4c287f6d27bf399ee1661c86a6fee5f9ef0fa056'},indent=2)+'\n')
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'post_215.blend'))
 print('POST_215_NEW',STATS,flush=True)
if __name__=='__main__':main()
