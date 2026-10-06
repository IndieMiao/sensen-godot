"""SGODOT-184: red burger diner with a real pickup aperture and modular kitchen."""
from pathlib import Path
import sys,math,random
sys.path.insert(0,str(Path(__file__).resolve().parent/'source/coffee_shop'))
import kit as k
import storefront as s
from kit import begin,cube,cylinder,tube,ellipsoid,lathe,leaf
RED='B94E3D';STEEL='AEA89A'

def burger(at=(0,0,0),scale=1):
    x,y,z=at;t=scale
    cylinder('Toasted bottom bun',(x,y+.03*t,z),.13*t,.06*t,'D5A04B',vertices=20)
    cylinder('Beef patty',(x,y+.078*t,z),.135*t,.055*t,'805039',vertices=20)
    for j in range(8):
        a=j*math.tau/8
        ellipsoid('Ruffled lettuce',(x+math.cos(a)*.09*t,y+.112*t,z+math.sin(a)*.09*t),(.13*t,.035*t,.12*t),'8CA643',12,5)
    cheese=cube('Cheese slice',(x,y+.137*t,z),(.245*t,.016*t,.245*t),'EDC052',.008*t);cheese.rotation_euler.z=.25
    ellipsoid('Sesame crown',(x,y+.177*t,z),(.279*t,.145*t,.279*t),'E3AC58',20,12)
    for j in range(15):
        a=j*2.399;r=.10*t*math.sqrt((j+1)/15)
        ellipsoid('Sesame seed',(x+math.cos(a)*r,y+.18*t+math.sqrt(max(0,1-(r/(.14*t))**2))*.071*t,z+math.sin(a)*r),(.018*t,.007*t,.009*t),'porcelain',6,4)

def sauce(at,c):
    lathe('Squeeze bottle',at,[(0,.05),(.035,.06),(.23,.06),(.28,.044),(.30,.022),(.39,.010)],c,16)

def badge(at,size=.45,color='EFC163'):
    x,y,z=at
    ellipsoid('Burger badge bun',(x,y+.095*size,z),(.85*size,.36*size,.045),color,20,8)
    cube('Burger badge filling',(x,y-.04*size,z),(.81*size,.075*size,.038),color,.018)
    ellipsoid('Burger badge base',(x,y-.17*size,z),(.78*size,.19*size,.04),color,20,6)

def cabinet(width=1.0):
    cube('Stainless cabinet',(0,.49,0),(width,.92,.76),STEEL,.035)
    cube('Work surface',(0,.98,0),(width+.035,.065,.81),'C6C0AE',.025)
    for x in (-width*.235,width*.235):
        cube('Equipment cabinet door',(x,.45,.39),(width*.455,.76,.026),'ABA494',.02)
        tube('Metal cabinet handle',[(x,.59,.414),(x,.59,.449),(x,.77,.449),(x,.77,.414)],.012,'porcelain',6)
    cube('Equipment toe kick',(0,.06,0),(width-.07,.12,.68),'iron',.014)


