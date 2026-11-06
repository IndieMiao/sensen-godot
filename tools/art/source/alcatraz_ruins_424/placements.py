"""World and ruins-relative suggested points. Check actual v6 ground; no layout edits."""
from pathlib import Path
import hashlib,json,sys,math
import numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/alcatraz-ruins-424';KIT=QA/'project/assets/landmarks/alcatraz_island'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
def main():
 layout=json.loads((HERE/'reference/layout-b16c3198.json').read_text());stats=json.loads((HERE/'asset_stats.json').read_text())['assets'];ruin=next(p for p in layout['placements'] if p['name']=='ruins_000');origin=np.array(ruin['position'])
 ground=[]
 for name in ['alc_ground_dock','alc_ground_terraces','alc_ground_summit']:
  doc,data=load_glb(KIT/(name+'.glb'))
  for mesh in doc['meshes']:
   for p in mesh['primitives']:
    xyz=np.array(accessor(doc,data,p['attributes']['POSITION']));ind=np.array(accessor(doc,data,p['indices'])).reshape(-1,3);tri=xyz[ind];normal=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);ground.extend(tri[normal[:,1]>1e-6])
 ground=np.array(ground)
 def height(x,z):
  a=ground[:,0];u=ground[:,1]-a;v=ground[:,2]-a;det=u[:,0]*v[:,2]-u[:,2]*v[:,0];valid=np.abs(det)>1e-8;uu=np.zeros(len(a));vv=uu.copy();dx=x-a[:,0];dz=z-a[:,2]
  uu[valid]=(dx[valid]*v[valid,2]-dz[valid]*v[valid,0])/det[valid];vv[valid]=(u[valid,0]*dz[valid]-u[valid,2]*dx[valid])/det[valid];valid&=(uu>=-1e-6)&(vv>=-1e-6)&(uu+vv<=1.000001)
  return float(np.max((a[:,1]+uu*u[:,1]+vv*v[:,1])[valid])) if np.any(valid) else None
 candidates=[
  ('alc_ruin_arch',[15.3,3.25,5.95],-12,'fallen_arch'),
  ('alc_ruin_rubble',[11.2,3.25,5.55],18,'approach'),
  ('alc_ruin_rubble',[15.6,3.25,6.65],-20,'fallen_arch'),
  ('alc_ruin_rubble',[21.6,3.25,5.95],8,'east_wall'),
  ('alc_ruin_vine',[16.5,3.85,5.245],0,'wall_cover'),
  ('alc_ruin_vine',[18.5,4.35,5.245],0,'wall_cover'),
  ('alc_ruin_vine',[20.5,3.75,5.245],0,'wall_cover'),
  ('alc_ruin_flowers',[11.8,3.25,4.95],0,'approach'),
  ('alc_ruin_flowers',[13.0,3.25,6.10],18,'fallen_arch'),
  ('alc_ruin_flowers',[16.45,3.25,6.95],0,'fallen_arch'),
  ('alc_ruin_flowers',[20.0,3.25,5.80],-15,'east_wall'),
  ('alc_ruin_flowers',[22.9,3.25,5.65],0,'east_wall'),
  ('alc_ruin_plaque',[13.25,3.25,6.85],-12,'fallen_arch')]
 rows=[]
 for i,(name,at,angle,group) in enumerate(candidates):
  yaw=math.radians(angle);c,s=math.cos(yaw),math.sin(yaw);lo,hi=stats[name]['bounds'];corners=[(at[0]+c*x+s*z,at[2]-s*x+c*z) for x in [lo[0],hi[0]] for z in [lo[2],hi[2]]]
  if name!='alc_ruin_vine':
   for x,z in corners+[(at[0],at[2])]:assert height(x,z) is not None and abs(height(x,z)-at[1])<.06,(name,at,(x,z),height(x,z))
  else:
   # Existing pillars are centred at local X -2,0,+2; front depth is +.225m.
   assert abs(at[2]-(origin[2]+.225)-.020)<1e-6
   assert any(abs(at[0]-(origin[0]+x))<1e-6 for x in [-2,0,2])
   assert at[1]+hi[1] < origin[1]+[4,4.5,3.5][[-2,0,2].index(round(at[0]-origin[0]))]
  rows.append({'name':f'{name}_detail_{i:02d}','asset':name,'position':at,'relative_to_ruins_000':(np.array(at)-origin).round(6).tolist(),'rotation_degrees':[0,angle,0],'scale':[1,1,1],'zone':'TerraceZone','group':group,'multimesh':True,'collision':False,'placement_mode':'wall front; back plane +20mm' if name=='alc_ruin_vine' else 'ground support at every bounding corner verified'})
 report={'author':'赵云','task':'SGODOT-424','layout_reference':'b16c31982f34a64cdd4f9c6683064edbf20837a0','ruins_000':ruin,'instances':rows,'counts':{n:sum(p['asset']==n for p in rows) for n in stats},'placed_triangles':sum(stats[p['asset']]['triangles'] for p in rows),'route':layout['route'],
  'rules':['保留ruins_000及原layout/导航；此表为场景方整合建议，不是运行时自动覆盖。','废墟位于主路右侧、不是可走区；低碎石/野花向靠路侧引导，其余围着旧墙摆。此包不单独证明主路每6–7m覆盖。','藤蔓背平面Z=0，+Z为叶片正面；建议背面在墙前20mm，按主墙形状重新校贴，不要将整片悬空放在草地。','碎石是最高0.12m的单层砖石碎片，无底座、不堆圆丘，不应被当作采集资源。','说明牌完全空白、无按钮/标记/描边/文字；不挂交互和碰撞。','原树冠/主体后续替换时，场景方再核遮挡和整岛预算；禁止铁栏、铁丝网、牢门等监狱元素。']}
 (HERE/'suggested_placements.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('RUIN_PLACEMENTS',len(rows),report['counts'],'triangles',report['placed_triangles'])
if __name__=='__main__':main()
