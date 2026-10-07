"""SGODOT-183: recognizable low-poly groceries, octagonal tiles and usable aisles."""
import json,math,random
import kit as k
import storefront as s
import series_revision as r
from kit import cube,cylinder,lathe,mesh,begin,tube
COLORS=['DB785C','7AA799','E4B855','719BAE','CD91A2','95A768','F2D1A2','7690B3']
PACKAGE_STATS={}

def panel(name,verts,c):return mesh(name,verts,[(0,1,2,3)],c)

from revision2 import package, PACKAGE_STATS


def tiles():
    r.clear('floor');cube('Thick cream foundation',(0,-.12,0),(6.18,.27,5.68),'DFCCAF',.12)
    for i in range(12):
        for j in range(11):
            x=-2.75+i*.5;z=-2.50+j*.5;c=['DED2B6','BDD0B8','E8DCC4','C8D0B7'][(i+3*j)%4];a=.241;b=.165
            ring=[(-a,-b),(-b,-a),(b,-a),(a,-b),(a,b),(b,a),(-b,a),(-a,b)]
            verts=[(x+dx,y,z+dz) for y in (.002,.054) for dx,dz in ring]
            faces=[tuple(reversed(range(8))),tuple(range(8,16))]+[(q,(q+1)%8,(q+1)%8+8,q+8) for q in range(8)]
            mesh('Cream and mint octagonal tile',verts,faces,c)
            if i<11 and j<10:
                o=cube('Small diamond joining tile',(x+.25,.028,z+.25),(.101,.052,.101),'9BB59F',.008);o.rotation_euler.z=math.pi/4


def finishing_details():
    from mathutils import Matrix
    for name in ('snacks_wall_rack','essentials_wall_rack','drinks_header'):
        rec=k.KITS[name];k.CURRENT=rec
        for o in rec['objects']:
            if o.name.startswith('Lettering '):o.location.x+=.14
        x=-.90 if name!='drinks_header' else -.82;y=1.68 if name!='drinks_header' else 0
        panel('Category icon silhouette',[(x-.10,y-.09,.184),(x+.10,y-.09,.184),(x+.13,y+.07,.184),(x-.13,y+.07,.184)],'EFE8D8')
        tube('Category icon handle',[(x-.05,y+.07,.19),(x-.05,y+.14,.19),(x+.05,y+.14,.19),(x+.05,y+.07,.19)],.012,'EFE8D8',4)
    k.CURRENT=k.KITS['checkout_small_goods']
    for j in range(2):package((-.18+j*.20,.02,-.12),3+j,'wash')
    # Source flower objects leave the collider-bearing checkout and become one
    # botanical asset, so every plant triangle is budgeted and casts no shadow.
    rec=k.KITS['checkout'];parts=[o for o in rec['objects'] if any(t in o.name for t in ['Celadon bud vase','Bouquet ','Daisy ','Pollen'])]
    if parts:
        begin('checkout_flowers',at=rec['at']);new=k.CURRENT
        for o in parts:
            rec['objects'].remove(o);rec['collection'].objects.unlink(o);new['collection'].objects.link(o);o.parent=new['root'];new['objects'].append(o)

