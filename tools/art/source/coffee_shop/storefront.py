"""Reusable store fixtures for the bright-shop series, in the Coffee Shop kit namespace."""
import math, random
import json
import bpy
import kit as k
from kit import begin,cube,cylinder,tube,ellipsoid,lathe,leaf

def reuse_coffee(asset,at,yaw=0):
    """Append editable objects, then rebake into this shop's atlas; never edit the source kit."""
    path=k.ROOT/'tools/art/source/coffee_shop/coffee_shop.blend'
    with bpy.data.libraries.load(str(path),link=False) as (src,dst):
        dst.collections=['KIT_'+asset]
    collection=dst.collections[0];bpy.context.scene.collection.children.link(collection)
    root=next(o for o in collection.objects if o.type=='EMPTY')
    root.name=asset;collection.name='KIT_'+asset
    root.location=k.v(at);root.rotation_euler.z=math.radians(yaw)
    original=next(a for a in json.loads((k.ROOT/'assets/rooms/coffee_shop/layout.json').read_text())['assets'] if a['name']==asset)
    k.KITS[asset]={'collection':collection,'root':root,'objects':[o for o in collection.objects if o.type=='MESH'],'at':list(at),'yaw':yaw,'collision':original['colliders']}

def flower_border(length=1.0):
    cube('Planter trough',(0,.08,0),(length,.16,.35),'plaster',.045)
    cube('Planter soil',(0,.167,0),(length-.08,.015,.26),'soil',.01)
    n=max(3,round(length/.23))
    for j in range(n):
        x=-length*.41+j*(length*.82)/(n-1)
        for i in range(7):
            a=i*2.399
            leaf('Bushy planter leaf',(x,.18,0),(x+math.cos(a)*.20,.27+(i%3)*.045,math.sin(a)*.20),.14,random.choice(['leaf','leaf_light']))
        if j%2==0:k.flower((x,.40,.04),1.20)

def awning(width=3.5,depth=.82,colors=('porcelain','D7BE8B')):
    n=round(width/.22)
    for j in range(n):
        x=-width/2+(j+.5)*width/n;c=colors[j%2]
        roof=cube('Striped canvas canopy',(x,-.10,depth/2),(width/n+.004,.037,depth),c,.006,'cloth')
        roof.rotation_euler.x=math.radians(15)
        cube('Scalloped canvas valance',(x,-.28,depth-.01),(width/n+.008,.25,.07),c,.09,'cloth')
    for x in (-width*.47,width*.47):
        tube('Awning triangular support',[(x,-.39,0),(x,-.24,depth),(x,.08,0)],.024,'oak_edge',6)

def crate(width=.83,depth=.64,height=.29):
    cube('Crate base',(0,.024,0),(width,.048,depth),'oak_light',.01,'wood')
    for z in (-depth/2,depth/2):
        for row in range(3):cube('Crate long slat',(0,.072+row*height/3,z),(width,.075,.032),'oak_light',.010,'wood')
    for x in (-width/2,width/2):
        for row in range(3):cube('Crate end slat',(x,.072+row*height/3,0),(.033,.075,depth),'oak',.01,'wood','Z')
        for z in (-depth/2,depth/2):cube('Crate corner brace',(x,.18,z),(.065,height+.03,.065),'oak_edge',.01,'wood','Y')

