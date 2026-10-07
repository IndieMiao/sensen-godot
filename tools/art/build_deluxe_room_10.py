"""Deluxe Room-10: editable loft home, Figma 545:2970."""
from pathlib import Path
import math
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import scene_room_pipeline as p
from scene_room_pipeline import *
from build_standard_room_5 import sofa, bookshelf, range_cooker


def cabinet(name,at,width=1.6,yaw=0,height=1.08):
    begin(name,at,yaw,[{'at':[0,height/2,0],'size':[width,height,.77]}])
    cube('Sage cabinet',(0,height/2,0),(width,height,.69),'sage',.04,'wood','Y')
    cube('Oak counter',(0,height+.06,0),(width+.12,.14,.83),'oak_light',.045,'wood')
    cube('Oak plinth',(0,.06,0),(width+.06,.12,.73),'oak_edge',.022,'wood')
    for x in (-width/4,width/4):
        cube('Recessed door panel',(x,height*.50,.36),(width*.43,height*.75,.033),'sage_light',.025,'wood','Y')
        ellipsoid('Brass cabinet knob',(x+width*.12,height*.77,.407),(.07,.07,.065),'brass')


def loft():
    # Stairs are 12 real 19cm risers / 28cm treads. Art collision has one box
    # per tread; a character controller's eventual step policy is not assumed.
    begin('loft_structure',(1.9,.4,-2.6),collision=[{'at':[0,2.20,0],'size':[4.50,.25,2.32]},
          {'at':[-2.13,1.1,1.02],'size':[.20,2.2,.20]},{'at':[2.13,1.1,1.02],'size':[.20,2.2,.20]},
          {'at':[0,2.78,1.09],'size':[4.40,.87,.10]},{'at':[-2.19,2.77,-.70],'size':[.1,.87,.87]}])
    cube('Stair top landing',(-2.63,2.20,.27),(.88,.25,.70),'oak_light',.03,'wood')
    p.KITS['loft_structure']['collision'].append({'at':[-2.63,2.20,.27],'size':[.88,.25,.70]})
    cube('Loft floor platform',(0,2.20,0),(4.52,.25,2.35),'oak',.04,'wood')
    for j in range(8):cube('Loft floor plank',(0,2.345,-1.04+j*.29),(4.38,.06,.278),'floor_light',.014,'wood')
    for x in (-2.14,2.14):
        cube('Loft supporting post',(x,1.12,1.04),(.21,2.25,.22),'oak',.055,'wood','Y')
        cube('Balustrade newel',(x,2.81,1.10),(.18,1.08,.18),'oak_light',.03,'wood','Y')
        cube('Balustrade post cap',(x,3.36,1.10),(.25,.11,.25),'oak_light',.035,'wood')
    cube('Loft continuous handrail',(0,3.24,1.10),(4.48,.14,.16),'oak_light',.04,'wood')
    for i in range(14):cube('Loft safety baluster',(-2.02+i*.31,2.78,1.10),(.08,.88,.09),'oak',.022,'wood','Y')
    # Left side has an opening aligned to the top stair landing.
    for zz in (-1.05,-.72,-.38):cube('Side safety baluster',(-2.19,2.78,zz),(.08,.88,.08),'oak',.02,'wood','Y')
    cube('Side guardrail',(-2.19,3.23,-.73),(.13,.14,.84),'oak_light',.03,'wood','Z')
    begin('loft_stairs',(-.99,.082,-.24),collision=[])
    for i in range(12):
        y=.223*(i+1);z=.99-i*.28
        cube('Solid wooden stair tread',(0,y-.065,z),(.94,.13,.29),'oak_light',.02,'wood')
        cube('Stair riser',(0,y-.155,z-.11),(.90,.19,.07),'oak',.01,'wood')
        p.KITS['loft_stairs']['collision'].append({'at':[0,y/2,z],'size':[.94,y,.28]})
    # Stringers and balusters follow the stair, keeping 80cm clear width.
    for x in (-.46,.46):
        tube('Stair solid stringer',[(x,.09,1.16),(x,2.62,-2.05)],.09,'oak_edge',4)
    for i in range(7):
        y=.223*(1+i*1.7);z=.99-i*.476
        cube('Stair outer baluster',(.48,y+.40,z),(.10,.86,.10),'oak',.024,'wood','Y')
    tube('Continuous stair handrail',[(.48,1.02,1.02),(.48,3.53,-1.99)],.077,'oak_light',8)