def geometry():
    k.PALETTE.update({'porcelain':'EFE2C5','oak':'BA8650','oak_light':'D7A564','terra':RED,'iron':'4C4439','iron_edge':'706150'})
    begin('checker_floor',collision=[{'at':[0,-.10,0],'size':[6.10,.25,5.68]}])
    cube('Diner foundation',(0,-.115,0),(6.16,.28,5.76),'76604D',.13)
    for i in range(12):
        for j in range(11):cube('Warm checker tile',(-2.75+i*.5,.027,-2.50+j*.5),(.491,.053,.491),'DABC92' if (i+j)%2 else 'E8D6B5',.012)
    begin('left_wall',at=(-3,.06,0),yaw=90,collision=[{'at':[0,1.51,0],'size':[5.55,3.02,.20]}])
    cube('Cream diner wall',(0,1.50,0),(5.58,3,.20),'E8D6B7',.07)
    cube('Red wall coping',(0,3.02,0),(5.65,.18,.32),RED,.075)
    cube('Red dado rail',(0,.95,.12),(5.58,.14,.09),RED,.028)
    cube('Dado panel backing',(0,.47,.13),(5.56,.82,.07),RED,.015)
    for j in range(28):cube('Red dado vertical seam',(-2.67+j*.20,.47,.172),(.021,.77,.025),'913D32',.006)
    begin('pickup_wall',at=(0,.06,-2.75),collision=[{'at':[-1.5,1.50,0],'size':[3,3,.20]},{'at':[2.44,1.50,0],'size':[1.12,3,.20]},{'at':[.94,.55,0],'size':[1.88,1.10,.20]}])
    # Construct around the pickup opening; no filled slab behind it.
    for at,size in [((-1.5,1.5,0),(3,3,.20)),((2.44,1.5,0),(1.12,3,.20)),((.94,.55,0),(1.88,1.10,.20)),((.94,2.68,0),(1.88,.64,.20))]:cube('Pickup wall masonry',at,size,'E8D6B7',.023)
    cube('Rear red coping',(0,3.02,0),(6.12,.18,.32),RED,.065)
    cube('Pickup red dado',(1.06,.49,.13),(3.88,.89,.08),RED,.015)
    for j in range(19):cube('Rear dado vertical seam',(-.74+j*.20,.49,.18),(.024,.83,.025),'913D32',.006)
    begin('pickup_window',at=(.94,.06,-2.60))
    for x in (-.92,.92):cube('Pickup timber jamb',(x,1.73,0),(.10,1.33,.30),'oak',.023)
    cube('Pickup cream sill',(0,1.12,.06),(2.03,.13,.51),'porcelain',.054)
    cube('Pickup header',(0,2.37,0),(2.03,.12,.31),'oak',.025)
    begin('pickup_canopy',at=(.94,2.56,-2.58));s.awning(2.07,.58,('porcelain',RED))
    s.menu('pickup_sign',(.94,2.78,-2.46),'PICK UP HERE',[],2.02,.36,RED,'porcelain')
    begin('pickup_paper_bags',at=(.94,1.25,-2.55))
    for j in range(4):
        x=-.61+j*.40
        cube('Kraft takeaway bag',(x,.20,0),(.31,.40,.20),'D5B073',.018)
        cube('Folded paper bag mouth',(x,.40,0),(.32,.040,.17),'C99C5D',.012)
        badge((x,.20,.109),.23,RED)
    s.fridge((-1.25,.06,-2.30),'',RED)
    k.CURRENT=k.KITS['drinks_fridge']
    for o in k.CURRENT['objects']:
        if 'Cabinet door edge' in o.name or 'Refrigerator handle' in o.name:o.location.y-=.25
    for x in (-.54,.54):cube('Chiller insulated side extension',(x,1.16,.48),(.07,1.97,.37),RED,.02)
    for y in (.18,2.15):cube('Chiller front door crossrail',(0,y,.70),(1.08,.06,.07),'porcelain',.02)
    begin('drinks_glass',at=(-1.25,.06,-2.30));cube('Cold drinks door glazing',(0,1.16,.70),(.94,1.85,.012),'porcelain',0)
    begin('grill_station',at=(-2.45,.06,-.28),yaw=90,collision=[{'at':[0,.55,0],'size':[1.17,1.10,.81]}]);cabinet(1.17)
    cube('Griddle cast plate',(0,1.024,0),(1.075,.045,.70),'iron',.025)
    for x in (-.53,.53):cube('Griddle raised rim',(x,1.06,0),(.024,.079,.70),STEEL,.01)
    for j in range(6):
        x=-.36+(j%3)*.36;z=-.19+(j//3)*.38
        cylinder('Cooking beef patty',(x,1.075,z),.12,.055,'976345',vertices=16)
        for n in range(3):cube('Patty grill mark',(x-.057+n*.053,1.105,z),(.011,.003,.135),'704A35',.002)
    for x in (-.40,0,.40):
        knob=cylinder('Griddle control',(x,.85,.42),.041,.032,'iron',vertices=16);knob.rotation_euler.x=math.pi/2
    cube('Extractor metal hood',(0,1.80,-.18),(1.23,.23,.52),'BBB4A4',.055)
    cube('Extractor underside',(0,1.67,-.17),(1.05,.024,.38),'iron_edge',.01)
    for j in range(3):
        x=-.37+j*.21
        tube('Hanging spatula handle',[(x,1.66,-.32),(x,1.42,-.32)],.012,'iron',6)
        cube('Spatula blade',(x,1.34,-.31),(.088,.14,.018),STEEL,.018)
    begin('fryer_station',at=(-2.45,.06,-1.44),yaw=90,collision=[{'at':[0,.56,0],'size':[1.09,1.12,.81]}]);cabinet(1.09)
    for x in (-.26,.26):
        cube('Fryer basin',(x,1.034,0),(.48,.040,.65),'iron',.019)
        for z in (-.28,.28):tube('Basket top long rim',[(x-.20,1.20,z),(x+.20,1.20,z)],.012,STEEL,6)
        for bx in (x-.20,x+.20):tube('Basket end rim',[(bx,1.20,-.28),(bx,1.20,.28)],.012,STEEL,6)
        for j in range(8):
            bx=x-.19+j*.055
            tube('Wire fryer basket',[(bx,1.20,-.28),(bx,1.065,-.25),(bx,1.065,.25),(bx,1.20,.28)],.004,STEEL,4)
        for j in range(16):
            o=cube('French fry',(x+random.uniform(-.16,.16),1.13+random.random()*.05,random.uniform(-.20,.20)),(.020,.024,.18),'EAC162',.004);o.rotation_euler.z=random.uniform(-.6,.6)
        tube('Basket handle',[(x,1.20,.28),(x,1.28,.39),(x,1.28,.61)],.018,'iron',6)
    begin('prep_station',at=(-2.45,.06,-2.38),yaw=90,collision=[{'at':[0,.53,0],'size':[.76,1.06,.81]}]);cabinet(.76)
    for j,c in enumerate(('789A46','C16B46','DDB64D','A9778D')):
        x=-.19+(j%2)*.38;z=-.17+(j//2)*.34
        cube('Ingredient tray inset',(x,1.034,z),(.34,.04,.29),'iron_edge',.014)
        for n in range(7):ellipsoid('Prep ingredient',(x+random.uniform(-.10,.10),1.08,z+random.uniform(-.07,.07)),(.085,.035,.08),c,8,5)
    begin('burger_warming_shelf',at=(-2.76,1.48,-1.93),yaw=90)
    cube('Warming shelf',(0,0,0),(1.46,.048,.46),STEEL,.023)
    for j in range(4):burger((-.54+j*.36,.03,0),.95)
    begin('menu_board',at=(-2.82,2.31,-1.30),yaw=90)
    cube('Dark menu edge',(0,0,0),(3.22,1.16,.10),'iron',.09)
    cube('Red menu panel',(0,0,.06),(3.13,1.07,.06),RED,.075)
    cube('Dark menu list',(0,-.18,.095),(3.0,.65,.022),'4D392F',.015)
    k.text_label('BURGER BAR',(.25,.27,.111),.29,'porcelain')
    badge((-1.23,.27,.115),.46)
    menus=[('BURGERS',['Classic Burger     5.90','Cheese Burger      6.50','Bacon Burger       7.50','Double Burger      8.90']),('SIDES',['Fries               3.50','Onion Rings         3.90','Chicken Bites       4.50']),('DRINKS',['Soda                2.50','Iced Tea            2.50','Lemonade            2.50','Milkshake           3.90'])]
    for i,(title,lines) in enumerate(menus):
        x=-1.43+i*1.02
        k.text_label(title,(x,.012,.12),.11,'porcelain','LEFT')
        for j,line in enumerate(lines):k.text_label(line,(x,-.13-j*.089,.12),.070,'porcelain','LEFT')
        if i:cube('Menu column divider',(x-.06,-.20,.117),(.009,.48,.012),'C38362',.002)
    begin('red_order_counter',at=(-.42,.06,.78),collision=[{'at':[0,.54,0],'size':[4.48,1.08,.74]}])
    cube('Counter dark plinth',(0,.07,0),(4.55,.16,.81),'iron_edge',.075)
    cube('Red counter cabinet',(0,.57,0),(4.46,.92,.73),RED,.10)
    for j in range(24):cube('Counter red panel seam',(-2.15+j*.185,.57,.372),(.012,.79,.025),'913D32',.005)
    cube('Golden cream countertop',(0,1.08,0),(4.64,.15,.88),'EBDCAB',.10)
    badge((0,.59,.395),.67)
    for x in (-1.09,1.09):
        for y in (.48,.67):cube('Counter decorative stripe',(x,y,.40),(.74,.035,.020),'F9D681',.012)
    cube('Register base',(-1.41,1.21,0),(.40,.07,.33),'iron',.028)
    cube('Register stand',(-1.41,1.37,-.04),(.075,.28,.075),'iron_edge',.02)
    cube('Register casing',(-1.41,1.53,-.04),(.46,.30,.07),'iron',.026)
    cube('Register screen',(-1.41,1.53,.003),(.39,.23,.012),'68716B',.014)
    cube('Burger service tray',(-.57,1.18,.08),(.73,.035,.41),'oak_edge',.035)
    for x in (-.74,-.40):burger((x,1.206,.08),1)
    for j,c in enumerate((RED,'E7BD42','947A58')):sauce((.25+j*.17,1.17,.03),c)
    for j in range(2):
        cube('Takeaway box',(1.11+j*.48,1.38,.03),(.42,.39,.33),'DDC39A',.035)
        cube('Takeaway lid seam',(1.11+j*.48,1.43,.206),(.42,.014,.015),'C6A779',.004)
        badge((1.11+j*.48,1.38,.208),.30,RED)
    begin('customer_bar',at=(.90,.06,1.89),collision=[{'at':[0,.55,0],'size':[3.73,1.10,.43]}])
    for x in (-1.47,1.47):
        cube('Bar pedestal',(x,.54,0),(.105,1.07,.105),'iron_edge',.025)
        cube('Bar foot',(x,.055,0),(.30,.08,.35),'iron_edge',.032)
    cube('Rounded long dining bar',(0,1.13,0),(3.80,.13,.48),'oak_light',.060,'wood')
    for j,c in enumerate((RED,'E7BD42',RED)):sauce((1.10+j*.16,1.20,0),c)
    begin('red_diner_stool',at=(-.36,.065,2.49),collision=[{'at':[0,.43,0],'size':[.52,.86,.52]}]);s.stool()
    for j,x in enumerate((.91,2.18)):k.instance('red_diner_stool','red_diner_stool_'+str(j),(x,.065,2.49))
    begin('wood_planter_barrier',at=(-2.90,.06,1.47),yaw=90,collision=[{'at':[0,.43,0],'size':[2.46,.86,.36]}])
    cube('Wood fence frame',(0,.47,0),(2.49,.81,.24),'oak_edge',.050)
    for j in range(16):cube('Barrier timber plank',(-1.14+j*.151,.43,.14),(.134,.76,.055),'oak_light',.016,'wood','Y')
    cube('Long planter soil',(0,.885,0),(2.43,.045,.25),'soil',.01)
    for j in range(12):
        x=-1.10+j*.20
        for n in range(5):
            a=n*2.399;leaf('Planter greenery',(x,.90,0),(x+math.cos(a)*.17,1.0+(n%3)*.06,math.sin(a)*.18),.15,'leaf')
    s.menu('good_burgers_poster',(-2.82,1.91,1.70),'GOOD',['BURGERS','BRIGHTER','DAYS'],.74,1.16,'E9CF95',RED)
    r=k.KITS['good_burgers_poster'];r['root'].rotation_euler.z=math.pi/2;r['yaw']=90
    s.menu('fresh_buns_poster',(2.52,1.85,-2.60),'FRESH',['BUNS','BETTER','PEOPLE'],.65,1.13,'E9CF95',RED)
    begin('corner_plant',at=(2.56,.06,-2.21));k.plant(scale=1.28)
    begin('wall_lamp',at=(2.51,2.64,-2.58))
    cube('Sconce backplate',(0,0,0),(.12,.20,.04),'brass',.045)
    tube('Bent lamp arm',[(0,0,.03),(0,.06,.11),(0,.06,.19),(0,-.04,.25)],.018,'brass',8)
    lathe('Diner lamp shade',(0,-.15,.25),[(0,.107),(.06,.08),(.11,.035)],'brass',20)
    ellipsoid('Warm lamp bulb',(0,-.17,.25),(.10,.07,.10),'FFF0BF',12,6)
    k.instance('wall_lamp','wall_lamp_left',(-2.81,2.63,1.70),90)
    k.instance('wall_lamp','wall_lamp_pickup',(.03,2.91,-2.57))
    k.save('545:2960',{'position':[10,9.2,12],'target':[0,1.16,.03],'size':9.5})

if __name__=='__main__':
    k.configure('burger_shop');args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    if '--bake-only' in args:k.load()
    else:geometry()
    if '--geometry-only' not in args:k.bake_and_export()
