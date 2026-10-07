"""Zhao Yun batch-review helpers, keeping Basic Room and Liu Bei assets read-only."""
from pathlib import Path
import sys,json,math,importlib.util,struct
import bpy
from mathutils import Matrix,Vector
import scene_room_pipeline as p
from scene_room_pipeline import *
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('zhaoyun_standard_r2',ROOT/'tools/art/source/standard_room_5/revision2.py')
r2=importlib.util.module_from_spec(spec);spec.loader.exec_module(r2)

def merge_modules(name,names):
    """One static runtime surface per meaningful zone; all source parts named."""
    begin(name,(0,0,0));dest=p.KITS[name]
    bpy.context.view_layer.update()
    for old in names:
        kit=p.KITS[old];root=kit['root'];matrix=root.matrix_world.copy()
        for obj in kit['objects']:
            world=obj.matrix_world.copy()
            for c in list(obj.users_collection):c.objects.unlink(obj)
            dest['collection'].objects.link(obj);obj.parent=dest['root'];obj.matrix_world=world;dest['objects'].append(obj)
        for c in kit['collision']:
            if c.get('points'):
                points=[matrix@v(q) for q in c['points']]
                dest['collision'].append({'points':[[q.x,q.z,-q.y] for q in points]})
            else:
                q=matrix@v(c['at']);dest['collision'].append(dict(c,at=[q.x,q.z,-q.y],rotation=[0,kit['yaw'],0]))
        bpy.data.objects.remove(root,do_unlink=True);bpy.data.collections.remove(kit['collection']);del p.KITS[old]
    p.b.CURRENT=dest

def soften_materials():
    r2.recolor_reused()
    for mat in list(bpy.data.materials):
        if not mat.use_nodes:continue
        bsdf=mat.node_tree.nodes.get('Principled BSDF')
        if not bsdf:continue
        bsdf.inputs['Roughness'].default_value=.86
        for node in mat.node_tree.nodes:
            if node.type=='VALTORGB' and ('_wood_' in mat.name or '_plaster_' in mat.name):
                high=node.color_ramp.elements[-1].color
                factor=.93 if '_wood_' in mat.name else .975
                node.color_ramp.elements[0].color=tuple(float(c)*factor for c in high[:3])+(1,)
    p.BAKE_SETTINGS.update(ao_distance=.9,ao_strength=.80,floor_ao_strength=.63)

def door_and_bounds(width,depth,height,door_x):
    x=width/2;z=depth/2
    p.KITS['room_shell']['collision']=[{'at':[0,-.07,0],'size':[width+.3,.30,depth+.3]},
      {'at':[-x,height/2,0],'size':[.22,height,depth+.3]},
      {'at':[(-x+door_x-.59)/2,height/2,-z],'size':[door_x-.59+x,height,.22]},
      {'at':[(door_x+.59+x)/2,height/2,-z],'size':[x-door_x-.59,height,.22]},
      {'at':[door_x,(2.46+height)/2,-z],'size':[1.18,height-2.46,.22]},
      {'at':[x+.10,.75,0],'size':[.10,1.5,depth+.3]},
      {'at':[0,.75,z+.10],'size':[width+.3,1.5,.10]},
      {'at':[door_x,-.07,-z-.36],'size':[1.18,.30,.92]},
      {'at':[door_x-.60,.7,-z-.4],'size':[.08,1.4,.90]},
      {'at':[door_x+.60,.7,-z-.4],'size':[.08,1.4,.90]},
      {'at':[door_x,.7,-z-.88],'size':[1.24,1.4,.08]}]
    old=p.KITS['green_door'];frames=[o for o in old['objects'] if 'doorway' in o.name.lower()]
    begin('door_frame',tuple(old['at']));new=p.KITS['door_frame']
    for o in frames:
        old['objects'].remove(o)
        for c in list(o.users_collection):c.objects.unlink(o)
        new['collection'].objects.link(o);o.parent=new['root'];new['objects'].append(o)
    for o in old['objects']:o.location.x+=.52
    r2.move_kit('green_door',(door_x-.52,.05,-z+.115))
    p.MANIFEST_EXTRA['door']={'module':'green_door','open_yaw_degrees':100}

def jute(name,at,width,depth):
    begin(name,at)
    cube('Natural pale jute backing',(0,.018,0),(width,.035,depth),'DCC495',.035,'cloth')
    for z in (-depth/2+.085,depth/2-.085):cube('Cream rug end binding',(0,.039,z),(width-.04,.006,.11),'EFE0BC',.007,'cloth')
    for x in (-width/2+.065,width/2-.065):cube('Cream rug side binding',(x,.039,0),(.085,.006,depth-.05),'EFE0BC',.006,'cloth')
    for j in range(round(depth/.065)):
        z=-depth/2+.05+j*.065
        tube('Fine jute weft',[(-width/2+.07,.041,z),(width/2-.07,.041,z)],.006,'C9AD7F',4)

