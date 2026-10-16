#!/usr/bin/env python3
"""Blender: independent GLB/UV/hash checks and actual triangle intersections.
-- --layout <path> accepts a preview; runtime anchors are never written.
"""
import hashlib,json,sys,subprocess,itertools,argparse
from pathlib import Path
import bpy,numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from verify_warming_cabinet import geometry,matrix,bounds
from verify_chef_sign import load_glb,accessor
ROOT=Path(__file__).resolve().parents[2];KIT=ROOT/'assets/rooms/post_office';OUT=ROOT/'output/post-215';SRC=ROOT/'tools/art/source/post_215';BASE='4c287f6d27bf399ee1661c86a6fee5f9ef0fa056'
a=argparse.ArgumentParser();a.add_argument('--layout',default=str(KIT/'layout.json'));args=a.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
layout=json.loads(Path(args.layout).read_text());contract=json.loads((SRC/'contract.json').read_text());original=json.loads(subprocess.check_output(['git','show',BASE+':assets/rooms/post_office/layout.json'],cwd=ROOT));report={'checks':[],'assets':{},'pairs':[],'preexisting_pairs':[],'method':'Actual GLB triangle BVHs, imported transforms and exact atlas/old-asset preservation. Contacts are separated only at measured support planes; existing assembly contacts retained explicitly.'}
def check(ok,label):
 report['checks'].append({'check':label,'passed':bool(ok)})
 if not ok:print('FAIL',label,flush=True)
by={r['name']:r for r in layout['assets']};old={r['name']:r for r in original['assets']}
for name in ['room_shell','window_wall','back_wall','postal_blue_door','postal_door_frame','postal_door_glass','postal_counter','sorting_cabinet','sorted_letters','wall_clock','red_post_box','parcel_shelves','parcel_shelf_stock']:
 check(by[name]==old[name],name+' exact preserved layout')
 p=KIT/old[name]['file'];check(p.read_bytes()==subprocess.check_output(['git','show',BASE+':'+str(p.relative_to(ROOT))],cwd=ROOT),name+' byte-identical GLB')
check((KIT/'packing_table.glb').read_bytes()==subprocess.check_output(['git','show',BASE+':assets/rooms/post_office/packing_table.glb'],cwd=ROOT),'packing table original mesh unchanged')
check(all(n not in by for n in ['counter_computer','magazine_rack','front_floor_runner']),'removed computer/rack/runner from scene')
check(by['fare_board']['position']==[-3.208,1.65,-1.65] and by['fare_board']['yaw_degrees']==90,'fare board exact approved runtime position')
check((KIT/'fare_board.glb').read_bytes()==subprocess.check_output(['git','show',BASE+':assets/rooms/post_office/fare_board.glb'],cwd=ROOT),'fare board byte-identical')
check(hashlib.sha256((KIT/'room_albedo_ao.png').read_bytes()).hexdigest()==contract['atlas']['atlas_sha256'],'atlas byte-identical / zero changed regions')
tex=bpy.data.images.load(str(KIT/'room_albedo_ao.png'));pixels=np.array(tex.pixels[:]).reshape(2048,2048,4)[::-1]
for name,r in contract['atlas']['swatches'].items():
 x,y=r['pixel_xy_top_left'];patch=pixels[y-3:y+4,x-3:x+4];check(patch[:,:,:3].min()>.01 and patch[:,:,3].min()>.99,'swatch '+name+' nonblack / nonblank padded patch')
