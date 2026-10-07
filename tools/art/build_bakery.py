"""Bakery art kit from Figma 545:2964. Real oven cavity and glazed display."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from shop_room_parts import *
from build_deluxe_room_10 import cabinet
import scene_room_pipeline as p


def bread(at=(0,0,0),kind='loaf'):
    x,y,z=at
    if kind=='baguette':
        ellipsoid('Long golden baguette',(x,y+.105,z),(.19,.19,.62),'D99944',18,10)
        for j in range(5):tube('Baguette diagonal score',[(x-.065,y+.18,z-.23+j*.11),(x+.065,y+.19,z-.19+j*.11)],.012,'linen',5)
    elif kind=='croissant':
        for j in range(9):
            t=math.pi*.18+j/8*math.pi*.64
            size=.085+.10*math.sin(j/8*math.pi)
            o=ellipsoid('Croissant laminated fold',(x+math.cos(t)*.18,y+.075,z+math.sin(t)*.14),(size,.14,size*.7),'DCA65C' if j%2 else 'C98A3F',14,8)
            o.rotation_euler.z=t
    elif kind=='cake':
        cylinder('Cake sponge',(x,y+.11,z),.19,.22,'terra',vertices=28)
        cylinder('Cream cake icing',(x,y+.245,z),.20,.075,'porcelain',vertices=28)
        for i in range(6):
            a=i*math.pi/3;ellipsoid('Cake strawberry',(x+math.cos(a)*.12,y+.31,z+math.sin(a)*.12),(.073,.085,.073),'C94435',12,8)
    else:
        ellipsoid('Crusty bread loaf',(x,y+.105,z),(.34,.22,.28),'D69542',18,10)
        for dx in (-.075,0,.075):tube('Loaf flour score',[(x+dx-.02,y+.183,z-.08),(x+dx+.025,y+.218,z+.03),(x+dx+.03,y+.19,z+.08)],.014,'linen',6)


def oven():
    begin('brick_oven',(-2.23,.082,-2.22),collision=[{'at':[0,1.45,0],'size':[1.72,2.90,1.50]}])
    body=cube('Oven masonry plinth',(0,.48,0),(1.75,.96,1.45),'A95C39',.05)
    cut=arch_solid('Real wood storage aperture',1.12,.08,.46,.34,2.0,.16,'iron');boolean_cut(body,cut)
    cube('Wood storage dark back',(0,.40,-.63),(1.2,.65,.06),'oak_dark',.02)
    for x,y in [(-.36,.23),(-.03,.22),(.30,.24),(-.17,.46),(.16,.46)]:
        o=cylinder('Oven firewood',(x,y,.08),.13,.67,'oak',vertices=12);o.rotation_euler.x=math.pi/2
    cube('Oven hearthstone',(0,1.0,.06),(1.89,.17,1.63),'plaster_light',.065)
    dome=ellipsoid('Rounded plaster oven dome',(0,1.70,-.06),(1.77,1.53,1.54),'plaster_light',40,24)
    cut=arch_solid('True oven mouth',1.08,1.055,1.51,.40,2.2,.12,'iron');boolean_cut(dome,cut)
    cube('Oven firebox back',(0,1.42,.10),(1.1,.76,.075),'8C3E27',.025)
    arch_trim('Terracotta oven mouth arch',1.08,1.05,1.51,.40,.13,.15,.61,'B76440')
    for side in (-1,1):
        for j in range(3):cube('Oven arch jamb brick',(side*.615,1.13+j*.15,.61),(.13,.137,.17),'BB6F47',.018)
    for i in range(11):
        a=i*math.pi/11+.03;c=(i+1)*math.pi/11-.03
        verts=[]
        for z in (.54,.71):
            for r,ry in [(.54,.40),(.68,.53)]:
                for t in (a,c):verts.append((math.cos(t)*r,1.51+math.sin(t)*ry,z))
        mesh('Radiating brick voussoir',verts,[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)],'C77A50')
    for side in (-1,1):cube('Oven iron jamb plate',(side*.72,1.30,.72),(.10,.37,.045),'iron_edge',.02)
    cylinder('Oven chimney',(0,3.08,-.12),.23,1.40,'B85F3E',vertices=24)
    for j in range(9):
        y=2.45+j*.15
        lathe('Chimney mortar course',(0,y,-.12),[(0,.232),(.016,.232),(.016,.222),(0,.222)],'plaster',24)
        for i in range(6):
            a=i*math.pi/3+(j%2)*math.pi/6
            tube('Chimney mortar joint',[(.233*math.cos(a),y,-.12+.233*math.sin(a)),(.233*math.cos(a),y+.15,-.12+.233*math.sin(a))],.007,'plaster',4)
    lathe('Open chimney crown',(0,3.80,-.12),[(0,.28),(.16,.28),(.16,.19),(-.08,.19)],'B85F3E',32)
    reuse('fire',(-2.23,1.18,-1.84))
    begin('baking_loaves',(-2.23,1.18,-1.82))
    for x in (-.25,.22):bread((x,0,0))
    begin('oven_peel',(-3.02,.082,-1.42),12)
    cube('Wooden bread peel blade',(0,.65,0),(.28,.53,.05),'oak_light',.08,'wood','Y')
    tube('Long bread peel handle',[(0,.79,0),(0,1.91,0)],.028,'oak',8)


def display():
    counter('pastry_display',(1.79,.082,.71),2.20,.99,.68)
    begin('pastry_trays',(1.79,.87,.71))
    for j in range(3):
        y=j*.39;z=-j*.15
        cube('Pastry shelf',(0,y,z),(2.04,.047,.85-j*.10),'oak_light',.02,'wood')
        for i in range(5):bread((-.79+i*.40,y+.045,z),['cake','croissant','loaf'][j])
    begin('display_frame',(1.79,.80,.71))
    profile=[(.58,.02),(.55,.52),(.40,.98),(.18,1.19),(-.40,1.21)]
    for x in (-1.11,1.11):tube('Curved glass display frame',[(x,y,z) for z,y in profile],.03,'brass',10)
    for z,y in [profile[0],profile[-1]]:tube('Display cross rail',[(-1.11,y,z),(1.11,y,z)],.025,'brass',10)
    begin('display_glass',(1.79,.80,.71))
    verts=[];faces=[]
    for z,y in profile:
        for x in (-1.08,1.08):verts.append((x,y,z))
    for j in range(len(profile)-1):faces.append((j*2,j*2+1,j*2+3,j*2+2))
    o=mesh('Continuous curved display glazing',verts,faces,'DAE5DC',smooth=True)
    shader=o.data.materials[0].node_tree.nodes.get('Principled BSDF')
    shader.inputs['Alpha'].default_value=.10
    shader.inputs['Roughness'].default_value=.14
    counter('checkout_counter',(3.00,.082,-.63),.87,.85,1.02)
    begin('register',(3.00,1.25,-.65));register()


def build():
    start('bakery','545:2964')
    shell(7.2,6.4,3.65,open_left=False,open_back=False)
    wall_window('back_window_left','back_wall',-.90,.81,1.38,2.32,.13)
    wall_window('back_window_right','back_wall',2.36,.81,1.38,2.32,.13)
    oven();display()
    sign('bakery_sign','BAKERY',(.61,2.94,-3.04),2.0,.62,color='linen',letter_color='oak_dark')
    sign('bread_motto','Good Bread\nBrighter Days',(3.20,2.44,-3.035),.50,.94,color='iron',letter_color='linen')
    reuse('sink_cabinet',(-.66,.082,-2.73));reuse('utensil_crock',(-1.30,1.26,-2.71))
    cabinet('back_counter',(.81,.082,-2.72),1.03)
    shelf('pantry',(.75,1.18,-2.77),1.04,1.15,.32,3)
    begin('pantry_jars',(.75,1.27,-2.72))
    for j in range(2):
        for i in range(3):bottle((-.32+i*.32,j*.565,0),['jar_ochre','porcelain','sage'][i],.35)
    begin('baguette_basket',(.30,2.51,-2.74));basket(width=.38,height=.25,depth=.30)
    for i in range(3):
        o=ellipsoid('Upright baguette',(-.10+i*.10,.42,0),(.11,.63,.11),'D99944',14,10)
        for j in range(4):cube('Baguette flour slash',(-.10+i*.10,.20+j*.10,.06),(.074,.020,.008),'linen',.006)
    reuse('pantry_plant',(1.19,2.51,-2.74),original='shelf_plant')
    shelf('jar_wall_shelves',(-3.35,.68,1.16),1.13,1.53,.31,4,90)
    begin('jar_collection',(-3.18,.79,1.49),90)
    for j in range(4):
        for i in range(3):bottle((i*.28,j*.51,0),['jar_green','porcelain','jar_ochre'][(i+j)%3],.29)
    begin('bakery_rack',(-2.93,.08,-.11),collision=[{'at':[0,.92,0],'size':[.68,1.84,.61]}])
    for x in (-.33,.33):
        for z in (-.27,.27):tube('Rack iron upright',[(x,.05,z),(x,1.80,z)],.023,'iron_edge',8)
    for j in range(5):
        yy=.22+j*.32;cube('Rack metal baking tray',(0,yy,0),(.70,.036,.59),'iron_edge',.012)
        for x in (-.17,.17):bread((x,yy+.02,0))
    worktable('baking_workbench',(-.66,.082,.03),1.91,.98,.96)
    begin('workbench_baking_props',(-.66,1.20,.03))
    ellipsoid('Resting dough',(0,.075,0),(.42,.18,.34),'linen',20,12)
    tube('Rolling pin',[(-.60,.035,-.12),(-.22,.035,-.12)],.055,'oak_light',12)
    tube('Rolling pin handles',[(-.71,.035,-.12),(-.10,.035,-.12)],.024,'oak',8)
    pot((.55,0,-.15),.12,.24,'porcelain')
    for i in range(3):tube('Baking spoon',[(.55,0,-.15),(.50+i*.05,.49,-.15)],.016,'oak',6)
    lathe('Mixing bowl',(.54,0,.24),[(0,.07),(.07,.12),(.17,.18),(.19,.18),(.19,.15),(.05,.05)],'iron_edge',24)
    begin('flour_storage',(-.66,.37,.05));basket((.45,0,0),.60,.41,.63)
    cube('Flour sack',(-.45,.20,0),(.56,.43,.55),'linen',.09,'cloth');lettering('FLOUR',(-.45,.18,.29),.37,'oak_dark')
    round_table('cafe_table',(-1.65,.082,2.13),.65,.83)
    reuse('chair',(-2.44,.082,2.13),-90)
    instance('chair','chair_opposite',(-.85,.082,2.13),90)
    rug('cafe_rope_rug',(-1.65,.093,2.13),2.09,2.09,True)
    reuse('cafe_flowers',(-1.66,1.04,2.12),original='daisy_jug')
    begin('cafe_cup',(-1.30,1.02,2.30));mug()
    reuse('floor_plant',(-3.12,.083,2.62));reuse('display_plant',(2.97,.083,1.74),original='floor_plant')
    lantern('left_wall_light',(-3.40,2.63,1.94),90)
    lantern('right_wall_light',(2.37,2.93,-2.92))
    finalize({'position':[10.5,9.4,12],'target':[0,1.6,0],'size':11.9});complete()


if __name__=='__main__':
    import runpy
    runpy.run_path(str(Path(__file__).resolve().parent/'source/bakery/revision.py'),run_name='__main__')
