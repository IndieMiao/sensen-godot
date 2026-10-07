"""SGODOT-173 review: reference layout, climbable back-wall loft, furnished home."""
from pathlib import Path
import sys,math,json
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from zhaoyun_review import *
from build_deluxe_room_10 import cabinet,bed,lamp
from shop_room_parts import pot

PALETTE=dict(r2.PALETTE,oak='BB824D',oak_light='CC9258',oak_edge='A06A3F',oak_end='B47C49',floor='C38A55',floor_light='C8925F',floor_shade='BD8450',joint='A37244',plaster='F0D4B2',plaster_light='F3DEC1',linen='F0E2C8')

def kitchen():
    reuse('sink_cabinet',(-4.08,.082,1.35),90)
    cabinet('sink_left',(-4.08,.082,2.48),.56,90)
    cabinet('prep_counter',(-4.08,.082,.25),.58,90)
    r2.cooker();r2.move_kit('range_cooker',(-4.08,.082,-.62),90);r2.scale_kit('range_cooker',(1.65,.88,1))
    cabinet('kitchen_end',(-4.08,.082,-1.69),.96,90)
    # Pantry at far end, safely west of the staircase approach.
    begin('kitchen_pantry',(-4.12,.082,-2.52),90,[{'at':[0,1.1,0],'size':[.82,2.2,.76]}])
    cube('Tall sage cupboard',(0,1.05,0),(.79,2.10,.66),'sage',.045,'wood','Y')
    cube('Pantry cornice',(0,2.16,0),(.94,.13,.81),'oak_light',.04,'wood')
    cube('Pantry recessed tall door',(0,.73,.345),(.66,1.22,.05),'sage_light',.025,'wood','Y')
    tube('Pantry long iron handle',[(.23,.67,.40),(.23,.89,.40)],.022,'iron',8)
    for y in (1.48,1.94):cube('Pantry open shelf',(0,y,.38),(.66,.07,.33),'oak_light',.02,'wood')
    for i in range(3):pot((-.23+i*.23,1.52,.35),.073,.23,['porcelain','terra','jar_green'][i])
    begin('range_hood',(-4.35,1.55,-.62),90)
    cube('Hood heavy oak lower beam',(0,.52,.06),(1.49,.16,.79),'oak_light',.055,'wood')
    mesh('Broad cream tapered hood',[(-.70,.59,-.3),(.70,.59,-.3),(.70,.59,.42),(-.70,.59,.42),(-.30,1.43,-.29),(.30,1.43,-.29),(.30,1.43,.12),(-.30,1.43,.12)],[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],'plaster_light')
    cube('Hood tall plaster chimney',(0,1.96,-.085),(.60,1.06,.41),'plaster_light',.045,'plaster')
    begin('kitchen_dressing',(-4.14,1.245,.25),90)
    cube('Counter chopping board',(0,0,0),(.40,.035,.31),'oak_light',.045,'wood')
    pot((0,.025,0),.15,.21,'jar_green')
    cylinder('Covered cooking pot lid',(0,.25,0),.175,.035,'porcelain',vertices=24)
    ellipsoid('Pot lid knob',(0,.29,0),(.08,.07,.08),'sage',12,8)
    begin('open_pantry_shelves',(-4.41,2.03,.38),90)
    for y in (0,.56):
        cube('Rounded floating pantry shelf',(0,y,.09),(.98,.12,.43),'oak_light',.045,'wood')
        for i in range(3):
            pot((-.31+i*.30,y+.06,.12),.09,.23+.05*(i%2),['porcelain','jar_green','terra_light'][i])
            cylinder('Pantry jar cork',(-.31+i*.30,y+.30+.05*(i%2),.12),.08,.035,'oak',vertices=16)
    reuse('kitchen_utensils',(-4.0,1.245,-1.60),90,original='utensil_crock')
    reuse('stove_kettle',(-4.08,1.305,-.55),original='kettle')
    cabinet('island',(-2.0,.082,-.30),2.0,0,1.04)
    stool('bar_stool',(-2.66,.082,.31),height=.72,radius=.22)
    instance('bar_stool','bar_stool_middle',(-2,.082,.31));instance('bar_stool','bar_stool_right',(-1.34,.082,.31))
    begin('island_still_life',(-2,1.245,-.30))
    r2.metric_cloth('Island folded runner',[(-.38,.02),(.38,.02)],-.35,.7)
    lathe('Wood fruit bowl',(-.68,.02,0),[(0,.14),(.05,.23),(.15,.24),(.15,.21),(.04,.12)],'oak',24)
    for i in range(5):ellipsoid('Fresh orchard fruit',(-.78+.095*(i%3),.20,-.09+.14*(i//3)),(.15,.16,.15),'99A648' if i%2 else '8B9B40',12,8)
    reuse('island_daisies',(-1.72,1.245,-.30),original='daisy_jug');r2.scale_kit('island_daisies',(.76,.76,.76))
    begin('green_pendant',(-2,3.83,-.30))
    tube('Long black pendant flex',[(0,0,0),(0,-1.25,0)],.014,'iron',8)
    lathe('Green enamel shade',(0,-1.48,0),[(0,.32),(.04,.34),(.13,.30),(.31,.13),(.34,.10)],'sage_dark',28)
    begin('pendant_glow',(-2,2.36,-.30));ellipsoid('Warm pendant bulb',(0,0,0),(.25,.15,.25),'FFD383',18,10)
    merge_modules('kitchen_fittings',['sink_left','prep_counter','kitchen_end','kitchen_dressing','open_pantry_shelves','kitchen_utensils','stove_kettle','island_still_life'])
    r2.metric_cloth('Island side checked towel',[(.11,1.19),(.16,1.21),(.19,1.16),(.21,.79)],-2.92,.28,.09)
    tube('Island towel rail',[(-2.97,1.18,.15),(-2.59,1.18,.15)],.019,'iron',8)

def loft():
    level=2.73
    begin('loft_structure',(0,0,0),collision=[{'at':[2.45,2.60,-2.50],'size':[4.30,.25,2.32]},
        {'at':[.39,1.35,-1.35],'size':[.24,2.55,.24]},{'at':[4.40,1.35,-1.35],'size':[.24,2.55,.24]},
        {'at':[2.46,3.22,-1.32],'size':[4.22,1.04,.15]},{'at':[.32,3.22,-1.99],'size':[.15,1.04,1.17]}])
    cube('Loft thick oak platform',(2.45,2.60,-2.50),(4.30,.25,2.32),'oak',.045,'wood')
    for j in range(8):cube('Loft narrow plank',(2.45,2.742,-3.52+j*.29),(4.18,.038,.28),'floor',.009,'wood')
    for x in (.39,4.4):
        cube('Load bearing loft post',(x,1.33,-1.35),(.24,2.54,.26),'oak',.045,'wood','Y')
        cube('Loft newel post',(x,3.22,-1.32),(.22,1.05,.22),'oak_light',.035,'wood','Y')
        cube('Loft newel cap',(x,3.76,-1.32),(.30,.12,.30),'oak_light',.035,'wood')
    cube('Front structural beam',(2.45,2.41,-1.35),(4.3,.26,.26),'oak',.045,'wood')
    cube('Heavy continuous guardrail',(2.44,3.69,-1.32),(4.22,.18,.21),'oak_light',.035,'wood')
    for i in range(11):cube('Spaced solid guard baluster',(.63+i*.365,3.22,-1.32),(.13,.96,.13),'oak',.025,'wood','Y')
    cube('Loft west guardrail',(.32,3.69,-1.98),(.19,.18,1.22),'oak_light',.025,'wood','Z')
    for z in (-1.7,-2.05,-2.37):cube('West loft baluster',(.32,3.23,z),(.12,.94,.12),'oak',.025,'wood','Y')
    begin('back_wall_stairs',(0,0,0))
    start=-2.88;end=.31;run=end-start;rise=level-.083
    # Closed solid wedge prevents entry under low headroom and provides one
    # continuous <45-degree walkable collider. Art steps are independent.
    p.KITS['back_wall_stairs']['collision']=[{'points':[[start,.08,-3.54],[start,.08,-2.39],[end,.08,-3.54],[end,.08,-2.39],[end,level,-3.54],[end,level,-2.39],[.63,.08,-3.54],[.63,.08,-2.39],[.63,level,-3.54],[.63,level,-2.39]]}]
    for i in range(13):
        x=start+(i+.5)*run/13;y=.083+(i+1)*rise/13
        cube('Solid oak stair tread',(x,y-.055,-2.97),(run/13+.025,.11,1.14),'oak_light',.018,'wood','Z')
        cube('Tall stair riser',(x+run/26-.035,y-rise/26,-2.97),(.07,rise/13,1.10),'oak',.012,'wood','Y')
    cube('Top stair landing',(.46,2.66,-2.97),(.35,.13,1.14),'oak_light',.025,'wood')
    for z in (-3.51,-2.42):
        tube('Stair solid diagonal stringer',[(start,.12,z),(end,2.67,z)],.087,'oak_edge',4)
    # Broad front guard follows the climb, closes the outer edge along its full run.
    for i in range(6):
        t=i/6;x=start+run*t;y=.10+rise*t
        cube('Stair baluster',(x,y+.45,-2.37),(.12,.90,.12),'oak',.025,'wood','Y')
    tube('Continuous stair handrail',[(start,1.01,-2.37),(start+run*5/6,.10+rise*5/6+.91,-2.37)],.082,'oak_light',8)
    p.KITS['back_wall_stairs']['collision'].append({'points':[[start,.1,-2.43],[start,1.08,-2.43],[start+run*5/6,.10+rise*5/6+.98,-2.43],[start+run*5/6,.10+rise*5/6,-2.43],[start,.1,-2.31],[start,1.08,-2.31],[start+run*5/6,.10+rise*5/6+.98,-2.31],[start+run*5/6,.10+rise*5/6,-2.31]]})
    for name in ('loft_structure','back_wall_stairs'):
        k=p.KITS[name]
        for o in k['objects']:o.location.z*=.90;o.scale.z*=.90
        for c in k['collision']:
            if 'points' in c:
                for q in c['points']:q[1]*=.90
            else:c['at'][1]*=.90;c['size'][1]*=.90
    r2.move_kit('back_wall_stairs',(2.70,0,-2.98),90)
    bed();r2.move_kit('loft_bed',(2.49,2.493,-2.90));r2.move_kit('bedside_table',(3.88,2.493,-2.90));r2.move_kit('bedside_lamp',(3.88,3.063,-2.90))
    r2.move_kit('loft_curtain_left',(1.06,4.09,-3.48));r2.move_kit('loft_curtain_right',(4.15,4.09,-3.48));r2.scale_kit('loft_curtain_left',(1,.72,1));r2.scale_kit('loft_curtain_right',(1,.72,1))
    # Replace tiled duvet panels with metre-based checked cloth following the bed.
    r2.remove_named('loft_bed',['duvet panel','duvet edge']);p.b.CURRENT=p.KITS['loft_bed']
    r2.metric_cloth('Square gingham bed duvet',[(-.21,.62),(.50,.62),(.82,.58),(.86,.30)],-.88,1.76,.15)
    frame('bedroom_botanical',(2.13,3.76,-3.54),width=.42,height=.53)
    # Upper back-wall aperture and green window frame.
    k=p.KITS['back_wall'];p.b.CURRENT=k
    wall=next(o for o in k['objects'] if 'plaster infill' in o.name.lower())
    cut=arch_solid('Upper arched window aperture',.65,2.98,3.53,.32,.8,0,'plaster');cut.location.x=1.45;boolean_cut(wall,cut)
    begin('loft_window',(1.45,0,-3.57))
    arch_trim('Sage upper arch frame',.65,2.98,3.53,.32,.065,.085,0,'sage_dark')
    cube('Upper window sill',(0,2.97,.03),(.83,.12,.24),'sage',.025,'wood')
    cube('Upper window upright',(0,3.37,.01),(.045,.78,.06),'sage',.01,'wood','Y')
    cube('Upper window crossbar',(0,3.35,.01),(.61,.045,.06),'sage',.008,'wood')
    begin('loft_garden',(1.45,0,-3.78));arch_solid('Upper distant sky',.63,2.99,3.52,.31,.012,0,'sky')
    begin('loft_lamp_glow',(3.88,3.443,-2.90));ellipsoid('Bedside warm light',(0,0,0),(.22,.17,.22),'FFE1A0',16,10)
    merge_modules('loft_soft_furnishings',['loft_curtain_left','loft_curtain_right','bedroom_botanical','bedside_lamp'])

def underloft():
    r2.bookcase();r2.move_kit('bookshelf',(.94,.082,-2.30));r2.scale_kit('bookshelf',(1.18,.94,1))
    r2.hearth();r2.move_kit('hearth',(2.14,.082,-1.77));r2.move_kit('fire',(2.14,.30,-1.45));r2.move_kit('firewood_alcove',(3.05,.082,-1.84))
    r2.remove_named('hearth',['pipe','mount','chimney breast']);p.b.CURRENT=p.KITS['hearth'];cube('Underloft rounded plaster breast',(0,1.70,-.22),(.72,.77,.52),'plaster_light',.10,'plaster');r2.remove_named('kettle',[''])
    # Mantel and a landscape print replace the smaller room's stovepipe.
    begin('mantel_details',(2.14,1.53,-1.72))
    cube('Deep oak mantel shelf',(0,0,.05),(1.47,.15,.99),'oak_light',.055,'wood')
    for x in (.42,.62):
        lathe('Brass candlestick',(x,.085,.25),[(0,.075),(.04,.075),(.09,.025),(.22,.028)],'brass',14)
        cylinder('Cream wax candle',(x,.39,.25),.028,.19,'linen',vertices=12)
    frame('mantel_landscape',(2.02,1.98,-1.41),width=.52,height=.62)
    k=p.KITS['mantel_landscape'];r2.remove_named('mantel_landscape',['botanical']);p.b.CURRENT=k
    cube('Landscape sky',(0,0,.031),(.44,.54,.008),'B9D9D3',0)
    mesh('Landscape distant hills',[(-.22,-.02,.04),(-.04,.17,.04),(.1,-.04,.04),(.22,.05,.04),(.22,-.26,.04),(-.22,-.26,.04)],[(0,1,2,3,4,5)],'A6AD6C')
    mesh('Landscape foreground',[(-.22,-.16,.05),(.08,-.06,.05),(.22,-.13,.05),(.22,-.26,.05),(-.22,-.26,.05)],[(0,1,2,3,4)],'778E54')
    lamp('mantel_lamp',(3.05,1.245,-1.79))
    begin('door_wall_lamp',(3.93,2.89,-3.48))
    tube('Curved wall light bracket',[(0,0,0),(0,.14,.17),(0,.13,.31),(0,-.04,.39)],.032,'iron',10)
    lathe('Wall lamp black shade',(0,-.25,.39),[(0,.18),(.06,.17),(.18,.07)],'iron',20)
    begin('wall_lamp_glow',(3.93,2.66,-3.09));ellipsoid('Wall lamp warm bulb',(0,0,0),(.22,.12,.22),'FFDD94',16,10)
    merge_modules('hearth_mantel_details',['mantel_details','mantel_landscape','mantel_lamp','door_wall_lamp','kettle'])

def living_dining():
    jute('living_rug',(2.35,.09,1.26),3.48,3.28)
    r2.sofa((2.04,.082,-.03),0);r2.scale_kit('sofa',(1.22,1,1));r2.remove_named('sofa',['throw','fringe'])
    pillow=next(o for o in p.KITS['sofa']['objects'] if o.name.startswith('Puffed loose cushion'))
    mat=material('linen','cloth').copy();mat.name='Metric green cream checked pillow';pillow.data.materials.clear();pillow.data.materials.append(mat)
    nt=mat.node_tree;coords=nt.nodes.new('ShaderNodeTexCoord');checker=nt.nodes.new('ShaderNodeTexChecker');checker.inputs['Scale'].default_value=8.8
    checker.inputs['Color1'].default_value=(*rgb('linen'),1);checker.inputs['Color2'].default_value=(*rgb('sage_light'),1)
    nt.links.new(coords.outputs['Object'],checker.inputs['Vector']);nt.links.new(checker.outputs['Color'],nt.nodes.get('Principled BSDF').inputs['Base Color'])
    begin('sofa_basket' ,(.54,.083,.03),collision=[{'at':[0,.23,0],'size':[.43,.46,.46]}]);basket(width=.43,height=.39,depth=.42,handle=True)
    reuse('coffee_table',(2.13,.082,1.72),original='dining_table');r2.scale_kit('coffee_table',(.86,.54,.62))
    begin('coffee_still_life',(1.89,.723,1.72));cube('Reading book',(0,.034,0),(.34,.06,.25),'sage',.018);r2.mug((0,.07,0))
    begin('tv_console',(2.52,.082,3.02),collision=[{'at':[0,.31,0],'size':[2.40,.62,.48]}])
    cube('Oak television console',(0,.30,0),(2.4,.53,.46),'oak',.045,'wood')
    cube('Console cap',(0,.62,0),(2.48,.11,.55),'oak_light',.038,'wood')
    for x in (-.8,.8):
        cube('Console drawer front',(x,.35,.25),(.60,.31,.045),'oak_light',.023,'wood')
        ellipsoid('Drawer brass knob',(x,.35,.29),(.065,.065,.05),'brass',12,8)
    cube('Open console shelf shadow',(0,.34,.26),(.71,.34,.025),'oak_dark',.014)
    cube('Central console shelf',(0,.25,.31),(.71,.045,.31),'oak_light',.01,'wood')
    begin('television',(2.52,.82,3.02),180)
    cube('Thin TV black frame',(0,.48,0),(1.85,1.05,.06),'29302C',.035)
    cube('Television matte dark glass',(0,.48,.04),(1.76,.96,.012),'29302C',.025)
    for x in (-.56,.56):tube('Angled TV foot',[(x,.12,0),(x-.1,0,.11)],.022,'iron',8)
    jute('dining_rug',(-1.99,.09,2.42),3.83,2.22)
    reuse('dining_table',(-1.99,.082,2.43));r2.scale_kit('dining_table',(1.46,1,.84))
    begin('checked_runner',(-1.99,1.233,2.43),90)
    r2.metric_cloth('Long dining runner square gingham',[(-1.50,-.30),(-1.455,-.10),(-1.40,0),(-1.34,.01),(1.34,.01),(1.40,0),(1.455,-.10),(1.50,-.30)],-.32,.64,.125)
    r2.chair((-2.70,.082,3.24));r2.chair_pad((-2.70,.082,3.24));merge_modules('dining_chair',['chair','chair_cushion'])
    # Restore local reusable pivot after zone merging for the six repeated seats.
    k=p.KITS['dining_chair'];offset=v((-2.70,.082,3.24))
    for o in k['objects']:o.location-=offset
    for c in k['collision']:c['at']=[c['at'][i]-[-2.70,.082,3.24][i] for i in range(3)]
    r2.move_kit('dining_chair',(-2.70,.082,3.24))
    for name,at,yaw in [('front_middle',(-1.91,.082,3.24),0),('back_left',(-2.70,.082,1.60),180),('back_middle',(-1.91,.082,1.60),180),('end_left',(-3.63,.082,2.43),-90),('end_right',(-.36,.082,2.43),90)]:instance('dining_chair','chair_'+name,at,yaw)
    reuse('dining_daisies',(-2.1,1.26,2.43),original='daisy_jug');r2.scale_kit('dining_daisies',(.85,.85,.85))
    merge_modules('living_dressing',['coffee_still_life','sofa_basket'])
    merge_modules('natural_woven_rugs',['living_rug','dining_rug'])

def plants():
    for name,asset,at,s,yaw,col in [
      ('kitchen_floor_plant','peace_lily',(-4.04,.083,3.05),1.12,20,True),
      ('door_right_plant','monstera',(4.32,.083,-2.60),.95,-30,True),
      ('door_left_plant','peace_lily',(.46,.083,-1.83),.94,55,True),
      ('loft_trailing_plant','pothos',(4.13,2.493,-1.73),1.25,20,False),
      ('loft_extra_trail','ivy_long',(4.21,2.823,-1.45),.85,15,False),
      ('window_plant','pothos',(-4.21,1.40,2.05),1.10,80,False),
      ('pantry_plant','pothos',(-4.10,2.32,-2.42),1.06,70,False),
      ('shelf_plant','pothos',(-4.19,2.69,.50),.78,92,False),
      ('bookcase_plant','pothos',(1.11,2.22,-2.27),.88,-5,False),
      ('coffee_plant','peace_lily',(2.73,.723,1.72),.34,0,False)]:
        r2.shared_plant(name,asset,at,s,yaw,[{'at':[0,.24,0],'size':[.48,.48,.48]}] if col else None)

def build():
    start('deluxe_room_10','545:2970');p.b.PALETTE.update(PALETTE)
    shell(9.2,7.4,4.25,window_z=1.36,door_x=3.93);door_and_bounds(9.2,7.4,4.25,3.93)
    kitchen();loft();underloft();living_dining();plants()
    for o in p.KITS['back_wall']['objects']:
        if 'plaster infill' in o.name.lower():o.data.materials.clear();o.data.materials.append(material('F1C8B4','plaster'))
    # Fabric lampshades themselves glow; a hidden bulb does not illuminate an
    # opaque outward-facing shade. Keep metal stems in their opaque modules.
    begin('lampshade_glow',(0,0,0));dest=p.KITS['lampshade_glow'];bpy.context.view_layer.update()
    for name in ('loft_soft_furnishings','hearth_mantel_details'):
        kit=p.KITS[name]
        for obj in list(kit['objects']):
            if not obj.name.startswith('Cream lampshade'):continue
            world=obj.matrix_world.copy();kit['objects'].remove(obj)
            for c in list(obj.users_collection):c.objects.unlink(obj)
            dest['collection'].objects.link(obj);obj.parent=dest['root'];obj.matrix_world=world;dest['objects'].append(obj)
    merge_modules('warm_lamps_glow',['lampshade_glow','loft_lamp_glow','wall_lamp_glow','pendant_glow'])
    # Shared fire texture remains a separate material, not a baked white flame.
    r2.export_fire()
    p.MANIFEST_EXTRA['review_views']=[{'name':'detail-kitchen','position':[4,5,5],'target':[-2.70,1.6,-.30],'size':7.1}, {'name':'detail-loft','position':[7,5,7],'target':[1.15,2.45,-2.72],'size':7.4}, {'name':'detail-living','position':[8,5,9],'target':[1.7,.85,1.7],'size':6.4}]
    camera=json.loads(Path(__file__).with_name('camera-review.json').read_text())
    lighting={'ambient':.48,'ambient_color':'FFE5C4','sun':1.33,'sun_color':'FFE2AE','sun_position':[-7,5,-2.0], 'sun_target':[0,0,0], 'shadow_bias':.065,'shadow_normal_bias':.65,'shadow_distance':30,'background':'D5EAE0','background_gradient':True,
      'points':[{'position':[2.14,.70,-1.24],'energy':1.0,'color':'FF943D','range':2.4},{'position':[-2,2.35,-.30],'energy':.75,'color':'FFDD8C','range':2.7},{'position':[3.9,3.40,-2.80],'energy':.65,'color':'FFE0A1','range':2.1},{'position':[3.92,2.56,-3.0],'energy':.5,'color':'FFDC90','range':1.8}]}
    bench=json.loads(Path(__file__).with_name('bench-review.json').read_text())
    finish(camera['camera'],lighting,bench,materials={'fire':'fire','warm_lamps_glow':'glow','firewood_alcove':'matte'},no_shadow=['dining_daisies','island_daisies'],botanical=['dining_daisies','island_daisies'],post_export=r2.export_fire)
    if '--geometry-only' not in sys.argv:
        # finish/views reloads source, so export fire before optional ortho views
        pass

if __name__=='__main__':build()
