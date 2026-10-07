"""Merge authored R2 placements into runtime-only groups while retaining local GLBs.
One primitive per group; atlas UVs and normals are copied without repacking.
"""
from pathlib import Path
import json,struct,math,subprocess
import numpy as np
ROOT=Path(__file__).resolve().parents[4]

def read_glb(path):
    b=path.read_bytes();jl=struct.unpack_from('<I',b,12)[0];g=json.loads(b[20:20+jl]);offset=20+jl;raw=b[offset+8:]
    assert all(not any(k in n for k in ('matrix','rotation','translation','scale')) for n in g['nodes'])
    p=g['meshes'][0]['primitives'][0]
    def acc(i):
        a=g['accessors'][i];v=g['bufferViews'][a['bufferView']];types={5126:np.float32,5125:np.uint32,5123:np.uint16,5121:np.uint8};dim={'SCALAR':1,'VEC2':2,'VEC3':3}[a['type']];dt=np.dtype(types[a['componentType']]);start=v.get('byteOffset',0)+a.get('byteOffset',0)
        return np.ndarray((a['count'],dim),dtype=dt,buffer=raw,offset=start,strides=(v.get('byteStride',dim*dt.itemsize),dt.itemsize)).copy()
    return acc(p['attributes']['POSITION']),acc(p['attributes']['NORMAL']),acc(p['attributes']['TEXCOORD_0']),acc(p['indices']).ravel()

def write_glb(path,positions,normals,uv,indices):
    blob=bytearray();views=[];accessors=[]
    for a,typ,ctype in [(positions,'VEC3',5126),(normals,'VEC3',5126),(uv,'VEC2',5126),(indices,'SCALAR',5125)]:
        a=np.asarray(a,dtype=np.float32 if ctype==5126 else np.uint32);data=a.tobytes();offset=len(blob);blob.extend(data)
        while len(blob)%4:blob.append(0)
        views.append({'buffer':0,'byteOffset':offset,'byteLength':len(data)})
        x={'bufferView':len(views)-1,'componentType':ctype,'count':len(a),'type':typ}
        if len(accessors)==0:x.update(min=a.min(axis=0).tolist(),max=a.max(axis=0).tolist())
        accessors.append(x)
    g={'asset':{'version':'2.0','generator':'Coffee Shop R2 placement batcher'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'mesh':0,'name':path.stem}],'meshes':[{'primitives':[{'attributes':{'POSITION':0,'NORMAL':1,'TEXCOORD_0':2},'indices':3,'mode':4}]}],'buffers':[{'byteLength':len(blob)}],'bufferViews':views,'accessors':accessors}
    encoded=json.dumps(g,separators=(',',':')).encode()
    encoded+=b' '*((-len(encoded))%4)
    path.parent.mkdir(exist_ok=True)
    path.write_bytes(struct.pack('<III',0x46546c67,2,12+8+len(encoded)+8+len(blob))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(blob),0x004e4942)+blob)

def merged(path,placements):
    positions=[];normals=[];uvs=[];indices=[];offset=0
    for item in placements:
        p,n,uv,idx=read_glb(ROOT/item['file'].removeprefix('res://'))
        x,y,z=np.radians(item.get('rotation_degrees',[0,item.get('yaw_degrees',0),0]));cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
        rot=np.array([[cy,0,sy],[0,1,0],[-sy,0,cy]])@np.array([[1,0,0],[0,cx,-sx],[0,sx,cx]])@np.array([[cz,-sz,0],[sz,cz,0],[0,0,1]])
        scale=np.array(item.get('scale',[1,1,1]));p=(p*scale)@rot.T+item['position'];n=(n/scale)@rot.T;n/=np.linalg.norm(n,axis=1)[:,None]
        positions.append(p);normals.append(n);uvs.append(uv);indices.append(idx.astype(np.uint32)+offset);offset+=len(p)
    write_glb(path,np.concatenate(positions),np.concatenate(normals),np.concatenate(uvs),np.concatenate(indices))
    return sum(len(x) for x in indices)//3

