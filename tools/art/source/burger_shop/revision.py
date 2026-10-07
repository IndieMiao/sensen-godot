"""SGODOT-184 burger diner: L counter, warm logo, stocked kitchen and clear bar aisle."""
import json,math,random
import kit as k
import series_revision as r
from kit import begin,cube,cylinder,tube,ellipsoid

def move_parts(source,target,words):
    rec=k.KITS[source];begin(target,at=rec['at'],yaw=rec['yaw']);dst=k.CURRENT
    for o in list(rec['objects']):
        if any(w in o.name for w in words):
            rec['objects'].remove(o);rec['collection'].objects.unlink(o);dst['collection'].objects.link(o);o.parent=dst['root'];dst['objects'].append(o)

def revise():
    rng=random.Random(184)
    r.remove('corner_plant')
    r.move('red_order_counter',(-.42,.06,.37))
    k.CURRENT=k.KITS['checker_floor']
    for o in k.CURRENT['objects']:
        if 'foundation' in o.name.lower():o.location.z=-.19;o.scale.z*=1.54;o.data.materials.clear();o.data.materials.append(k.material('684937'))
    r.recolor('checker_floor','DBBA91',lambda o:'checker tile' in o.name.lower())
    for i,o in enumerate(k.KITS['checker_floor']['objects']):
        if 'checker tile' in o.name.lower() and i%2:o.data.materials.clear();o.data.materials.append(k.material('E1C39F'))
    k.KITS['checker_floor']['collision']=[{'at':[0,-.08,0],'size':[6.1,.267,5.68]}]
    for name in ('left_wall','pickup_wall'):
        r.recolor(name,'A64035',lambda o:'red' in o.name.lower())
        for o in k.KITS[name]['objects']:
            if 'coping' in o.name.lower():o.scale.z*=1.50
    r.recolor('red_order_counter','AC4436',lambda o:'Red counter' in o.name)
    begin('left_counter_return',at=(-2.30,.06,1.02),collision=[{'at':[0,.54,0],'size':[.80,1.08,1.56]}])
    cube('Left return dark plinth',(0,.07,0),(.86,.16,1.59),'654B37',.06)
    cube('L return red cabinet',(0,.57,0),(.80,.92,1.54),'AC4436',.10)
    cube('L return thick cream top',(0,1.08,0),(.90,.15,1.64),'EBDCAB',.10)
    for j in range(7):cube('Return front panel seams',(.412,.57,-.67+j*.22),(.015,.80,.014),'913D32',.004)
    move_parts('red_order_counter','counter_logo_glow',['Burger badge ','Counter decorative stripe'])
    lift_logo()
    # Kitchen griddle has four irregular patties instead of a six-piece grid.
    rec=k.KITS['grill_station'];k.CURRENT=rec
    for o in list(rec['objects']):
        if 'Cooking beef patty' in o.name or 'Patty grill mark' in o.name:rec['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)
    for j,(x,z) in enumerate([(-.30,-.16),(.02,-.12),(.32,.12),(-.22,.18)]):
        radius=.115+rng.uniform(-.009,.009);cylinder('Irregular cooking patty',(x,1.078,z),radius,.058,'885338',vertices=13)
        for n in range(3):
            o=cube('Dark sear line',(x-.055+n*.05,1.110,z),(.012,.004,.13),'5F3C2B',0);o.rotation_euler.z=.2+j*.13
    # Keep the two detailed fryer baskets and prep trays; fill the upper shelf.
    rec=k.KITS['burger_warming_shelf'];k.CURRENT=rec
    cube('Second warm steel shelf',(0,.42,0),(1.46,.04,.43),'BEB9AA',.018)
    for j in range(4):
        x=-.54+j*.36;ellipsoid('Varied upper bread bun',(x,.51,0),(.27+rng.uniform(-.02,.02),.14,.25),'DEA14F',12,6)
    for x,c in [(-.48,'B65A3B'),(-.29,'DCAE38')]:
        cylinder('Shelf sauce bottle',(x,.77,0),.06,.23,c,vertices=10);cylinder('Shelf bottle cap',(x,.90,0),.025,.04,'E8D0A3',vertices=8)
    # Two bags at pickup, original four replaced without changing sill height.
    rec=k.KITS['pickup_paper_bags'];k.CURRENT=rec
    for o in list(rec['objects']):
        if o.location.x>.05:rec['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)
    for o in rec['objects']:o.location.x+=.25
    # Thick high stools are intentionally paired with the accepted 1.20 m bar.
    rec=k.KITS['red_diner_stool'];k.CURRENT=rec
    for o in rec['objects']:
        if 'seat' in o.name.lower():o.scale.z*=1.5;o.data.materials.clear();o.data.materials.append(k.material('B84739','cloth'))
        elif 'ring' in o.name.lower() or 'pedestal' in o.name.lower():o.data.materials.clear();o.data.materials.append(k.material('393D39','metal'))
    begin('counter_napkins',at=(-1.56,1.23,.32))
    cube('Napkin holder body',(0,.12,0),(.21,.24,.18),'645B4C',.025)
    for j in range(5):cube('Folded paper napkin',(-.073+j*.035,.255,0),(.025,.10,.15),'EEE7D7',.006)
    k.instance('counter_napkins','bar_napkins',(1.36,1.26,1.89))
    # All foliage is a budgeted shared placement, not uncounted leaves in a fence.
    rec=k.KITS['wood_planter_barrier']
    for o in list(rec['objects']):
        if 'greenery' in o.name.lower():rec['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)
    # Each poster gets a small distinct burger illustration under the copy.
    for name in ('good_burgers_poster','fresh_buns_poster'):
        k.CURRENT=k.KITS[name]
        ellipsoid('Poster illustrated bun',(0,-.40,.095),(.25,.10,.015),'DDA44E',12,6)
        cube('Poster illustrated filling',(0,-.445,.101),(.25,.023,.011),'738646',.006)
        ellipsoid('Poster illustrated bun base',(0,-.48,.095),(.23,.06,.015),'DDA44E',12,5)
    # Distinct opt-in emissive geometries use no shadow/projection pass.
    move_parts('wall_lamp','lamp_bulb_glow',['Warm lamp bulb'])
    for p in list(k.INSTANCES):
        if p['asset']=='wall_lamp':k.instance('lamp_bulb_glow',p['name']+'_glow',p['position'],p['yaw_degrees'])
    begin('fridge_light_glow',at=(-1.25,.06,-2.30))
    for x in (-.48,.48):cube('Fridge cold strip',(x,1.16,.665),(.023,1.88,.025),'DCEEFF',0)
    r.recolor('menu_board','8E3029',lambda o:'Red menu panel' in o.name)
    r.recolor('menu_board','372C24',lambda o:'Dark menu list' in o.name)
    r.recolor('counter_logo_glow','DDAE4A')
    add_steam()
    layout_open_path()
    r.sync_instances()

def add_steam():
    rec=k.KITS['grill_station'];begin('grill_steam',at=rec['at'],yaw=rec['yaw'])
    for j in range(3):
        points=[(-.30+j*.27+.022*math.sin(n*.9+j),1.12+n*.035,-.08+j*.075) for n in range(9)]
        tube('Soft rising steam ribbon',points,.012,'E8E5DA',5)

def lift_logo():
    for o in k.KITS['counter_logo_glow']['objects']:
        if 'Counter decorative stripe' in o.name:o.location.z+=.15
        elif abs(o.location.x)<.45:o.location.z+=.18

def layout_open_path():
    for name,at in [('red_order_counter',(-.42,.06,.04)),('counter_logo_glow',(-.42,.06,.04)),('left_counter_return',(-2.30,.06,.62)),('customer_bar',(.90,.06,1.49)),('red_diner_stool',(-.36,.065,2.08)),('counter_napkins',(-1.56,1.23,-.01))]:r.move(name,at)
    for p in k.INSTANCES:
        if p['asset']=='red_diner_stool':p['position'][2]=2.08
        if p['name']=='bar_napkins':p['position'][2]=1.49

def manifest():
    p=k.OUT/'layout.json';d=json.loads(p.read_text());d['revision']='R1'
    d['shared_plants']=[r.plant('WhiteCornerPlant','peace_lily',(2.48,.06,-2.12),1.27,35,colliders=[{'at':[0,.26,0],'size':[.60,.52,.60]}])]
    for j in range(6):d['shared_plants'].append(r.plant('FencePothos'+str(j),'pothos',(-2.88,.94,.49+j*.36),.75,90))
    d['material_overrides']={'counter_logo_glow':{'emission':'FFC567','emission_energy':.25,'unshaded':True},'lamp_bulb_glow':{'emission':'FFE7B8','emission_energy':1.3},'fridge_light_glow':{'emission':'D7EEFF','emission_energy':.8},'grill_steam':{'alpha':.20,'emission':'E8E5DA','emission_energy':.015},'menu_board':{'emission':'FFFFFF','emission_energy':.025,'emission_use_atlas':True},'drinks_glass':{'alpha':.1}}
    r.lighting(d,'D5DEBD',ambient='C6BBAA',sun='FFE0B8',energy=1.18,lamps=[{'position':[2.51,2.4,-2.1],'color':'FFCE83','energy':.85,'range':1.5},{'position':[-2.45,2.4,1.7],'color':'FFD187','energy':.8,'range':1.45},{'position':[.03,2.7,-2.1],'color':'FFE2A8','energy':.65,'range':1.3},{'position':[-1.25,1.25,-1.60],'color':'D9EFFF','energy':.45,'range':1.1}])
    d['lighting']['sun_position']=[6,9,4];d['review_lighting']['sun_position']=[6,9,4]
    d['boundaries']=[{'name':'front_edge','at':[0,.60,2.94],'size':[6.2,1.8,.12]}, {'name':'right_edge','at':[3.06,.60,0],'size':[.12,1.8,5.9]}]
    d['camera']={'position':[10,10,12],'target':[0,1.10,.04],'size':10.2}
    from burger_bench import bench
    bench(d);p.write_text(json.dumps(d,indent=2)+'\n');r.append_plants(d)
