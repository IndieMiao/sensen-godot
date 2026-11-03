"""Independent GLB, transparency, support, packing and gallery-dimension checks."""
from pathlib import Path
import configparser
import hashlib
import json
import sys
import numpy as np

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4]
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
KIT=ROOT/'assets/rooms/poi_culture_hall/props';OUT=ROOT/'output/culture-props-323'
manifest=json.loads((KIT/'prop_manifest.json').read_text());specs={a['name']:a for a in manifest['assets']}
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','checks':[],'assets':{},'placements':[]}
def check(ok,label):
    report['checks'].append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)
def linear(color):
    rgb=np.array(list(bytes.fromhex(color)))/255
    return np.where(rgb<=.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)
check(len(specs)==8 and sum(s['quantity'] for s in specs.values())==9,'8 grouped GLBs / 9 instances')
uids=[];unique=0;placed=0;surfaces=0
for name,spec in specs.items():
    path=KIT/spec['file'];doc,data=load_glb(path);primitives=doc['meshes'][0]['primitives'];all_points=[];triangles=0;glass=[]
    check(len(doc['meshes'])==1 and doc['meshes'][0]['name']==name+'_mobile',name+': one named mobile mesh')
    check(len(primitives)==spec['surfaces'],name+': expected surface count')
    check(not doc.get('images') and not doc.get('textures'),name+': no textures')
    for primitive in primitives:
        a=primitive['attributes'];points=np.array(accessor(doc,data,a['POSITION']));idx=np.array(accessor(doc,data,primitive['indices'])).reshape(-1,3)
        colors=np.array(accessor(doc,data,a['COLOR_0']));normals=np.array(accessor(doc,data,a['NORMAL']))
        all_points.append(points);triangles+=len(idx)
        check(np.isfinite(points).all() and np.allclose(np.linalg.norm(normals,axis=1),1,atol=1e-4),name+': finite vertices / unit normals')
        area=np.linalg.norm(np.cross(points[idx[:,1]]-points[idx[:,0]],points[idx[:,2]]-points[idx[:,0]]),axis=1)
        check(np.all(area>1e-12),name+': no degenerate triangles')
        check(np.all(colors>=0) and np.all(colors<=1) and np.allclose(colors[:,3],1),name+': linear vertex color data')
        mat=doc['materials'][primitive['material']];pbr=mat['pbrMetallicRoughness']
        if mat['name']=='CultureGlass':
            glass.append(primitive['material'])
            check(mat.get('alphaMode')=='BLEND' and mat.get('doubleSided') and abs(pbr['baseColorFactor'][3]-.16)<.001,'Cabinet separate alpha-blended glass surface')
            check(abs(points[:,1].min()-1.0)<1e-5 and points[:,1].max()>=1.49,'Glass hood starts at display bed and reaches 1.5m')
        else:
            check(mat.get('alphaMode','OPAQUE')=='OPAQUE' and pbr.get('roughnessFactor',1)>=.85 and pbr.get('metallicFactor',1)==0,name+': opaque matte body')
            if name in ['display_cabinet','exhibit_plinth']:
                bed=np.max(abs(colors[:,:3]-linear('F4E8CE')),axis=1)<.00004
                check(bed.any() and abs(points[bed,1].max()-spec['display_height_m'])<1e-5,name+': actual display support height')
                green=np.max(abs(colors[:,:3]-linear('465823')),axis=1)<.00004
                rim_triangles=idx[np.all(green[idx],axis=1)&np.all(abs(points[idx,1]-spec['display_height_m'])<1e-5,axis=1)]
                centers=points[rim_triangles].mean(axis=1)
                aperture=[.445,.87] if name=='display_cabinet' else [.31,.31]
                check(not np.any((abs(centers[:,0])<aperture[0]-.001)&(abs(centers[:,2])<aperture[1]-.001)),name+': no coplanar green top faces inside ivory display bed')
        if name=='floor_mosaic':check(np.all(normals[points[:,1]>.007,1]>.999),'Mosaic stone faces point upward')
        if name=='artwork_set':
            for component in spec['components']:
                x,y,_=component['position']
                art=(abs(points[:,0]-x)<.3131)&(abs(points[:,1]-y)<.239)&(points[:,2]>.037)&(points[:,2]<.043)
                check(art.any() and np.all(normals[art,2]>.999),component['name']+': artwork front faces outward')
    points=np.concatenate(all_points);lo=points.min(axis=0);hi=points.max(axis=0)
    check(triangles==spec['triangles'],name+': measured group triangles match manifest')
    if 'components' in spec:
        check(sum(c['triangles'] for c in spec['components'])==triangles and all(c['triangles']<=600 for c in spec['components']),name+': baked grouping preserves constituent budgets and triangle sum')
    else:check(triangles<=600,name+': single authored component <=600 triangles')
    check(len(glass)==(1 if name=='display_cabinet' else 0),name+': only cabinet has glass')
    check(np.allclose([lo,hi],spec['bounds'],atol=1e-5),name+': real bounds match manifest')
    if spec['origin']=='display_surface_center':check(abs(lo[1])<1e-5 and np.allclose(spec['display_assignment']['position'],[0,1.,0]),name+': origin at cabinet display-surface center')
    elif spec['origin']=='bottom_center':check(abs(lo[1])<1e-5 and abs(lo[0]+hi[0])<1e-5 and abs(lo[2]+hi[2])<1e-5,name+': bottom-center pivot')
    else:check(abs(lo[2])<1e-5 and np.max(abs(lo[:2]+hi[:2]))<1e-5,name+': back-center pivot')
    check(not doc.get('animations') and not doc.get('skins'),name+': static prop')
    for node in doc['nodes']:
        if 'mesh' in node:
            check(node.get('translation',[0,0,0])==[0,0,0] and node.get('rotation',[0,0,0,1])==[0,0,0,1]
                and node.get('scale',[1,1,1])==[1,1,1],name+': baked unit transform')
    check(all(not n.get('name','').startswith(('seat_','npc_','use_')) for n in doc['nodes']),name+': no seat or service anchors')
    if name=='name_sign':
        anchor=next(n for n in doc['nodes'] if n.get('name')=='sign_door');size=anchor['extras']['size']
        check(size[0]>=1.20 and size[1]>=.26 and np.allclose(size,[1.24,.28]),'Blank sign usable area 1.24 x .28m')
        check(np.allclose(anchor['translation'],spec['anchors'][0]['position'],atol=1e-5) and anchor['translation'][2]>hi[2],'Sign anchor at blank front center')
    cfg=configparser.ConfigParser(interpolation=None);cfg.read(str(path)+'.import');uid=json.loads(cfg['remap'].get('uid','""'));uids.append(uid)
    check(uid.startswith('uid://') and cfg['params']['gltf/texture_map_mode']=='1',name+': UID / texture_map_mode=1')
    check(json.loads(cfg['params']['import_script/path'])=='res://assets/rooms/poi_culture_hall/props/material_import.gd',name+': local material import hook')
    check((ROOT/spec['provenance']).exists(),name+': source provenance')
    report['assets'][name]={'triangles':triangles,'surfaces':len(primitives),'bounds':[lo.tolist(),hi.tolist()],
        'dimensions_m':(hi-lo).tolist(),'uid':uid,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    unique+=triangles;placed+=triangles*spec['quantity'];surfaces+=len(primitives)*spec['quantity']
check(len(set(uids))==8,'All 8 import UIDs are distinct')
check({p.name for p in KIT.glob('*.glb')}=={s['file'] for s in specs.values()},'Only the eight current grouped assets are delivered')
check(np.allclose(report['assets']['display_cabinet']['dimensions_m'],[.95,1.5,1.8],atol=1e-5),'Cabinet final envelope .95 x 1.50 x 1.80m')
check(np.allclose(report['assets']['exhibit_plinth']['dimensions_m'],[.70,1.10,.70],atol=1e-5),'Plinth final envelope .70 x 1.10 x .70m')
mosaic=report['assets']['floor_mosaic']['dimensions_m']
check(abs(mosaic[0]-1.94)<1e-5 and abs(mosaic[2]-1.94)<1e-5 and mosaic[1]<=.01,'Floor mosaic diameter 1.94m and height <=.01m')
frames=specs['artwork_set']['components']
check(len(frames)==6 and len({json.dumps(s['art_palette_srgb'],sort_keys=True) for s in frames})==6,'Six different abstract palettes')
for s in frames:check(np.allclose((np.array(s['bounds'][1])-np.array(s['bounds'][0]))[:2],[.70,.55],atol=1e-5),s['name']+': .70 x .55m')
gallery=np.array([np.array(s['bounds'])+np.array(s['position']) for s in frames])
width=gallery[:,1,0].max()-gallery[:,0,0].min();height=gallery[:,1,1].max()-gallery[:,0,1].min()
check(width<=2.50 and abs(width-2.40)<1e-5 and abs(height-1.25)<1e-5,'Two-by-three gallery fits 2.5m wall span')
groups={}
for s in specs.values():
    if 'display_assignment' not in s:continue
    slot=s['display_assignment'];bounds=np.array(s['bounds'])+np.array(slot['position'])
    for c in s.get('components',[{'name':s['name'],'bounds':s['bounds'],'position':[0,0,0]}]):
        cbounds=np.array(c['bounds'])+np.array(c['position'])+np.array(slot['position'])
        groups.setdefault(slot['container'],[]).append((c['name'],cbounds))
        check(abs(cbounds[0,1]-specs[slot['container_asset']]['display_height_m'])<1e-5,c['name']+': grouped constituent touches display surface')
    support=specs[slot['container_asset']]['display_height_m']
    check(abs(bounds[0,1]-support)<1e-5,s['name']+': sits on actual parent support height')
    if slot['container_asset']=='display_cabinet':
        inside=np.array(specs['display_cabinet']['interior_bounds'])
        check(np.all(bounds[0]>=inside[0]-1e-5) and np.all(bounds[1]<=inside[1]),s['name']+': wholly inside glass hood')
    else:check(np.all(abs(bounds[:,[0,2]])<=.31),s['name']+': fits plinth display surface')
    report['placements'].append({'asset':s['name'],**slot,'parent_local_bounds':bounds.tolist()})
check({k:len(v) for k,v in groups.items()}=={'glass_case_1':3,'glass_case_2':3,'display_plinth':1},'Exactly three exhibits per case plus one plinth ammonite')
for name,items in groups.items():
    for i,(a,ab) in enumerate(items):
        for b,bb in items[i+1:]:check(np.any(ab[1]<bb[0]-.005) or np.any(bb[1]<ab[0]-.005),a+' / '+b+': no exhibit overlap')
check(unique==manifest['unique_triangles'] and placed==manifest['placed_triangles'] and surfaces==manifest['placed_surfaces'],'Unique and placed totals match measured buffers')
report.update(unique_triangles=unique,placed_triangles=placed,placed_surfaces=surfaces,gallery_size_m=[float(width),float(height)],passed=all(c['passed'] for c in report['checks']))
(OUT/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(len(report['checks']),'checks; passed:',report['passed'],'triangles',unique,placed,'surfaces',surfaces)
raise SystemExit(0 if report['passed'] else 1)
