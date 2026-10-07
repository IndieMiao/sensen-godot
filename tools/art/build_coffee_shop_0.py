"""SGODOT-181 courtyard Coffee Shop-0. Editable static cats, orange trees, real sink cavity."""
from pathlib import Path
import sys,math,random
sys.path.insert(0,str(Path(__file__).resolve().parent/'source/coffee_shop'))
import kit as k
import storefront as s
from kit import begin,cube,cylinder,tube,ellipsoid,lathe,leaf,mesh

def cat(color='C7C3BD',lying=False):
    y=.18 if lying else .32
    ellipsoid('Rounded cat torso',(0,y,0),(.32,.27 if lying else .37,.55),color,20,12)
    ellipsoid('Round cat head',(0,y+.045,.28),(.31,.29,.29),color,20,12)
    for x in (-.11,.11):
        verts=[(x-.08,y+.13,.24),(x+.07,y+.13,.24),(x,y+.32,.23),(x-.05,y+.13,.34),(x+.05,y+.13,.34),(x,y+.285,.31)]
        mesh('Soft triangular cat ear',verts,[(0,1,2),(3,5,4),(0,3,4,1),(1,4,5,2),(2,5,3,0)],color,smooth=True)
        ellipsoid('Ear blush',(x,y+.215,.308),(.064,.091,.022),'D6A5A7',12,6)
        for z in (-.15,.18):ellipsoid('Cat paw',(x,.075 if not lying else .08,z),(.13,.17 if not lying else .11,.18),'porcelain',12,6)
        ellipsoid('Cat eye',(x*.62,y+.080,.410),(.037,.045,.020),'iron',12,6)
        ellipsoid('Cat cheek',(x*.40,y-.020,.419),(.097,.066,.026),'porcelain',12,6)
    ellipsoid('Pink cat nose',(0,y+.006,.438),(.031,.020,.015),'D49A9F',8,4)
    tube('Curved cat tail',[(0,y,-.22),(.19,y+.08,-.31),(.28,y+.24,-.24),(.26,y+.35,-.11)],.045,color,8)
    for i in range(3):
        z=-.16+i*.12;points=[]
        for j in range(13):
            x=-.125+j*.25/12
            yy=y+(.139 if lying else .189)*math.sqrt(max(.02,1-(x/.16)**2-(z/.275)**2))
            points.append((x,yy,z))
        tube('Fur stripe follows body',points,.009,'oak_dark' if color=='D7A04F' else 'iron_edge',5)

