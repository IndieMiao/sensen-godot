"""Liu Bei shop-series revision helpers; opt-in, preserving each scene's source pivots."""
import json,math
import kit as k
from kit import cube

def clear(name):
    r=k.KITS[name];k.CURRENT=r
    for o in list(r['objects']):k.bpy.data.objects.remove(o,do_unlink=True)
    r['objects'].clear();return r

def remove(name):
    r=clear(name)
    for p in list(k.INSTANCES):
        if p['asset']==name:
            root=k.bpy.data.objects.get(p['name'])
            if root:
                for o in list(root.children):k.bpy.data.objects.remove(o,do_unlink=True)
                k.bpy.data.objects.remove(root,do_unlink=True)
            k.INSTANCES.remove(p)
    k.bpy.data.objects.remove(r['root'],do_unlink=True);del k.KITS[name]

def recolor(name,color,predicate=lambda o:True,kind='matte'):
    for o in k.KITS[name]['objects']:
        if predicate(o):o.data.materials.clear();o.data.materials.append(k.material(color,kind))

def move(name,at):
    r=k.KITS[name];r['at']=list(at);r['root'].location=k.v(at)

def vertical(name,factor):
    r=k.KITS[name]
    for o in r['objects']:o.location.z*=factor;o.scale.z*=factor
    for b in r['collision']:b['at'][1]*=factor;b['size'][1]*=factor

def sync_instances():
    for p in k.INSTANCES:
        root=k.bpy.data.objects[p['name']];root.location=k.v(p['position'])
        for o in list(root.children):k.bpy.data.objects.remove(o,do_unlink=True)
        for source in k.KITS[p['asset']]['objects']:
            o=source.copy();o.data=source.data;k.bpy.context.scene.collection.objects.link(o);o.parent=root

def plant(name,asset,at,scale=1,yaw=0,roll=0,colliders=None):
    return {'name':name,'asset':asset,'file':'res://assets/rooms/_shared/plants/'+asset+'.glb','position':list(at),'rotation_degrees':[0,yaw,roll],'scale':[scale]*3,'colliders':colliders or []}

def brick_panel(name,spans,rows,height,width,depth,tones):
    """Clipped staggered courses, no hidden bricks across openings."""
    for lo,hi in spans:
        for row in range(rows):
            y=(row+.5)*height/rows
            cuts=[lo]+[lo+width*(j+.5*(row%2)) for j in range(int((hi-lo)/width)+2) if lo+.03<lo+width*(j+.5*(row%2))<hi-.03]+[hi]
            for i,(a,b) in enumerate(zip(cuts,cuts[1:])):
                cube(name,((a+b)/2,y,depth),(b-a-.014,height/rows-.016,.075),tones[(i+row*3)%len(tones)],.025)

def front_entry(layout,width=2.06):
    # Continuous low ramp follows the two visual treads, enclosed landing prevents edge fall.
    a=next(a for a in layout['assets'] if a['name']=='entry_step')
    a['colliders']=[{'at':[0,0,0],'points':[[x,y,z] for x in (-width/2,width/2) for y,z in ((-.19,-.4),(.211,-.4),(.211,.21),(-.02,.70),(-.19,.70))]}]
    layout['boundaries']=[{'name':'side_arch_limit','at':[-3.13,1.4,0],'size':[.10,3,5.6]}, {'name':'landing_floor','at':[.15,-.245,3.20],'size':[width,.10,.80]}, {'name':'landing_front_edge','at':[.15,.5,3.63],'size':[width+.1,1.6,.10]}, {'name':'landing_left_edge','at':[.15-width/2-.05,.5,3.17],'size':[.1,1.6,.9]}, {'name':'landing_right_edge','at':[.15+width/2+.05,.5,3.17],'size':[.1,1.6,.9]}]
    next(a for a in layout['assets'] if a['name']=='floor')['colliders']=[{'at':[0,-.08,0],'size':[6.1,.26,5.6]}]

def lighting(layout,background,ambient='D6BBCB',sun='FFE2C5',energy=1.5,lamps=None):
    l={'background':background,'ambient':ambient,'ambient_energy':.72,'sun_color':sun,'sun_energy':energy,'sun_position':[-3,8,5],'sun_target':[0,0,-.8],'angular_distance':6,'lamps':lamps or []}
    layout['lighting']=l;layout['review_lighting']={'background':background,'ambient_color':ambient,'ambient':l['ambient_energy'],'sun_color':sun,'sun':energy,'sun_position':l['sun_position'],'sun_target':l['sun_target'],'points':l['lamps']}

def append_plants(layout):
    import importlib.util
    from pathlib import Path
    # Incremental source rebakes replace placements rather than duplicating them.
    for collection in list(k.bpy.data.collections):
        if collection.name.startswith('Shared botanical instances'):
            for obj in list(collection.objects):k.bpy.data.objects.remove(obj,do_unlink=True)
            k.bpy.data.collections.remove(collection)
    spec=importlib.util.spec_from_file_location('coffee_botanical_source',Path(__file__).with_name('revision.py'))
    revision=importlib.util.module_from_spec(spec);spec.loader.exec_module(revision)
    revision.PLANTS[:]=layout['shared_plants'];revision.append_source_plants()
    k.bpy.ops.wm.save_as_mainfile(filepath=str(k.SOURCE/(k.SLUG+'.blend')))