def finish(camera,lighting,bench,materials=None,no_shadow=(),botanical=(),post_export=None):
    soften_materials();p.MANIFEST_EXTRA.update(bench)
    finalize(camera,lighting)
    path=p.OUT/'layout.json';layout=json.loads(path.read_text())
    for asset in layout['assets']:
        mode=(materials or {}).get(asset['name'],'garden' if asset['name'].endswith('garden') else 'plain')
        asset['material']=mode
        asset['cast_shadow']=asset['name'] not in no_shadow
    path.write_text(json.dumps(layout,indent=2)+'\n')
    if '--geometry-only' in sys.argv:return
    p.bake_and_export()
    if post_export:post_export()
    stats=json.loads((p.OUT/'asset_stats.json').read_text())
    # A custom post-export (e.g. height-UV flames) may change triangulation.
    # Measure delivered GLBs rather than retaining the pre-override numbers.
    for a in stats['assets']:
        path=p.OUT/(a['name']+'.glb');raw=path.read_bytes()
        g=json.loads(raw[20:20+struct.unpack_from('<I',raw,12)[0]])
        a['triangles']=sum(g['accessors'][q['indices']]['count']//3 for m in g['meshes'] for q in m['primitives'])
        a['bytes']=len(raw)
    stats['unique_triangles']=sum(a['triangles'] for a in stats['assets'])
    counts={a['name']:a['triangles'] for a in stats['assets']}
    stats['scene_triangles']=stats['unique_triangles']+sum(counts[i['asset']] for i in p.INSTANCES)
    stats['glb_bytes']=sum(a['bytes'] for a in stats['assets'])
    catalogue=json.loads((ROOT/'assets/rooms/_shared/plants/asset_stats.json').read_text())
    lookup={a['name']+'.glb':a for a in catalogue['assets']}
    plants=p.MANIFEST_EXTRA.get('shared_plants',[])
    stats['local_scene_triangles']=stats['scene_triangles']
    stats['shared_scene_triangles']=sum(lookup[q['file']]['triangles'] for q in plants)
    stats['scene_triangles']+=stats['shared_scene_triangles'];stats['static_draw_surfaces']+=len(plants);stats['placed_instances']+=len(plants)
    stats['shared_assets']=[lookup[n] for n in sorted({q['file'] for q in plants})]
    stats['plant_budget_triangles']=stats['shared_scene_triangles']+sum(a['triangles'] for a in stats['assets'] if a['name'] in botanical)
    stats['budget_limits']={'placed_triangles':200000,'plant_triangles':100000,'static_surfaces':60}
    stats['budget_passed']=stats['scene_triangles']<=200000 and stats['plant_budget_triangles']<=100000 and stats['static_draw_surfaces']<=60
    (p.OUT/'asset_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
    print('BATCH_BUDGET',stats['scene_triangles'],stats['plant_budget_triangles'],stats['static_draw_surfaces'],flush=True)
    assert stats['budget_passed'],stats
    if '--views' in sys.argv:p.render_views()

def draft_scene(slug):
    """Load named first-draft parts without exporting stale layout or media."""
    spec=importlib.util.spec_from_file_location('zhaoyun_draft_'+slug,ROOT/'tools/art'/('build_'+slug+'.py'))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.finalize=lambda *a,**kw:None
    module.complete=lambda:None
    module.build()
    return module

def drop_modules(*names):
    for name in names:
        if name not in p.KITS:continue
        kit=p.KITS.pop(name)
        for obj in list(kit['objects']):bpy.data.objects.remove(obj,do_unlink=True)
        bpy.data.objects.remove(kit['root'],do_unlink=True);bpy.data.collections.remove(kit['collection'])
        for root in list(bpy.context.scene.objects):
            if root.type=='EMPTY' and root.get('linked_asset')==name:
                for obj in list(root.children):bpy.data.objects.remove(obj,do_unlink=True)
                bpy.data.objects.remove(root,do_unlink=True)
        p.INSTANCES[:]=[i for i in p.INSTANCES if i['asset']!=name]

def move_zone(names,delta):
    for name in names:
        k=p.KITS[name];r2.move_kit(name,tuple(k['at'][i]+delta[i] for i in range(3)))
