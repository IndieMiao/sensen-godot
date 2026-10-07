"""SGODOT-174: compact, well-stocked farm-tool shop with a usable main aisle."""
from pathlib import Path
import sys,math,json
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from zhaoyun_review import *
from shop_room_parts import *
from mathutils import Matrix

PALETTE=dict(r2.PALETTE,oak='B57F47',oak_light='CB965B',oak_edge='9E6C3B',floor='C88E55',floor_light='CC965F',floor_shade='C08850',plaster='F2DBBC',plaster_light='F6E4C9',terra='B9743D',terra_light='D89457')

def packet(name,at,crop,yaw=0):
    begin(name,at,yaw)
    colors=['7E9661','A99C69','C6A65C','89A0A0']
    cube('Folded coloured seed envelope',(0,.17,0),(.25,.35,.065),colors[crop],.016)
    cube('Cream illustrated packet label',(0,.17,.038),(.205,.282,.012),'linen',.009)
    if crop==0:
        ellipsoid('Tomato packet illustration',(0,.14,.049),(.13,.13,.012),'D55E35',12,8)
        for sign in (-1,1):leaf('Tomato calyx',(0,.20,.056),(sign*.043,.245,.056),.025,'leaf')
    elif crop==1:
        for yy in (.09,.15,.22):
            for sign in (-1,1):leaf('Spinach packet illustration',(0,.065,.055),(sign*.06,yy+.02,.055),.043,'leaf')
    elif crop==2:
        for i in range(8):
            a=i*math.tau/8;ellipsoid('Sunflower packet petal',(.058*math.cos(a),.17+.058*math.sin(a),.051),(.05,.05,.01),'E8BE4D',10,6)
        ellipsoid('Sunflower packet centre',(0,.17,.059),(.064,.064,.012),'785234',10,6)
    else:
        mesh('Carrot packet illustration',[(-.045,.22,.052),(.06,.21,.052),(-.012,.06,.052)],[(0,2,1)],'E29348')
        for sign in (-1,0,1):leaf('Carrot greens',(0,.22,.057),(sign*.055,.282,.057),.025,'leaf')
    for obj in p.KITS[name]['objects']:obj.matrix_basis=Matrix.Rotation(math.radians(-14),4,'X')@obj.matrix_basis

def pruning_tool(at,kind=0):
    x,y,z=at
    for sign in (-1,1):
        tube('Pruning tool curved handle',[(x+sign*.045,y+.22,z),(x+sign*.080,y+.12,z),(x+sign*.055,y+.02,z)],.025,'sage_dark' if kind==0 else 'terra',8)
        tube('Pruning steel jaw',[(x+sign*.045,y+.20,z),(x-sign*.055,y+.31,z),(x-sign*.07,y+.39,z)],.020,'iron_edge',8)
    cylinder('Steel pivot rivet',(x,y+.22,z+.008),.025,.024,'brass',vertices=10).rotation_euler.x=math.pi/2

