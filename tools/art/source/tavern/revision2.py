"""SGODOT-177 R2: dark timber tavern, 172 structure, varied props and local lamplight."""
import math,random,json
from mathutils import Matrix,Vector
import bpy
import scene_room_pipeline as p
from scene_room_pipeline import *
from shop_room_parts import barrel,pot
import takeover as t

def cloth(name,at,width,profile,color='linen_green'):
    begin(name,at);vs=[]
    for j,(z,y) in enumerate(profile):
        for i in range(13):vs.append((-width/2+i*width/12,y+.008*math.sin(i*.6+j),z))
    fs=[(j*13+i,j*13+i+1,(j+1)*13+i+1,(j+1)*13+i) for j in range(len(profile)-1) for i in range(12)]
    o=mesh('Draped woven runner',vs,fs,color,'cloth',True);o.modifiers.new('Fabric thickness','SOLIDIFY').thickness=.009
    for x in (-width/2+.028,width/2-.028):tube('Runner narrow cream border',[(x,y+.01,z) for z,y in profile],.007,'B5A885',5)

def bottle_shape(kind):
    heights=[.42,.32,.37,.46,.30];h=heights[kind];r=[.074,.092,.071,.064,.088][kind]
    profiles=[[(0,r*.8),(.035,r),(.28,r),(.34,r*.40),(.40,r*.40),(.42,r*.48)],[(0,r*.8),(.04,r),(.20,r*1.08),(.265,r*.52),(.32,r*.52)],[(0,r*.76),(.06,r),(.22,r),(.29,r*.40),(.37,r*.40)],[(0,r*.80),(.04,r),(.32,r*.86),(.38,r*.4),(.46,r*.4)],[(0,r*.86),(.03,r),(.18,r),(.235,r*.75),(.30,r*.75)]]
    colors=['3E6045','6B3D27','557A75','3D594C','9A7145']
    lathe('Bottle side silhouette variant '+str(kind),(0,0,0),profiles[kind],colors[kind],12)
    cylinder('Bottle cork or metal cap',(0,h+.013,0),r*(.5 if kind!=4 else .8),.028,'9E8055' if kind%2 else '4A4741',vertices=10)
    cube('Cream bottle label',(0,h*.42,r+.003),(r*1.4,h*.30,.008),['D6C6A4','BEA070','A2B294','D8C7A3','C39A69'][kind],.005)
    for j in range(2):cube('Printed label bar',(0,h*.39+j*.038,r+.011),(r*.92,.009,.004),'4D493B',0)
    for o in p.b.CURRENT['objects']:
        if 'label' in o.name.lower():o['atlas_constant_colour']=True

def mug_shape(kind):
    colors=['A86435','CCB595','6D7D6B'];h=[.25,.28,.22][kind];r=[.12,.104,.137][kind]
    lathe('Mug variant '+str(kind),(0,0,0),[(0,r*.83),(.035,r),(h-.02,r),(h,r*.94),(h,r*.76),(.045,r*.72)],colors[kind],16)
    cylinder('Dark ale surface',(0,h-.045,0),r*.73,.008,'533826',vertices=16)
    tube('Round mug handle',[(r*.85+.09*math.cos(a),h*.5+.09*math.sin(a),0) for a in [(-math.pi*.55+j*math.pi*1.1/14) for j in range(15)]],.024,colors[kind],8)
    if kind==1:
        for y in (.05,h-.04):lathe('Tankard metal band',(0,y,0),[(0,r+.004),(.014,r+.004)],'6E716C',16)

