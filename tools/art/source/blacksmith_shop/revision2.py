"""SGODOT-178 R2.1: accepted 172 sections, gray forge, grouped varied tools."""
import math,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tavern'))
import takeover as t
import thermal
import scene_room_pipeline as p
from scene_room_pipeline import *
from shop_room_parts import crate
from mathutils import Matrix

def drape(name,at,width,color,profile):
    begin(name,at);verts=[]
    for j,(z,y) in enumerate(profile):
        for i in range(9):verts.append((-width/2+width*i/8,y+.011*math.sin(i+j),z))
    ob=mesh('Soft hanging cloth',verts,[(j*9+i,j*9+i+1,(j+1)*9+i+1,(j+1)*9+i) for j in range(len(profile)-1) for i in range(8)],color,'cloth',True);ob.modifiers.new('Cloth thickness','SOLIDIFY').thickness=.009

def tools():
    for name in ('hammer_wall','tongs_wall'):t.clear(name)
    for name,width in [('hammer_wall',1.96),('tongs_wall',1.98)]:
        p.b.CURRENT=p.KITS[name];cube('Irregular tool hanging rail',(0,.71,0),(width,.12,.12),'oak',.018,'wood')
    for kind in range(3):
        begin('hammer_variant_'+str(kind),(.73-.79+kind*.4,1.49+(kind%2)*.04,-2.63))
        height=[.64,.57,.68][kind]
        tube('Curved hickory handle',[(0,0,0),(.015,height*.45,0),(0,height,0)],.032,'oak_light',8)
        cube('Steel hammer head',(0,height,0),[(.33,.16,.16),(.22,.22,.20),(.39,.13,.14)][kind],'iron_edge',.017)
        cube('Cool polished striking face',(-[.17,.115,.20][kind],height,0),(.016,[.13,.19,.11][kind],.13),'929AA0',.005)
        tube('Iron hanging hook',[(-.025,height+.12,-.06),(-.025,height+.06,.03),(.025,height+.04,.03)],.013,'iron',6)
    for i in range(3,5):instance('hammer_variant_'+str(i%3),'wall_hammer_'+str(i),(.73-.79+i*.4,1.49+(i%2)*.04,-2.63))
    for kind in range(3):
        begin('tong_variant_'+str(kind),(.69-.80+kind*.32,.55+(kind%2)*.055,-2.59))
        h=[.72,.64,.78][kind]
        for side in (-1,1):
            pts=[(side*.065,0,0),(side*.10,h*.17,0),(side*.074,h*.49,0),(-side*.027,h*.72,0),(-side*.095,h*.87,0),(-side*[.047,.018,.065][kind],h,0)]
            tube('Tong curved jaw variant',pts,.018,'iron_edge',8)
        ellipsoid('Tong pivot pin',(0,h*.72,.022),(.057,.057,.03),'929AA0',10,6)
    for i in range(3,6):instance('tong_variant_'+str(i%3),'wall_tong_'+str(i),(.69-.80+i*.32,.55+(i%2)*.055,-2.59))
    # Horizontal bench tool is authored directly so both local GLB and merge keep its pose.
    t.delete('bench_tongs')
    begin('bench_tongs',(.32,1.80,1.20))
    for side in (-1,1):tube('Tongs on hot stock',[(side*.05,0,-.10),(side*.025,.015,0),(side*.075,0,.28),(side*.10,0,.54)],.018,'iron_edge',8)



def forge():
    t.remove_matching('brick_forge',['stored forge firewood'])
    p.b.CURRENT=p.KITS['brick_forge']
    for row in range(3):
        for col in range(4-row%2):
            x=-.41+col*.27+(row%2)*.12;y=.16+row*.23
            o=cylinder('Bark firewood log',(x,y,.0),.125,.86,['624331','77533B','684535'][(col+row)%3],vertices=10);o.rotation_euler.x=math.pi/2
            o=cylinder('Readable log endgrain',(x,y,.435),.11,.009,['AA7849','A57145','B18354'][(col+row)%3],vertices=10);o.rotation_euler.x=math.pi/2
            for r in (.045,.077):tube('Log growth ring',[(x+r*math.cos(a),y+r*math.sin(a),.442) for a in [i*math.tau/14 for i in range(15)]],.004,'755138',5)
    # Mortar follows the real solid side panels, with staggered vertical brick joints.
    for side in (-1,1):
        for row in range(7):
            y=1.15+row*.205
            cube('Side brick mortar course',(side*.958,y,-.07),(.009,.014,1.32),'70483A',.002)
            for z in [-.60+(row%2)*.22+i*.43 for i in range(3)]:cube('Staggered side brick joint',(side*.961,y+.098,z),(.010,.183,.014),'70483A',.002)
    p.b.CURRENT=p.KITS['forge_hood']
    for side in (-1,1):
        tube('Vertical hood iron strap',[(side*.80,.11,.733),(side*.25,.79,.29)],.034,'iron_edge',6)
        for y in (.34,.63):ellipsoid('Hood strap rivet',(side*(.80-(y-.11)*.81),y,.733-(y-.11)*.65+.025),(.049,.049,.032),'8F9397',10,6)
    thermal.smoke();thermal.fire()