def build():
    def configure(base):base.shell=lambda *a,**kw:shell(6.4,5.8,3.6,window_z=.23,door_x=2.29)
    draft_scene('farm_tools_store',configure);p.b.PALETTE.update(PALETTE);p.b.MATS.clear()
    door_and_bounds(6.4,5.8,3.6,2.29)
    # Smaller rear counter, lower to the accepted worktop scale.
    r2.scale_kit('sales_counter',(.76,.89,1));r2.move_kit('sales_counter',(-.55,.082,-1.94))
    move_zone(['cash_register','counter_flowers','counter_pencil_pot','counter_price_card'],[-.11,-.165,-.66])
    r2.move_kit('farm_tools_sign',(-1.10,2.77,-2.73));r2.move_kit('sign_sprout',(-1.10,2.50,-2.59))
    r2.remove_named('farm_tools_sign',['sign farm tools']);p.b.CURRENT=p.KITS['farm_tools_sign'];bold_lettering('FARM TOOLS',(0,-.10,.102),2.19,'linen')
    r2.move_kit('pot_wall_shelf',(1.0,2.44,-2.70));move_zone(['pots_on_shelf','hand_tools_board','shelf_supplies'],[0,0,.1])
    r2.move_kit('seed_wall_shelf',(-3.02,.63,1.87));r2.scale_kit('seed_wall_shelf',(1.20,.94,1.12))
    p.KITS['seed_wall_shelf']['collision']=[{'at':[0,.74,0],'size':[1.63,1.60,.39]}]
    r2.move_kit('silver_watering_can',(-2.99,2.17,2.29),90)
    move_zone(['front_display','display_gloves','display_tools','display_flowers','display_under_crates'],[-.35,0,.04])
    r2.move_kit('entry_crate',(1.40,.082,-2.25));p.KITS['entry_crate']['collision']=[{'at':[0,.24,0],'size':[.69,.48,.63]}]
    r2.move_kit('door_lantern',(1.79,2.46,-2.58))
    drop_modules('seed_packet','seed_packet_top','shelf_plant','window_plant','pot_shelf_plant','floor_plant','display_seed_tray','long_tools_wall','tool_barrel')
    # Leaning two-row table display, with four reusable illustrated packet types.
    begin('display_seed_rack',(-.55,1.11,1.27))
    cube('Seed display back rail',(0,.19,-.18),(1.14,.39,.075),'sage',.025,'wood')
    for row in range(2):
        z=.11-row*.20;y=.055+row*.15
        cube('Tiered seed display shelf',(0,y,z),(1.15,.07,.24),'oak_light',.018,'wood')
        cube('Seed display retaining rail',(0,y+.06,z+.12),(1.15,.08,.04),'oak',.012,'wood')
    for crop in range(4):
        row=crop//3;i=crop%3;packet('seed_crop_'+str(crop),(-.91+i*.35,1.20+row*.15,1.39-row*.20),crop)
    for i,crop in enumerate((2,0)):instance('seed_crop_'+str(crop),'rack_packet_'+str(i),(-.56+i*.35,1.35,1.19))
    # Six stocked packets on the wall shelf; same prototype GLBs reused.
    for row in range(2):
        for i in range(3):instance('seed_crop_'+str((row*3+i)%4),'wall_seed_'+str(row)+'_'+str(i),(-2.81,.71+row*.73,2.34-i*.43),90)
    begin('price_boards',(-.55,1.13,1.54))
    for x in (-.81,.85):
        cube('Small price-board frame',(x,.17,.19),(.28,.30,.038),'oak_light',.018,'wood')
        cube('Small chalkboard face',(x,.17,.215),(.23,.245,.014),'iron',.011)
        for j,length in enumerate((.13,.17)):
            tube('Chalk price dash',[(x-length/2,.12+j*.065,.225),(x+length/2,.12+j*.065,.225)],.008,'linen',5)
        cube('Price board foot',(x,.018,.17),(.28,.035,.18),'oak',.012,'wood')
    # Second laid-out hand tool, plus twine rolls on the display's lower level.
    begin('display_small_goods',(.01,1.13,1.80))
    before=len(p.KITS['display_small_goods']['objects']);garden_tool('rake',(0,0,0),.48)
    for o in p.KITS['display_small_goods']['objects'][before:]:o.matrix_basis=Matrix.Rotation(math.pi/2,4,'X')@o.matrix_basis
    for x in (-.90,.83):
        for z in (-.16,.14):
            lathe('Coarse twine roll',(x,-.71,z-.30),[(0,.10),(.15,.10),(.16,.09),(.16,.03),(.02,.03)],'terra_light',18)
    # Five varied tools in the foreground coopered barrel.
    begin('tool_barrel',(-2.35,.082,1.80),collision=[{'at':[0,.40,0],'size':[.66,.80,.66]}]);barrel(radius=.32,height=.76,lid=False)
    for i,(kind,h) in enumerate([('shovel',1.12),('fork',1.40),('rake',1.25),('shovel',.98)]):
        before=len(p.KITS['tool_barrel']['objects']);garden_tool(kind,(-.16+i*.11,.42,.05*(i%2)),h)
        pivot=v((-.16+i*.11,.42,0));mat=Matrix.Translation(pivot)@Matrix.Rotation(math.radians([-7,4,-3,9][i]),4,'Y')@Matrix.Translation(-pivot)
        for o in p.KITS['tool_barrel']['objects'][before:]:
            o.matrix_basis=mat@o.matrix_basis
            if i>=2:
                centre=v((-.16+i*.11,.42+h/2,0));o.matrix_basis=Matrix.Translation(centre)@Matrix.Rotation(math.pi,4,'X')@Matrix.Translation(-centre)@o.matrix_basis
    # Reverse two tools so metal rake/shovel heads project above the rim.
    # The remaining handles and bamboo retain varied heights.
    tube('Tall bamboo garden stake',[(.19,.18,-.07),(.24,1.84,-.12)],.025,'sage',8)
    begin('long_tools_wall',(-3.03,.87,-1.95),90)
    cube('Long-tool hanging rail',(0,1.52,0),(1.38,.14,.12),'oak',.025,'wood')
    for i,(kind,h) in enumerate([('shovel',1.48),('fork',1.11),('rake',1.57),('shovel',1.26),('fork',1.38)]):
        before=len(p.KITS['long_tools_wall']['objects']);garden_tool(kind,(-.53+i*.26,0,.14),h)
        pivot=v((-.53+i*.26,1.40,.14));rot=Matrix.Translation(pivot)@Matrix.Rotation(math.radians([-9,6,-5,11,-7][i]),4,'Y')@Matrix.Translation(-pivot)
        for o in p.KITS['long_tools_wall']['objects'][before:]:o.matrix_basis=rot@o.matrix_basis
    # Replace the old identical four-tool lineup with seven distinct lengths/jaws.
    r2.remove_named('hand_tools_board',['shaft','grip','blade','fork','rake','tooth','tine','shoulder']);p.b.CURRENT=p.KITS['hand_tools_board']
    pruning_tool((-.50,.13,.13),0);pruning_tool((-.27,.12,.13),1)
    for i in range(5):garden_tool('fork' if i%2 else 'shovel',(-.03+i*.21,.09,.13),.57+.045*(i%3))
    begin('left_sack_crate',(-2.87,.082,2.31),90,[{'at':[0,.29,0],'size':[1.22,.58,.52]}])
    crate(width=1.12,height=.42,depth=.47)
    for x in (-.28,.28):
        cube('Folded filled linen seed sack',(x,.41,0),(.47,.30,.37),'linen',.08,'cloth')
        cube('Sack green woven stripe',(x,.568,0),(.13,.012,.34),'sage',.013,'cloth')
        for i in range(9):ellipsoid('Visible sack seed',(x+.13+(i%3)*.018,.51+(i//3)*.018,.16),(.033,.035,.025),'terra_light',8,6)
    begin('counter_side_stock',(.75,.082,-2.38),collision=[{'at':[0,.34,0],'size':[.48,.68,.50]}])
    for y in (0,.16,.32):pot((0,y,0),.19,.27)
    begin('counter_checked_cloth',(.19,1.25,-1.94))
    r2.metric_cloth('Counter folded square gingham',[(-.39,.01),(.35,.01),(.45,-.07),(.46,-.39)],-.22,.44,.105)
    begin('door_copper_bell',(3.02,2.35,-2.53))
    tube('Bell wrought mounting arm',[(0,.31,-.07),(0,.32,.15),(0,.17,.15)],.024,'iron',8)
    lathe('Copper shop bell',(0,-.10,.15),[(0,.14),(.03,.15),(.10,.11),(.27,.055),(.29,.042)],'B48043',24)
    ellipsoid('Bell hanging clapper',(0,-.12,.15),(.054,.072,.054),'brass',12,8)
    r2.scale_kit('door_copper_bell',(1.23,1.23,1.23));r2.scale_kit('entry_mat',(1.17,1,1.20))
    begin('sign_iron_chains',(-1.10,3.21,-2.64))
    for x in (-.90,.90):
        for i in range(3):tube('Interlocking sign chain',[(x+.028*math.cos(a),-.02-i*.060+.048*math.sin(a),.01*(i%2)) for a in [j*math.tau/12 for j in range(13)]],.009,'iron',6)
    for name,asset,at,s,yaw,col in [
      ('entry_terracotta_plant','monstera_woven',(2.88,.083,-1.65),.96,-25,True),
      ('shelf_trailing_plant','pothos',(-2.97,2.16,1.33),.83,90,False),
      ('window_trailing_plant','pothos',(-2.98,1.40,.73),1.06,90,False),
      ('pot_shelf_trailing_plant','pothos',(1.38,2.56,-2.61),.91,0,False)]:
        r2.shared_plant(name,asset,at,s,yaw,[{'at':[0,.30,0],'size':[.76,.60,.76]}] if col else None)
    r2.scale_kit('front_display',(.91,1,1))
    move_zone(['front_display','display_gloves','display_tools','display_flowers','display_under_crates','display_seed_rack','display_small_goods','price_boards'],[.75,0,.24])
    for name in ('seed_crop_0','seed_crop_1','seed_crop_2','seed_crop_3'):
        k=p.KITS[name];r2.move_kit(name,(k['at'][0]+.75,k['at'][1],k['at'][2]+.24))
    for inst in p.INSTANCES:
        if inst['name'].startswith('rack_packet_'):
            inst['position'][0]+=.75;inst['position'][2]+=.24
            bpy.data.objects[inst['name']].location.x+=.75;bpy.data.objects[inst['name']].location.y-=.24
    # Reference calls for a terracotta vessel: use the supplied standalone pot
    # around the existing plant, retaining the same shared atlas and source.
    r2.shared_plant('entry_terracotta_pot','pot_terracotta',(2.88,.083,-1.65),1.18,0)
    merge_modules('counter_dressing',['cash_register','counter_flowers','counter_pencil_pot','counter_price_card','counter_checked_cloth'])
    merge_modules('display_dressing',['display_gloves','display_tools','display_flowers','display_under_crates','display_seed_rack','display_small_goods','price_boards'])
    merge_modules('wall_dressing',['pots_on_shelf','shelf_supplies','sign_sprout','sign_iron_chains','door_copper_bell','silver_watering_can'])
    begin('front_sack_crate',(-2.12,.082,2.63),collision=[{'at':[0,.29,0],'size':[.68,.58,.49]}])
    crate(width=.66,height=.40,depth=.47)
    for x in (-.15,.15):
        cube('Soft sack in front corner crate',(x,.43,0),(.28,.32,.38),'linen',.055,'cloth')
        cube('Seed sack woven green band',(x,.598,0),(.10,.01,.34),'sage',.008,'cloth')
    begin('counter_extra_pots',(.99,.082,-1.75),collision=[{'at':[0,.28,0],'size':[.47,.56,.47]}])
    for h in (0,.13,.26):pot((0,h,0),.19,.28)
    begin('metal_fittings',(0,0,0));dest=p.KITS['metal_fittings'];bpy.context.view_layer.update()
    for name,kit in list(p.KITS.items()):
        if name=='metal_fittings':continue
        for obj in list(kit['objects']):
            if not any(t in obj.name.lower() for t in ('iron barrel hoop','hoop rivet','shovel blade','fork tine','fork shoulder','rake tooth','rake transverse','pruning steel','steel pivot','copper shop bell','bell hanging clapper')):continue
            world=obj.matrix_world.copy();kit['objects'].remove(obj)
            for c in list(obj.users_collection):c.objects.unlink(obj)
            dest['collection'].objects.link(obj);obj.parent=dest['root'];obj.matrix_world=world;dest['objects'].append(obj)
    p.MANIFEST_EXTRA['review_views']=[{'name':'detail-display','position':[5,3.8,6],'target':[-.65,1.0,1.20],'size':4.5},{'name':'detail-tools','position':[6,3.7,6],'target':[.15,1.80,-2.30],'size':5.4}]
    lighting={'ambient':.53,'ambient_color':'FFE8CA','sun':1.28,'sun_color':'FFE4B5','sun_position':[-7,5.3,-1.4],'sun_target':[0,0,0],'shadow_bias':.07,'shadow_normal_bias':.7,'shadow_distance':25,'background':'D4E8D8','background_gradient':True,'points':[{'position':[1.80,2.36,-2.4],'energy':.45,'color':'FFE0A4','range':1.8}]}
    camera=json.loads(Path(__file__).with_name('camera-review.json').read_text())
    finish(camera['camera'],lighting,json.loads(Path(__file__).with_name('bench-review.json').read_text()),materials={'metal_fittings':'metal'},no_shadow=['counter_dressing','display_dressing'],botanical=['counter_dressing','display_dressing'])

if __name__=='__main__':build()