def rebuild_stock():
    for name in ('bottle_green','bottle_amber','back_bar','table_mug','bar_drinks'):t.delete(name)
    begin('back_bar',(.07,1.51,-3.04))
    for x in (-1.48,1.48):cube('Open rack end post',(x,.67,-.055),(.105,1.48,.38),'oak',.026,'wood','Y')
    for y in (.02,.68,1.37):cube('Open bottle shelf',(0,y,.08),(3.10,.075,.49),'oak_light',.025,'wood')
    placements=[]
    for row in range(2):
        for col in range(10):placements.append((row,col,(-1.20+col*.282,1.578+row*.66,-2.96)))
    made=set()
    for i,(row,col,at) in enumerate(placements):
        kind=(col*3+row*2)%5;name='bottle_variant_'+str(kind)
        if name not in made:begin(name,at,yaw=(col%3-1)*7);bottle_shape(kind);made.add(name)
        else:instance(name,'shelf_bottle_'+str(i),at,(col%3-1)*7)
    for kind,at in enumerate([(-.92,1.418,-1.22),(-2.56,1.297,.92),(.39,1.174,2.28)]):
        begin('mug_variant_'+str(kind),at,yaw=kind*26);mug_shape(kind)
    for i,(at,kind,yaw) in enumerate([((-.24,1.418,-1.13),1,-27),((.52,1.418,-1.29),2,12),((-1.62,1.297,.80),0,66),((-.27,1.174,2.47),1,81),((2.18,1.174,.91),2,10),((2.89,1.174,1.13),0,-35),((-.55,1.578,-2.68),1,10),((.28,2.238,-2.68),2,30)]):instance('mug_variant_'+str(kind),'varied_mug_'+str(i),at,yaw)
    for i,(at,kind) in enumerate([((-1.82,1.29,.70),2),((.33,1.176,2.02),0),((2.58,1.176,.65),3),((2.54,2.13,-3.06),4)]):instance('bottle_variant_'+str(kind),'table_bottle_'+str(i),at,i*25)

def wall_panels():
    for name in ('window_wall','back_wall'):
        for o in p.KITS[name]['objects']:
            if 'plaster infill' not in o.name.lower():continue
            mat=material('734B32','wood').copy();mat.name='Tavern varied wide timber '+name;o.data.materials.clear();o.data.materials.append(mat)
            nt=mat.node_tree;bsdf=nt.nodes.get('Principled BSDF');base=bsdf.inputs['Base Color'].links[0].from_socket
            geo=nt.nodes.new('ShaderNodeNewGeometry');sep=nt.nodes.new('ShaderNodeSeparateXYZ');nt.links.new(geo.outputs['Position'],sep.inputs[0])
            def op(kind,a,b):
                n=nt.nodes.new('ShaderNodeMath');n.operation=kind
                for i,val in enumerate((a,b)):
                    if isinstance(val,(int,float)):n.inputs[i].default_value=val
                    else:nt.links.new(val,n.inputs[i])
                return n.outputs[0]
            y=sep.outputs['Z'];within=op('MODULO',y,.68)
            seam=op('LESS_THAN',within,.007)
            for height in (.18,.41):seam=op('MAXIMUM',seam,op('LESS_THAN',op('ABSOLUTE',op('SUBTRACT',within,height),0),.006))
            shade=op('ADD',op('MULTIPLY',op('SINE',op('MULTIPLY',op('FLOOR',op('DIVIDE',y,.18),0),12.989),0),.06),.90)
            mix=nt.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;nt.links.new(base,mix.inputs[1]);nt.links.new(shade,mix.inputs[2])
            joint=nt.nodes.new('ShaderNodeMixRGB');nt.links.new(seam,joint.inputs[0]);nt.links.new(mix.outputs[0],joint.inputs[1]);joint.inputs[2].default_value=(*rgb('423023'),1);nt.links.new(joint.outputs[0],bsdf.inputs['Base Color'])
        p.b.CURRENT=p.KITS[name]
        length=6.8 if name=='window_wall' else 7.4
        for x in [(-length/2+.28)+i*.20 for i in range(int((length-.4)/.20))]:
            if name=='window_wall' and 1.83<x<3.17:continue
            cube('Lower vertical oak wainscot',(x,.40,.115),(.188,.72,.032),['624630','72513A','694A33'][int(abs(x)*10)%3],.005,'wood','Y')
        t.remove_matching(name,['timber dado rail'])
        if name=='window_wall':
            for x,w in [(-.72,4.92),(3.23,.13)]:cube('Dark dado rail around arch',(x,.84,.155),(w,.105,.095),'oak_edge',.022,'wood')
        else:cube('Dark dado rail',(0,.84,.155),(length-.38,.105,.095),'oak_edge',.022,'wood')