def revise():
    rng=random.Random(183)
    for name in ('entrance_plant','trailing_plant','front_flowers','side_leaves'):r.remove(name)
    tiles()
    for name in ('back_wall','left_door_wall'):
        rec=k.KITS[name];k.CURRENT=rec
        for o in list(rec['objects']):
            if 'brick' in o.name.lower():rec['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)
        spans=[(-3,3)] if name=='back_wall' else [(-2.70,-1.65),(-.15,2.90)]
        for lo,hi in spans:
            n=max(1,round((hi-lo)/.55))
            for row in range(6):
                for col in range(n):cube('Thick soft cream mint block',(lo+(col+.5)*(hi-lo)/n,(row+.5)*.49,.145),((hi-lo)/n-.018,.477,.20),'B8CDBB' if (row+col)%4==0 else 'E7CEC3',.055)
        r.recolor(name,'94B4A4',lambda o:any(w in o.name.lower() for w in ['coping','lintel','door jamb']))
    for name in ('front_wall_left','front_wall_right','side_low_wall','corner_pier'):
        r.recolor(name,'EADBC2');r.recolor(name,'97B7A6',lambda o:'coping' in o.name.lower() or 'pier block' in o.name.lower())
    k.KITS['side_low_wall']['collision']=[{'at':[0,.38,0],'size':[5.28,.76,.3]}]
    # Rotate the right island along depth, keep established furniture footprints.
    r.move('produce_aisle',(-1.19,.07,.25));r.move('essentials_aisle',(1.45,.07,1.19));rec=k.KITS['essentials_aisle'];rec['yaw']=90;rec['root'].rotation_euler.z=math.pi/2
    r.move('basket_stack',(2.56,.07,.06))
    # Individual package objects are retained in source but not runtime nodes.
    for name in ('snacks_wall_rack','essentials_wall_rack','produce_aisle','essentials_aisle'):
        rec=k.KITS[name]
        # varied package gaps: remove complete groups based on label order handled in builder.
        for o in rec['objects']:
            if 'category sign' in o.name.lower():o.data.materials.clear();o.data.materials.append(k.material('507C66'))
    # Add microwave, price sign and checkout impulse shelf as separate reusable assets.
    begin('checkout_small_goods',at=(-.37,1.17,-1.42))
    cube('Impulse shelf base',(.66,0,.13),(.54,.055,.33),'C6975E',.014)
    for j in range(3):package((.46+j*.17,.04,.12),j+5,'soap')
    cube('Small price board',(.27,.18,.08),(.29,.33,.04),'D3A15F',.02)
    cube('Price chalk face',(.27,.18,.11),(.25,.28,.01),'527160',.012)
    k.text_label('TODAY',(.27,.23,.119),.06,'EEE5D4');k.text_label('$ 3',(.27,.13,.119),.085,'EEE5D4')
    begin('microwave',at=(.90,1.17,-1.65))
    cube('Cream microwave shell',(0,.23,0),(.54,.46,.38),'E5DECF',.04)
    cube('Dark microwave window',(-.06,.23,.20),(.31,.31,.015),'454D48',.023)
    cube('Control strip',(.18,.22,.208),(.075,.30,.015),'7D8781',.012)
    for y in (.16,.28):cylinder('Microwave knob',(.18,y,.225),.029,.025,'CCC6B7',vertices=10).rotation_euler.x=math.pi/2
    # Refrigerator source has five clearly stocked shelves. Keep only two doors.
    for p in list(k.INSTANCES):
        if p['name'] in ('drink_cabinet_2','chiller_glass_2'):
            root=k.bpy.data.objects[p['name']]
            for o in list(root.children):k.bpy.data.objects.remove(o,do_unlink=True)
            k.bpy.data.objects.remove(root,do_unlink=True);k.INSTANCES.remove(p)
    r.move('drink_cabinet',(-2.68,.065,-.72));r.move('chiller_glass',(-2.68,.065,-.72))
    for p in k.INSTANCES:
        if p['name'] in ('drink_cabinet_1','chiller_glass_1'):p['position']=[-2.68,.065,-1.48]
    k.CURRENT=k.KITS['drink_cabinet']
    for x in (-.28,.28):cube('Cold cabinet light strip',(x,1.2,.2),(.018,1.92,.02),'E2F6FF',0)
    # Two glowing lantern shapes and a coral mat, with no per-product lights.
    k.instance('entrance_sconce','entrance_sconce_2',(-2.80,1.93,.06),90)
    r.recolor('entry_step','DB8068',lambda o:'mat' in o.name.lower());k.CURRENT=k.KITS['entry_step'];cube('Lower ivory entrance tread',(0,-.065,.33),(2.06,.13,.65),'EADBC7',.045)
    for j in range(9):cube('Coral mat stitch',(-.50+j*.125,.16,0),(.009,.004,.42),'EAA587',0)
    finishing_details()
    window_sky()
    from revision2 import revise as revise_r2
    revise_r2()
    r.sync_instances()
    (k.OUT/'product-budget.json').write_text(json.dumps({'per_variant_triangles':PACKAGE_STATS,'max_triangles':max(PACKAGE_STATS.values()),'limit':60,'runtime':'merged into each fixture mesh; no product nodes'},indent=2)+'\n')


def window_sky():
    begin('entrance_sky',at=(-3.20,.07,1.05),yaw=90)
    cube('Blue sky beyond glass',(0,1.18,0),(1.37,2.18,.012),'A5D7E5',0)
    for i in range(7):
        x=-.65+i*.22
        k.ellipsoid('Soft distant canopy',(x,.40+(i%3)*.045,.012),(.43,.33,.016),['98BB9D','ADCBA4','8FB599'][i%3],8,4)

def manifest():
    p=k.OUT/'layout.json';d=json.loads(p.read_text());d['revision']='R1';d['botanical_assets']=['entrance_sky']
    d['shared_plants']=[r.plant('EntranceMonstera','monstera_woven',(-2.21,.07,-.03),1.15,25,colliders=[{'at':[0,.25,0],'size':[.50,.50,.50]}]),r.plant('HighPothos','pothos',(2.62,2.51,-2.26),.82,10),r.plant('IslandPothos','pothos',(1.42,1.34,.33),.45,45),r.plant('IslandHangingPothos','pothos',(1.71,.70,2.01),.47,90)]
    for i,(x,z) in enumerate([(-2.63,2.68),(-1.98,2.68),(-1.33,2.68),(1.64,2.68),(2.3,2.68),(3,2.14),(3,1.38)]):d['shared_plants'].append(r.plant('FlowerBox%02d'%i,'flower_shrub',(x,.75,z),.85,i*37))
    r.front_entry(d);d['material_overrides']={'chiller_glass':{'alpha':.11},'freezer_glass':{'alpha':.16},'entrance_glass':{'alpha':.075},'entrance_sky':{'unshaded':True}}
    r.lighting(d,'E5B78E',ambient='C5B9AF',sun='FFE0C6',energy=1.22,lamps=[{'position':[-2.27,1.48,-1.06],'color':'DAF0FF','energy':.60,'range':1.7},{'position':[-2.56,1.94,2.04],'color':'FFDB99','energy':.65,'range':1.15},{'position':[-2.56,1.94,.04],'color':'FFDB99','energy':.65,'range':1.15}])
    d['lighting']['sun_position']=[6,9,4];d['review_lighting']['sun_position']=[6,9,4];d['camera']={'position':[10,10,12],'target':[0,1.08,.15],'size':10.2}
    from convenience_bench import bench
    bench(d)
    from revision2 import manifest as manifest_r2
    manifest_r2(d)
    p.write_text(json.dumps(d,indent=2)+'\n');r.append_plants(d)
