"""SGODOT-179: Greenhouse Cafe. Rebuild with Blender --background --python <absolute path>.
Trailing -- --geometry-only or --bake-only preserves a separate edit/bake workflow.
The source reference is Figma 545:2956; hidden dimensions are inferred in metres.
"""
from pathlib import Path
import sys, math, random
sys.path.insert(0,str(Path(__file__).resolve().parent/'source/coffee_shop'))
import kit as k
from kit import begin,cube,cylinder,ellipsoid,tube,lathe,leaf,arch_trim,mesh

def greenhouse_pane(name,at,size):
    # Soft opaque glazing deliberately avoids costly refraction and sort artifacts.
    cube(name,at,size,'B7D8CB',.003)
    x,y,z=at
    for j in range(24):
        xx=x+random.uniform(-size[0]*.45,size[0]*.45)
        yy=y+random.uniform(-size[1]*.44,size[1]*.44)
        leaf('Blurred garden silhouette',(xx,yy,z+.013),(xx+random.uniform(-.16,.16),yy+.22,z+.015),.13,random.choice(['C9D7A9','DCE3B9','A6C8AE']))

def geometry():
    k.PALETTE.update({'oak':'BA8F5B','oak_light':'D9AF79','oak_edge':'AE8252','plaster':'E8D8BF','plaster_light':'F4E8D3','sage':'A5B299','linen_green':'D4C6A2','linen':'F3E7CD','leaf':'678347','leaf_light':'8EA15C','leaf_dark':'3E623D','terra':'C6AC7C','terra_light':'DDC59C','jar_green':'ADBC91'})
    begin('floor',collision=[{'at':[0,-.08,0],'size':[6.2,.20,5.7]}])
    cube('Rounded diorama foundation',(0,-.14,0),(6.25,.28,5.75),'plaster',.12)
    for j in range(21):
        z=-2.71+j*.265
        for i in range(3):
            x=-2.05+i*2.05
            cube('Honey oak floor plank',(x,.018,z),(2.04,.066,.252),random.choice(['oak_light','D5A875','DDB784']),.012,'wood')
    begin('entry_steps',at=(.15,-.18,2.90),collision=[{'at':[0,.065,.10],'size':[1.52,.13,.58]}])
    cube('Lower entry tread',(0,-.055,.30),(1.62,.16,.78),'plaster',.055)
    cube('Upper entry tread',(0,.065,.04),(1.52,.14,.40),'plaster_light',.045)
    begin('low_wall_long',at=(3,.04,0),yaw=90,collision=[{'at':[0,.37,0],'size':[5.4,.74,.23]}]);k.low_wall(5.4)
    begin('low_wall_front_left',at=(-1.85,.04,2.72),collision=[{'at':[0,.37,0],'size':[2.0,.74,.23]}]);k.low_wall(2)
    begin('low_wall_front_right',at=(1.94,.04,2.72),collision=[{'at':[0,.37,0],'size':[1.86,.74,.23]}]);k.low_wall(1.86)
    begin('low_pillar',at=(3,.03,2.72),collision=[{'at':[0,.44,0],'size':[.36,.88,.36]}])
    cube('Cut limestone pier',(0,.39,0),(.32,.80,.32),'plaster',.038)
    cube('Pillar rounded cap',(0,.85,0),(.41,.18,.41),'plaster_light',.055)
    for i,at in enumerate([(-3,.03,2.72),(-.69,.03,2.72),(.99,.03,2.72),(3,.03,-2.72)]):k.instance('low_pillar','low_pillar_%d'%i,at)
    begin('tall_pillar',at=(-3,.04,-2.72),collision=[{'at':[0,1.52,0],'size':[.30,3.04,.30]}])
    for j in range(7):cube('Limestone block',(0,.215+j*.425,0),(.31,.414,.31),'plaster',.027)
    cube('Tall capital',(0,3.03,0),(.41,.18,.41),'plaster_light',.055)
    for i,at in enumerate([(-3,.04,-.87),(-3,.04,2.1),(1.46,.04,-2.72),(3,.04,-2.72)]):k.instance('tall_pillar','tall_pillar_%d'%i,at)
    # Tall left opening. Local +Z faces into the room after a +90 degree turn.
    begin('ivy_arch_door',at=(-3,.04,.65),yaw=90,collision=[{'at':[-.91,1.40,0],'size':[.26,2.8,.26]},{'at':[.91,1.40,0],'size':[.26,2.8,.26]}])
    arch_trim('Open limestone arch',1.60,0,1.93,.76,.20,.27,0,'plaster')
    arch_trim('Oak door reveal',1.54,0,1.93,.73,.058,.30,.045,'oak_light')
    cube('Arch wall coping',(0,3.00,0),(2.80,.16,.29),'plaster_light',.045)
    path=[(x,y,.20) for x,y in k.arch_path(1.98,.62,1.99,.97,28)]
    k.vine(path)
    begin('left_window',at=(-3,.04,-1.83),yaw=90,collision=[{'at':[0,1.40,0],'size':[1.66,2.8,.16]}])
    greenhouse_pane('Garden glazing',(0,1.57,-.02),(1.62,2.55,.028))
    for x in (-.83,0,.83):cube('Window vertical mullion',(x,1.58,.03),(.055,2.74,.095),'oak_light',.012,'wood','Y')
    for y in (.23,1.07,1.92,2.94):cube('Window cross bar',(0,y,.04),(1.68,.06,.10),'oak_light',.012,'wood')
    cube('Window coping',(0,3.00,0),(1.80,.16,.29),'plaster_light',.04)
    begin('back_counter_wall',at=(-.81,.04,-2.72),collision=[{'at':[0,1.45,0],'size':[4.16,2.9,.19]}])
    cube('Sage panel base',(0,.97,0),(4.12,1.94,.19),'sage',.018,'plaster')
    for i in range(23):cube('Vertical painted boarding',(-1.99+i*.181,.97,.107),(.168,1.84,.020),'sage',.005,'wood','Y')
    greenhouse_pane('Clerestory glass',(0,2.45,0),(4.14,.93,.034))
    for y in (1.98,2.95):cube('Clerestory oak rail',(0,y,.06),(4.19,.075,.12),'oak_light',.018,'wood')
    for x in (-2.03,-.68,.68,2.03):
        cube('Transom upright',(x,2.46,.06),(.058,.94,.10),'oak',.012,'wood','Y')
        if x> -2:
            tube('Transom angled opening support',[(x-.32,2.04,.08),(x-.57,2.81,.08)],.025,'oak_light',6)
    cube('Back limestone coping',(0,3.0,0),(4.30,.16,.28),'plaster_light',.05)
    begin('right_arch_window',at=(2.24,.04,-2.72),collision=[{'at':[0,1.40,0],'size':[1.5,2.8,.16]}])
    k.arch_solid('Pale frosted garden',1.30,.05,2.12,.65,.035,-.02,'BBD7C2')
    arch_trim('Arched oak frame',1.30,.05,2.12,.65,.07,.13,.06,'oak_light')
    for y in (.77,1.56,2.14):cube('Arch window cross bar',(0,y,.07),(1.34,.055,.13),'oak_light',.013,'wood')
    cube('Arch window central bar',(0,1.40,.09),(.053,2.70,.12),'oak_light',.01,'wood','Y')
    for j in range(14):
        x=random.uniform(-.55,.55);y=random.uniform(.18,2.35)
        leaf('Garden leaf behind glazing',(x,y,.011),(x+.10,y+.22,.017),.16,'C9D7A9')
    cube('Window upper coping',(0,3.,0),(1.51,.16,.28),'plaster_light',.045)
    k.vine([(x,y,.20) for x,y in k.arch_path(1.52,.56,2.14,.73,24)])
    begin('counter',at=(-.20,.06,-1.80),collision=[{'at':[0,.58,0],'size':[3.40,1.16,.98]}]);k.counter()
    begin('espresso_machine',at=(.45,1.26,-1.76))
    cube('Cream espresso body',(0,.34,0),(.68,.43,.40),'porcelain',.055)
    cube('Espresso warming tray',(0,.57,0),(.70,.045,.43),'oak_light',.025)
    cube('Drip tray',(0,.065,.055),(.70,.07,.59),'porcelain',.045)
    cube('Dark drip grille',(0,.108,.14),(.58,.018,.31),'iron_edge',.012)
    for j in range(9):cube('Drip grille slat',(-.25+j*.062,.12,.14),(.012,.006,.27),'plaster',.001)
    for x in (-.22,0,.22):
        o=cylinder('Espresso dial',(x,.39,.217),.040,.028,'iron',vertices=16);o.rotation_euler.x=math.pi/2
        o=cylinder('Dial center',(x,.39,.234),.024,.007,'brass',vertices=16);o.rotation_euler.x=math.pi/2
    for x in (-.18,.18):
        cylinder('Group head',(x,.25,.15),.062,.045,'iron_edge',vertices=16)
        tube('Portafilter handle',[(x,.24,.17),(x,.23,.40)],.020,'iron',8)
        tube('Steam wand',[(x*1.8,.27,.13),(x*1.9,.18,.18),(x*1.9,.14,.26)],.01,'iron_edge',6)
    for x in (-.20,0,.20):k.cup((x,.595,0),.72,coffee=False)
    begin('coffee_grinder',at=(1.05,1.26,-1.86))
    cube('Grinder base',(0,.045,0),(.31,.09,.31),'iron',.03)
    cube('Grinder motor',(0,.22,-.035),(.22,.35,.22),'iron_edge',.035)
    lathe('Bean hopper',(0,.38,-.035),[(0,.07),(.13,.12),(.27,.125),(.29,.13)],'oak_dark',20)
    cylinder('Hopper lid',(0,.68,-.035),.135,.025,'iron',vertices=20)
    for j in range(19):ellipsoid('Coffee bean',(random.uniform(-.09,.09),.65,random.uniform(-.08,.06)),(.035,.018,.024),'iron_edge',8,4)
    begin('pastry_case',at=(-.79,1.26,-1.79))
    cube('Patisserie plinth',(0,.026,0),(1.07,.052,.63),'oak_light',.015)
    for y in (.11,.43):
        cube('Cream display shelf',(0,y,0),(.99,.027,.55),'porcelain',.012)
        for i in range(3):
            x=-.32+i*.32
            if y<.2:
                cylinder('Cupcake case',(x,y+.065,.08),.075,.09,'terra',top=.091,vertices=12)
                ellipsoid('Cupcake cream',(x,y+.14,.08),(.16,.12,.16),'porcelain',16,6)
                ellipsoid('Caramel topping',(x,y+.193,.08),(.055,.025,.055),'oak_edge',8,4)
            else:
                for j in range(6):ellipsoid('Croissant folded segment',(x+(j-2.5)*.029,y+.07,.025+abs(j-2.5)*.018),(.070,.09*(1-abs(j-2.5)*.10),.14),'D9A052',12,6)
    for x in (-.525,.525):
        tube('Display curved metal edge',[(x,.05,.30),(x,.52,.30),(x,.72,-.19),(x,.04,-.28)],.018,'brass',6)
    for z,y in ((.30,.52),(-.19,.72),(-.28,.05)):
        tube('Display edge crossbar',[(-.525,y,z),(.525,y,z)],.013,'brass',6)
    # Glass exported as an independent module with its own shared translucent material.
    begin('display_glass',at=(-.79,1.26,-1.79))
    mesh('Display roof glass',[(-.51,.523,.298),(.51,.523,.298),(.51,.715,-.19),(-.51,.715,-.19)],[(0,1,2,3)],'C3DCD6')
    for x in (-.52,.52):mesh('Display side glass',[(x,.06,.29),(x,.52,.29),(x,.71,-.19),(x,.06,-.27)],[(0,1,2,3)],'C3DCD6')
    begin('cups_and_saucers',at=(1.17,1.26,-1.53))
    for j in range(4):cylinder('Stacked saucer',(0,j*.023,0),.155,.021,'porcelain',vertices=24)
    k.cup((0,.082,0),.95)
    begin('counter_daisies',at=(-1.49,1.26,-1.83));k.bouquet(scale=1.4)
    begin('small_planter',at=(1.36,1.26,-2.01));k.plant(scale=.63)
    begin('pendant',at=(-1.06,2.92,-1.83))
    tube('Pendant cable',[(0,0,0),(0,-.62,0)],.008,'iron',6)
    cylinder('Brass lampholder',(0,-.61,0),.055,.12,'brass',vertices=16)
    lathe('Cream bell shade',(0,-.88,0),[(0,.25),(.03,.27),(.09,.24),(.21,.125),(.25,.058)],'porcelain',32)
    k.instance('pendant','pendant_2',(.20,2.92,-1.83))
    begin('botanical_picture',at=(.93,1.54,-2.56))
    cube('Picture oak frame',(0,.29,0),(.54,.72,.055),'oak_light',.02)
    cube('Picture ivory mount',(0,.29,.032),(.45,.62,.014),'porcelain',.003)
    tube('Printed botanical stem',[(0,.03,.044),(0,.49,.044)],.008,'leaf_dark',5)
    for j in range(5):
        yy=.12+j*.070;sgn=1 if j%2 else -1
        leaf('Botanical print leaf',(0,yy,.047),(.14*sgn,yy+.13,.049),.082,'leaf')
    begin('table',at=(-1.34,.065,.55),collision=[{'at':[0,.42,0],'size':[1.12,.84,1.12]}]);k.table()
    k.instance('table','table_2',(1.45,.065,1.00))
    begin('chair',at=(-2.13,.065,.55),yaw=90,collision=[{'at':[0,.49,0],'size':[.67,.98,.64]}]);k.chair()
    for name,at,yaw in [('chair_2',(-.55,.065,.55),-90),('chair_3',(.66,.065,1.),90),('chair_4',(2.24,.065,1.),-90)]:k.instance('chair',name,at,yaw)
    begin('jute_rug',at=(-1.34,.058,.55));k.rug();k.instance('jute_rug','jute_rug_2',(1.45,.058,1.))
    begin('table_bouquet',at=(-1.41,.903,.40));k.bouquet(scale=.8)
    k.instance('table_bouquet','table_bouquet_2',(1.40,.903,.83))
    begin('table_coffee',at=(-1.08,.903,.70));cylinder('Coffee saucer',(0,.009,0),.15,.019,'porcelain',vertices=24);k.cup((0,.02,0),.90)
    k.instance('table_coffee','table_coffee_2',(1.67,.903,1.16))
    begin('floor_planter',at=(-2.53,.067,-1.31),collision=[{'at':[0,.31,0],'size':[.62,.62,.62]}]);k.plant(scale=1.65)
    k.instance('floor_planter','floor_planter_2',(2.52,.067,-1.96),-40)
    begin('medium_planter',at=(-2.70,.067,-.57),collision=[{'at':[0,.23,0],'size':[.45,.46,.45]}]);k.plant(scale=1.0)
    k.instance('medium_planter','medium_planter_2',(1.96,.067,-2.12),45)
    begin('low_trailing_planter',at=(-2.80,.068,1.74));k.plant(scale=1.05)
    begin('front_ivy',at=(1.63,.82,2.65))
    for dx in (-.45,-.15,.15,.4):
        k.vine([(dx+math.sin(j*.5)*.085,-j*.07,.08+j*.019) for j in range(13)])
    begin('back_trailing_ivy',at=(-2.76,2.96,-2.52))
    for dx in (0,.16):k.vine([(dx+math.sin(j*.5)*.065,-j*.080,.10) for j in range(17)])
    k.instance('back_trailing_ivy','back_trailing_ivy_2',(-1.50,2.94,-2.50))
    k.instance('back_trailing_ivy','back_trailing_ivy_3',(1.29,2.94,-2.50))
    begin('hanging_cafe_sign',at=(-2.90,1.57,1.56),yaw=90)
    cube('Rounded wood sign edge',(0,0,0),(1.12,.81,.10),'oak_light',.18,'wood')
    cube('Cream sign face',(0,0,.058),(1.01,.70,.045),'porcelain',.16)
    k.text_label('GREENHOUSE',(0,.08,.086),.125,'leaf_dark')
    k.text_label('CAFE',(0,-.10,.087),.165,'leaf_dark')
    for x in (-.30,.30):tube('Sign suspension',[(x,.40,0),(x,.65,0)],.012,'iron',6)
    tube('Wrought iron sign arm',[(-.65,.66,0),(.62,.66,0)],.030,'iron',8)
    tube('Iron bracket scroll',[(-.60,.67,0),(-.60,.95,0),(-.39,.89,0),(-.41,.75,0),(-.50,.76,0)],.015,'iron',6)
    for x in (-.20,-.07,.07,.20):leaf('Sign leaf ornament',(0,-.22,.087),(x,-.27,.094),.055,'leaf')
    k.save('545:2956',{'position':[10,9.2,12],'target':[0,1.16,0],'size':9.15})

if __name__=='__main__':
    k.configure('coffee_shop')
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    if '--bake-only' in args:k.load()
    else:geometry()
    if '--geometry-only' not in args:k.bake_and_export()