def wheel():
    t.clear('hanging_chandelier')
    lathe('Thick wooden wagon wheel',(0,0,0),[(0,.67),(.12,.67),(.12,.55),(0,.55)],'oak',40)
    lathe('Outer iron binding',(0,.035,0),[(0,.675),(.044,.675),(.044,.67),(0,.67)],'49473D',40)
    cylinder('Wood wheel hub',(0,.055,0),.105,.12,'oak_light',vertices=16)
    for i in range(8):
        a=i*math.pi/4;tube('Oak wheel spoke',[(math.cos(a)*.08,.05,math.sin(a)*.08),(math.cos(a)*.58,.05,math.sin(a)*.58)],.029,'oak_light',8)
    for i in range(4):
        a=i*math.pi/2;start=Vector((math.cos(a)*.53,.13,math.sin(a)*.53));end=Vector((0,.74,0))
        for j in range(10):
            c=start.lerp(end,j/9);side=Vector((math.cos(a),0,math.sin(a))) if j%2 else Vector((-math.sin(a),0,math.cos(a)))
            points=[tuple(c+side*(.027*math.cos(q))+Vector((0,.043*math.sin(q),0))) for q in [n*math.tau/10 for n in range(11)]]
            tube('Individual interlocked suspension link',points,.007,'4E4A40',5)
    for a in p.INSTANCES:
        if a['name'].startswith('chandelier_'):
            idx=int(a['name'][-1]);angle=idx*math.pi/2;a['position']=[-2.2+math.cos(angle)*.60,2.71,.10+math.sin(angle)*.60]

def details():
    t.remove_matching('landscape_frame',['botanical'])
    p.b.CURRENT=p.KITS['landscape_frame']
    cube('Landscape muted sky',(0,0,.033),(.60,.37,.006),'B3B2A0',.002)
    for title,pts,col in [('Far mountains',[(-.3,-.12,.04),(-.3,.00,.04),(-.2,.08,.04),(-.1,.02,.04),(.03,.13,.04),(.16,.01,.04),(.3,.09,.04),(.3,-.12,.04)],'7F8980'),('Near grassy hills',[(-.3,-.18,.05),(-.3,-.04,.05),(-.15,-.10,.05),(0,.02,.05),(.12,-.04,.05),(.3,-.01,.05),(.3,-.18,.05)],'626F4F')]:mesh(title,pts,[tuple(range(len(pts)))],col)
    t.clear('tavern_sign')
    cube('Framed tavern wood sign',(0,0,0),(2.78,.66,.10),'7C563A',.05,'wood')
    cube('Sign inset warm timber',(0,0,.065),(2.56,.46,.035),'B6824B',.035,'wood')
    t.bold('TAVERN',(0,-.125,.091),2.13,'382D25')
    tube('Iron hanging rail',[(-1.61,.49,-.04),(1.61,.49,-.04)],.028,'41423D',10)
    for x in (-1.13,1.13):
        tube('Forged sign bracket',[(x,.29,.025),(x,.52,.025),(x+.10,.58,-.01),(x+.15,.51,-.03)],.024,'41423D',8)
        cube('Sign corner iron cleat',(x,-.21,.095),(.11,.08,.016),'41423D',.012)
    begin('beer_chalkboard',(2.64,2.43,-3.12))
    cube('Chalkboard framed wood',(0,0,0),(.63,.89,.07),'oak',.037,'wood');cube('Chalk face',(0,0,.04),(.52,.77,.014),'34413A',.015)
    tube('Chalk beer mug',[(-.15,.13,.056),(-.15,-.22,.056),(.13,-.22,.056),(.13,.13,.056),(-.15,.13,.056)],.012,'D0C09A',6)
    tube('Chalk mug handle',[(.13,.08,.056),(.23,.08,.056),(.23,-.12,.056),(.13,-.12,.056)],.012,'D0C09A',6)
    for x in (-.10,0,.10):tube('Chalk beer foam',[(x-.07,.15,.056),(x-.06,.23,.056),(x,.26,.056),(x+.05,.20,.056)],.015,'D0C09A',6)
    begin('copper_cookware',(-3.48,2.65,-1.79),90)
    tube('Pot hanging bar',[(-.42,.19,0),(.42,.19,0)],.022,'oak_edge',8)
    for x,dy in [(-.22,0),(.22,-.09)]:
        o=lathe('Copper hanging skillet',(x,-.21+dy,.07),[(0,.14),(.035,.17),(.073,.17),(.075,.14),(.018,.12)],'A76F38',18);o.rotation_euler.x=math.pi/2
        tube('Copper pot handle',[(x,-.17+dy,.07),(x,.16,.07)],.018,'805333',8)
    p.b.CURRENT=p.KITS['long_bar'];cube('Bar front waist rail',(0,.58,.473),(3.84,.095,.074),'oak_light',.020,'wood')
    tube('Brass customer footrest',[(-1.79,.23,.60),(1.8,.23,.60)],.032,'9B7E4B',10)
    for x in (-1.65,0,1.65):tube('Footrest bracket',[(x,.23,.61),(x,.20,.43)],.026,'79643D',8)
    cloth('table_runner',(-2.14,1.287,.91),.54,[(-.61,.0),(.50,0),(.63,-.04),(.67,-.36),(.69,-.55)])
    cloth('bar_runner',(.93,1.418,-1.45),.42,[(-.40,0),(.43,0),(.52,-.06),(.55,-.53)],'B9AB87')
    begin('ceramic_jug',(.73,1.427,-1.68));lathe('Round tavern pitcher',(0,0,0),[(0,.095),(.05,.16),(.22,.18),(.31,.095),(.38,.082),(.40,.095)],'B9BCA2',20)
    tube('Pitcher loop handle',[(.09,.35,0),(.25,.32,0),(.27,.16,0),(.14,.08,0)],.027,'9EAA95',8)
    # A second barrel orientation, keeping the existing collision footprint outside the aisle.
    a=next(a for a in p.INSTANCES if a['name']=='barrel_right_two');a['asset']='horizontal_floor_barrel'
    begin('horizontal_floor_barrel',(3.10,.082,-1.58),collision=[{'at':[0,.33,0],'size':[.67,.66,.84]}]);barrel(radius=.32,height=.82)
    rec=p.KITS['horizontal_floor_barrel'];change=Matrix.Translation(v((0,.34,.40)))@Matrix.Rotation(math.pi/2,4,'X')
    for o in rec['objects']:o.matrix_basis=change@o.matrix_basis
    # The primary is the former placement, so discard the redundant instance.
    root=bpy.data.objects[a['name']]
    for o in list(root.children):bpy.data.objects.remove(o,do_unlink=True)
    bpy.data.objects.remove(root,do_unlink=True);p.INSTANCES.remove(a)
    begin('right_plant_shelf',(2.24,2.16,-3.15));cube('Right bottle and plant shelf',(0,0,0),(.74,.08,.38),'oak',.024,'wood')
    begin('floor_clay_pitcher',(2.86,.082,-.76));pot(radius=.21,height=.48,color='AB8D6B')


