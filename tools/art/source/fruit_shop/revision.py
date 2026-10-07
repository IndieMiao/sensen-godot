"""SGODOT-182: plaster, tilted produce crates and the accepted shared botanical kit."""
import math,random,json
from mathutils import Matrix,Vector
import kit as k
import storefront as s
import series_revision as r
from kit import begin,cube,cylinder,tube,ellipsoid,mesh,lathe
KINDS=['orange','lemon','fig','peach','grape']

def fruit(kind):
    tone={'orange':'EC922D','lemon':'E9CE35','fig':'70537F','peach':'EEAD70','grape':'725487'}[kind]
    if kind=='grape':
        for j in range(8):
            a=j*2.399;rr=.047 if j<5 else .027
            # Eight octahedral berries = 64 triangles per bunch, plus stem and leaf.
            x,z=math.cos(a)*rr,math.sin(a)*rr;y=.055+(j%3)*.045
            vs=[(x+.045,y,z),(x-.045,y,z),(x,y+.048,z),(x,y-.048,z),(x,y,z+.044),(x,y,z-.044)]
            mesh('Low-poly grape berry',vs,[(0,2,4),(4,2,1),(1,2,5),(5,2,0),(0,4,3),(4,1,3),(1,5,3),(5,0,3)],tone,smooth=True)
    else:
        o=ellipsoid('Reusable '+kind,(0,.103,0),(.235 if kind=='lemon' else .19,.22 if kind=='fig' else .20,.16 if kind=='lemon' else .19),tone,8,4)
        if kind=='fig':
            for v in o.data.vertices:
                if v.co.z>.1:v.co.x*=1-v.co.z*.6;v.co.y*=1-v.co.z*.6
        if kind=='peach':
            o.data.materials.append(k.material('E38F8E'))
            for poly in o.data.polygons:
                if poly.center.x>0:poly.material_index=1
    # 8 stem triangles and 4 folded leaf triangles; all fruit <= 80.
    mesh('Fruit stem',[(x,y,z) for y in (.19,.232) for x,z in [(-.006,-.004),(.006,-.004),(0,.006)]],[(0,1,2),(3,5,4),(0,3,4,1),(1,4,5,2),(2,5,3,0)],'756346')
    mesh('Folded fruit leaf',[(0,.227,0),(.055,.259,-.025),(.105,.249,.008),(.049,.232,.031),(.055,.255,.005)],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],'718949')

def clone_fruit(kind,at,scale,yaw):
    for src in k.KITS['fruit_'+kind]['objects']:
        o=src.copy();o.data=src.data;k.CURRENT['collection'].objects.link(o);o.parent=k.CURRENT['root'];o.name='Heap '+kind
        rot=Matrix.Rotation(yaw,4,'Z');trans=Matrix.Translation(k.v(at));sz=Matrix.Diagonal((scale,scale,scale,1));o.matrix_basis=trans@rot@sz@src.matrix_basis;k.CURRENT['objects'].append(o)

def produce_crate(kind,rng,tilted=True):
    s.crate()
    for layer in range(2):
        for row in range(3 if layer==0 else 2):
            for col in range(3 if layer==0 else 2):
                clone_fruit(kind,(-.25+col*.245+layer*.12+rng.uniform(-.025,.025),.14+layer*.155,-.19+row*.18+layer*.08+rng.uniform(-.018,.018)),rng.uniform(.94,1.18),rng.uniform(-math.pi,math.pi))
    if tilted:
        mat=Matrix.Translation(k.v((0,.12,0)))@Matrix.Rotation(math.radians(20),4,'X')
        for o in k.CURRENT['objects']:o.matrix_basis=mat@o.matrix_basis