def fruit(kind,at,s=1):
    x,y,z=at
    color={'orange':'E8AA37','lemon':'EBD35B','fig':'795B92','peach':'DBA06F','apple':'C97758','grape':'786394'}[kind]
    if kind=='grape':
        for j in range(13):
            a=j*2.399;r=.07*s*(1-(j%3)*.13)
            ellipsoid('Grape',(x+math.cos(a)*r,y+.04*s+(j%3)*.055*s,z+math.sin(a)*r),(.072*s,.075*s,.072*s),color,8,5)
    elif kind=='fig':lathe('Fig',at,[(0,.044*s),(.025*s,.076*s),(.065*s,.095*s),(.11*s,.084*s),(.155*s,.045*s),(.19*s,.018*s),(.21*s,.014*s)],color,12)
    else:
        ellipsoid(kind.title(),(x,y+.088*s,z),(.17*s,.17*s if kind!='lemon' else .21*s,.17*s),color,12,8)
        if kind=='peach':tube('Peach groove',[(x,y+.17*s,z-.02*s),(x,y+.12*s,z+.088*s),(x,y+.065*s,z+.085*s)],.003*s,'C18461',4)
    tube('Fruit stem',[(x,y+.17*s,z),(x+.005*s,y+.22*s,z)],.007*s,'oak_dark',5)
    if random.random()<.25:leaf('Fresh fruit leaf',(x,y+.19*s,z),(x+.10*s,y+.24*s,z),.065*s,'leaf')

def shell(wall='EAD4BA',accent='C5B6CF',floor='EBD7B7',wood=False,door_center=-.90,rectangular=False):
    begin('floor',collision=[{'at':[0,-.09,0],'size':[6.1,.22,5.6]}])
    cube('Diorama foundation',(0,-.12,0),(6.18,.27,5.68),wall,.12)
    if wood:
        for j in range(22):
            for i in range(3):cube('Timber floorboard',(-2.02+i*2.02,.031,-2.66+j*.25),(2.01,.055,.242),floor,.008,'wood')
    else:
        for i in range(12):
            for j in range(11):
                cube('Rounded ceramic floor tile',(-2.75+i*.5,.027,-2.50+j*.5),(.486,.052,.486),floor,.063)
                if (i+j)%3==0:cube('Pastel tile inset',(-2.5+i*.5,.029,-2.25+j*.5),(.10,.056,.10),accent,.024)
    begin('back_wall',at=(0,.06,-2.75),collision=[{'at':[0,1.50,0],'size':[6,3,.22]}])
    cube('Wall backing',(0,1.48,0),(6.08,2.96,.17),wall,.03)
    for y in range(8):
        for x in range(10):
            cube('Soft brick block',(-2.71+x*.60, .18+y*.364,.101),(.585,.347,.09),wall,.031)
    cube('Cream coping',(0,3.0,0),(6.20,.16,.29),'porcelain',.045)
    edges=((-2.70,door_center-.75),(door_center+.75,2.90))
    begin('left_door_wall',at=(-3,.06,.15),yaw=90,collision=[{'at':[(a+b)/2,1.50,0],'size':[b-a,3,.23]} for a,b in edges])
    # Arch opening occupies local x=-.90; all wall blocks stay outside it.
    for left,right in edges:
        cube('Door flanking masonry',((left+right)/2,1.48,0),(right-left,2.96,.20),wall,.035)
        n=max(1,round((right-left)/.53))
        for row in range(8):
            for j in range(n):cube('Left wall brick',(left+(j+.5)*(right-left)/n,.18+row*.364,.12),((right-left)/n-.015,.347,.055),wall,.028)
    # Centered in temporary local coordinates, then offset entire arch mesh objects.
    start=len(k.CURRENT['objects'])
    if rectangular:
        for x in (-.72,.72):cube('Rectangular door jamb',(x,1.22,.05),(.10,2.44,.28),accent,.024)
        cube('Door lintel',(0,2.43,.05),(1.54,.12,.28),accent,.024)
        cube('Masonry above rectangular entrance',(0,2.73,0),(1.52,.50,.20),wall,.02)
    else:
        k.arch_trim('Open pastel doorway',1.44,0,1.96,.67,.15,.28,.025,accent)
    for obj in k.CURRENT['objects'][start:]:obj.location.x+=door_center
    cube('Left wall top lintel',(.10,2.96,0),(5.75,.19,.29),'porcelain',.045)
    begin('front_wall_left',at=(-1.99,.06,2.68),collision=[{'at':[0,.32,0],'size':[1.95,.64,.30]}])
    for i in range(5):
        for j in range(2):cube('Front masonry',(-.78+i*.39,.17+j*.31,0),(.376,.297,.30),wall,.045)
    cube('Wall coping',(0,.68,0),(2.0,.14,.37),'porcelain',.05)
    begin('front_wall_right',at=(2.17,.06,2.68),collision=[{'at':[0,.32,0],'size':[1.65,.64,.30]}])
    for i in range(4):
        for j in range(2):cube('Front masonry',(-.61+i*.405,.17+j*.31,0),(.39,.297,.30),wall,.045)
    cube('Wall coping',(0,.68,0),(1.68,.14,.37),'porcelain',.05)
    begin('side_low_wall',at=(3,.06,0),yaw=90,collision=[{'at':[0,.32,0],'size':[5.28,.64,.30]}])
    for i in range(11):
        for j in range(2):cube('Right masonry',(-2.4+i*.48,.17+j*.31,0),(.466,.297,.30),wall,.045)
    cube('Side coping',(0,.68,0),(5.35,.14,.37),'porcelain',.05)
    begin('corner_pier',at=(3,.06,2.68),collision=[{'at':[0,.43,0],'size':[.40,.86,.40]}])
    for y in (.18,.53):cube('Pastel pier block',(0,y,0),(.40,.34,.40),accent,.060)
    cube('Cream pier cap',(0,.84,0),(.42,.24,.42),'porcelain',.06)
    for j,at in enumerate([(-3,.06,2.68),(-.97,.06,2.68),(1.28,.06,2.68)]):k.instance('corner_pier','corner_pier_'+str(j),at)
    begin('entry_step',at=(.15,-.16,2.82),collision=[{'at':[0,.025,.05],'size':[2.06,.17,.50]}])
    cube('Entrance tread',(0,.025,.08),(2.06,.17,.56),'porcelain',.060)
    cube('Woven welcome mat',(0,.13,.00),(1.10,.055,.46),accent,.05,'cloth')

