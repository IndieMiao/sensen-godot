"""SGODOT-180 reviewed pink/lavender architecture and prop revision."""
import math,json,random
import kit as k
import storefront as s
import series_revision as r
from kit import begin,cube,cylinder,tube,ellipsoid

def revise():
    # Remove the original heavy plants; shared R2.1 forms supply all living foliage.
    for name in ('corner_plant','trailing_wall_plant','flower_wall_ivy'):r.remove(name)
    r.recolor('back_wall','F2CCCA');r.recolor('left_door_wall','F2CCCA')
    for name in ('back_wall','left_door_wall'):
        rec=k.KITS[name];k.CURRENT=rec
        for o in list(rec['objects']):
            if 'brick' in o.name.lower():rec['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)
        spans=[(-3.0,3.0)] if name=='back_wall' else [(-2.70,-1.65),(-.15,2.90)]
        r.brick_panel('Staggered pink-white long brick',spans,9,2.91,.78,.12,['F2D6D0','F5DCD4','EDCCC8','F7DDD2'])
        r.recolor(name,'F6E3E1',lambda o:'coping' in o.name.lower() or 'lintel' in o.name.lower())
        r.recolor(name,'BCD3B9',lambda o:'Open pastel' in o.name)
    for name in ('front_wall_left','front_wall_right','side_low_wall'):
        r.recolor(name,'F1D0CE');r.recolor(name,'D6ACD5',lambda o:'coping' in o.name.lower())
    r.recolor('corner_pier','C8A0D4');r.recolor('corner_pier','F5DCE1',lambda o:'cap' in o.name)
    r.clear('floor');cube('Pink foundation',(0,-.12,0),(6.18,.27,5.68),'EAC1C1',.12)
    cube('Rose grout bed',(0,.018,0),(6.03,.032,5.55),'D8A9B6',.018)
    rng=random.Random(180)
    for i in range(12):
        for j in range(11):
            x=-2.75+i*.5;z=-2.50+j*.5
            cube('Pink porcelain large square tile',(x,.028,z),(.492,.05,.492),rng.choice(['F5DCD4','F4D6D0','F8E3D9']),.045)
            if i<11 and j<10:
                o=cube('Lavender diamond at four-tile junction',(x+.25,.051,z+.25),(.115,.008,.115),'CEAAD0',.009);o.rotation_euler.z=math.pi/4
    r.recolor('cafe_table','F4E4DD',lambda o:'tabletop' in o.name)
    r.vertical('cafe_table',1.20);r.vertical('chair',1.13)
    r.recolor('chair','DEABB9',lambda o:'cushion' in o.name.lower())
    for name in ('table_flower_vase',):r.move(name,(-1.45,1.104,.63))
    for p in k.INSTANCES:
        if p['name']=='table_flower_vase_2':p['position'][1]=1.104
    r.clear('pastel_bench')
    cube('Lavender upholstered bench frame',(0,.42,0),(1.65,.40,.52),'B998C5',.06)
    for ix in range(4):
        for iz in range(2):cube('Square puff bench cushion',(-.60+ix*.40,.57,-.125+iz*.25),(.393,.18,.243),'CAA4D5',.053,'cloth')
    cube('Continuous lavender padded back',(0,.87,.22),(1.64,.60,.13),'D0ADD8',.055,'cloth')
    for x,tone in ((-.52,'E7B4BC'),(-.11,'B8D6C5')):cube('Loose pastel pillow',(x,.87,.09),(.37,.37,.15),tone,.067,'cloth')
    k.KITS['pastel_bench']['collision']=[{'at':[0,.40,0],'size':[1.68,.80,.56]}]
    r.recolor('drinks_fridge','A3C4B4',lambda o:'body' in o.name.lower())
    k.CURRENT=k.KITS['drinks_fridge']
    for x,y in ((-.25,2.38),(.20,2.42)):
        cube('Tea supply carton',(x,y,0),(.33,.22,.29),'C99964',.015,'wood')
        cube('Carton paper seal',(x,y+.116,0),(.055,.007,.29),'EED5AE',.001)
    begin('fridge_glass',at=(-2.30,.06,-1.94));cube('Clear cold cabinet door',(0,1.17,.49),(.91,1.86,.006),'C3E0D5',0)
    # Tea liquid is inset inside the thin transparent tank rather than opaque solid glass.
    for o in k.KITS['tea_urns']['objects']:
        if 'Beverage tank' in o.name:o.scale.x*=.90;o.scale.y*=.90;o.scale.z*=.80;o.location.z-=.045
    begin('urn_glass',at=(.16,1.26,-2.09))
    for x in (-.35,0,.35):k.lathe('Transparent tea tank',(x,.14,0),[(0,.127),(.60,.127)],'DCE9DF',20)
    k.CURRENT=k.KITS['syrup_shelf']
    for o in k.CURRENT['objects']:
        if 'bottle' in o.name.lower() or 'pump' in o.name.lower():
            o.location.x+=.015*math.sin(o.location.x*31);o.scale.z*=1+.1*math.sin(o.location.x*12)
    # Six generous topping bays, irregular fruit/pearls surfaces baked as source geometry.
    r.clear('topping_case');cube('Recessed ingredient cooler',(0,.05,0),(1.70,.10,.60),'B7B9AC',.025)
    for i,tone in enumerate(['604436','D9A448','D19FC5','D77D92','D9D894','EDD5A8']):
        x=-.54+(i%3)*.54;z=-.14+(i//3)*.28
        cube('Steel topping tray',(x,.11,z),(.51,.05,.26),'D2D1BE',.013)
        cube('Visible topping fill',(x,.14,z),(.46,.028,.215),tone,.016)
        for j in range(10):ellipsoid('Loose topping piece',(x+rng.uniform(-.20,.20),.173,z+rng.uniform(-.085,.085)),(.053,.044,.047),tone,6,3)
    for x in (-.87,.87):tube('Sloping glass rail',[(x,.09,.32),(x,.29,.32),(x,.49,-.20)],.013,'B1B3AB',6)
    # Menu cup illustrations are planar relief on the existing wood framed cards.
    for name in ('main_menu','toppings_menu'):
        rec=k.KITS[name];k.CURRENT=rec
        for o in rec['objects']:
            if o.name.startswith('Lettering '):o.location.x+=.25;o.scale*=.86
        x=-.66 if name=='main_menu' else -.50
        cube('Milk tea illustration cup',(x,-.06,.085),(.25,.37,.012),'DEADA0',.015)
        tube('Printed tea straw',[(x,-.02,.103),(x-.025,.25,.103)],.009,'8D664B',5)
        for j in range(5):ellipsoid('Printed tapioca pearl',(x-.06+(j%2)*.10,-.19+(j//2)*.048,.099),(.036,.036,.006),'71513E',6,3)
    # Wall logo and lit green-brass sconce mounted to the actual left wall.
    begin('left_tea_logo',at=(-2.85,1.78,1.23),yaw=90)
    for rad,dep,tone in ((.40,.05,'C99A5D'),(.36,.07,'F1D2B2')):
        o=cylinder('Round tea badge',(0,0,dep),rad,.05,tone,vertices=32);o.rotation_euler.x=math.pi/2
    cube('Cup illustration',(0,-.035,.11),(.24,.34,.02),'E5B4BC',.025)
    tube('Badge straw',[(0,.06,.13),(.035,.31,.13)],.012,'7F6441',6)
    for j in range(6):ellipsoid('Badge pearl',(-.065+(j%3)*.065,-.15+(j//3)*.06,.13),(.04,.04,.02),'634D3C',6,3)
    tube('Curved sconce arm',[(0,.67,-.01),(0,.72,.18),(0,.58,.25)],.023,'735F3C',8)
    k.lathe('Mint sconce shade',(0,.46,.25),[(0,.14),(.06,.13),(.13,.05)],'87A38B',24)
    ellipsoid('Sconce warm bulb',(0,.445,.25),(.13,.042,.13),'FFE2B0',12,6,'fire')
    r.recolor('entry_step','C49BCF',lambda o:'mat' in o.name.lower())
    k.CURRENT=k.KITS['entry_step'];cube('Lower rounded entry tread',(0,-.065,.33),(2.06,.13,.65),'F2D9D6',.045)
    polish()
    r.sync_instances()

def polish():
    # Let the accepted-height seat read above the low wall; remove the tall rear slab.
    r.vertical('front_wall_left',.63)
    rec=k.KITS['pastel_bench'];k.CURRENT=rec
    for o in list(rec['objects']):
        if 'Continuous lavender padded back' in o.name:
            rec['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)
        elif 'Loose pastel pillow' in o.name:o.location.x-=.20
    r.recolor('corner_pier','D5A5CF',lambda o:'block' in o.name.lower())
    for name in ('front_wall_right','side_low_wall','front_wall_left'):
        r.recolor(name,'EBCBBF',lambda o:'masonry' in o.name.lower())
        r.recolor(name,'DAB4D0',lambda o:'coping' in o.name.lower())
    for name in ('left_door_wall','back_wall'):
        r.recolor(name,'F0D7CD',lambda o:'brick' in o.name.lower())
    r.recolor('floor','EDC7B8',lambda o:'large square tile' in o.name)

def manifest():
    p=k.OUT/'layout.json';d=json.loads(p.read_text());d['revision']='R1'
    plants=[r.plant('MonsteraCorner','monstera',(-2.54,.06,-.54),1.0,20,colliders=[{'at':[0,.28,0],'size':[.57,.56,.57]}])]
    for i,x in enumerate((-2.60,2.64)):
        plants.append(r.plant('WallPothos'+str(i),'pothos',(x,2.70,-2.39),1.15))
    for i,(x,z) in enumerate(((-2.57,2.61),(-1.01,2.65),(1.40,2.63),(2.07,2.64),(2.72,2.62),(2.92,1.92),(2.93,1.21))):
        plants.append(r.plant('FlowerBox'+str(i),'flower_shrub',(x,.80,z),.84,yaw=i*29))
        plants.append(r.plant('FlowerDrape'+str(i),'ivy_short',(x,.95,z+.16),.75,roll=i%3*7))
    d['shared_plants']=plants
    d['material_overrides']={'floor':{'roughness':.46},'urn_glass':{'alpha':.12},'fridge_glass':{'alpha':.07}}
    r.front_entry(d);r.lighting(d,'E3AF96',ambient='C8BFB6',sun='FFE4C3',energy=1.20,lamps=[{'position':[-2.46,2.30,1.27],'color':'FFE1AB','energy':.65,'range':1.6}])
    d['lighting']['sun_position']=[6,9,4];d['review_lighting']['sun_position']=[6,9,4]
    d['camera']={'position':[10.8,10.6,11.4],'target':[0,1.24,.05],'size':9.4}
    from milk_bench import bench
    bench(d)
    p.write_text(json.dumps(d,indent=2)+'\n');r.append_plants(d)
