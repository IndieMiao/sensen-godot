"""Blacksmith Shop / FORGE WORKSHOP, Figma 545:2965. Art-only kit."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from shop_room_parts import *
import scene_room_pipeline as p


def hammer(at=(0,0,0),length=.66):
    x,y,z=at
    tube('Hickory hammer handle',[(x,y,z),(x,y+length,z)],.036,'oak_light',8)
    cube('Forged hammer head',(x,y+length,z),(.31,.18,.17),'iron_edge',.025)
    cube('Hammer polished striking face',(x-.162,y+length,z),(.018,.14,.13),'8C8782',.006)


def tongs(at=(0,0,0),length=.79):
    x,y,z=at
    for s in (-1,1):
        pts=[(x+s*.06,y,z),(x+s*.10,y+length*.12,z),(x+s*.08,y+length*.50,z),(x-s*.025,y+length*.70,z),(x-s*.09,y+length*.85,z),(x-s*.055,y+length,z)]
        tube('Forged tong arm',pts,.020,'iron_edge',8)
    ellipsoid('Tong pivot rivet',(x,y+length*.68,z+.023),(.066,.066,.035),'iron',12,8)


def horseshoe(at=(0,0,0),radius=.15):
    x,y,z=at
    pts=[(x+radius*math.cos(a),y+radius*math.sin(a),z) for a in [-.35+i*(math.pi+.7)/24 for i in range(25)]]
    tube('Forged horseshoe',pts,.026,'iron_edge',8)
    for a in (.15,.60,1.0,2.1,2.55,3.0):ellipsoid('Horseshoe nail recess',(x+radius*math.cos(a),y+radius*math.sin(a),z+.027),(.022,.022,.010),'iron',8,6)


def anvil(name,at,scale=1):
    begin(name,at,collision=[{'at':[.18,.30,0],'size':[1.58,.60,.58]}])
    cube('Anvil broad base',(0,.06,0),(.88,.12,.58),'iron_edge',.045)
    verts=[(-.38,.11,-.23),(.38,.11,-.23),(.38,.11,.23),(-.38,.11,.23),
           (-.22,.28,-.15),(.22,.28,-.15),(.22,.28,.15),(-.22,.28,.15),
           (-.39,.49,-.22),(.39,.49,-.22),(.39,.49,.22),(-.39,.49,.22)]
    faces=[(0,3,2,1),(8,9,10,11)]
    for j in range(2):
        for i in range(4):faces.append((j*4+i,j*4+(i+1)%4,(j+1)*4+(i+1)%4,(j+1)*4+i))
    o=mesh('Anvil flared shoulders and waist',verts,faces,'iron_edge')
    m=o.modifiers.new('Soft forged corners','BEVEL');m.width=.036;m.segments=3
    m=o.modifiers.new('Anvil weighted normals','WEIGHTED_NORMAL');m.keep_sharp=True
    top=cube('Anvil flat work face',(-.05,.53,0),(1.03,.13,.48),'807B75',.022)
    cut=cube('Hardy square tool socket',(-.43,.55,0),(.075,.30,.075),'iron',0);boolean_cut(top,cut)
    cube('Hardy socket dark bottom',(-.43,.42,0),(.075,.025,.075),'iron',.003)
    # Tapered round horn oriented along X, with a lifted sharp tip.
    profile=[(.0,.195),(.15,.15),(.32,.085),(.53,.009)]
    o=lathe('Anvil conical horn',(.42,.46,0),profile,'807B75',20)
    # Model the horn directly in its object-local vertex coordinates.
    for vert in o.data.vertices:
        x,y,z=vert.co.x,-vert.co.y,vert.co.z
        vert.co=v((.42+(z-.46),.46+x-.42,y))
    if scale!=1:
        for o in p.KITS[name]['objects']:o.location*=scale;o.scale*=scale
        p.KITS[name]['collision']=[{'at':[0,.30*scale,0],'size':[1.35*scale,.6*scale,.54*scale]}]


def forge():
    begin('brick_forge',(-1.55,.082,-2.20),collision=[{'at':[0,1.3,0],'size':[1.96,2.60,1.44]}])
    for x in (-.77,.77):cube('Forge stone pier',(x,.49,0),(.40,.98,1.34),'777068',.06)
    cube('Forge dark log store',(0,.45,-.59),(1.15,.78,.12),'oak_dark',.025)
    for row in range(3):
        for col in range(4-row%2):
            x=-.40+col*.27+(row%2)*.10
            o=cylinder('Stored forge firewood',(x,.16+row*.23,.02),.13,.83,'oak',vertices=12);o.rotation_euler.x=math.pi/2
    cube('Forge hearth slab',(0,1.02,.12),(2.03,.19,1.63),'989086',.055)
    body=cube('Brick furnace body',(0,1.81,-.07),(1.91,1.49,1.43),'985B43',.05)
    cut=arch_solid('Actual furnace arch',1.30,1.10,1.68,.45,2.3,.2,'iron');boolean_cut(body,cut)
    cube('Furnace black lining',(0,1.62,.12),(1.35,1.0,.065),'492E24',.016)
    arch_trim('Stone forge arch',1.30,1.10,1.68,.45,.14,.19,.67,'777068')
    # Readable exterior brick courses. Joints stop before the real opening.
    for j in range(7):
        y=1.15+j*.205
        for s in (-1,1):cube('Furnace brick seam',(s*.84,y,.662),(.20,.017,.025),'57483D',.004)
        if y>2.20:cube('Brick header seam',(0,y,.662),(1.76,.017,.025),'57483D',.004)
    for i in range(9):
        a=math.pi*i/9+.025;c=math.pi*(i+1)/9-.025;verts=[]
        for z in (.57,.78):
            for r,ry in [(.65,.45),(.79,.59)]:
                for t in (a,c):verts.append((r*math.cos(t),1.68+ry*math.sin(t),z))
        mesh('Forge radial arch stone',verts,[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)],'827A71')
    begin('forge_hood',(-1.55,2.59,-2.29))
    cube('Iron hood lower band',(0,.025,0),(2.02,.18,1.53),'iron_edge',.04)
    mesh('Tapered extraction hood',[(-.98,.10,-.72),(.98,.10,-.72),(.98,.10,.72),(-.98,.10,.72),
         (-.30,.83,-.28),(.30,.83,-.28),(.30,.83,.28),(-.30,.83,.28)],[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],'686260')
    cube('Square forge flue',(0,1.23,0),(.60,.86,.57),'77706B',.025)
    for y in (.82,1.66):
        cube('Flue riveted collar',(0,y,0),(.73,.16,.70),'iron_edge',.025)
        for x in (-.23,0,.23):ellipsoid('Flue band rivet',(x,y,.363),(.048,.048,.028),'97918B',10,8)
    cube('Open flue dark throat',(0,1.749,0),(.47,.015,.44),'iron',.006)
    for x in (-.83,-.41,0,.41,.83):ellipsoid('Hood rim rivet',(x,.03,.784),(.057,.057,.024),'97918B',10,8)
    begin('smoke',(-1.55,4.32,-2.29))
    for i in range(7):
        x=.05*i+.11*math.sin(i*1.8);y=i*.145;r=.28+i*.045
        ellipsoid('Sculpted smoke puff',(x,y,0),(r,r*.89,r*.83),'D7D2CE',16,10)
    reuse('fire',(-1.55,1.17,-1.65))
    begin('forge_coals',(-1.55,1.18,-1.69))
    for i in range(28):
        x=random.uniform(-.51,.51);z=random.uniform(-.14,.15)
        ellipsoid('Forge coal clinker',(x,.03,z),(.10,.08,.09),'iron' if i%4 else '963A21',8,6)


def build():
    start('blacksmith_shop','545:2965')
    p.b.PALETTE.update({'oak':'9B6847','oak_light':'B9865D','oak_edge':'76513B','oak_dark':'503C2E','floor':'AC7B54','floor_light':'B7855C','floor_shade':'96694B','plaster':'77706A'})
    shell(6.4,6.0,3.70,open_left=False,open_back=False)
    forge()
    begin('forge_sign',(.94,2.98,-2.84))
    cube('Workshop sign board',(0,0,0),(2.29,.82,.10),'oak_light',.05,'wood')
    lettering('FORGE',(0,.13,.06),1.12,'oak_dark');lettering('WORKSHOP',(0,-.18,.06),1.90,'oak_dark')
    for x in (-1.02,1.02):
        for y in (-.30,.30):ellipsoid('Sign rivet',(x,y,.072),(.055,.055,.025),'iron_edge',10,8)
    begin('hammer_wall',(.73,1.49,-2.77))
    cube('Hammer oak rack',(0,.71,0),(1.79,.14,.12),'oak',.023,'wood')
    for i in range(4):hammer((-.66+i*.43,0,.12),.69)
    begin('tongs_wall',(.69,.61,-2.75))
    cube('Tongs lower rack',(0,.71,0),(1.67,.13,.12),'oak',.02,'wood')
    for i in range(4):tongs((-.63+i*.40,0,.14),.71)
    shelf('left_tool_shelves',(-2.99,.74,.33),1.39,1.64,.38,3,90)
    begin('display_swords',(-2.75,1.58,.90),90)
    for i in range(3):
        x=i*.39;length=.69+i*.07
        blade=mesh('Sword tapered blade',[(x,0,0),(x-.065,.16,0),(x-.065,length,0),(x+.065,length,0),(x+.065,.16,0)],[(0,1,2,3,4)],'9E9E9D')
        blade.modifiers.new('Steel blade thickness','SOLIDIFY').thickness=.033
        tube('Sword fuller',[(x,.19,.02),(x,length-.02,.02)],.007,'iron_edge',5)
        cube('Sword bronze crossguard',(x,length+.04,0),(.25,.075,.075),'brass',.022)
        tube('Leather sword grip',[(x,length+.04,0),(x,length+.32,0)],.034,'oak_edge',10)
        ellipsoid('Sword pommel',(x,length+.34,0),(.08,.09,.08),'brass',12,8)
    begin('horseshoe_stock',(-2.76,.92,.72),90)
    for x in (0,.41,.82):horseshoe((x,.13,0),.15)
    begin('tool_shelf_mugs',(-2.76,1.64,-.03),90)
    mug((0,0,0),'iron_edge');mug((.39,0,0),'iron_edge')
    reuse('shelf_plant',(-2.85,2.49,-.29),90)
    begin('quench_barrel',(-2.52,.082,1.35),collision=[{'at':[0,.46,0],'size':[.94,.92,.94]}]);barrel(radius=.47,height=.91,water=True)
    begin('coal_bucket',(-2.76,.082,-1.13),collision=[{'at':[0,.35,0],'size':[.58,.70,.58]}]);barrel(radius=.29,height=.66,lid=False)
    for i in range(24):
        a=random.random()*math.pi*2;r=random.random()*.21
        ellipsoid('Bucket coal',(math.cos(a)*r,.58+random.random()*.07,math.sin(a)*r),(.095,.09,.10),'iron_edge',8,6)
    tube('Bucket swing handle',[(-.27,.52,0),(-.22,.90,0),(0,1.04,0),(.22,.9,0),(.27,.52,0)],.021,'iron',8)
    worktable('anvil_workbench',(.15,.082,1.28),2.31,1.15,.97)
    anvil('main_anvil',(.15,1.24,1.23))
    begin('heated_bar_glow',(.31,1.865,1.20));cube('Heated steel blank',(0,0,0),(.44,.038,.075),'FF9C24',.013)
    begin('bench_hammer',(-.63,1.16,1.28))
    hammer(length=.52)
    from mathutils import Matrix
    for o in p.KITS['bench_hammer']['objects']:o.matrix_basis=Matrix.Rotation(math.pi/2,4,'X')@o.matrix_basis
    begin('leather_apron',(.68,1.22,1.40))
    profile=[(-.26,.04),(.25,.045),(.47,.015),(.53,-.20),(.55,-.48),(.59,-.81)]
    verts=[];faces=[]
    for j,(z,y) in enumerate(profile):
        for i in range(9):verts.append((-.23+i*.058,y+.015*math.sin(i*2+j),z))
    for j in range(len(profile)-1):
        for i in range(8):faces.append((j*9+i,j*9+i+1,(j+1)*9+i+1,(j+1)*9+i))
    o=mesh('Draped leather apron',verts,faces,'8E513D','cloth',True);o.modifiers.new('Leather thickness','SOLIDIFY').thickness=.017
    begin('metal_ingot_crate',(.13,.33,1.28));crate(width=1.13,height=.44,depth=.77)
    for x in (-.35,0,.35):cube('Stacked iron ingot',(x,.27,0),(.24,.16,.51),'iron_edge',.025)
    worktable('back_tool_bench',(1.54,.082,-1.99),1.39,.58,.77)
    begin('punch_set',(1.31,.96,-2.0))
    for i in range(6):
        cylinder('Steel punch',(-.42+i*.17,.15,0),.021,.31,'iron_edge',vertices=10)
        cylinder('Punch flared foot',(-.42+i*.17,.025,0),.046,.036,'iron_edge',vertices=12)
    begin('stump',(2.39,.082,-.52),collision=[{'at':[0,.42,0],'size':[.87,.84,.87]}])
    cylinder('Oak anvil stump',(0,.41,0),.42,.82,'oak_edge',top=.39,vertices=18)
    cylinder('Stump cut surface',(0,.827,0),.37,.025,'oak_light',vertices=32)
    for i in range(1,6):
        r=i*.052;tube('Stump growth ring',[(r*math.cos(a),.844,r*math.sin(a)) for a in [j*math.pi/24 for j in range(49)]],.006,'oak',5)
    instance('main_anvil','small_anvil',(2.39,.94,-.52),scale=.48)
    begin('tool_bucket',(2.54,.082,.46),collision=[{'at':[0,.27,0],'size':[.5,.54,.5]}]);barrel(radius=.25,height=.53,lid=False)
    tongs((-.06,.30,0),.74);tongs((.09,.36,0),.72)
    stool('forge_stool',(-1.43,.082,2.18),height=.50,radius=.28)
    rug('forge_mat',(.22,.094,2.33),2.09,.73)
    lantern('forge_lantern',(2.74,2.54,-2.76))
    begin('right_wall_shelf',(2.48,2.875,-2.77))
    cube('Lantern wall shelf',(0,0,0),(.93,.11,.44),'oak_light',.028,'wood')
    for x in (-.30,.30):cube('Shelf bracket',(x,-.13,-.10),(.08,.24,.18),'oak_edge',.021,'wood','Y')
    mug((-.22,.06,.015),'iron_edge')
    reuse('right_shelf_plant',(2.63,2.93,-2.73),original='shelf_plant')
    lighting={'ambient':.60,'sun':.92,'ambient_color':'eef0e9','sun_color':'fff2e5',
              'points':[{'position':[-1.55,1.60,-1.20],'color':'ff873b','energy':1.5,'range':2.4}]}
    sys.path.insert(0,str(Path(__file__).resolve().parent/'source/blacksmith_shop'))
    import revision2
    revision2.revise()


if __name__=='__main__':build()