def menu(name,at,title,lines,width=1.5,height=1.12,bg='porcelain',ink='iron'):
    begin(name,at=at)
    cube('Rounded menu frame',(0,0,0),(width+.08,height+.08,.09),'oak_light',.085)
    cube('Menu face',(0,0,.053),(width,height,.029),bg,.065)
    k.text_label(title,(-width*.42,height*.34,.072),min(.16,width/(len(title)*.61)),ink,'LEFT')
    step=min(.155,height*.60/max(len(lines),1))
    for j,line in enumerate(lines):k.text_label(line,(-width*.42,height*.15-j*step,.073),min(.105,(width*.85)/(max(len(line),1)*.57)),ink,'LEFT')

def tea_cup(at=(0,0,0),s=1,color='DBB286'):
    x,y,z=at
    lathe('Tapered milk tea cup',at,[(0,.080*s),(.30*s,.112*s),(.315*s,.114*s)],color,20)
    cylinder('Cup sealed lid',(x,y+.327*s,z),.12*s,.026*s,'porcelain',vertices=24)
    tube('Wide tea straw',[(x,y+.33*s,z),(x+.033*s,y+.56*s,z)],.014*s,'oak_dark',8)
    for j in range(14):
        a=j*2.399;h=(.035+(j%3)*.030)*s;r=.083*s
        ellipsoid('Tapioca pearl',(x+math.cos(a)*r,y+h,z+math.sin(a)*r),(.029*s,.029*s,.029*s),'iron',8,4)
    leaf('Tea cup leaf badge',(x-.024*s,y+.20*s,z+.105*s),(x+.035*s,y+.26*s,z+.107*s),.040*s,'leaf')

def bottle(at,color='sage',height=.33,label=''):
    x,y,z=at
    lathe('Drink bottle',at,[(0,.055),(.03,.070),(height*.70,.070),(height*.84,.041),(height,.035)],color,12)
    cylinder('Bottle cap',(x,y+height+.013,z),.039,.030,'porcelain',vertices=12)
    cube('Bottle paper label',(x,y+height*.43,z+.065),(.095,height*.32,.007),'porcelain',.009)
    if label:k.text_label(label,(x,y+height*.39,z+.072),.05,'leaf_dark')

