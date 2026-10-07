"""Standard Room-5, Figma 545:2969. Run with Blender --python (absolute path).

Options after --: --geometry-only, --views (also render model orthographics).
Source rebuild overwrites this scene's generated blend; preserve manual edits.
"""
from pathlib import Path
import math
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import scene_room_pipeline as p
from scene_room_pipeline import *


def sofa(at=(-3.30,.082,.75),yaw=90):
    begin('sofa',at,yaw,[{'at':[0,.55,0],'size':[2.1,1.1,.90]}])
    cube('Oak sofa base',(0,.29,0),(2.13,.23,.87),'oak',.08,'wood')
    for x in (-.88,.88):
        for z in (-.32,.32):cube('Sofa block foot',(x,.14,z),(.17,.27,.16),'oak_edge',.035,'wood','Y')
    cube('Upholstered cream back',(0,.89,-.29),(1.86,.65,.26),'linen',.13,'cloth')
    for x in (-.48,.48):cube('Soft seat cushion',(x,.51,.06),(.94,.25,.73),'porcelain',.11,'cloth')
    for x in (-1.0,1.0):
        cube('Rounded oak arm post',(x,.56,.23),(.18,.88,.22),'oak_light',.08,'wood','Y')
        cube('Padded sofa arm',(x,.78,-.02),(.24,.21,.76),'linen',.09,'cloth')
    for x,color,tilt in [(-.16,'EABC48',-.20),(.49,'linen_green',.17)]:
        o=cube('Loose square pillow',(x,.86,-.03),(.50,.48,.21),color,.11,'cloth');o.rotation_euler.y=tilt
    # Gingham throw follows the back and seat, with a hanging hem.
    verts=[];faces=[];xs=8;profile=[(-.46,1.14),(-.29,1.21),(-.16,1.03),(-.1,.66),(.18,.65),(.45,.63),(.51,.47),(.52,.20)]
    for z,y in profile:
        for i in range(xs+1):verts.append((-.91+i*.085,y+.008*math.sin(i*3),z))
    for j in range(len(profile)-1):
        for i in range(xs):faces.append((j*(xs+1)+i,j*(xs+1)+i+1,(j+1)*(xs+1)+i+1,(j+1)*(xs+1)+i))
    o=mesh('Draped green checked throw',verts,faces,'linen','cloth',True)
    o.data.materials.append(material('linen_green','cloth'));o.data.materials.append(material('sage','cloth'))
    for f in o.data.polygons:
        j=f.index//xs;i=f.index%xs;f.material_index=2 if i%2 and j%2 else 1 if (i+j)%2 else 0
    o.modifiers.new('Cloth thickness','SOLIDIFY').thickness=.009
    for i in range(16):tube('Throw fringe',[(-.91+i*.043,.20,.52),(-.92+i*.043,.13,.53)],.008,'sage',5)


def bookshelf(at=(-3.23,.082,-2.74),yaw=0):
    begin('bookshelf',at,yaw,[{'at':[0,1.10,0],'size':[1.12,2.2,.48]}])
    cube('Bookcase back',(0,1.07,-.18),(1.05,2.10,.09),'oak_edge',.025,'wood','Y')
    for x in (-.53,.53):cube('Bookcase upright',(x,1.12,0),(.13,2.25,.49),'oak',.035,'wood','Y')
    for y in (.12,.70,1.29,1.92):cube('Thick bookcase shelf',(0,y,.03),(1.10,.12,.50),'oak_light',.04,'wood')
    cube('Bookcase crown',(0,2.18,.015),(1.22,.16,.59),'oak_light',.055,'wood')
    for y in (.77,1.36):
        for i in range(6):book((-.41+i*.145,y,.02),.39+(i%3)*.045,.115,['sage','oak_light','terra','linen_green'][i%4])
    basket((0,.19,.08),.76,.38,.34)


def range_cooker(at=(2.0,.082,-2.77)):
    begin('range_cooker',at,collision=[{'at':[0,.59,0],'size':[.91,1.18,.85]}])
    cube('Sage range cabinet',(0,.54,0),(.89,1.05,.77),'sage',.04,'wood','Y')
    cube('Range oak foot',(0,.08,.01),(.94,.15,.83),'oak',.035,'wood')
    cube('Range oak countertop',(0,1.09,0),(1.0,.15,.90),'oak_light',.055,'wood')
    cube('Cast iron four ring hob',(0,1.18,0),(.79,.045,.68),'iron',.025)
    for x in (-.20,.20):
        for z in (-.17,.17):
            lathe('Round stove burner',(x,1.21,z),[(0,.105),(.025,.105),(.025,.073),(0,.073)],'iron_edge',20)
            for dz in (-.09,.09):cube('Burner trivet',(x,1.24,z+dz),(.26,.021,.018),'iron',.007)
    cube('Cream oven fascia',(0,.78,.43),(.87,.35,.11),'porcelain',.03)
    for x in (-.27,0,.27):ellipsoid('Oven control knob',(x,.82,.51),(.12,.12,.08),'iron_edge',12,8)
    cube('Cream oven door',(0,.40,.44),(.79,.52,.09),'porcelain',.04)
    cube('Dark inset oven window',(0,.41,.495),(.54,.30,.013),'iron',.03)
    cube('Oven handle',(0,.66,.55),(.48,.063,.07),'iron_edge',.022)


