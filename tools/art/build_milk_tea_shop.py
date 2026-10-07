"""SGODOT-180 Milk Tea Shop. Blender background generator; --geometry-only / --bake-only."""
from pathlib import Path
import sys, math, random
sys.path.insert(0,str(Path(__file__).resolve().parent/'source/coffee_shop'))
import kit as k
import storefront as s
from kit import begin,cube,cylinder,ellipsoid,tube,lathe

def geometry():
    k.PALETTE.update({'oak':'BD8B50','oak_light':'D9AD72','porcelain':'F4E8D7','sage':'98B19A','leaf':'587C3E','leaf_light':'86A25A','terra':'DAC397'})
    s.shell()
    s.fridge()
    begin('service_counter',at=(.35,.06,-1.62),collision=[{'at':[0,.57,0],'size':[3.85,1.14,.86]}]);k.counter(3.85,.86)
    s.menu('main_menu',(-1.08,2.42,-2.55),'MILK TEA',['Classic Milk Tea      4.5','Brown Sugar           4.8','Matcha Latte          4.8','Taro Milk Tea         4.5','Strawberry Milk       4.5'],1.76,1.05)
    s.menu('toppings_menu',(.65,2.42,-2.55),'TOPPINGS',['Tapioca Pearls','Crystal Boba','Pudding','Aloe Vera','Red Bean','Grass Jelly'],1.34,1.05)
    s.menu('freshly_made',(2.02,2.38,-2.55),'FRESHLY',['MADE'],.89,1.18,'sage','porcelain')
    begin('wall_tea_symbol',at=(2.00,2.17,-2.44));s.tea_cup((0,-.20,0),.80,'E2A6A7')
    begin('syrup_shelf',at=(-1.18,1.49,-2.40))
    cube('Syrup shelf board',(0,0,0),(1.65,.065,.33),'oak_light',.017,'wood')
    for i in range(6):
        x=-.65+i*.26;s.bottle((x,.04,.035),['B8873D','AD6754','D6B560','76955B'][i%4],.32)
        tube('Syrup pump spout',[(x,.40,.035),(x,.47,.035),(x,.47,.13)],.011,'porcelain',6)
    begin('tea_urns',at=(.16,1.26,-2.09))
    cube('Tea urn shelf',(0,.06,0),(1.09,.09,.40),'oak_light',.02)
    for i in range(3):
        x=-.35+i*.35
        cylinder('Beverage tank',(x,.44,0),.125,.60,['B58640','7E9851','C8AB7C'][i],vertices=24)
        for y in (.15,.74):cylinder('Tank dark ring',(x,y,0),.138,.035,'iron',vertices=24)
        cylinder('Lid handle',(x,.785,0),.042,.043,'iron',vertices=16)
        cube('Urn dispenser tap',(x,.21,.16),(.047,.085,.105),'iron',.015)
    begin('cup_sealer',at=(1.42,1.26,-2.00))
    cube('Lavender machine base',(0,.065,0),(.54,.13,.46),'BBA7CC',.047)
    cube('Sealer rear pillar',(0,.39,-.11),(.47,.67,.21),'BBA7CC',.055)
    cube('Machine head',(0,.61,.00),(.48,.22,.40),'C7B4D5',.047)
    for x in (-.15,0,.15):
        o=cylinder('Sealer button',(x,.62,.215),.039,.025,'iron_edge',vertices=12);o.rotation_euler.x=math.pi/2
    cylinder('Cup tray',(0,.24,.12),.17,.047,'iron',vertices=24)
    s.tea_cup((0,.27,.12),.83,'D8B686')
    o=cylinder('Seal film roll',(0,.87,-.045),.13,.46,'B7A4C5',vertices=24);o.rotation_euler.y=math.pi/2
    begin('ingredient_jars',at=(2.12,1.41,-2.28))
    cube('Topping jar shelf',(0,0,0),(1.14,.065,.36),'oak_light',.02)
    for i in range(4):
        x=-.40+i*.267
        cylinder('Jar body',(x,.22,.025),.105,.35,['6B5640','DEB35A','C68186','BA994F'][i],vertices=16)
        cylinder('Jar lid',(x,.41,.025),.116,.035,'porcelain',vertices=20)
        for j in range(12):
            a=j*2.399
            ellipsoid('Visible jar topping',(x+math.cos(a)*.099,.10+j%4*.077,.025+math.sin(a)*.099),(.042,.050,.042),['iron','pollen','D99CA2','DAB260'][i],8,4)
    begin('shakers',at=(-.38,1.26,-1.93))
    for x in (-.22,0,.22):
        lathe('Stainless shaker',(x,0,.04),[(0,.055),(.05,.070),(.23,.065),(.27,.050),(.30,.05)],'stone',16)
        cylinder('Shaker cap',(x,.33,.04),.028,.07,'iron_edge',vertices=12)
    begin('topping_case',at=(-.96,1.26,-1.38))
    cube('Recessed topping case',(0,.04,0),(1.70,.085,.60),'iron_edge',.028)
    colors=['iron','DCA74C','D8BF71','C77F91','CBE2CB','F0DDBB','BA8C5C','B58569']
    for i,color in enumerate(colors):
        x=-.63+(i%4)*.42;z=-.135+(i//4)*.28
        cube('Stainless ingredient bin',(x,.10,z),(.395,.06,.258),'stone',.015)
        cube('Bin filled ingredient surface',(x,.137,z),(.350,.016,.215),color,.012)
        for j in range(12):ellipsoid('Topping portion',(x-.13+(j%4)*.085,.16,z-.071+(j//4)*.066),(.057,.047,.045),color,8,4)
    for x in (-.87,.87):tube('Curved protective display rail',[(x,.07,.32),(x,.29,.32),(x,.49,-.20),(x,.03,-.30)],.017,'stone',6)
    tube('Display top crossbar',[(-.87,.49,-.20),(.87,.49,-.20)],.015,'stone',6)
    begin('topping_glass',at=(-.96,1.26,-1.38))
    k.mesh('Clear topping cover',[(-.86,.29,.32),(.86,.29,.32),(.86,.49,-.20),(-.86,.49,-.20)],[(0,1,2,3)],'sky')
    begin('checkout_register',at=(.49,1.26,-1.26))
    cube('POS base',(0,.025,0),(.32,.05,.26),'iron',.025)
    tube('POS support',[(0,.05,0),(0,.25,-.04)],.036,'iron',8)
    cube('POS display',(0,.33,-.035),(.40,.29,.045),'iron',.026)
    cube('POS screen',(0,.33,.003),(.345,.23,.013),'sage_dark',.012)
    begin('pickup_counter',at=(2.23,1.25,-1.27))
    cube('Pickup cabinet',(0,.25,0),(.76,.51,.43),'oak_light',.058,'wood')
    cube('Pickup shelf',(0,.03,.33),(.76,.07,.34),'porcelain',.025)
    cube('Pickup sign',(0,.47,.245),(.57,.17,.04),'iron_edge',.017)
    k.text_label('PICK UP',(0,.425,.27),.092,'porcelain')
    for i,c in enumerate(['D8B78C','B4C6A1','D8A1A5']):s.tea_cup((-.24+i*.24,.071,.32),.75,c)
    begin('straw_box',at=(2.54,1.26,-1.95))
    cube('Straw caddy',(0,.105,0),(.27,.21,.20),'oak_light',.028)
    for i in range(5):
        for j in range(3):tube('Paper straw',[(-.095+i*.044,.07,-.06+j*.05),(-.102+i*.047,.37+random.uniform(-.025,.025),-.06+j*.05)],.011,'porcelain',6)
    begin('cup_stacks',at=(.97,1.26,-1.90))
    for i in range(6):cylinder('Nested paper cup',(0,.042+i*.047,0),.087+i*.005,.052,'C7B3CB',vertices=20)
    begin('cafe_table',at=(-1.45,.06,.63),collision=[{'at':[0,.44,0],'size':[1.10,.88,1.10]}])
    lathe('Oak pedestal',(0,0,0),[(0,.26),(.04,.28),(.08,.15),(.12,.08),(.76,.08),(.80,.17)],'oak',24)
    cylinder('Round terrazzo tabletop',(0,.82,0),.55,.09,'porcelain',vertices=40)
    for j in range(55):
        a=j*2.399;r=math.sqrt(random.random())*.51
        cube('Terrazzo inlay',(math.cos(a)*r,.869,math.sin(a)*r),(.016,.002,.024),random.choice(['sage','E2B39A','C5B4D2']),.004)
    k.instance('cafe_table','cafe_table_2',(1.45,.06,1.18))
    begin('chair',at=(-2.22,.06,.63),yaw=90,collision=[{'at':[0,.48,0],'size':[.59,.96,.60]}]);s.simple_chair()
    for i,at,yaw in [(2,(-.68,.06,.63),-90),(3,(.68,.06,1.18),90),(4,(2.22,.06,1.18),-90)]:k.instance('chair','chair_'+str(i),at,yaw)
    begin('table_flower_vase',at=(-1.45,.93,.63));k.bouquet(scale=.65)
    k.instance('table_flower_vase','table_flower_vase_2',(1.45,.93,1.18))
    k.instance('table_flower_vase','counter_flower_vase',(.03,1.26,-1.46))
    begin('pastel_bench',at=(-1.8,.07,2.36),collision=[{'at':[0,.35,0],'size':[1.68,.7,.52]}])
    cube('Bench wooden base',(0,.24,0),(1.65,.36,.50),'oak_light',.065)
    for j in range(6):cube('Lavender tufted seat',(-.68+j*.275,.47,0),(.268,.15,.48),'CBB3D1',.06,'cloth')
    cube('Rose back pillow',(-.52,.74,-.17),(.45,.57,.15),'DEB2B2',.075,'cloth')
    cube('Mint loose cushion',(-.42,.76,-.05),(.35,.36,.16),'C4D0B3',.070,'cloth')
    s.plants();s.signboard()
    s.menu('good_tea_wall_sign',(-2.84,1.14,1.49),'GOOD TEA',['BRIGHTER','DAYS'],.63,.81)
    # Left-wall signage faces the room; root transforms are manifest-owned.
    root=k.KITS['good_tea_wall_sign']['root'];root.rotation_euler.z=math.pi/2;k.KITS['good_tea_wall_sign']['yaw']=90
    import importlib.util
    spec=importlib.util.spec_from_file_location('milk_revision',Path(__file__).resolve().parent/'source/milk_tea_shop/revision.py')
    rev=importlib.util.module_from_spec(spec);spec.loader.exec_module(rev)
    sys.path.insert(0,str(Path(__file__).resolve().parent/'source/milk_tea_shop'))
    rev.revise()
    k.save('545:2962',{'position':[10,9.2,12],'target':[0,1.10,.15],'size':9.4})
    rev.manifest()

if __name__=='__main__':
    k.configure('milk_tea_shop');args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    if '--bake-only' in args:k.load()
    else:geometry()
    if '--geometry-only' not in args:k.bake_and_export(ao_strength=.45,ao_distance=.36,coherent_swatches=True)
    if '--geometry-only' not in args:
        from series_batch import build
        build('milk_tea_shop')
