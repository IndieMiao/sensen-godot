"""Diner R2: large three-column menu, red soda cabinet, legible posters and foliage."""
import math,json,importlib.util
import kit as k
import series_revision as r
from kit import begin,cube,cylinder,ellipsoid,tube,lathe

def graphic_burger(x,y,z,s=1):
    for name,cy,sy,c in [('Bun crown',.11,.19,'E8AB46'),('Lettuce',.012,.044,'537936'),('Beef',-.044,.055,'713D28'),('Bun base',-.12,.11,'DD9A36')]:
        o=ellipsoid('Printed burger '+name,(x,y+cy*s,z),(.45*s,sy*s,.016),c,18,7);o['atlas_constant_colour']=True
    for j in range(8):
        xj=-.15+(j%4)*.10;yj=.115+(j//4)*.045
        o=ellipsoid('Printed sesame seed',(x+xj*s,y+yj*s,z+.014),(.018*s,.009*s,.005),'FCE0A0',6,4);o['atlas_constant_colour']=True

def soda(at,index):
    x,y,z=at;color=['BF362C','287A58','357BBA','DE9D31'][index%4]
    if index%5==4:
        lathe('Sparkling soda bottle',at,[(0,.059),(.19,.064),(.24,.031),(.31,.031)],color,10)
        cylinder('Soda crown cap',(x,y+.32,z),.034,.024,'AFC3C5',vertices=10)
        cube('Bottle soda band',(x,y+.12,z+.064),(.077,.070,.005),'EAE4D2',0)['atlas_constant_colour']=True
    else:
        lathe('Soda can shaped rim',at,[(0,.061),(.015,.068),(.242,.068),(.255,.062)],color,12)
        for yy in (.008,.253):cylinder('Aluminium can end',(x,y+yy,z),.062,.009,'B8C6C4',vertices=12)
        tube('Can ring pull',[(x-.013,y+.261,z-.007),(x+.013,y+.261,z-.007),(x+.013,y+.261,z+.019),(x-.013,y+.261,z+.019),(x-.013,y+.261,z-.007)],.005,'738887',4)
        for dx in (-.021,.018):cube('Soda slanted cream flash',(x+dx,y+.136,z+.067),(.019,.085,.005),'F5D996',0)['atlas_constant_colour']=True

def menu():
    r.clear('menu_board');r.move('menu_board',(-2.82,2.50,-.40))
    cube('Dark rolled menu edge',(0,0,0),(4.65,1.18,.10),'39342C',.08)
    cube('Deep red main menu',(0,0,.064),(4.54,1.08,.055),'922D25',.06)
    cube('Dark lower menu list',(0,-.265,.099),(4.36,.56,.018),'413029',.012)
    graphic_burger(-1.82,.31,.110,1.30)
    k.text_label('BURGER BAR',(.25,.23,.105),.38,'F6DEAD')
    cube('Cream title underline',(.25,.16,.116),(3.25,.015,.012),'F6DEAD',0)
    columns=[('BURGERS',['Classic  5.90','Cheese   6.50','Bacon    7.50','Double   8.90']),('SIDES',['Fries    3.50','Onion    3.90','Bites    4.50']),('DRINKS',['Soda     2.50','Iced Tea 2.50','Lemonade 2.50','Shake    3.90'])]
    for i,(title,lines) in enumerate(columns):
        x=-2.10+i*1.45;k.text_label(title,(x,-.026,.117),.15,'F6DEAD','LEFT')
        for j,line in enumerate(lines):k.text_label(line,(x,-.19-j*.085,.117),.094,'F6DEAD','LEFT')
        if i:cube('Menu column separator',(x-.08,-.28,.115),(.012,.45,.010),'B76848',0)
def lower_warmer():
    r.move('burger_warming_shelf',(-2.76,1.32,-1.93))
    for o in k.KITS['burger_warming_shelf']['objects']:
        if 'Shelf sauce bottle' in o.name or 'Shelf bottle cap' in o.name:o.location.z-=.52

def revise():
    menu();lower_warmer()
    # The poster sits in the remaining front wall strip, with the same wall-mounted fixture.
    r.move('good_burgers_poster',(-2.82,1.95,2.42))
    for p in k.INSTANCES:
        if p['name'] in ('wall_lamp_left','wall_lamp_left_glow'):p['position']=[-2.81,2.80,2.42]
        if p['name'] in ('wall_lamp_pickup','wall_lamp_pickup_glow'):p['position']=[-.35,2.91,-2.57]
    for name,lines,width in [('good_burgers_poster',['GOOD','BURGERS','BRIGHTER','DAYS'],.64),('fresh_buns_poster',['FRESH','BUNS','BETTER','PEOPLE'],.65)]:
        r.clear(name);cube('Orange yellow slogan board',(0,0,0),(width,1.17,.07),'EAB354',.04)
        for j,line in enumerate(lines):
            size=min(.174,(width-.07)/(len(line)*.64));k.text_label(line,(0,.32-j*.176,.044),size,'A22F24')
        graphic_burger(0,-.43,.049,.80)
        for x in (-width/2+.035,width/2-.035):
            for y in (-.54,.54):ellipsoid('Slogan brass screw',(x,y,.044),(.022,.022,.010),'AC6030',8,4)
    # One hollow red body encloses the original occupied envelope, no white second case.
    r.clear('drinks_fridge')
    cube('Red cabinet back',(0,1.16,-.24),(1.13,2.32,.12),'9E352E',.045)
    for x in (-.53,.53):cube('Deep red insulated cabinet side',(x,1.16,.21),(.09,2.32,.98),'B53D31',.03)
    for y in (.10,2.23):cube('Red insulated cabinet end',(0,y,.20),(1.13,.18,1.0),'B53D31',.03)
    cube('Dark cool interior back',(0,1.16,-.174),(.96,1.94,.018),'567A77',.005)
    for row in range(4):
        y=.30+row*.43;cube('Thin refrigerator shelf',(0,y,.31),(.98,.025,.74),'ADBCB8',.008)
        for j in range(6):soda((-.40+j*.159,y+.020,.40),j+row*5)
    for x in (-.50,.50):cube('Red front door vertical rail',(x,1.16,.695),(.065,2.03,.058),'AC3429',.016)
    for y in (.165,2.15):cube('Red front door cross rail',(0,y,.695),(1.07,.065,.058),'AC3429',.015)
    tube('Fridge dark metal pull',[(.438,.96,.742),(.438,.96,.80),(.438,1.39,.80),(.438,1.39,.742)],.016,'4A4440',6)
    k.KITS['drinks_fridge']['collision']=[{'at':[0,1.15,.20],'size':[1.13,2.30,1.0]}]
    r.clear('fridge_light_glow')
    for x in (-.47,.47):cube('Cold internal LED strip',(x,1.16,.575),(.016,1.86,.020),'D9F0FF',0)
    # Dense foliage follows the same shared small-leaf shape and deep palette, without flowers/pots.
    src=k.ROOT/'assets/rooms/_shared/plants/source/build_plants.py';spec=importlib.util.spec_from_file_location('diner_shared',src);lib=importlib.util.module_from_spec(spec);spec.loader.exec_module(lib)
    begin('planter_dense_leaves',at=(-2.88,.94,.42),yaw=90);lib.shrub();rec=k.CURRENT
    for o in list(rec['objects']):
        if 'petal' in o.name.lower() or 'daisy' in o.name.lower():rec['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)
        else:
            o['atlas_constant_colour']=True
            for v in o.data.vertices:v.co.x*=.65;v.co.y*=.65;v.co.z*=1.35
    for i in range(1,8):k.instance('planter_dense_leaves','planter_crown_'+str(i),(-2.88,.94,.42+i*.30),90+i*37)
    r.sync_instances()

def manifest(d):
    d['revision']='R2';d['botanical_assets']=['planter_dense_leaves']
    d['shared_plants']=[p for p in d['shared_plants'] if not p['name'].startswith('FencePothos')]
    d['material_overrides']['drinks_glass']={'alpha':.045}
    d['material_overrides']['menu_board']['emission_energy']=.045
    for field,key in [('lighting','lamps'),('review_lighting','points')]:
        # These two lists initially alias; copy before adding this scene's kitchen light.
        d[field][key]=[dict(p) for p in d[field][key]]
        for p in d[field][key]:
            if p['position']==[-2.45,2.4,1.7]:p['position']=[-2.45,2.57,2.42]
            if p['position']==[.03,2.7,-2.1]:p['position']=[-.35,2.7,-2.1]
        d[field][key].append({'position':[-1.85,2.35,-1.30],'color':'FFD498','energy':.42,'range':2.0})
    d['bench']['scale']['door']={'applicable':False,'reason':'Open front diorama; no doorway is modeled, so there is no door-height measurement.'}
    from liubei_r2 import fit_camera
    fit_camera(d,(1544,1544),[(41,1015),(677,1456),(1498,1127)],footprint=(6.16,5.76),plinth_y=-.4056)
    d['review_views']=[{'name':'menu-kitchen-detail','position':[3.4,3.9,4.0],'target':[-1.95,1.95,-.65],'size':4.4},{'name':'soda-poster-detail','position':[3.2,3.1,4.8],'target':[.50,1.56,-2.03],'size':4.0}]