def geometry():
    k.PALETTE.update({'oak':'B6894F','oak_light':'CEA069','porcelain':'EFE9DD','plaster':'E4CE9F','leaf':'5C8449','leaf_light':'85A25A','leaf_dark':'486D3B'})
    s.shell(wall='E7D2AA',accent='D8C299',floor='E3CBA5')
    begin('grass_base',at=(0,-.30,.42))
    cube('Rounded turf island',(0,0,0),(8.0,.16,8.3),'9BAC69',.18,'plaster')
    for j in range(85):
        x=random.uniform(-3.85,3.85);z=random.uniform(-3.95,3.95)
        if abs(x)<3.13 and -3.25<z<2.50:continue
        for i in range(3):
            mesh('Small meadow blade',[(x+i*.027,.075,z),(x+.02+i*.027,.075,z),(x+.025+i*.027,.18,z-.025)],[(0,1,2)],'leaf_light')
    begin('back_crenellations',at=(0,3.11,-2.75))
    for j in range(10):cube('Rounded garden battlement',(-2.76+j*.615,.12,0),(.44,.25,.32),'porcelain',.065)
    begin('left_crenellations',at=(-3,3.11,0),yaw=90)
    for j in range(9):cube('Rounded garden battlement',(-2.46+j*.615,.12,0),(.44,.25,.32),'porcelain',.065)
    begin('back_cabinet',at=(.08,.06,-2.15),collision=[{'at':[0,.54,0],'size':[3.15,1.08,.72]}]);k.counter(3.15,.72)
    for i in range(4):
        x=-1.13+i*.76
        cube('Cabinet door',(x,.54,.371),(.70,.80,.025),'oak_light',.025,'wood','Y')
        ellipsoid('Cabinet round knob',(x+.22,.85,.411),(.048,.048,.033),'brass',12,6)
    begin('serving_counter',at=(.08,.06,-.98),collision=[{'at':[0,.49,0],'size':[3.25,.98,.48]}]);k.counter(3.25,.48)
    begin('counter_return',at=(1.65,.06,-1.56),yaw=90,collision=[{'at':[0,.54,0],'size':[1.38,1.08,.53]}]);k.counter(1.38,.53)
    # Real sink cavity: four separate stone surround pieces, basin below the opening.
    begin('sink',at=(1.12,1.26,-2.11))
    for x in (-.32,.32):cube('Sink side rim',(x,.01,0),(.075,.048,.48),'stone',.023)
    for z in (-.225,.225):cube('Sink front rear rim',(0,.01,z),(.60,.048,.058),'stone',.021)
    cube('Basin bottom',(0,-.135,0),(.53,.025,.36),'iron_edge',.038)
    for x in (-.273,.273):cube('Basin liner',(x,-.069,0),(.024,.15,.36),'stone',.008)
    for z in (-.181,.181):cube('Basin liner',(0,-.069,z),(.54,.15,.025),'stone',.008)
    tube('Arched faucet',[(.09,.01,-.22),(.09,.31,-.22),(.09,.38,-.13),(.09,.30,-.045)],.018,'iron_edge',8)
    # Remove stone below the sink aperture on the cabinet, retaining editable objects.
    cabinet=k.KITS['back_cabinet']
    for o in cabinet['objects']:
        if o.name.startswith('Stone worktop'):
            k.CURRENT=cabinet
            cutter=cube('Sink aperture cutter',(1.04,1.12,.04),(.56,.42,.38),'iron',0)
            k.boolean_cut(o,cutter)
            break
    s.reuse_coffee('espresso_machine',(.04,1.26,-2.13))
    s.reuse_coffee('coffee_grinder',(.61,1.26,-2.20))
    s.reuse_coffee('pastry_case',(-1.01,1.26,-2.11))
    s.reuse_coffee('display_glass',(-1.01,1.26,-2.11))
    begin('supply_shelf',at=(-.31,2.04,-2.55))
    cube('Wall shelf',(0,0,0),(2.46,.085,.43),'oak_light',.02,'wood')
    for i in range(3):
        x=-.79+i*.40
        cube('Folded coffee bag',(x,.24,0),(.26,.42,.17),'terra',.025)
        cube('Coffee bag fold',(x,.46,0),(.26,.042,.085),'oak_edge',.013)
        cube('Coffee bag label',(x,.24,.09),(.15,.17,.005),'porcelain',.003)
    for x in (.54,.79):k.cup((x,.045,.045),.95,coffee=False)
    begin('cookie_jars',at=(.80,1.26,-2.15))
    for x in (-.17,.17):
        cylinder('Cookie jar',(x,.23,0),.11,.43,'terra_light',vertices=20)
        cylinder('Cookie jar lid',(x,.46,0),.12,.037,'oak_edge',vertices=20)
        for j in range(12):ellipsoid('Golden biscuits',(x+math.cos(j*2.4)*.10,.065+(j%4)*.09,math.sin(j*2.4)*.10),(.055,.055,.02),'pollen',8,4)
    begin('service_tray',at=(-.92,1.26,-.94))
    cube('Oak serving tray',(0,.018,0),(.72,.036,.40),'oak_light',.036)
    k.cup((.17,.04,0));cube('Small pastry plate',(-.19,.04,0),(.27,.025,.27),'porcelain',.03)
    cube('Square butter cake',(-.19,.11,0),(.20,.11,.17),'pollen',.03)
    k.instance('service_tray','service_tray_2',(.05,1.26,-.94))
    s.menu('counter_chalkboard',(.80,1.45,-.93),'MENU',['Coffee','Cake'],.36,.39,'iron_edge','porcelain')
    begin('orange_tree',at=(-2.25,.06,-1.77),collision=[{'at':[0,.37,0],'size':[.71,.74,.71]}])
    cube('Tree stone planter',(0,.17,0),(.77,.34,.77),'plaster',.08)
    cylinder('Tree soil',(0,.35,0),.32,.015,'soil',vertices=20)
    tube('Orange tree trunk',[(0,.32,0),(-.04,.80,.01),(.04,1.34,0),(0,1.92,.02)],.11,'oak',10,'wood')
    for j in range(8):
        a=j*2.399
        tube('Tree branch',[(0,1.1,0),(math.cos(a)*.34,1.60,math.sin(a)*.34)],.041,'oak',7)
    for j in range(7):
        a=j*2.399
        ellipsoid('Soft rounded crown cluster',(math.cos(a)*.24,1.63+(j%3)*.25,math.sin(a)*.24),(.69,.67,.69),'leaf' if j%2 else 'leaf_light',16,8)
    for j in range(62):
        a=j*2.399;t=(j%7)/6
        yy=1.40+t*.93;r=.62*math.sin(.35+t*2.3)
        x=math.cos(a)*r;z=math.sin(a)*r
        leaf('Broad orange tree leaf',(x*.65,yy-.08,z*.65),(x*1.18,yy+.11,z*1.18),.25,random.choice(['leaf','leaf_light']))
    for x,y,z in [(-.33,1.45,.40),(.36,1.82,.38),(.32,1.33,-.06),(-.29,1.93,-.27)]:
        ellipsoid('Ripe orange',(x,y,z),(.26,.27,.26),'E4AC40',16,8)
        leaf('Orange fruit leaf',(x,y+.13,z),(x+.10,y+.19,z),.070,'leaf')
    k.instance('orange_tree','orange_tree_2',(2.37,.06,-1.72),70)
    begin('flower_border',at=(-2.12,.78,2.68));s.flower_border(1.66)
    k.instance('flower_border','flower_border_front_right',(2.16,.78,2.68))
    for j,z in enumerate((-1.65,0,1.65)):k.instance('flower_border','flower_border_right_'+str(j),(3,.78,z),90)
    s.reuse_coffee('chair',(-2.24,.06,.65),90)
    for i,at,yaw in [(2,(-.66,.06,.65),-90),(3,(.66,.06,1.24),90),(4,(2.24,.06,1.24),-90)]:k.instance('chair','chair_'+str(i),at,yaw)
    begin('round_table',at=(-1.45,.06,.65),collision=[{'at':[0,.43,0],'size':[1.10,.86,1.10]}])
    for a in (0,math.tau/3,math.tau*2/3):tube('Splayed wood table leg',[(.26*math.cos(a),.01,.26*math.sin(a)),(.12*math.cos(a),.76,.12*math.sin(a))],.04,'oak',8)
    cylinder('Ivory cafe tabletop',(0,.80,0),.55,.085,'porcelain',vertices=40)
    k.instance('round_table','round_table_2',(1.45,.06,1.24))
    begin('blue_vase_flowers',at=(-1.45,.91,.65));k.bouquet(scale=.72)
    for o in k.CURRENT['objects']:
        if 'vase' in o.name.lower():o.data.materials.clear();o.data.materials.append(k.material('647C9E'))
    k.instance('blue_vase_flowers','blue_vase_flowers_2',(1.45,.91,1.24))
    begin('table_cup',at=(1.76,.91,1.38));k.cup((0,0,0),.9)
    begin('sleeping_cat',at=(.12,.035,2.70),yaw=-25);cat(lying=True)
    begin('counter_cat',at=(1.32,1.225,-.90),yaw=-45);cat('D7A04F',True)
    begin('walking_cat',at=(-.23,.06,.67),yaw=-35);cat('EFE5D0')
    k.instance('walking_cat','walking_cat_2',(1.0,.06,2.15),150)
    begin('garden_stepping_stones',at=(.10,-.13,3.24))
    for j in range(4):cube('Garden stepping stone',((-.18 if j%2 else .16),-.07,j*.35),(.40,.09,.29),'plaster',.08)
    s.signboard(at=(-1.56,.02,3.13),lines=('COFFEE','& CAKE'))
    import importlib.util
    spec=importlib.util.spec_from_file_location('courtyard_revision',Path(__file__).resolve().parent/'source/coffee_shop_0/revision.py')
    rev=importlib.util.module_from_spec(spec);spec.loader.exec_module(rev)
    sys.path.insert(0,str(Path(__file__).resolve().parent/'source/coffee_shop_0'))
    rev.revise()
    k.save('545:2955',{'position':[10,10,12],'target':[0,1.0,.45],'size':12.0})
    rev.manifest()

if __name__=='__main__':
    k.configure('coffee_shop_0');args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    if '--bake-only' in args:k.load()
    else:geometry()
    if '--geometry-only' not in args:k.bake_and_export(ao_strength=.45,ao_distance=.38,coherent_swatches=True)
    if '--geometry-only' not in args:
        from series_batch import build
        build('coffee_shop_0')
