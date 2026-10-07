"""SGODOT-185: tufted boutique bench, fuller fashions and an accessible round island."""
import math,json,random
import kit as k
import boutique as b
import series_revision as r
from kit import begin,cube,cylinder,tube,ellipsoid,mesh

def garment_print(name,floral=False):
    k.CURRENT=k.KITS[name]
    for o in k.CURRENT['objects']:
        if 'garment body' in o.name.lower():o.scale.y*=1.5
    for j in range(9):
        x=-.12+(j%3)*.12;y=-.92-(j//3)*.13;z=.13+(abs(y)-.85)*.17
        if floral:
            for n in range(5):
                a=n*math.tau/5;ellipsoid('Printed small blossom',(x+math.cos(a)*.022,y+math.sin(a)*.022,z),(.028,.027,.006),'DD93A4',6,4)
        else:ellipsoid('Printed ivory polka',(x,y,z),(.027,.034,.006),'EEE7DA',6,4)

def cushion(x,z):
    verts=[];faces=[];n=8
    for j in range(n+1):
        for i in range(n+1):
            u=-1+2*i/n;v=-1+2*j/n
            y=.588+.080*(1-max(abs(u),abs(v))**4)-.030*math.exp(-((u/.27)**2+(v/.34)**2))
            verts.append((x+u*.231,y,z+v*.142))
    for j in range(n):
        for i in range(n):a=j*(n+1)+i;faces.append((a,a+1,a+n+2,a+n+1))
    edge=list(range(n+1))+[j*(n+1)+n for j in range(1,n+1)]+[n*(n+1)+i for i in range(n-1,-1,-1)]+[j*(n+1) for j in range(n-1,0,-1)]
    offset=len(verts)
    for i in edge:verts.append((verts[i][0],.55,verts[i][2]))
    for j,a in enumerate(edge):faces.append((a,edge[(j+1)%len(edge)],offset+(j+1)%len(edge),offset+j))
    faces.append(tuple(offset+j for j in reversed(range(len(edge)))))
    mesh('Square pillow with true recessed tuft',verts,faces,'D996AD','cloth',True)

def soften_floor_joints():
    for o in k.KITS['boutique_floor']['objects']:
        if 'parquet' not in o.name.lower():continue
        coords=[v.co.copy() for v in o.data.vertices];cx=sum(v.x for v in coords)/len(coords);cy=sum(v.y for v in coords)/len(coords)
        for v in o.data.vertices:v.co.x=max(-3,min(3,cx+(v.co.x-cx)*1.018));v.co.y=max(-2.73,min(2.73,cy+(v.co.y-cy)*1.006))

def revise():
    for name in ('entrance_plant','fitting_plant','trailing_rack_plant'):r.remove(name)
    r.recolor('boutique_floor','DDC0AC',lambda o:'parquet' in o.name.lower(),kind='wood')
    for i,o in enumerate(k.KITS['boutique_floor']['objects']):
        if 'parquet' in o.name.lower() and i%3==0:o.data.materials.clear();o.data.materials.append(k.material('E4CAB5','wood'))
    soften_floor_joints()
    k.KITS['boutique_floor']['collision']=[{'at':[0,-.08,0],'size':[6.1,.276,5.68]}]
    for name in ('boutique_left_wall','boutique_back_wall'):
        r.recolor(name,'DCA6AC',lambda o:o.name.split('.')[0] in ('Left boutique wall','Rear boutique wall','Left wall inset','Rear wall panel'),kind='plaster')
        r.recolor(name,'DA829A',lambda o:any(t in o.name.lower() for t in ['moulding','panel stile','panel rail']))
        for o in k.KITS[name]['objects']:
            if any(t in o.name.lower() for t in ['moulding','panel stile','panel rail']):
                o.scale.y*=1.6
                if 'vertical' in o.name.lower() or 'stile' in o.name.lower():o.scale.x*=1.6
                else:o.scale.z*=1.6
    r.clear('pink_tufted_bench')
    for x in (-.78,.78):
        for z in (-.19,.19):ellipsoid('Bench gold foot',(x,.06,z),(.13,.12,.13),'brass',10,5)
    cube('Soft bench upholstered base',(0,.31,0),(1.91,.49,.58),'CB859B',.12,'cloth')
    for i in range(4):
        for j in range(2):
            x=-.708+i*.472;z=-.148+j*.296
            cushion(x,z)
            # Dark inset and small gold button sit below the pillow shoulders.
            cylinder('Recessed tuft well',(x,.638,z),.027,.008,'B77189',vertices=10)
            cylinder('Deep tuft button',(x,.640,z),.011,.006,'C38F83',vertices=8)
    k.KITS['pink_tufted_bench']['collision']=[{'at':[0,.34,0],'size':[1.90,.68,.56]}]
    # Eight left-rail garments, distinct dresses and blouse silhouettes.
    dress_names=['hanging_dress_ivory','hanging_dress_rose','hanging_dress_cream','hanging_dress_blue','hanging_dress_mint']
    colors=['EADCCC','D995A8','E7C6AF','91B7CC','A9C4AF']
    for j,name in enumerate(dress_names):
        r.clear(name);b.garment(colors[j],'dress',False);garment_print(name,j%2==0)
        r.move(name,(-2.57,2.23,-.35-j*.275))
    for j in range(3):k.instance(dress_names[j], 'left_extra_dress_'+str(j),(-2.57,2.23,-.35-(5+j)*.275),90)
    # Seven upper garments + six lower garments, each garment owns real volume.
    for p in list(k.INSTANCES):
        if p['name']=='right_pattern_dress':
            root=k.bpy.data.objects[p['name']]
            for o in list(root.children):k.bpy.data.objects.remove(o,do_unlink=True)
            k.bpy.data.objects.remove(root,do_unlink=True);k.INSTANCES.remove(p)
    shirts=['hanging_blouse_blue','hanging_blouse_ivory','hanging_blouse_mint']
    for j,name in enumerate(shirts):r.move(name,(.62+j*.325,2.23,-2.25))
    for j in range(3,7):k.instance(shirts[j%3],'right_upper_'+str(j),(.62+j*.325,2.23,-2.25))
    r.clear('scarf_rail');tube('Lower garment rail',[(-1.10,1.12,.12),(1.10,1.12,.12)],.022,'brass',8)
    for j in range(6):k.instance(shirts[(j+1)%3],'right_lower_'+str(j),(.72+j*.355,1.25,-2.17))
    # Retain island diameter. Shift 0.4m back to clear both bench and rear rack.
    r.vertical('round_display_island',1.30);r.move('round_display_island',(-.27,.09,-.15));r.move('pink_round_rug',(-.27,.07,-.15))
    pts=[[math.cos(j*math.tau/24)*1.17,y,math.sin(j*math.tau/24)*1.17] for y in (0,1.001) for j in range(24)]
    k.KITS['round_display_island']['collision']=[{'at':[0,0,0],'points':pts}]
    for p in k.INSTANCES:
        if p['name'].startswith('island_bag_'):p['position'][1]=1.103;p['position'][2]-=.4
        if p['name']=='stacked_knit':p['position'][1]=.81;p['position'][2]-=.4
    for name in ('pink_pumps','black_pumps','folded_ivory_knit','folded_blue_knit'):
        at=k.KITS[name]['at'];r.move(name,(at[0],.68,at[2]-.4))
    r.move('island_bouquet',(-.27,1.103,-.21))
    k.instance('handbag_blue','island_bag_blue',(.12,1.103,-.66),-22)
    k.instance('handbag_pink','island_bag_coral',(-.72,1.103,-.54),20)
    begin('ivory_sneakers',at=(-1.00,.68,-.43),yaw=-90);b.shoes('EEE2D1',True)
    begin('mint_mary_janes',at=(.57,.68,-.57),yaw=60);b.shoes('A9C4AF')
    for x in (-.105,.105):tube('Mary Jane strap',[(x-.077,.132,-.005),(x,.164,-.005),(x+.077,.132,-.005)],.014,'91AF9C',6)
    k.instance('pink_pumps','cream_shoe_pair',(-.53,.68,-1.10),160)
    k.instance('folded_blue_knit','stacked_blue_knit',(.72,.79,-.18),90)
    # Jewelry includes necklace busts, rings, earrings and sunglasses.
    rec=k.KITS['jewelry_display'];k.CURRENT=rec
    for j in range(3):
        x=-.80+j*.79
        tube('Gold earring T stand',[(x,.45,.20),(x,.77,.20)],.012,'brass',6)
        tube('Gold earring crossarm',[(x-.11,.77,.20),(x+.11,.77,.20)],.012,'brass',6)
        for dx in (-.09,.09):
            b.ring('Dangling earring',(x+dx,.69,.212),.025,.049,'brass',.006)
            ellipsoid('Earring coloured stone',(x+dx,.65,.218),(.037,.055,.014),['91B7CC','D995A8','A9C4AF'][j],8,4)
        for dx in (-.065,.065):b.ring('Sunglasses lens rim',(x+dx,.47,-.17),.05,.031,'brass',.007)
        tube('Sunglasses bridge',[(x-.015,.47,-.17),(x+.015,.47,-.17)],.008,'brass',5)
    r.vertical('jewelry_display',1.10);r.vertical('jewelry_glass',1.10)
    r.recolor('standing_mirror','D4A94D',lambda o:'frame' in o.name.lower(),kind='metal')
    k.CURRENT=k.KITS['display_mannequin_dress']
    for x in (-.069,.069):ellipsoid('Mannequin waist bow',(x,-.70,.148),(.155,.11,.072),'D787A0',12,6)
    r.clear('petal_pendant');tube('Gold flower stem',[(0,0,0),(0,-.37,0)],.020,'brass',8)
    for layer,n,radius in [(0,8,.20),(1,10,.26),(2,8,.19)]:
        for j in range(n):
            a=j*math.tau/n+layer*.2
            ellipsoid('Layered luminous petal',(math.cos(a)*radius,-.45-layer*.14,math.sin(a)*radius),(.31,.25,.34),'F5E4C3',12,6)
    ellipsoid('Flower opal diffuser',(0,-.77,0),(.33,.12,.33),'FFF0C8',12,6)
    # The backdrop lives beyond the real cutout and never casts onto the room.
    begin('entrance_sky',at=(-3.18,.06,1.96),yaw=90)
    k.arch_solid('Sky seen through boutique entrance',1.34,.025,2.13,.34,.012,0,'A6CDDA')
    for j in range(7):ellipsoid('Garden canopy silhouette',(-.60+j*.20,.56+(j%3)*.14,.016),(.48,.52,.018),['8FB8AA','A9C5A3','A7CAB6'][j%3],8,4)
    from revision2 import revise as revise_r2
    revise_r2()
    r.sync_instances()

def manifest():
    p=k.OUT/'layout.json';d=json.loads(p.read_text());d['revision']='R1';d['botanical_assets']=['entrance_sky']
    d['shared_plants']=[r.plant('EntrancePlant','peace_lily',(-2.65,.07,2.53),.95,30,colliders=[{'at':[0,.23,0],'size':[.44,.46,.44]}]),r.plant('FittingPlant','monstera_woven',(-2.39,.07,-2.21),.78,60),r.plant('LeftTrailing','pothos',(-2.65,2.49,-.26),.60,90),r.plant('RightTrailing','pothos',(2.55,2.49,-2.29),.60,0)]
    d['material_overrides']={'entrance_sky':{'unshaded':True},'petal_pendant':{'emission':'FFE4B2','emission_energy':.28},'boutique_floor':{'roughness':.48},'jewelry_glass':{'alpha':.08},'entrance_glass':{'alpha':.08}}
    d['boundaries']=[{'name':'front_edge','at':[0,.6,2.94],'size':[6.2,1.8,.12]}, {'name':'right_edge','at':[3.06,.6,0],'size':[.12,1.8,5.9]}, {'name':'left_door_limit','at':[-3.12,1.4,1.96],'size':[.10,2.8,1.4]}]
    r.lighting(d,'DFA571',ambient='C6B4BB',sun='FFE2C9',energy=1.10,lamps=[{'position':[-1.63,2.9,-1.94],'color':'FFE3B6','energy':.70,'range':2.1}]+[{'position':p,'color':'FFE6BF','energy':.42,'range':1.25} for p in [[-.88,2,-2.3],[-2.60,1.68,2.64],[-2.35,2.05,-2.3],[2.70,1.92,-2.3]]])
    d['lighting']['sun_position']=[6,9,4];d['review_lighting']['sun_position']=[6,9,4];d['camera']={'position':[10,10,12],'target':[0,1.28,.08],'size':10.4}
    from boutique_bench import bench
    bench(d)
    from revision2 import manifest as manifest_r2
    manifest_r2(d)
    p.write_text(json.dumps(d,indent=2)+'\n');r.append_plants(d)