def build_batches():
    folder=ROOT/'assets/rooms/coffee_shop';path=folder/'layout.json';layout=json.loads(path.read_text());groups={}
    for plant in layout['shared_plants']:
        name=plant['name']
        if name.startswith('Arch'):group='ivy_left_arch'
        elif name.startswith('Transom'):group='ivy_back_transom'
        elif name.startswith(('WindowArch','RightPillar')):group='ivy_right_arch'
        elif name.startswith(('Front','LeftPier')):group='front_flowers'
        else:continue
        groups.setdefault((group,'plants'),[]).append(plant)
    dressing={'coffee_grinder','cups_and_saucers','counter_daisies','small_planter','wall_shelf','botanical_picture'}
    room_assets={a['name']:a for a in layout['assets']}
    for p in layout['assets']+layout['instances']:
        a=room_assets[p.get('asset',p['name'])]
        if a['name'] in ('counter_daisies','small_planter'):group,mat='counter_botanical','room'
        elif a['name'] in dressing:group,mat='counter_dressing','room'
        elif a['name'].startswith('window_glass'):group,mat='window_glazing','glass'
        elif a['name'] in ('table_bouquet','table_coffee'):group,mat='table_settings','room'
        else:continue
        groups.setdefault((group,mat),[]).append({**p,'file':'res://assets/rooms/coffee_shop/'+a['name']+'.glb'})
    batches=[]
    for (name,material),placements in groups.items():
        dst=folder/'batches'/('r2_'+name+'.glb');triangles=merged(dst,placements)
        batches.append({'name':name,'file':'res://'+str(dst.relative_to(ROOT)),'material':material,'sources':[p['name'] for p in placements],'triangles':triangles,'cast_shadow':False if material in ('plants','glass') or name in ('table_settings','counter_botanical') else True})
    layout['render_batches']=batches;layout['revision']='R2.1';path.write_text(json.dumps(layout,indent=2)+'\n')
    stats=json.loads((folder/'asset_stats.json').read_text());plants=json.loads((ROOT/'assets/rooms/_shared/plants/asset_stats.json').read_text());counts={p['name']:p['triangles'] for p in plants['assets']}
    placed=sum(counts[p['asset']] for p in layout['shared_plants']);surfaces=stats['static_draw_surfaces']+len(layout['shared_plants'])-sum(len(b['sources'])-1 for b in batches)
    before={'room_triangles':80734,'plant_triangles':441576,'total_triangles':522310,'static_surfaces':97}
    botanical_counts={'counter_daisies':1,'small_planter':1,'table_bouquet':2,'window_garden_backdrop':1}
    incidental=sum(a['triangles']*botanical_counts.get(a['name'],0) for a in stats['assets'])
    old=json.loads(subprocess.check_output(['git','show','b3bc947:assets/rooms/coffee_shop/asset_stats.json'],cwd=ROOT))
    before['shared_plant_triangles']=before['plant_triangles']
    before['plant_triangles']+=sum(a['triangles']*botanical_counts.get(a['name'],0) for a in old['assets'])
    after={'room_triangles':stats['scene_triangles'],'shared_plant_triangles':placed,'room_botanical_triangles':incidental,'plant_triangles':placed+incidental,'total_triangles':stats['scene_triangles']+placed,'static_surfaces':surfaces}
    stats['revision']='R2.1';stats['scene_budget']={'before':before,'after':after,'limits':{'total_triangles':200000,'plant_triangles':100000,'static_surfaces':60},'plant_leaf_triangle_max':plants['leaf_triangle_max'],'render_batches':batches}
    assert after['total_triangles']<=200000 and after['plant_triangles']<=100000 and surfaces<=60,after
    (folder/'asset_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
    print('COFFEE_R2_BUDGET',json.dumps(after),flush=True)
if __name__=='__main__':build_batches()