def details():
    t.clear('forge_sign')
    cube('Reddish oak workshop sign',(0,0,0),(2.29,.82,.10),'BA875F',.05,'wood')
    t.bold('FORGE',(0,.08,.062),1.22,'3A302B');t.bold('WORKSHOP',(0,-.22,.062),1.92,'3A302B')
    for x in (-1.02,1.02):
        for y in (-.30,.30):ellipsoid('Iron sign nail',(x,y,.072),(.052,.052,.025),'iron_edge',10,6)
        tube('Workshop sign hook',[(x,.36,0),(x,.52,0),(x+.08,.53,-.07)],.023,'iron',8)
    p.b.CURRENT=p.KITS['anvil_workbench']
    for x in (-1.05,1.05):
        for z in (-.49,.49):
            cube('Iron bench corner plate',(x,.92,z),(.20,.24,.025),'iron_edge',.019)
            ellipsoid('Bench rivet',(x,.91,z+math.copysign(.024,z)),(.06,.06,.032),'979CA0',10,6)
            cube('Iron bench foot wrap',(x,.14,z),(.21,.23,.18),'iron_edge',.018)
    drape('barrel_towel',(-2.25,1.01,1.35),.34,'9B9290',[(-.28,0),(.15,0),(.31,-.05),(.36,-.44)])
    drape('shelf_green_cloth',(-2.76,1.65,.35),.34,'7E8660',[(-.10,0),(.14,0),(.25,-.08),(.29,-.38)])
    drape('green_apron',(2.76,1.67,-2.72),.42,'697556',[(0,0),(.025,-.33),(.06,-.78)])
    p.b.CURRENT=p.KITS['green_apron'];tube('Apron neck loop',[(-.14,0,0),(-.12,.26,0),(.12,.26,0),(.14,0,0)],.022,'777B58',8)
    begin('left_floor_crate',(-2.51,.082,2.32),collision=[{'at':[0,.26,0],'size':[.64,.52,.49]}]);crate(width=.64,height=.52,depth=.49)
    for x in (-.17,.10):cube('Crated spare steel',(x,.48,0),(.18,.24,.27),'iron_edge',.022)
    begin('shelf_toolbox',(-2.75,.79,.41),90);cube('Leather tool box',(0,.18,0),(.46,.34,.30),'785340',.035)
    for x in (-.16,.16):cube('Box metal clasp',(x,.15,.161),(.045,.10,.025),'iron_edge',.006)
    tube('Tool box carry handle',[(-.11,.36,0),(-.09,.42,0),(.09,.42,0),(.11,.36,0)],.016,'iron',8)
    begin('coal_shovel',(-2.72,.18,-1.22));cube('Long coal shovel blade',(0,.1,0),(.25,.30,.035),'iron_edge',.035);tube('Shovel shaft',[(0,.21,0),(0,1.23,-.08)],.022,'iron',8)
    tube('Shovel loop grip',[(-.09,1.22,-.08),(-.09,1.42,-.08),(.09,1.42,-.08),(.09,1.22,-.08),(-.09,1.22,-.08)],.018,'iron_edge',8)
    begin('bench_vise',(1.92,.963,-1.97));cube('Vise pedestal',(0,.05,0),(.32,.10,.25),'iron',.02)
    for x in (-.10,.10):cube('Vise jaw',(x,.19,0),(.075,.23,.24),'iron_edge',.02)
    tube('Vise spindle',[(-.20,.12,0),(.24,.12,0)],.025,'959EA4',8);tube('Vise T handle',[(.24,-.02,0),(.24,.28,0)],.015,'959EA4',8)
    t.clear('forge_mat');cube('Gray green woven mat',(0,0,0),(2.09,.025,.73),'727863',.032,'cloth')
    for x in [-.93+i*.31 for i in range(7)]:cube('Check vertical border',(x,.016,0),(.039,.004,.65),'9B8A6C',.001)
    for z in (-.27,-.04,.19):cube('Check horizontal border',(0,.019,z),(1.98,.004,.041),'9B8A6C',.001)
    # Luminous lantern glass is its own material group.
    t.remove_matching('forge_lantern',['warm glass'])
    begin('lantern_glow',(2.74,2.54,-2.76));cube('Amber lantern glass',(0,0,0),(.205,.28,.205),'FFCC71',.025)


