"""Post-export shared-FX migration; run in Blender. Never rebakes a room atlas."""
from pathlib import Path
import sys,json,hashlib,bpy
ROOT=Path(__file__).resolve().parents[2];slug=globals().get('ROOM_SLUG') or sys.argv[sys.argv.index('--')+1];source=ROOT/'tools/art/source'/slug;kit=ROOT/'assets/rooms'/slug
config=json.loads((source/'shared-hearth-fx.json').read_text());p=kit/'layout.json';layout=json.loads(p.read_text());removed=config['replaces_asset']
old=[a for a in layout['assets'] if a['name']==removed]
if old:layout.setdefault('archived_assets',[]).extend(old)
layout['assets']=[a for a in layout['assets'] if a['name']!=removed]
layout['effects']=config['effects'];layout['ember_surfaces']=config['ember_surfaces'];layout['fx_review_camera']=config['fx_review_camera']
positions=[fx['light']['position'] for fx in config['effects']]
layout['review_lighting']['points']=[light for light in layout['review_lighting'].get('points',[]) if light['position'] not in positions]
p.write_text(json.dumps(layout,indent=2)+'\n')
p=kit/'asset_stats.json';stats=json.loads(p.read_text());old=[a for a in stats['assets'] if a['name']==removed]
if old:stats.setdefault('archived_assets',[]).extend(old)
stats['assets']=[a for a in stats['assets'] if a['name']!=removed];counts={a['name']:a['triangles'] for a in stats['assets']}
stats['unique_triangles']=sum(counts.values());stats['local_scene_triangles']=stats['unique_triangles']+sum(counts[i['asset']] for i in layout['instances']);stats['scene_triangles']=stats['local_scene_triangles']+stats.get('shared_scene_triangles',0)
stats['static_draw_surfaces']=len(layout['assets'])+len(layout['instances'])+len(layout.get('shared_plants',[]));stats['placed_instances']=stats['static_draw_surfaces'];stats['glb_bytes']=sum(a['bytes'] for a in stats['assets'])
stats['particles']={'library_commit':config['library_commit'],'capacity':sum(f['flame_count']+f['spark_count'] for f in config['effects']),'limit':40,'emitters':sum(1+int(f['spark_count']>0) for f in config['effects']),'dynamic_draws':sum(1+int(f['spark_count']>0) for f in config['effects'])}
stats['budget_passed']=stats['scene_triangles']<=200000 and stats['plant_budget_triangles']<=100000 and stats['static_draw_surfaces']<=60 and stats['particles']['capacity']<=40;assert stats['budget_passed'];p.write_text(json.dumps(stats,indent=2)+'\n')
# Retain original named geometry as an archived editable source. Runtime no
# longer instantiates its static flames. All non-fire meshes stay byte-identical.
bpy.ops.wm.open_mainfile(filepath=str(source/(slug+'.blend')));bpy.context.preferences.filepaths.save_version=0
for o in bpy.data.collections['KIT_fire'].objects:o.hide_render=True;o.hide_viewport=True
collection=bpy.data.collections.get('SHARED_FX')
if collection:
 for o in list(collection.objects):bpy.data.objects.remove(o,do_unlink=True)
 bpy.data.collections.remove(collection)
collection=bpy.data.collections.new('SHARED_FX');bpy.context.scene.collection.children.link(collection)
for fx in config['effects']:
 o=bpy.data.objects.new(fx['name'],None);collection.objects.link(o);x,y,z=fx['position'];o.location=(x,-z,y);o.empty_display_type='CUBE';o.empty_display_size=.15;o['runtime_scene']=fx['scene'];o['creation_settings']=json.dumps(fx)
bpy.ops.wm.save_as_mainfile(filepath=str(source/(slug+'.blend')))
print('SHARED_FIRE_MIGRATED',slug,stats['scene_triangles'],stats['static_draw_surfaces'],stats['particles']['capacity'])
