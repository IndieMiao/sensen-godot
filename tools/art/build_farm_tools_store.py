"""Farm Tools Store, Figma 545:2961. Art-only room kit."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from shop_room_parts import *
import scene_room_pipeline as p


def build():
    start('farm_tools_store','545:2961')
    shell(6.8,6.0,3.65,window_z=.23,door_x=2.49)
    sign('farm_tools_sign','FARM TOOLS',(-.64,2.80,-2.84),2.38,.64)
    begin('sign_sprout',(-.64,2.44,-2.71))
    for s in (-1,1):leaf('Sign carved sprout',(0,0,0),(s*.12,.13,0),.10,'linen_green')
    counter('sales_counter',(-.44,.082,-1.28),2.75,.77,1.18)
    begin('cash_register',(-.44,1.415,-1.28));register()
    reuse('counter_flowers',(-1.32,1.41,-1.33),original='daisy_jug')
    begin('counter_pencil_pot',(.09,1.42,-1.30));pot(radius=.085,height=.19)
    for i in range(5):tube('Counter pencil',[(0,.10,0),((i-2)*.029,.34,.02*(i%2))],.011,'oak',6)
    frame('counter_price_card',(.48,1.59,-1.21),width=.25,height=.25)
    shelf('seed_wall_shelf',(-3.14,.80,2.04),1.27,1.56,.29,3,90)
    begin('seed_packet',(-2.95,.92,2.46),90);seed_packet(crop=0)
    for j in range(2):
        for i in range(3):
            if i==0 and j==0:continue
            instance('seed_packet','seed_packet_'+str(j)+'_'+str(i),(-2.95,.92+j*.78,2.46-i*.36),90)
    begin('seed_packet_top',(-2.95,2.48,2.46),90)
    for i in range(3):seed_packet((i*.35,0,0),crop=i+1)
    reuse('shelf_plant',(-3.03,2.58,1.60),original='shelf_plant')
    begin('silver_watering_can',(-2.99,2.50,2.37),90);watering_can(color='iron_edge')
    reuse('window_plant',(-3.12,1.40,.67),90)
    begin('long_tools_wall',(-3.20,.93,-1.97),90)
    cube('Wall tool hanging rail',(0,1.28,0),(1.27,.16,.12),'oak',.025,'wood')
    for i,kind in enumerate(['shovel','fork','rake']):
        garden_tool(kind,(-.43+i*.43,0,.14),1.35)
        ellipsoid('Tool rail hook',(-.43+i*.43,1.23,.12),(.09,.09,.08),'brass')
    shelf('pot_wall_shelf',(1.0,2.46,-2.79),1.18,.1,.38,2)
    begin('pots_on_shelf',(.60,2.58,-2.69))
    for x in (0,.29):
        for j in range(2):pot((x,j*.12,0),.13,.23)
    reuse('pot_shelf_plant',(1.40,2.60,-2.69),original='shelf_plant')
    begin('hand_tools_board',(1.06,1.04,-2.78))
    cube('Pegboard backing',(0,.40,0),(1.35,.92,.10),'oak',.03,'wood')
    for j in range(5):
        for i in range(8):ellipsoid('Pegboard hole',(-.56+i*.16,.06+j*.16,.055),(.024,.024,.007),'oak_dark',8,6)
    for i in range(4):garden_tool('fork' if i%2 else 'shovel',(-.47+i*.31,.07,.12),.68)
    begin('shelf_supplies',(.50,2.04,-2.63));watering_can()
    seed_packet((.48,0,0),crop=1);seed_packet((.79,0,0),crop=1)
    worktable('front_display',(-.20,.082,1.50),2.53,1.12,.94)
    begin('display_seed_tray',(-.20,1.11,1.30));crate(width=1.06,height=.18,depth=.25)
    for i in range(3):seed_packet((-.35+i*.35,.06,0),crop=i)
    begin('display_gloves',(-.79,1.12,1.69))
    for x in (0,.36):
        cube('Garden glove palm',(x,.025,0),(.26,.065,.27),'sage',.055)
        for i in range(4):cube('Glove finger',(x-.09+i*.06,.025,.19),(.051,.061,.17),'sage',.02)
        o=cube('Glove thumb',(x+.15,.025,.05),(.095,.06,.15),'sage',.03);o.rotation_euler.z=.55
    begin('display_tools',(.52,1.12,1.75),90)
    garden_tool('shovel',(0,0,0),.65)
    # Lay the small tools across the tabletop in local space.
    for o in p.KITS['display_tools']['objects']:
        from mathutils import Matrix
        o.matrix_basis=Matrix.Rotation(math.pi/2,4,'X')@o.matrix_basis
    reuse('display_flowers',(-1.09,1.13,1.24),original='daisy_jug')
    begin('display_under_crates',(-.20,.32,1.50))
    for x in (-.82,.79):
        crate((x,0,0),.64,.38,.78)
        for z in (-.18,.12):pot((x,.075,z),.16,.29)
    for x in (-.18,.12):
        cube('Seed sack',(x,.23,0),(.28,.45,.34),'linen',.08,'cloth')
        leaf('Sack seed emblem',(x,.15,.18),(x+.07,.32,.18),.09,'sage')
    begin('tool_barrel',(-2.07,.082,.92),collision=[{'at':[0,.45,0],'size':[.68,.9,.68]}]);tool_bin()
    garden_tool('shovel',(-.10,.46,0),1.05);garden_tool('rake',(.12,.52,0),1.05)
    begin('entry_crate',(1.59,.082,-2.12));crate(width=.65,height=.46,depth=.59)
    for x in (-.15,.14):lathe('Twine spool',(x,.06,0),[(0,.14),(.22,.14),(.23,.12),(.23,.035),(.03,.035)],'terra_light',20)
    reuse('floor_plant',(2.96,.083,-1.66))
    lantern('door_lantern',(1.91,2.40,-2.69))
    finalize({'position':[10,8.5,11.5],'target':[0,1.45,0],'size':11.2});complete()


if __name__=='__main__':build()
