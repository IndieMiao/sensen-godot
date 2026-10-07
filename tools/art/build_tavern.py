"""Tavern, Figma 545:2966. Dark timber, reused seating and warm lantern set."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from shop_room_parts import *
import scene_room_pipeline as p


def wooden_walls():
    for name in ('window_wall','back_wall'):
        kit=p.KITS[name];p.b.CURRENT=kit
        wall=next(o for o in kit['objects'] if 'plaster infill' in o.name)
        wall.data.materials.clear();wall.data.materials.append(material('916440','wood'))
        length=6.8 if name=='window_wall' else 7.4
        # Bake fine plank seams into the wall UV island, keeping sub-pixel
        # strips out of the exported mesh and avoiding atlas edge bleed.
        mat=wall.data.materials[0];nt=mat.node_tree
        shader=nt.nodes.get('Principled BSDF');base=shader.inputs['Base Color'].links[0].from_socket
        geo=nt.nodes.new('ShaderNodeNewGeometry');xyz=nt.nodes.new('ShaderNodeSeparateXYZ')
        nt.links.new(geo.outputs['Position'],xyz.inputs[0])
        modulo=nt.nodes.new('ShaderNodeMath');modulo.operation='MODULO';modulo.inputs[1].default_value=.202
        nt.links.new(xyz.outputs['Z'],modulo.inputs[0])
        stripe=nt.nodes.new('ShaderNodeMath');stripe.operation='LESS_THAN';stripe.inputs[1].default_value=.008
        nt.links.new(modulo.outputs[0],stripe.inputs[0])
        blend=nt.nodes.new('ShaderNodeMixRGB');blend.inputs[2].default_value=(*rgb('68472E'),1)
        nt.links.new(stripe.outputs[0],blend.inputs[0]);nt.links.new(base,blend.inputs[1]);nt.links.new(blend.outputs[0],shader.inputs['Base Color'])
        cube('Timber dado rail',(0,.82,.12),(length-.39,.105,.10),'oak',.02,'wood')


def saloon_door():
    kit=p.KITS['window_wall'];p.b.CURRENT=kit
    target=next(o for o in kit['objects'] if 'plaster infill' in o.name)
    cut=arch_solid('Saloon entrance aperture',1.04,.07,1.89,.50,.8,0,'plaster');cut.location.x=2.50;boolean_cut(target,cut)
    begin('saloon_door',(-3.59,.07,-2.50),90)
    arch_trim('Oak tavern doorway',1.08,0,1.89,.52,.14,.18,.05,'oak')
    cube('Dark pantry behind arch',(0,1.21,-.20),(1.04,2.35,.05),'oak_dark',.02)
    for side in (-1,1):
        for i in range(4):
            x=side*(.085+i*.108);h=1.10+.13*math.sin(i/3*math.pi)
            cube('Swing door vertical plank',(x,.35+h/2,.14),(.103,h,.065),'oak',.017,'wood','Y')
        for y in (.57,1.10):cube('Swing door cross rail',(side*.26,y,.19),(.43,.075,.055),'oak_light',.013,'wood')
    for y in (1.62,1.94):
        cube('Pantry shelf behind door',(0,y,-.11),(.94,.04,.17),'oak_light',.013,'wood')
        for x in (-.31,0,.31):bottle((x,y+.03,-.10),'iron_edge',.25)


def lantern_set():
    placements=[('wall_left',(-3.45,2.06,2.22),90),('bar_left',(-1.31,2.94,-3.13),0),('bar_right',(1.56,2.94,-3.13),0),('window_right',(3.28,2.49,-3.13),0)]
    lantern('wall_lantern',placements[0][1],90)
    framekit=p.KITS['wall_lantern']
    glass=next(o for o in framekit['objects'] if 'warm glass' in o.name)
    framekit['objects'].remove(glass);p.bpy.data.objects.remove(glass,do_unlink=True)
    begin('lantern_glow',placements[0][1],90);cube('Warm lantern luminous glass',(0,0,0),(.205,.28,.205),'FFCA70',.025)
    for name,at,yaw in placements[1:]:
        instance('wall_lantern',name+'_frame',at,yaw);instance('lantern_glow',name+'_glow',at,yaw)
    begin('hanging_chandelier',(-2.20,2.99,.10))
    lathe('Iron wheel chandelier',(0,0,0),[(0,.60),(.07,.60),(.07,.52),(0,.52)],'iron_edge',40)
    for i in range(4):
        a=i*math.pi/2
        tube('Suspension chain',[(math.cos(a)*.55,.07,math.sin(a)*.55),(0,.85,0)],.018,'iron',6)
        tube('Chandelier spoke',[(0,.03,0),(math.cos(a)*.55,.03,math.sin(a)*.55)],.026,'oak_edge',8)
        at=(-2.20+math.cos(a)*.65,2.72,.10+math.sin(a)*.65)
        instance('wall_lantern','chandelier_frame_'+str(i),at)
        instance('lantern_glow','chandelier_glow_'+str(i),at)


def build():
    start('tavern','545:2966')
    p.b.PALETTE.update({'oak':'95633B','oak_light':'B98149','oak_edge':'754B2E','oak_dark':'523522','floor':'A67546','floor_light':'B38250','floor_shade':'97633A'})
    shell(7.4,6.8,3.8,open_left=False,open_back=False)
    saloon_door();wall_window('tavern_window','back_wall',2.65,.86,1.39,2.27,.08);wooden_walls()
    counter('long_bar',(.03,.082,-1.54),3.75,.88,1.20,'oak')
    # A return at the barrel end makes the counter a compact L.
    counter('bar_return',(1.99,.082,-1.98),.66,1.75,1.20,'oak')
    shelf('back_bar',(.07,.94,-3.04),2.87,1.49,.43,4)
    begin('bottle_green',(-1.16,1.047,-2.96));bottle(color='sage_dark',height=.34)
    begin('bottle_amber',(-.83,1.047,-2.96));bottle(color='975122',height=.32)
    for row in range(3):
        for col in range(8):
            if row==0 and col in (0,1):continue
            instance('bottle_green' if (row+col)%2==0 else 'bottle_amber','bar_bottle_'+str(row)+'_'+str(col),(-1.16+col*.34,1.047+row*.495,-2.96))
    sign('tavern_sign','TAVERN',(.07,3.07,-3.21),2.70,.55,color='oak_light',letter_color='oak_dark')
    stool('bar_stool',(-1.29,.082,-.66),height=.76,radius=.25)
    for i,x in enumerate((-.41,.47,1.35)):instance('bar_stool','bar_stool_'+str(i),(x,.082,-.66))
    begin('beer_cask',(1.30,1.45,-1.78))
    barrel(radius=.29,height=.59)
    from mathutils import Matrix, Vector
    transform=Matrix.Translation(Vector((0,.295,.34)))@Matrix.Rotation(math.pi/2,4,'X')
    for o in p.KITS['beer_cask']['objects']:o.matrix_basis=transform@o.matrix_basis
    o=cylinder('Beer cask front lid',(0,.34,.31),.256,.035,'oak_light',vertices=32);o.rotation_euler.x=math.pi/2
    cube('Cask wooden cradle',(0,.03,0),(.63,.14,.49),'oak_dark',.028,'wood')
    tube('Brass beer tap',[(0,.27,.28),(0,.21,.39),(0,.15,.40)],.025,'brass',8)
    begin('bar_drinks',(-.25,1.46,-1.34))
    for x in (-.83,0,.75):mug((x,0,0),'terra')
    begin('barrel',(-2.93,.082,-1.58),collision=[{'at':[0,.42,0],'size':[.65,.84,.65]}]);barrel(radius=.32,height=.82)
    instance('barrel','barrel_left',(-2.42,.082,-2.03))
    instance('barrel','barrel_right_one',(2.67,.082,-2.09))
    instance('barrel','barrel_right_two',(3.16,.082,-1.59))
    rug('left_table_rug',(-2.14,.092,.94),2.47,1.95)
    reuse('square_table',(-2.14,.082,.91),original='dining_table')
    round_table('round_table',(0.07,.082,2.22),.79,.86)
    instance('round_table','round_table_right',(2.52,.082,.94))
    stool('dining_stool',(-2.14,.082,1.87),height=.59,radius=.25)
    placements=[(-3.02,.082,.85),(-1.26,.082,.85),(-2.14,.082,-.04),(-.83,.082,2.22),(.04,.082,3.13),(.94,.082,2.23),(.05,.082,1.31),(1.62,.082,.94),(2.50,.082,1.84),(3.39,.082,.91),(2.52,.082,.04)]
    for i,at in enumerate(placements):instance('dining_stool','seat_'+str(i),at)
    begin('table_mug',(-2.59,1.29,.85));mug(color='terra')
    for i,at in enumerate([(-1.62,1.29,1.02),(-.21,1.08,2.42),(.48,1.08,2.03),(2.10,1.08,.95),(2.85,1.08,1.1)]):instance('table_mug','table_mug_'+str(i),at)
    begin('table_candle',(-2.12,1.29,.95))
    cylinder('Candleholder dish',(0,.025,0),.12,.05,'brass',vertices=20)
    cylinder('Wax candle',(0,.15,0),.06,.22,'linen',vertices=16)
    begin('candle_glow',(-2.12,1.57,.95));ellipsoid('Small candle flame',(0,.043,0),(.065,.12,.065),'FFE49C',12,8)
    for i,at in enumerate([(.10,1.08,2.18),(2.50,1.08,.94)]):
        instance('table_candle','table_candle_'+str(i),at)
        instance('candle_glow','candle_glow_'+str(i),(at[0],at[1]+.28,at[2]))
    begin('tavern_snacks',(.12,1.09,2.35))
    lathe('Snack plate',(0,0,0),[(0,.16),(.03,.21),(.07,.22),(.075,.19)],'terra',24)
    for i in range(5):ellipsoid('Round baked snack',(-.12+i*.056,.10,.025*(i%2)),(.09,.085,.09),'terra_light',12,8)
    shelf('left_display_shelf',(-3.47,1.37,.27),1.27,.20,.32,2,90)
    reuse('shelf_plant',(-3.26,1.64,.65),90)
    frame('landscape_frame',(-3.54,1.62,1.36),90,width=.66,height=.43)
    begin('stag_banner',(-3.51,2.85,1.22),90)
    mesh('Green pointed pennant',[(-.36,.38,0),(.36,.38,0),(.36,-.20,0),(0,-.48,0),(-.36,-.20,0)],[(0,4,3,2,1)],'sage_dark')
    ellipsoid('Stag emblem head',(0,-.01,.022),(.16,.20,.023),'terra_light',12,8)
    for s in (-1,1):
        tube('Stag antler',[(s*.035,.06,.035),(s*.16,.18,.035),(s*.19,.32,.035)],.012,'terra_light',6)
        tube('Stag antler tine',[(s*.13,.15,.035),(s*.26,.18,.035)],.011,'terra_light',6)
    reuse('floor_plant',(1.44,.083,3.03))
    lantern_set()
    lighting={'ambient':.50,'sun':.65,'points':[{'position':[-2.2,2.7,.1],'energy':1.5,'range':3.7},
              {'position':[-1.25,2.7,-2.85],'energy':.95,'range':2.8},
              {'position':[1.6,2.7,-2.85],'energy':.95,'range':2.8}]}
    sys.path.insert(0,str(Path(__file__).resolve().parent/'source/tavern'))
    import revision2
    revision2.revise()


if __name__=='__main__':build()