def plaster_low_walls(rng):
    for name,width in [('front_wall_left',1.95),('front_wall_right',1.65),('side_low_wall',5.28)]:
        rec=k.KITS[name];k.CURRENT=rec
        for o in list(rec['objects']):
            if 'masonry' in o.name.lower():rec['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)
        cube('Continuous white lime plaster',(0,.32,0),(width,.64,.30),'E8DEC8',.045)
        for j in range(max(3,int(width/.45))):
            x=-width/2+.18+j*.45
            if x>width/2-.1:continue
            for z in (-.16,.16):
                cube('Exposed limestone in lower plaster',(x,.14+(j%2)*.31,z),(rng.uniform(.22,.39),rng.uniform(.17,.29),.035),'D8C5A7',.042)

def revise():
    rng=random.Random(182)
    for name in ('olive_planter','flower_border','doorway_vine'):r.remove(name)
    # Keep original architectural dimensions; exposed stones occupy only selected edges.
    for name in ('back_wall','left_door_wall'):
        rec=k.KITS[name];k.CURRENT=rec
        for o in list(rec['objects']):
            if 'brick' in o.name.lower():rec['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)
        r.recolor(name,'E9E3D5')
        r.recolor(name,'C9825D',lambda o:any(w in o.name.lower() for w in ['coping','lintel']))
        for i in range(22):
            x=rng.choice([-2.82,2.78])+rng.uniform(-.15,.12) if i<12 else rng.uniform(-2.7,2.7)
            y=.22+(i%6)*.44 if i<12 else rng.uniform(.13,.53)
            if name=='left_door_wall' and -.38<x<1.18:continue
            o=cube('Irregular exposed edge limestone',(x,y,.123),(rng.uniform(.22,.44),rng.uniform(.18,.38),.105),rng.choice(['CFB899','DBC4A3','D9C2A2']),.065)
            o.rotation_euler.y=rng.uniform(-.10,.10)
        if name=='left_door_wall':r.recolor(name,'DDC4A3',lambda o:'doorway' in o.name.lower())
    for name in ('front_wall_left','front_wall_right','side_low_wall','corner_pier'):
        r.recolor(name,'E8DEC8');r.recolor(name,'C9825D',lambda o:'coping' in o.name.lower() or 'cap' in o.name.lower())
    plaster_low_walls(rng)
    k.KITS['side_low_wall']['collision']=[{'at':[0,.38,0],'size':[5.28,.76,.30]}]
    r.recolor('floor','D79358',lambda o:'floorboard' in o.name.lower(),kind='wood')
    for kind in KINDS:
        begin('fruit_'+kind,at=(-1.78+KINDS.index(kind)*.95,1.09,-.77));fruit(kind)
        r.clear('crate_'+kind);produce_crate(kind,rng)
    # Floor baskets stay flat and have explicit collision instead of using tilted display crates.
    k.INSTANCES[:]=[p for p in k.INSTANCES if not p['name'].startswith('floor_')]
    for name,kind,at in [('floor_orange_crate','orange',(-1.36,.064,1.10)),('floor_fig_crate','fig',(1.35,.064,1.54))]:
        old=k.bpy.data.objects.get(name)
        if old:
            for o in list(old.children):k.bpy.data.objects.remove(o,do_unlink=True)
            k.bpy.data.objects.remove(old,do_unlink=True)
        begin(name,at=at,collision=[{'at':[0,.27,0],'size':[.90,.54,.70]}]);produce_crate(kind,rng,False)
    r.clear('striped_awning');s.awning(4.04,.66,('EEE6D3','DCCCAD'))
    r.recolor('blue_shutter','4D7698',lambda o:'hinge' not in o.name.lower())
    k.KITS['blue_shutter']['yaw']=-17;k.KITS['blue_shutter']['root'].rotation_euler.z=math.radians(-17)
    for p in k.INSTANCES:
        if p['name']=='blue_shutter_2':p['rotation_degrees']=[0,21,0];p['yaw_degrees']=21
        if p['name']=='blue_shutter_3':p['position']=[2.54,1.70,-2.10];p['yaw_degrees']=-8
    # Silver bowl and a red dial ring, without expensive glass/refraction.
    r.recolor('analog_scale','B35949',lambda o:'housing' in o.name.lower())
    r.recolor('analog_scale','BFC4C4',lambda o:'bowl' in o.name.lower(),kind='metal')
    k.CURRENT=k.KITS['orchard_market_sign']
    tube('Iron wall lamp arm',[(-.44,.64,0),(-.44,.92,.06),(.33,.92,.17),(.33,.70,.17)],.025,'494943',7)
    lathe('Dark iron shade',(.33,.68,.17),[(0,.16),(.04,.17),(.11,.07),(.14,.04)],'4F5047',16)
    o=cylinder('Illustrated orange',(0,-.22,.09),.17,.012,'E8A14B',vertices=16);o.rotation_euler.x=math.pi/2
    tube('Orange painted twig',[(.04,-.06,.10),(.08,.045,.10)],.011,'7D8654',5)
    mesh('Illustrated leaf',[(.05,.0,.105),(.19,.04,.105),(.15,-.045,.105)],[(0,1,2)],'7D8654')
    r.recolor('entry_step','BD8D50',lambda o:'mat' in o.name.lower());k.CURRENT=k.KITS['entry_step']
    cube('Lower ivory tread',(0,-.065,.33),(2.06,.13,.65),'EFE5D2',.045)
    for j in range(17):cube('Woven mat stitch',(-.50+j*.062,.160,0),(.013,.006,.43),'D3AD71',0)
    # Hanging herb geometry counts as botanical and never casts leaf shadows.
    rec=k.KITS.pop('hanging_herbs');rec['root'].name='hanging_herbs_leaves';rec['collection'].name='KIT_hanging_herbs_leaves';k.KITS['hanging_herbs_leaves']=rec
    from revision2 import revise as revise_r2
    revise_r2()
    r.sync_instances()
    for p in k.INSTANCES:
        k.bpy.data.objects[p['name']].rotation_euler.z=math.radians(p.get('yaw_degrees',0))

def manifest():
    p=k.OUT/'layout.json';d=json.loads(p.read_text());d['revision']='R1'
    plants=[r.plant('LeftOlive','olive_tree',(-2.43,.07,1.13),1.0,35,colliders=[{'at':[0,.30,0],'size':[.66,.60,.66]}]),r.plant('RightOlive','olive_tree',(2.48,.07,-1.95),1.0,120,colliders=[{'at':[0,.30,0],'size':[.66,.60,.66]}]),r.plant('ShelfPothos','pothos',(-1.30,1.93,-2.08),.65,30),r.plant('ShelfHerb','pothos',(.78,1.37,-2.05),.75,10)]
    for i,(x,z) in enumerate([(-2.55,2.68),(-1.92,2.68),(-1.32,2.68),(1.64,2.68),(2.3,2.68)]+[(3.0,z) for z in [-1.38,-.63,.12,.87,1.62,2.33]]):plants.append(r.plant('WallFlower%02d'%i,'flower_shrub',(x,.74,z),.86,i*31))
    for i,z in enumerate([-1.15,-1.32]):plants.append(r.plant('DoorWhiteVine'+str(i),'ivy_long',(-2.84,2.98,z),1.1,90))
    for i,x in enumerate([-2.40,-1.71]):plants.append(r.plant('BackWhiteVine'+str(i),'ivy_medium',(x,2.99,-2.56),1.06,0))
    d['shared_plants']=plants;r.front_entry(d)
    r.lighting(d,'A3D5DF',ambient='AABDD2',sun='FFE1BD',energy=1.42)
    d['lighting']['sun_position']=[6,9,4];d['review_lighting']['sun_position']=[6,9,4];d['camera']={'position':[10,10,12],'target':[0,1.05,.15],'size':10.2}
    from fruit_bench import bench
    bench(d)
    from revision2 import manifest as manifest_r2
    manifest_r2(d)
    p.write_text(json.dumps(d,indent=2)+'\n');r.append_plants(d)
