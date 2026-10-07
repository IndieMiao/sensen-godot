"""Merge shop dressing by shelf/material; retain reusable GLBs, UVs and collisions."""
import json,sys
from pathlib import Path
from batch_r2 import merged
ROOT=Path(__file__).resolve().parents[4]
def build(slug):
    folder=ROOT/'assets/rooms'/slug;p=folder/'layout.json';d=json.loads(p.read_text());stats=json.loads((folder/'asset_stats.json').read_text());assets={a['name']:a for a in d['assets']};groups={}
    for a in d['assets']+d['instances']:
        name=a.get('asset',a['name']);source=assets[name]
        if source['colliders'] or name=='floor' or any(d.get('material_overrides',{}).get(name,{}).get(key,False) for key in ('unshaded','emission')):continue
        mat='glass' if 'glass' in name else 'room'
        group='glass' if mat=='glass' else 'botanical' if name in d.get('botanical_assets',[]) or any(x in name for x in ['flower','bouquet','leaves','grass']) else 'back_dressing' if a['position'][2]<-1 else 'front_dressing'
        groups.setdefault((group,mat),[]).append({**a,'file':'res://assets/rooms/'+slug+'/'+source['file']})
    for a in d.get('shared_plants',[]):
        group='large_plants' if a['colliders'] or a.get('cast_shadow',False) else 'back_plants' if a['position'][2]<-1 else 'front_plants'
        groups.setdefault((group,'plants'),[]).append(a)
    batches=[]
    for (name,mat),placements in groups.items():
        file=folder/'batches'/('review_'+name+'.glb');tris=merged(file,placements)
        batches.append({'name':name,'file':'res://'+str(file.relative_to(ROOT)),'material':mat,'sources':[p['name'] for p in placements],'triangles':tris,'cast_shadow':mat=='room' and name!='botanical' or name=='large_plants'})
    d['render_batches']=batches;p.write_text(json.dumps(d,indent=2)+'\n')
    ps=json.loads((ROOT/'assets/rooms/_shared/plants/asset_stats.json').read_text());pc={a['name']:a['triangles'] for a in ps['assets']}
    plant_total=sum(pc[a['asset']] for a in d.get('shared_plants',[]));counts={a['name']:a['triangles'] for a in stats['assets']}
    incidental=sum(counts[a.get('asset',a['name'])] for a in d['assets']+d['instances'] if a.get('asset',a['name']) in d.get('botanical_assets',[]) or any(x in a.get('asset',a['name']) for x in ['flower','bouquet','leaves','grass']))
    surfaces=stats['static_draw_surfaces']+len(d.get('shared_plants',[]))-sum(len(b['sources'])-1 for b in batches)
    after={'room_triangles':stats['scene_triangles'],'shared_plant_triangles':plant_total,'room_botanical_triangles':incidental,'plant_triangles':plant_total+incidental,'total_triangles':stats['scene_triangles']+plant_total,'static_surfaces':surfaces}
    stats['scene_budget']={'after':after,'limits':{'total_triangles':200000,'plant_triangles':100000,'static_surfaces':60},'render_batches':batches};(folder/'asset_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
    print('SHOP_REVIEW_BUDGET',slug,after,flush=True)
    assert after['total_triangles']<=200000 and after['plant_triangles']<=100000 and surfaces<=60,after
if __name__=='__main__':build(sys.argv[1])