def firewood(at=(-.91,.082,-2.72)):
    begin('firewood_alcove',at,collision=[{'at':[0,.52,0],'size':[.82,1.04,.80]}])
    body=cube('Plaster log alcove',(0,.51,0),(.85,1.03,.75),'plaster_light',.07,'plaster')
    cut=arch_solid('Log niche real opening',.61,.10,.48,.25,1.4,.1,'iron');boolean_cut(body,cut)
    arch_trim('Log niche oak lip',.61,.10,.48,.25,.048,.08,.39,'oak_edge')
    cube('Alcove counter',(0,1.06,0),(.95,.13,.86),'oak_light',.04,'wood')
    for x,y in [(-.17,.22),(.13,.22),(-.07,.39),(.19,.43)]:
        o=cylinder('Stacked split firewood',(x,y,.03),.10,.46,'oak',vertices=10);o.rotation_euler.x=math.pi/2
        o=cylinder('Visible firewood end',(x,y,.272),.084,.012,'oak_light',vertices=10);o.rotation_euler.x=math.pi/2


def build():
    start('standard_room_5','545:2969')
    shell()
    reuse('hearth',(-2.03,.082,-2.66));reuse('fire',(-2.03,.29,-2.39))
    kit=reuse('kettle',(-2.03,1.405,-2.45))
    for o in kit['objects']:
        if any(t in o.name.lower() for t in ('pot','kettle')):
            o.data.materials.clear();o.data.materials.append(material('sage'))
    firewood();range_cooker()
    reuse('sink_cabinet',(.60,.082,-2.72));reuse('utensil_crock',(-.69,1.25,-2.79))
    reuse('wall_shelf',(.47,2.36,-2.97));reuse('shelf_plant',(1.16,2.46,-2.83))
    reuse('hanging_towel',(1.22,1.91,-3.02))
    reuse('window_plant',(-3.72,1.40,-.50),90)
    sofa();bookshelf()
    reuse('bookcase_plant',(-2.94,2.40,-2.75),original='shelf_plant')
    frame('bookcase_picture',(-3.50,2.58,-2.89),width=.30,height=.38)
    frame('botanical_picture',(-3.86,1.99,1.95),90)
    rug('round_rope_rug',(-2.08,.096,1.04),1.65,1.65,True)
    rug('dining_rug',(.66,.093,1.26),3.10,2.25)
    stool('reading_stool',(-2.92,.083,2.14),height=.46)
    begin('reading_cup',(-2.92,.615,2.14));cube('Reading book',(0,0,0),(.37,.07,.28),'sage',.018);mug((0,.05,0))
    stool('bookcase_stool',(-2.79,.083,-1.74))
    reuse('dining_table',(.65,.15,1.17))
    reuse('checked_runner',(.65,1.301,1.17),90)
    reuse('chair',(.69,.15,2.10),0)
    instance('chair','chair_far',(.69,.15,.21),180)
    begin('chair_cushion',(.69,.15,2.10));cube('Sage seat cushion',(0,.725,0),(.53,.13,.48),'sage_light',.055,'cloth')
    instance('chair_cushion','chair_far_cushion',(.69,.15,.21),180)
    reuse('daisy_jug',(.28,1.33,1.09))
    begin('tabletop_still_life',(.65,1.33,1.17))
    lathe('Oak fruit bowl',(.12,0,0),[(0,.14),(.05,.21),(.22,.28),(.25,.28),(.25,.24),(.07,.14)],'oak',28)
    for x,z in [(-.015,-.02),(.23,.04),(.11,-.14)]:
        ellipsoid('Apple',(x,.25,z),(.22,.22,.21),'D9653E',16,10)
        tube('Apple stem',[(x,.34,z),(x+.02,.4,z)],.012,'oak_dark',5)
        leaf('Apple leaf',(x,.38,z),(x+.13,.40,z+.04),.045,'leaf')
    mug((.61,0,.19))
    reuse('floor_plant',(-3.58,.083,2.45))
    reuse('entry_plant',(3.61,.083,-1.73),original='floor_plant')
    begin('entry_basket',(3.04,.083,-2.02));basket(width=.48,height=.38,depth=.36,handle=True)
    for x in (-.13,.08):ellipsoid('Basket red apple',(x,.40,0),(.19,.20,.18),'D9653E')
    begin('garden_boots',(2.90,.083,-1.51))
    for x in (-.15,.15):
        lathe('Open rubber boot shaft',(x,0,0),[(0,.105),(.13,.10),(.38,.085),(.40,.094),(.40,.070),(.15,.065)],'sage_dark',18)
        ellipsoid('Rounded boot toe',(x,.08,.13),(.21,.16,.30),'sage_dark',16,8)
    frame('door_hook_board',(3.91,1.92,-2.82),90,width=.28,height=.45)
    finalize();complete()


if __name__=='__main__':
    sys.path.insert(0,str(Path(__file__).resolve().parent/'source/standard_room_5'))
    from revision2 import build as build_review
    build_review()