def revise():
    p.b.PALETTE.update({'oak':'795437','oak_light':'A27346','oak_edge':'60452F','oak_end':'795437','oak_dark':'3D2D22','floor':'986B43','floor_light':'A27247','floor_shade':'906440','joint':'58412B','iron':'333731','iron_edge':'4C4C43','linen_green':'777B54','linen_dark':'596247'})
    t.structure(7.4,6.8,3.8);wall_panels()
    # Preserve the Basic Room scale: table tops 1.04–1.21m and stool seats 0.65/0.78m.
    t.stretch('round_table',(1,1.18,1));t.stretch('bar_stool',(1,.95,1))
    for name in ('bar_stool','dining_stool'):p.KITS[name]['collision']=[]
    # 3 stool variants: round, square and round with a low back; same accepted seat height.
    begin('square_dining_stool',(-3.02,.082,.85));cube('Squared softened seat',(0,.60,0),(.48,.10,.48),'oak_light',.04,'wood')
    for x in (-.16,.16):
        for z in (-.16,.16):cube('Square stool leg',(x,.29,z),(.075,.58,.075),'oak',.016,'wood','Y')
    begin('backed_dining_stool',(1.62,.082,.94));cylinder('Round chair seat',(0,.60,0),.25,.10,'oak_light',vertices=24)
    for x in (-.17,.17):
        for z in (-.16,.16):cube('Chair stile',(x,.55 if z<0 else .29,z),(.075,1.10 if z<0 else .58,.075),'oak',.02,'wood','Y')
    cube('Low curved back rail',(0,1.02,-.16),(.45,.16,.075),'oak_light',.04,'wood')
    for a in list(p.INSTANCES):
        if a['name'] in ('seat_0','seat_7'):
            root=bpy.data.objects[a['name']]
            for o in list(root.children):bpy.data.objects.remove(o,do_unlink=True)
            bpy.data.objects.remove(root,do_unlink=True);p.INSTANCES.remove(a)
        elif a['asset']=='dining_stool':
            i=int(a['name'].split('_')[-1]);a['asset']='square_dining_stool' if i%3==0 else 'backed_dining_stool' if i%4==0 else 'dining_stool';a['yaw_degrees']=(i%5-2)*11
    rebuild_stock();wheel();details()
    for name in ('long_bar','bar_return'):t.stretch(name,(1,.99,1))
    for name in ('beer_cask','bar_runner','ceramic_jug','mug_variant_0'):t.move(name,(p.KITS[name]['at'][0],p.KITS[name]['at'][1]-.0133,p.KITS[name]['at'][2]))
    for a in p.INSTANCES:
        if a['name'] in ('varied_mug_0','varied_mug_1'):a['position'][1]-=.0133
    t.delete('floor_plant');t.delete('shelf_plant')
    t.clear('left_table_rug');cube('Deep green flat woven rug',(0,.012,0),(2.47,.024,1.95),'626A49',.025,'cloth')
    for x in (-1.15,1.15):cube('Rug narrow gold border',(x,.027,0),(.035,.003,1.78),'A09A70',.002)
    for z in (-.89,.89):cube('Rug narrow gold border',(0,.027,z),(2.30,.003,.035),'A09A70',.002)
    # Put each tabletop item exactly on the raised round table surface.
    t.move('tavern_snacks',(.12,1.177,2.35))
    for a in p.INSTANCES:
        if a['asset']=='table_candle':a['position'][1]=1.174
        if a['asset']=='candle_glow':a['position'][1]=1.454
    p.b.CURRENT=p.KITS['table_candle']
    for x in (-.095,.095):
        for z in (-.095,.095):tube('Candle lantern cage',[(x,.05,z),(x,.30,z)],.012,'534C3D',6)
    cylinder('Lantern top rim',(0,.30,0),.12,.025,'806B44',vertices=16)
    for idx,z in enumerate((-1.68,-3.16)):
        instance('wall_lantern','saloon_sconce_'+str(idx),(-3.45,2.38,z),90)
        instance('lantern_glow','saloon_sconce_glow_'+str(idx),(-3.45,2.38,z),90)
    for name,at in [('bar_candle_left',(-.70,1.418,-1.40)),('bar_candle_right',(.90,1.418,-1.20)),('shelf_candle',(-3.18,1.67,.03))]:
        instance('table_candle',name,at);instance('candle_glow',name+'_flame',(at[0],at[1]+.28,at[2]))
    d={};t.add_plant(d,'FrontTerracottaMonstera','monstera', (2.03,.082,2.92),.94,25,colliders=[{'at':[0,.20,0],'size':[.39,.40,.39]}]);t.add_plant(d,'ShelfPothos','pothos',(-3.30,1.65,.65),.68,90);t.add_plant(d,'RightShelfPothos','pothos',(2.25,2.22,-3.12),.54)
    d['botanical_assets']=['tavern_window_garden']
    d['material_overrides']={'lantern_glow':{'emission':'FFDC88','emission_use_atlas':True,'emission_energy':2.7},'candle_glow':{'emission':'FFE1A3','emission_use_atlas':True,'emission_energy':3.0},'tavern_window_garden':{'unshaded':True}}
    d['local_lights']=[]
    lamps=[('saloon_pair',[-3.18,2.38,-2.43],1.05,1.45),('chandelier',[-2.2,2.68,.1],1.6,1.8),('left_wall',[-3.23,2.06,2.22],1.15,1.35),('bar_left',[-1.31,2.90,-2.87],1.1,1.45),('bar_right',[1.56,2.90,-2.87],1.1,1.45),('right_wall',[3.12,2.49,-2.87],.95,1.35)]
    for name,pos,e,ran in lamps:d['local_lights'].append({'name':name,'position':pos,'energy':e,'range':ran,'color':'FFC16C'})
    for name,pos in [('left_table',[-2.12,1.57,.95]),('front_table',[.10,1.45,2.18]),('right_table',[2.50,1.45,.94]),('bar_left_candle',[-.70,1.70,-1.40]),('bar_right_candle',[.90,1.70,-1.20]),('shelf_candle',[-3.18,1.95,.03])]:d['local_lights'].append({'name':name,'position':pos,'energy':.75,'range':1.30,'color':'FFCA77'})
    d['lighting']={'background':'D9DDD1','ambient':'BEC8C8','ambient_energy':.27,'sun_color':'EDE0C9','sun_energy':.62,'sun_position':[5,8,4],'sun_target':[0,0,-1],'angular_distance':6,'lamps':[]}
    d['review_lighting']={'ambient':.27,'ambient_color':'BEC8C8','sun':.62,'sun_color':'EDE0C9','sun_position':[5,8,4],'sun_target':[0,0,-1],'points':[]}
    d['review_views']=[{'name':'bar-stock-detail','position':[3.5,3.8,5.5],'target':[.1,2,-2.1],'size':4.8},{'name':'wheel-table-detail','position':[4.5,4.5,7],'target':[-2.0,2,.65],'size':4.7}]
    entrance=t.bounds(d,7.4,6.8,entrance_x=-1.15)
    y=.082;d['spawn']=[-1.15,y,3.12]
    d['bench']={'floor_y':y,'route':[{'name':n,'position':[x,y,z],**({'capture':c} if c else {})} for n,x,z,c in [('entrance',-1.15,3.12,'door'),('left_front',-1.55,2.37,None),('left_table_side',-.82,.90,None),('bar_front',-.42,-.44,'main'),('right_back_corner',3.36,-.35,None),('right_table_outer',3.36,2.25,None),('front_table_right',1.17,2.7,None),('front_table_corner',1.17,3.22,None),('front_table_front',-1.15,3.22,None),('entrance_return',-1.15,3.12,None)]],'blocked':[{'name':n,'from':[a[0],y,a[1]],'to':[b[0],y,b[1]],'target':target} for n,a,b,target in [('bar',(-.4,-.4),(-.4,-1.7),'/long_bar/'),('left_table',(-.9,.9),(-2.14,.9),'/square_table/'),('round_table',(1.26,.94),(2.5,.94),'/round_table_right/'),('barrel',(2.62,-.75),(2.62,-2.13),'/barrel_right_one/'),('wall',(3.20,2.4),(4.0,2.4),'right_edge')]],'gaps':[{'name':'bar_to_round_table','from':[-.6,y,-.10],'to':[1.9,y,-.10],'measure':[[1.82,.60,-1.10],[1.82,.60,.15]],'width':1.25,'minimum':.70}],'entrance':entrance,'slide':{'from':[3.52,y,2.23],'direction':[1,0,-1],'tangent':[0,0,-1],'seconds':.4},'input_start':[-.8,y,.20],'scale':{'door':{'height':2.41,'source':'Saloon arch .07 to 2.48 local'},'counter':{'height':1.3167,'source':'Bar top (1.20+.055+.075)*.99; within Basic Room +15%'},'chair':{'height':.65,'source':'Dining stool .60+.05'},'table':{'height':1.0915,'source':'Round table (.86+.065)*1.18'}}}
    # Preserve all furniture sizes; shift the right/front table groups to provide >=.7m perimeter aisles.
    right_names={'round_table_right','seat_7','seat_8','seat_9','seat_10','varied_mug_4','varied_mug_5','table_bottle_2','table_candle_1','candle_glow_1'}
    front_names={'seat_3','seat_4','seat_5','seat_6','varied_mug_3','table_bottle_1','table_candle_0','candle_glow_0'}
    for a in p.INSTANCES:
        if a['name'] in right_names:a['position'][0]-=.28
        if a['name'] in front_names:a['position'][2]-=.26
    for name in ('backed_dining_stool',):t.move(name,(p.KITS[name]['at'][0]-.28,p.KITS[name]['at'][1],p.KITS[name]['at'][2]))
    for name in ('round_table','mug_variant_2','tavern_snacks'):t.move(name,(p.KITS[name]['at'][0],p.KITS[name]['at'][1],p.KITS[name]['at'][2]-.26))
    for lamp in d['local_lights']:
        if lamp['name']=='right_table':lamp['position'][0]-=.28
        if lamp['name']=='front_table':lamp['position'][2]-=.26
    t.add_plant(d,'FrontTerracottaSleeve','pot_terracotta',(2.03,.082,2.92),1.30)
    t.finish(d,[(37,993),(805,1364),(1518,971)],(1547,1516),(7.8,7.2))