def fridge(at=(-2.30,.06,-1.94),title='COLD DRINKS',color='sage'):
    begin('drinks_fridge',at=at,collision=[{'at':[0,1.15,0],'size':[1.1,2.30,.67]}])
    cube('Cold cabinet insulated body',(0,1.16,0),(1.13,2.32,.60),color,.070)
    cube('Open display recess',(0,1.16,.307),(.96,1.84,.03),'iron_edge',.02)
    for x in (-.51,.51):cube('Cabinet door edge',(x,1.16,.45),(.055,1.94,.075),'porcelain',.015)
    for row in range(4):
        y=.32+row*.43
        cube('Chilled shelf',(0,y,.45),(.98,.043,.42),'porcelain',.01)
        for j in range(4):bottle((-.34+j*.225,y+.026,.46),['DFABA1','B4C4A1','E2C27F','D8BDD2'][(j+row)%4],.29,'B')
    k.text_label(title,(0,2.14,.316),.124,'porcelain')
    cube('Refrigerator handle',(.46,1.18,.49),(.034,.47,.048),'oak_light',.014)

def simple_chair():
    for x in (-.22,.22):
        for z in (-.21,.21):tube('Cafe chair splayed leg',[(x*1.15,.01,z*1.15),(x,.48,z)],.035,'oak',8,'wood')
    cylinder('Cafe seat',(0,.49,0),.29,.075,'oak_light',vertices=28)
    ellipsoid('Pastel round cushion',(0,.55,0),(.55,.11,.52),'CDB4CC',24,8)
    for x in (-.21,.21):tube('Back support',[(x,.49,-.22),(x,.98,-.22)],.026,'oak',8)
    cube('Rounded wood backrest',(0,.91,-.23),(.56,.30,.07),'oak_light',.11,'wood')

def stool():
    lathe('Stool pedestal',(0,0,0),[(0,.25),(.04,.26),(.07,.13),(.11,.044),(.78,.044)],'iron_edge',24)
    tube('Stool foot ring',[(.17*math.cos(j*math.tau/32),.26,.17*math.sin(j*math.tau/32)) for j in range(33)],.015,'iron_edge',6)
    cylinder('Padded stool seat',(0,.80,0),.26,.12,'terra',vertices=32)

def plants():
    begin('corner_plant',at=(-2.56,.07,-.35),collision=[{'at':[0,.28,0],'size':[.52,.56,.52]}]);k.plant(scale=1.30)
    begin('trailing_wall_plant',at=(-2.66,2.72,-2.39));k.plant(scale=.72,trailing=True)
    k.instance('trailing_wall_plant','trailing_wall_plant_2',(2.62,2.72,-2.44))
    begin('flower_wall_ivy',at=(2.32,.85,2.67))
    for dx in (-.39,-.13,.13,.37):k.vine([(dx+math.sin(j*.71)*.07,-j*.062,.06+j*.009) for j in range(11)])
    k.instance('flower_wall_ivy','flower_wall_ivy_2',(-2.15,.85,2.68))

def signboard(at=(-1.55,.02,3.13),lines=('MILK TEA','GOOD','MOOD')):
    begin('street_signboard',at=at)
    cube('A board face',(0,.53,.04),(.67,.88,.070),'iron_edge',.025)
    for x in (-.37,.37):
        tube('A board front rail',[(x,.0,.19),(x,1.04,0)],.035,'oak_light',8,'wood')
        tube('A board rear rail',[(x,.0,-.34),(x,1.04,0)],.030,'oak',8,'wood')
    for y in (.13,.98):cube('A board horizontal frame',(0,y,.077),(.78,.055,.065),'oak_light',.017)
    for j,line in enumerate(lines):k.text_label(line,(0,.81-j*.22,.082),.118,'porcelain')