def bed():
    begin('loft_bed',(2.00,2.78,-2.88),collision=[{'at':[0,.32,0],'size':[1.82,.64,1.63]}])
    cube('Oak bed frame',(0,.21,0),(1.82,.22,1.70),'oak',.055,'wood')
    for x in (-.77,.77):
        for z in (-.69,.69):cube('Bed foot',(x,.10,z),(.13,.23,.13),'oak_edge',.025,'wood','Y')
    cube('Soft mattress',(0,.44,0),(1.77,.31,1.61),'linen',.12,'cloth')
    cube('Rounded oak headboard',(0,.64,-.78),(1.91,.85,.14),'oak',.10,'wood')
    for x in (-.45,.45):cube('Cream bed pillow',(x,.68,-.40),(.73,.16,.47),'porcelain',.085,'cloth')
    for i in range(8):
        for j in range(5):cube('Sage checked duvet panel',(-.77+i*.22,.621,.0+j*.16),(.222,.03,.162),['linen','linen_green','sage_light'][(i%2)+(j%2)],.013,'cloth')
    cube('Folded duvet edge',(0,.59,-.13),(1.78,.11,.20),'linen',.038,'cloth')
    begin('bedside_table',(3.30,2.78,-2.86),collision=[{'at':[0,.27,0],'size':[.54,.54,.5]}])
    for x in (-.20,.20):
        for z in (-.18,.18):cube('Nightstand leg',(x,.19,z),(.09,.38,.09),'oak',.02,'wood','Y')
    cube('Nightstand drawer',(0,.35,0),(.50,.27,.45),'oak',.035,'wood')
    cube('Nightstand top',(0,.52,0),(.59,.09,.53),'oak_light',.03,'wood')
    ellipsoid('Nightstand drawer knob',(0,.35,.26),(.06,.06,.06),'brass')
    lamp('bedside_lamp',(3.30,3.35,-2.86))
    # Curtains at the open loft corners are modeled folds with real thickness.
    for name,x in [('loft_curtain_left',.26),('loft_curtain_right',3.9)]:
        begin(name,(x,4.83,-3.54))
        verts=[];faces=[]
        for j in range(13):
            t=j/12;wid=.70-.35*math.sin(t*math.pi)
            for i in range(13):verts.append(((i/12-.5)*wid,-1.94*t,.04*math.cos(i/12*math.pi*8)))
        for j in range(12):
            for i in range(12):faces.append((j*13+i,j*13+i+1,(j+1)*13+i+1,(j+1)*13+i))
        o=mesh('Pleated cream curtain',verts,faces,'linen','cloth',True);o.modifiers.new('Fabric thickness','SOLIDIFY').thickness=.009
        cube('Curtain tie',(0,-1.20,.025),(.23,.085,.13),'terra_light',.022,'cloth')


def lamp(name,at):
    begin(name,at)
    lathe('Lamp brass foot',(0,0,0),[(0,.12),(.03,.13),(.07,.08),(.19,.045)],'iron_edge',20)
    cylinder('Lamp stem',(0,.25,0),.022,.24,'brass',vertices=12)
    lathe('Cream lampshade',(0,.24,0),[(0,.19),(.03,.20),(.27,.11),(.28,.10),(.28,.082),(.035,.175)],'linen',24)


