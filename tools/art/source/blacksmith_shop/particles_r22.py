"""Install manifest-driven FX without rebuilding borrowed workbench UVs or room atlas."""
from pathlib import Path
import sys,json,hashlib
ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT/'tools/art/source/coffee_shop'))
def apply():
 from series_batch import build
 folder=ROOT/'assets/rooms/blacksmith_shop';lp=folder/'layout.json';sp=folder/'asset_stats.json';d=json.loads(lp.read_text());stats=json.loads(sp.read_text())
 protected=['back_tool_bench.glb','bench_vise.glb','room_albedo_ao.png'];before={n:hashlib.sha256((folder/n).read_bytes()).hexdigest() for n in protected}
 remove={'fire','smoke'};old=[a for a in stats['assets'] if a['name'] in remove]
 d['assets']=[a for a in d['assets'] if a['name'] not in remove]
 d['instances']=[a for a in d['instances'] if a['asset'] not in remove]
 for name in remove:d['material_overrides'].pop(name,None)
 d['revision']='R2.2'
 d['effects']=[{'name':'ForgeFireFX','scene':'res://assets/rooms/_shared/fx/fx_hearth_fire.tscn','position':[-1.55,1.20,-1.78],'parameters':{'flame_count':16,'spark_count':4,'flame_height':.67,'flame_lifetime':.72,'emission_box':[.32,.012,.055],'light_energy':3.1,'flicker_strength':.08,'light_path':'../LocalLight_forge_fire'}},
 {'name':'ChimneySmokeFX','scene':'res://assets/rooms/_shared/fx/fx_chimney_smoke.tscn','position':[-1.55,4.36,-2.29],'parameters':{'smoke_count':12,'lifetime':3.5,'drift':[.19,.44,-.015],'start_size':.30,'end_size':1.15}}]
 for view in d['review_views']:
  if view['name']=='smoke-detail':view['target']=[-1.15,5.12,-2.29];view['size']=3.5;view['position']=[4.4,6.9,6.0]
 lp.write_text(json.dumps(d,indent=2)+'\n')
 stats['assets']=[a for a in stats['assets'] if a['name'] not in remove]
 for k in ['unique_triangles','scene_triangles']:stats[k]-=sum(a['triangles'] for a in old)
 for k in ['unique_assets','placed_instances','static_draw_surfaces']:stats[k]-=len(old)
 stats['glb_bytes']=sum(a['bytes'] for a in stats['assets']);stats['effects']={'flames':16,'sparks':4,'smoke':12,'total_particles':32,'particle_surfaces':3,'fixed_fps':30,'collision':False,'shadows':False,'textures':{'flame_strip.png':[1024,256],'smoke_strip.png':[1024,256],'spark.png':[64,64]}}
 sp.write_text(json.dumps(stats,indent=2)+'\n');build('blacksmith_shop')
 after={n:hashlib.sha256((folder/n).read_bytes()).hexdigest() for n in protected};assert before==after
 (ROOT/'docs/design/blacksmith_shop-2026-10-07/workbench-r22-preservation.json').write_text(json.dumps({'before':before,'after':after,'byte_identical':True,'note':'工作台未改动；back_tool_bench.glb、bench_vise.glb、原房间图集字节一致。仅重组去掉旧烟的运行时合批，不重烘。'},ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':apply()
