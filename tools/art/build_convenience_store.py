"""SGODOT-183: mint convenience store, editable merchandise and reusable fixtures."""
from pathlib import Path
import sys,math,random
sys.path.insert(0,str(Path(__file__).resolve().parent/'source/coffee_shop'))
import kit as k
from liubei_r2 import enable_lettering
enable_lettering()
import storefront as s
from kit import begin,cube,cylinder,tube,ellipsoid,lathe,leaf

COLORS=['D99273','87AAA0','E6BE74','98B9C6','D6A7AB','93A17A']
sys.path.insert(0,str(Path(__file__).resolve().parent/'source/convenience_store'))
from revision import package

def stock_rack(name,at,title,daily=False):
    begin(name,at=at,collision=[{'at':[0,.78,0],'size':[2.28,1.56,.49]}])
    cube('Rack wood back',(0,.78,-.14),(2.28,1.56,.12),'oak',.025,'wood','Y')
    for x in (-1.12,1.12):cube('Side upright',(x,.78,.06),(.075,1.56,.48),'oak_light',.024,'wood','Y')
    for row in range(3):
        y=.045+row*.47
        cube('Retail shelf',(0,y,.10),(2.25,.065,.52),'oak_light',.022,'wood')
        for j in range(8):
            if (j+row*3)%11==4:continue
            package((-.94+j*.267,y+.036,.12),j+row,(['roll','wash','soap'][(j+row)%3] if daily else ['bag','can','box'][(row+j//3)%3]))
    cube('Mint category frame',(0,1.69,.06),(2.34,.44,.13),'83A69A',.075)
    cube('Deep green category sign',(0,1.69,.14),(2.18,.32,.035),'496F60',.047)
    k.text_label(title,(0,1.64,.168),.16 if not daily else .13,'porcelain')

def aisle(name,at,daily=False):
    begin(name,at=at,collision=[{'at':[0,.60,0],'size':[1.92,1.20,.63]}])
    for x in (-.96,.96):
        cube('Aisle rounded side',(x,.59,0),(.105,1.18,.64),'oak_light',.052,'wood','Y')
        cube('Inset aisle handle',(x,.96,.33),(.038,.14,.016),'oak_edge',.012)
    cube('Aisle rear partition',(0,.58,-.21),(1.86,1.12,.06),'oak',.018,'wood')
    for row in range(3):
        y=.085+row*.38
        cube('Aisle shelf',(0,y,0),(1.92,.065,.65),'oak_light',.020,'wood')
        for j in range(7):package((-.78+j*.26,y+.04,.055),j+row,(['bottle','roll','box'][(j+row)%3] if daily else ['can','box','bag'][(row+j)%3]))
    cube('Aisle top shelf',(0,1.17,0),(1.94,.075,.66),'oak_light',.025,'wood')
    if daily:
        for j in range(7):package((-.78+j*.26,1.215,0),j,'bottle')
    else:
        for i,kind in enumerate(('apple','orange','lemon')):
            x=-.64+i*.64
            cube('Shallow produce bin',(x,1.25,0),(.58,.11,.52),'oak',.015,'wood')
            for j in range(5):
                if kind=='lemon':
                    bx=x+(j%3-1)*.105;bz=(j//3-.5)*.16
                    tube('Curved banana',[(bx-.08,1.41,bz-.13),(bx-.04,1.34,bz-.06),(bx+.03,1.33,bz+.07),(bx+.07,1.40,bz+.14)],.037,'E8CF63',8)
                    tube('Banana dark stem',[(bx+.07,1.40,bz+.14),(bx+.075,1.43,bz+.15)],.015,'oak_dark',6)
                else:s.fruit(kind,(x+(j%3-1)*.14,1.295,(j//3-.5)*.19),.95)

def geometry():
    k.PALETTE.update({'oak':'BF915D','oak_light':'D7AA70','sage':'8FAB9A','porcelain':'F0E4CF','leaf':'628C42','leaf_light':'8DAE55'})
    s.shell(wall='E9D3C8',accent='A3BCAF',floor='E5D4BA',rectangular=True)
    for i,o in enumerate(k.KITS['floor']['objects']):
        if 'Rounded ceramic' in o.name and i%4==0:o.data.materials.clear();o.data.materials.append(k.material('BAC6AD'))
    begin('entrance_frame',at=(-2.90,.07,1.05),yaw=90)
    for x in (-.64,.64):cube('Glass entrance timber stile',(x,1.13,0),(.065,2.24,.10),'oak_light',.020)
    for y in (.06,.38,2.25):cube('Glass entrance cross rail',(0,y,0),(1.34,.065,.10),'oak_light',.018)
    tube('Door pull handle',[(.45,.86,.09),(.45,.86,.17),(.45,1.35,.17),(.45,1.35,.09)],.027,'brass',8)
    tube('Hanging open sign cord',[(-.23,1.48,.105),(0,1.70,.10),(.23,1.48,.105)],.007,'leaf_dark',5)
    cube('Open sign',(0,1.33,.105),(.54,.29,.035),'496F60',.024)
    k.text_label('OPEN',(0,1.29,.129),.15,'porcelain')
    begin('entrance_glass',at=(-2.90,.07,1.05),yaw=90)
    cube('Entrance clear glazing',(0,1.18,-.008),(1.21,2.02,.015),'porcelain',0)
    begin('entrance_awning',at=(-2.85,2.55,1.05),yaw=90);s.awning(1.83,.61,('porcelain','DD9475'))
    s.menu('convenience_sign',(-2.80,2.82,1.05),'CONVENIENCE',[],1.94,.40,'496F60','porcelain')
    r=k.KITS['convenience_sign'];r['root'].rotation_euler.z=math.pi/2;r['yaw']=90
    begin('drink_cabinet',at=(-2.68,.065,-.55),yaw=90,collision=[{'at':[0,1.12,0],'size':[.70,2.24,.48]}])
    cube('Cold cabinet back',(0,1.13,-.12),(.70,2.26,.12),'658777',.04)
    for x in (-.34,.34):cube('Chiller insulated side',(x,1.13,.08),(.065,2.26,.50),'8FAA98',.022)
    for row in range(5):
        y=.25+row*.355
        cube('Chiller shelf',(0,y,.08),(.65,.036,.46),'porcelain',.01)
        for j in range(3):package((-.20+j*.20,y+.02,.07),j+row,'drink')
    for x in (-.306,.306):cube('Glass door trim',(x,1.23,.329),(.034,1.98,.045),'AEC6AF',.011)
    for y in (.245,2.21):cube('Glass door trim',(0,y,.329),(.64,.036,.045),'AEC6AF',.010)
    cube('Chiller handle',(.256,1.20,.38),(.029,.38,.038),'oak_light',.012)
    cube('Refrigerator plinth',(0,.13,.12),(.70,.23,.48),'8FAA98',.025)
    for j in range(4):cube('Refrigerator vent',(0,.055+j*.041,.369),(.54,.017,.006),'496F60',.004)
    for j in range(1,3):k.instance('drink_cabinet','drink_cabinet_'+str(j),(-2.68,.065,-.55-j*.72),90)
    begin('chiller_glass',at=(-2.68,.065,-.55),yaw=90);cube('Cabinet glazing',(0,1.23,.323),(.59,1.91,.012),'porcelain',0)
    for j in range(1,3):k.instance('chiller_glass','chiller_glass_'+str(j),(-2.68,.065,-.55-j*.72),90)
    s.menu('drinks_header',(-2.39,2.60,-1.28),'DRINKS',[],2.14,.44,'496F60','porcelain')
    r=k.KITS['drinks_header'];r['root'].rotation_euler.z=math.pi/2;r['yaw']=90
    stock_rack('snacks_wall_rack',(-1.06,.75,-2.45),'SNACKS')
    stock_rack('essentials_wall_rack',(1.40,.75,-2.45),'DAILY ESSENTIALS',True)
    begin('checkout',at=(-.37,.06,-1.42),collision=[{'at':[0,.53,0],'size':[2.45,1.06,.72]}])
    cube('Checkout cabinet',(0,.51,0),(2.45,.97,.71),'oak',.06,'wood','Y')
    for j in range(18):cube('Checkout timber slat',(-1.16+j*.137,.54,.363),(.119,.84,.038),'oak_light',.012,'wood','Y')
    cube('Sage stone checkout top',(0,1.035,0),(2.61,.115,.86),'A8BFAA',.075)
    cube('POS base',(-.10,1.12,0),(.38,.055,.28),'iron',.035)
    tube('POS stand',[(-.10,1.13,0),(-.10,1.34,-.035)],.045,'iron_edge',8)
    screen=cube('Point of sale monitor',(-.10,1.43,-.03),(.45,.31,.065),'iron',.028);screen.rotation_euler.x=-.17
    cube('POS screen',(-.10,1.43,.012),(.385,.245,.012),'798B88',.012)
    for x in (.55,.87):package((x,1.10,.06),3,'box')
    k.bouquet((-.90,1.10,0),.80)
    cube('Payment terminal',(.36,1.15,.22),(.16,.09,.22),'iron_edge',.02)
    aisle('produce_aisle',(-1.18,.07,.48))
    aisle('essentials_aisle',(1.05,.07,1.35),True)
    begin('ice_cream_freezer',at=(2.03,.07,-1.16),collision=[{'at':[0,.49,0],'size':[1.43,.98,.81]}])
    for x in (-.57,.57):
        for z in (-.29,.29):cylinder('Freezer foot',(x,.055,z),.045,.11,'iron',vertices=8)
    cube('Freezer base',(0,.19,0),(1.42,.21,.81),'porcelain',.08)
    for x in (-.67,.67):cube('Freezer end',(x,.57,0),(.10,.71,.82),'porcelain',.045)
    for z in (-.36,.36):cube('Freezer side',(0,.57,z),(1.43,.71,.10),'porcelain',.04)
    for x in (-.68,.68):cube('Pink freezer rim',(x,.98,0),(.13,.13,.87),'D99691',.045)
    for z in (-.38,.38):cube('Pink freezer rim',(0,.98,z),(1.42,.13,.13),'D99691',.045)
    cube('Sliding lid middle rail',(0,1.01,0),(.045,.038,.71),'porcelain',.01)
    for j in range(12):cube('Ice cream carton',(-.48+(j%4)*.32,.81,-.22+(j//4)*.22),(.25,.17,.17),COLORS[j%6],.03)
    for j,c in enumerate(('D99691','8CAA7E','E2B570')):
        x=-.43+j*.43
        k.mesh('Cone badge',[(x-.11,.61,.416),(x+.11,.61,.416),(x,.33,.418)],[(0,1,2)],'D4A053')
        ellipsoid('Ice cream scoop badge',(x,.68,.427),(.26,.24,.04),c,12,6)
    begin('freezer_glass',at=(2.03,.07,-1.16));cube('Freezer sliding glass',(0,1.02,0),(1.23,.012,.66),'porcelain',0)
    begin('basket_stack',at=(2.57,.07,-.18),collision=[{'at':[0,.43,0],'size':[.53,.86,.53]}])
    for j in range(6):
        y=.04+j*.105
        for z in (-.22,.22):
            for n in range(3):cube('Wicker basket band',(0,y+n*.025,z),(.48,.016,.022),'oak_light',.005)
        for x in (-.24,.24):
            for n in range(3):cube('Wicker basket end',(x,y+n*.025,0),(.022,.016,.44),'oak_light',.005)
    for x in (-.29,.29):tube('Basket cart frame',[(x,.0,.23),(x,.87,.23),(x,.94,-.20),(x,0,-.20)],.024,'sage',8)
    begin('entrance_plant',at=(-2.25,.07,.01));k.plant(scale=1.14)
    begin('trailing_plant',at=(2.56,2.56,-2.23));k.plant(scale=.65,trailing=True)
    begin('front_flowers',at=(-2.14,.79,2.68));s.flower_border(1.4)
    k.instance('front_flowers','front_flowers_right',(2.16,.79,2.68))
    begin('side_leaves',at=(3,.79,1.28),yaw=90);s.flower_border(1.85)
    begin('entrance_sconce',at=(-2.80,1.93,2.06),yaw=90)
    cube('Lamp backplate',(0,0,0),(.14,.39,.035),'brass',.025)
    lathe('Warm opal lantern',(0,-.17,.095),[(0,.066),(.045,.093),(.30,.093),(.35,.066)],'FFF0BA',16)
    for y in (-.18,.17):cylinder('Lantern cap',(0,y,.095),.105,.045,'brass',vertices=20)
    import revision
    revision.revise()
    k.save('545:2958',{'position':[10,9.2,12],'target':[0,1.12,.04],'size':9.5})
    revision.manifest()

if __name__=='__main__':
    k.configure('convenience_store');args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    if '--bake-only' in args:k.load()
    else:geometry()
    if '--geometry-only' not in args:k.bake_and_export(ao_strength=.45,ao_distance=.36,coherent_swatches=True)
    if '--geometry-only' not in args:
        from series_batch import build
        build('convenience_store')