for name,meta in contract['assets'].items():
 p=KIT/(name+'.glb');d,b,v,t,g=geometry(p);lo,hi=np.array(bounds(v));check(len(t)==meta['triangles'],name+' triangle count');check(sum(len(m['primitives']) for m in d['meshes'])==1,name+' one surface');check('gltf/texture_map_mode=1' in Path(str(p)+'.import').read_text(),name+' texture_map_mode=1')
 bad=deg=0
 for m in d['meshes']:
  for pr in m['primitives']:
   xyz=np.array(accessor(d,b,pr['attributes']['POSITION']));norm=np.array(accessor(d,b,pr['attributes']['NORMAL']));uv=np.array(accessor(d,b,pr['attributes']['TEXCOORD_0']));ix=np.array(accessor(d,b,pr['indices'])).reshape(-1,3);cross=np.cross(xyz[ix[:,1]]-xyz[ix[:,0]],xyz[ix[:,2]]-xyz[ix[:,0]]);deg+=int((np.linalg.norm(cross,axis=1)<1e-10).sum());bad+=int((np.sum(cross*norm[ix].sum(1),axis=1)<-1e-9).sum())
   check(np.all((uv>=0)&(uv<=1)),name+' UV inside atlas')
   if name not in ['brown_parcel_reused','blue_parcel_reused','packing_dressing_215','mail_sack_reused']:
    allowed=np.array([s['gltf_uv'] for s in contract['atlas']['swatches'].values()]);check(all(np.linalg.norm(allowed-q,axis=1).min()<1e-6 for q in uv),name+' only approved swatch UVs')
 check(deg==0,name+' no degenerate triangles');check(bad==0,name+' normals agree with winding')
 report['assets'][name]={'bounds':[lo.tolist(),hi.tolist()],'size_xyz':(hi-lo).tolist(),'triangles':len(t),'surfaces':1,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
rows={}
def entry(name,file,row):
 d,b,v,t,g=geometry(file,matrix(row['position'],row.get('yaw_degrees',0),row.get('scale',[1,1,1]),row.get('rotation_degrees')))
 rows[name]={'v':v,'t':t,'bounds':np.array(bounds(v)),'tree':BVHTree.FromPolygons(v,t,all_triangles=True),'row':row}
for row in layout['assets']+layout['instances']:entry(row['name'],KIT/by[row.get('asset',row['name'])]['file'],row)
for row in layout['shared_plants']:entry(row['name'],ROOT/'assets/rooms/_shared/plants'/row['file'],row)
# Target all changed or introduced modules. Original kit assembly issues are not
# silently called newly passing; checks record them separately below.
targets=set(by)-set(old)|{r['name'] for r in layout['instances']}|{'packing_dressing','door_floor_greenery'}
if layout['revision_215']['desk_option']=='left':targets|={'packing_table','packing_stool'}
for a,b in itertools.combinations(rows,2):
 if not (a in targets or b in targets):continue
 aa=rows[a];bb=rows[b];sep=np.maximum(aa['bounds'][0]-bb['bounds'][1],bb['bounds'][0]-aa['bounds'][1]);raw=aa['tree'].overlap(bb['tree']) if (sep<=0).all() else [];hits=[];contacts=[]
 for ia,ib in raw:
  va=np.array([aa['v'][j] for j in aa['t'][ia]]);vb=np.array([bb['v'][j] for j in bb['t'][ib]])
  floor=(a=='room_shell' and va[:,1].max()<=.083 and vb[:,1].min()>=.07999) or (b=='room_shell' and vb[:,1].max()<=.083 and va[:,1].min()>=.07999)
  old_assembly=set([a,b])=={'packing_table','packing_dressing'}
  desk_contact=set([a,b])=={'packing_table','stamp_desk_set'} and min(va[:,1].max(),vb[:,1].max())<=1.097002 and max(va[:,1].min(),vb[:,1].min())>=1.096998
  (contacts if floor or old_assembly or desk_contact else hits).append([ia,ib])
 check(not hits,a+' clear of '+b)
 report['pairs'].append({'a':a,'b':b,'axis_separation_m':sep.tolist(),'intersections':len(hits),'support_or_retained_assembly_pairs':len(contacts)})
report['world_bounds']={n:r['bounds'].tolist() for n,r in rows.items()}
# Positive control: intentionally put the new pot through the preserved table.
q=rows['stamp_desk_set'];shift=[v+Vector((0,-.15,0)) for v in q['v']];bad=BVHTree.FromPolygons(shift,q['t'],all_triangles=True).overlap(rows['packing_table']['tree']);check(bool(bad),'positive control detects tabletop penetration')
report['positive_control_hits']=len(bad);report['atlas_changed_regions']=[];report['failures']=[c for c in report['checks'] if not c['passed']];(OUT/('glb-validation-'+layout['revision_215']['desk_option']+'.json')).write_text(json.dumps(report,indent=2)+'\n');print('POST_215_BINARY_QA',len(report['checks']),len(report['failures']),flush=True)
if report['failures']:raise RuntimeError('Validation failed')