def build():
    start('deluxe_room_10','545:2970')
    shell(width=9.2,depth=7.4,height=4.9,window_z=1.2,door_x=3.94)
    reuse('sink_cabinet',(-4.10,.082,1.04),90)
    cabinet('sink_left_cabinet',(-4.12,.082,2.35),.74,90)
    cabinet('kitchen_drawers',(-4.12,.082,-.24),.75,90)
    range_cooker((-4.10,.082,-1.13));p.KITS['range_cooker']['root'].rotation_euler.z=math.pi/2;p.KITS['range_cooker']['yaw']=90
    cabinet('kitchen_end_cabinet',(-4.12,.082,-2.20),1.15,90)
    reuse('wall_shelf',(-4.45,2.50,-.10),90)
    reuse('shelf_plant',(-4.24,2.62,-.35),90)
    reuse('utensil_crock',(-3.97,1.25,-1.95),90)
    begin('range_hood',(-4.22,1.42,-1.10),90)
    cube('Hood oak lower lip',(0,.63,0),(1.37,.14,.70),'oak_light',.04,'wood')
    # Four-sided plaster hood with a tapered real silhouette.
    mesh('Tapered plaster hood',[(-.64,.70,-.3),(.64,.70,-.3),(.64,.70,.3),(-.64,.70,.3),(-.28,1.49,-.25),(.28,1.49,-.25),(.28,1.49,.14),(-.28,1.49,.14)],[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],'plaster_light')
    cube('Hood chimney',(0,1.90,-.06),(.56,.84,.40),'plaster_light',.04,'plaster')
    bookshelf((-3.97,.082,-3.09),90)
    loft();bed()
    frame('bedroom_botanical',(2.06,4.22,-3.55),width=.47,height=.61)
    reuse('loft_greenery',(3.91,2.8,-1.66),original='shelf_plant')
    k=reuse('hearth',(2.38,.082,-1.90))
    for o in list(k['objects']):
        if any(t in o.name.lower() for t in ['chimney','elbow']):k['objects'].remove(o);p.bpy.data.objects.remove(o,do_unlink=True)
    reuse('fire',(2.38,.29,-1.63))
    # Fireplace taller plaster breast and wooden mantel.
    begin('mantel',(2.38,1.40,-1.90));cube('Mantel shelf',(0,0,0),(1.53,.16,.94),'oak_light',.05,'wood')
    cube('Fireplace plaster breast',(0,.63,-.24),(1.18,1.26,.42),'plaster_light',.12,'plaster')
    frame('mantel_picture',(2.34,1.90,-1.98),width=.48,height=.60)
    reuse('mantel_plant',(1.92,1.49,-1.91),original='shelf_plant')
    k=reuse('underloft_bookcase',(.64,.082,-3.10),source='standard_room_5',original='bookshelf')
    for o in k['objects']:o.location.z*=.88;o.scale.z*=.88
    k['collision']=[{'at':[0,.98,0],'size':[1.12,1.96,.48]}]
    cabinet('island',(-2.40,.082,-.35),1.65,0,.99)
    reuse('island_flowers',(-2.40,1.23,-.36),original='daisy_jug')
    stool('bar_stool',(-2.93,.082,.33),height=.72,radius=.24)
    instance('bar_stool','bar_stool_middle',(-2.40,.082,.33));instance('bar_stool','bar_stool_right',(-1.87,.082,.33))
    rug('living_rug',(2.3,.095,1.20),2.90,2.8)
    sofa((2.27,.082,-.02),0)
    for o in p.KITS['sofa']['objects']:o.location.x*=1.25;o.scale.x*=1.25
    p.KITS['sofa']['collision']=[{'at':[0,.55,0],'size':[2.62,1.1,.9]}]
    reuse('coffee_table',(2.32,.082,1.22),original='dining_table')
    k=p.KITS['coffee_table']
    for o in k['objects']:
        o.location.z*=.54;o.scale.z*=.54
    k['collision']=[{'at':[0,.35,0],'size':[1.9,.70,1.18]}]
    reuse('coffee_plant',(2.83,.73,1.13),original='shelf_plant')
    begin('coffee_mug',(1.96,.73,1.21));mug()
    begin('tv_console',(2.33,.082,2.69),collision=[{'at':[0,.29,0],'size':[2.22,.58,.44]}])
    cube('TV cabinet carcass',(0,.28,0),(2.2,.53,.45),'oak',.04,'wood')
    cube('TV open dark cubby',(0,.27,-.234),(1.9,.32,.012),'oak_dark',.014)
    for x in (-.44,.44):cube('TV console shelf',(x,.13,-.27),(.83,.035,.31),'oak_light',.01,'wood')
    cube('Console cap',(0,.58,0),(2.29,.10,.54),'oak_light',.04,'wood')
    begin('television',(2.33,.73,2.69),180)
    cube('Television black screen',(0,.47,0),(1.58,.88,.06),'252829',.028)
    cube('Thin television bezel',(0,.47,-.018),(1.63,.93,.045),'iron_edge',.035)
    for x in (-.40,.40):tube('Television foot',[(x,.10,0),(x-.14,0,.11)],.024,'iron',8)
    rug('dining_rug',(-1.71,.095,2.30),3.25,2.4)
    reuse('dining_table',(-1.73,.13,2.29))
    reuse('checked_runner',(-1.73,1.281,2.29),90)
    reuse('daisy_jug',(-1.73,1.31,2.29))
    reuse('chair',(-2.22,.13,3.18),0)
    for name,at,yaw in [('chair_front_right',(-1.32,.13,3.18),0),('chair_back_left',(-2.22,.13,1.4),180),('chair_back_right',(-1.32,.13,1.4),180)]:instance('chair',name,at,yaw)
    reuse('floor_plant',(-4.0,.083,3.0));reuse('entry_plant',(4.02,.083,-2.80),original='floor_plant')
    lamp('living_lamp',(3.37,1.07,-1.63))
    finalize({'position':[12,11,14],'target':[0,1.8,0],'size':14.7});complete()


if __name__=='__main__':
    import runpy
    runpy.run_path(str(Path(__file__).resolve().parent/'source/deluxe_room_10/revision.py'),run_name='__main__')