def revise():
    p.b.PALETTE.update({'oak':'895B43','oak_light':'AA7553','oak_edge':'6B4939','oak_dark':'3C302B','floor':'A57754','floor_light':'AE805D','floor_shade':'906344','plaster':'4E565F','iron':'30353A','iron_edge':'5E666C'})
    t.structure(6.4,6.0,3.70)
    # Eliminate the old protruding yellow cap; accepted 172 timber stays reddish brown.
    for name in ('window_wall','back_wall'):
        t.remove_matching(name,['timber joint cap'])
    tools();forge();details()
    t.stretch('back_tool_bench',(1,1.16,1))
    t.move('punch_set',(1.31,1.0552,-2.0));t.move('bench_vise',(1.92,1.0622,-1.97))
    t.stretch('forge_stool',(1,1.18,1));p.KITS['forge_stool']['collision']=[]
    for name in ('main_anvil','heated_bar_glow','bench_tongs'):
        at=p.KITS[name]['at'];t.move(name,(at[0],at[1]-.11,at[2]))
    t.remove_matching('main_anvil',['conical horn']);p.b.CURRENT=p.KITS['main_anvil']
    verts=[];faces=[]
    for dx,r in [(0,.19),(.15,.145),(.33,.075),(.56,.004)]:
        for j in range(16):
            a=j*math.tau/16;verts.append((.42+dx,.46+r*math.cos(a),r*math.sin(a)))
    for i in range(3):
        for j in range(16):faces.append((i*16+j,i*16+(j+1)%16,(i+1)*16+(j+1)%16,(i+1)*16+j))
    mesh('Tapered forged horn',verts,faces,'858C93',smooth=True)
    t.delete('shelf_plant');t.delete('right_shelf_plant')
    d={'revision':'R2.1'};t.add_plant(d,'LeftPothos','pothos',(-2.85,2.49,-.29),.66,90);t.add_plant(d,'RightPothos','pothos',(2.63,2.93,-2.73),.65)
    d['material_overrides']={'fire':{'emission':'FF841F','emission_use_atlas':True,'emission_energy':.22,'unshaded':True},'forge_coals':{'emission':'FF6225','emission_use_atlas':True,'emission_energy':.65},'heated_bar_glow':{'emission':'FFB12E','emission_use_atlas':True,'emission_energy':3.0},'lantern_glow':{'emission':'FFCE80','emission_use_atlas':True,'emission_energy':2.5}}
    d['local_lights']=[{'name':'forge_fire','position':[-1.35,2.04,-1.16],'energy':3.1,'range':4.25,'color':'FF8B36','attenuation':1.15},{'name':'lantern','position':[2.66,2.50,-2.47],'energy':.85,'range':1.9,'color':'FFD08A'},{'name':'hot_steel','position':[.31,1.92,1.20],'energy':.50,'range':.85,'color':'FFAB37'}]
    d['lighting']={'background':'D5DAD3','ambient':'B7C7D1','ambient_energy':.37,'sun_color':'E1E7E8','sun_energy':.72,'sun_position':[5,8,4],'sun_target':[0,0,-1],'angular_distance':7,'lamps':[]}
    d['review_lighting']={'ambient':.37,'ambient_color':'B7C7D1','sun':.72,'sun_color':'E1E7E8','sun_position':[5,8,4],'sun_target':[0,0,-1],'points':[]}
    d['review_views']=[{'name':'forge-fire-detail','position':[3.7,3.7,5.5],'target':[-1.48,1.6,-2.03],'size':3.5},{'name':'smoke-detail','position':[4.4,6.7,6.0],'target':[-1.15,4.9,-2.29],'size':2.8},{'name':'tools-bench-detail','position':[5,4,7],'target':[1.15,1.75,-1.0],'size':4.3}]
    entry=t.bounds(d,6.4,6,entrance_x=-.95);y=.082;d['spawn']=[-.95,y,2.72]
    d['bench']={'floor_y':y,'route':[{'name':n,'position':[x,y,z],**({'capture':c} if c else {})} for n,x,z,c in [('entry',-.95,2.72,'door'),('left_front',-1.55,2.4,None),('left_bench',-1.48,.57,None),('forge_safe',-1.3,-.72,'main'),('water_side',-1.58,1.29,None),('front',-1.02,2.32,None),('bench_right',1.64,2.28,None),('stump_front',1.77,.28,None),('rear_bench',.45,-1.30,None)]],'blocked':[{'name':n,'from':[a[0],y,a[1]],'to':[b[0],y,b[1]],'target':target} for n,a,b,target in [('mainbench',(-1.55,1.25),(.15,1.25),'/anvil_workbench/'),('furnace',(-1.40,-.75),(-1.40,-2.2),'/brick_forge/'),('water',(-1.55,1.35),(-2.52,1.35),'/quench_barrel/'),('stump',(1.64,-.52),(2.39,-.52),'/stump/'),('smallbench',(1.50,-1.24),(1.5,-1.99),'/back_tool_bench/')]],'gaps':[{'name':'forge_to_mainbench','from':[-1.6,y,-.2],'to':[.7,y,-.2],'measure':[[-.8,.55,-1.48],[-.8,.55,.705]],'width':2.185,'minimum':.80}],'entrance':entry,'slide':{'from':[2.98,y,2.05],'direction':[1,0,-1],'tangent':[0,0,-1],'seconds':.4},'input_start':[-1.30,y,.10],'scale':{'door':{'applicable':False,'reason':'Open-front workshop; no human doorway asset.'},'counter':{'height':1.045,'source':'Main workbench serves as work counter'},'table':{'height':1.045,'source':'Main workbench .97+.075'},'chair':{'height':.66,'source':'Stool (.50+.06)*1.18'}}}
    t.finish(d,[(86,1114),(734,1455),(1394,1117)],(1489,1499),(6.8,6.4))

    if '--geometry-only' not in sys.argv:thermal.export_fire()
