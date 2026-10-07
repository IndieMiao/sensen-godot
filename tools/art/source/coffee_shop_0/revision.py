"""SGODOT-181 courtyard: warm irregular masonry, meadow, fruit trees and four cats."""
import math,random,json
import kit as k
import series_revision as r
from kit import begin,cube,cylinder,tube,ellipsoid,mesh

def cat(pose,tone):
    seated=pose=='sit';lying=pose in ('sleep','loaf');h=.20 if lying else .32
    ellipsoid('Soft feline torso',(0,.34 if seated else h,0),(.35,.56 if seated else .27 if lying else .37,.39 if seated else .58),tone,16,8)
    hy=.63 if seated else h+.08
    ellipsoid('Rounded cat head',(0,hy,.27),(.31,.29,.29),tone,16,8)
    for x in (-.105,.105):
        mesh('Triangular soft cat ear',[(x-.07,hy+.085,.24),(x+.06,hy+.085,.24),(x,hy+.27,.23),(x-.05,hy+.085,.32),(x+.045,hy+.085,.32),(x,hy+.235,.30)],[(0,1,2),(3,5,4),(0,3,4,1),(1,4,5,2),(2,5,3,0)],tone,smooth=True)
        mesh('Blush ear triangle',[(x-.025,hy+.12,.322),(x+.025,hy+.12,.322),(x,hy+.211,.31)],[(0,1,2)],'DAAC9D')
        if pose=='sleep':tube('Closed sleeping eye',[(x*.65-.021,hy+.06,.406),(x*.65,hy+.053,.414),(x*.65+.021,hy+.065,.409)],.005,'655C53',5)
        else:ellipsoid('Alert eye',(x*.65,hy+.058,.409),(.028,.036,.015),'4E5046',8,4)
        ellipsoid('Cream muzzle',(x*.43,hy-.035,.409),(.10,.065,.037),'F0E8D6',10,5)
        for z in (-.17,.18):ellipsoid('White paw',(x,.067,z),(.13,.13 if lying else .19,.19),'EFE6D8',10,5)
    ellipsoid('Pink nose',(0,hy-.002,.44),(.032,.021,.016),'C78E91',8,4)
    tail=[(0,h,-.25),(.18,h,-.35),(.30,h+.04,-.26),(.30,h+.11,-.05)] if lying or seated else [(0,h,-.25),(.12,h+.17,-.35),(.15,h+.44,-.31),(.10,h+.57,-.24)]
    tube('Posed curved tail',tail,.039,tone,7)
    if pose=='walk':
        for x,y,z,sz,c in [(-.11,.41,-.12,(.18,.11,.22),'C58E58'),(.10,.44,.03,(.17,.10,.21),'5F6461'),(-.085,hy+.09,.29,(.13,.09,.16),'6B6861')]:ellipsoid('Calico fur patch',(x,y,z),sz,c,10,5)
    else:
        for z in (-.17,-.05,.08):tube('Soft fur stripe',[(-.125,h+.08,z),(-.06,h+.137,z),(0,h+.15,z),(.07,h+.137,z),(.13,h+.07,z)],.013,'B48043' if tone=='D9A558' else '797F85',5)

def meadow_material():
    mat=k.material('799C4E','matte').copy();mat.name='Courtyard baked meadow mottling'
    n=mat.node_tree.nodes;l=mat.node_tree.links;p=n.get('Principled BSDF')
    tex=n.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=3.4;tex.inputs['Detail'].default_value=2.3;tex.inputs['Roughness'].default_value=.65
    coord=n.new('ShaderNodeTexCoord');l.new(coord.outputs['Object'],tex.inputs['Vector'])
    ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].position=.24;ramp.color_ramp.elements[0].color=(*k.rgb('698C48'),1)
    ramp.color_ramp.elements[1].position=.77;ramp.color_ramp.elements[1].color=(*k.rgb('91A653'),1)
    l.new(tex.outputs['Fac'],ramp.inputs[0]);l.new(ramp.outputs['Color'],p.inputs['Base Color'])
    for o in k.KITS['grass_base']['objects']:
        o.data.materials.clear();o.data.materials.append(mat)

def revise():
    for name in ('orange_tree','flower_border','walking_cat'):r.remove(name)
    rng=random.Random(181)
    for name in ('back_wall','left_door_wall'):
        rec=k.KITS[name];k.CURRENT=rec
        for o in list(rec['objects']):
            if 'brick' in o.name.lower():rec['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)
        r.recolor(name,'E3C8A7')
        spans=[(-3.0,3.0)] if name=='back_wall' else [(-2.70,-1.65),(-.15,2.90)]
        for lo,hi in spans:
            for row in range(6):
                cuts=[lo]+[lo+.89*(j+.5*(row%2)) for j in range(10) if lo+.09<lo+.89*(j+.5*(row%2))<hi-.09]+[hi]
                for i,(a,b) in enumerate(zip(cuts,cuts[1:])):
                    o=cube('Large rounded staggered sandstone',((a+b)/2,(row+.5)*.484,.13),(b-a-.017,.467,.18),['E5CBAA','EBD5B5','DFC5A4','EAD0AC'][(i+row)%4],.058)
                    if name=='back_wall' and row in (4,5) and any(a<x<b for x in (-1.35,1.50)):
                        for x in (-1.35,1.50):
                            if a<x<b:
                                cutter=k.arch_solid('Arched niche cutter',.34,2.00,2.36,.17,.24,.22,'iron');cutter.location.x=x;k.boolean_cut(o,cutter)
        if name=='back_wall':
            for x in (-1.35,1.50):
                o=k.arch_solid('Recessed niche shadow',.33,2.01,2.36,.17,.009,.027,'B59F7E');o.location.x=x
        r.recolor(name,'F1DDC0',lambda o:'coping' in o.name.lower() or 'lintel' in o.name.lower())
    for name,count in [('back_crenellations',7),('left_crenellations',7)]:
        r.clear(name)
        for j in range(count):cube('Large hand-rounded battlement',(-2.67+j*.89,.22+rng.uniform(-.018,.018),0),(.66+rng.uniform(-.03,.03),.45,.40),'F2DDC0',.12)
    r.clear('floor');cube('Thick courtyard stone foundation',(0,-.12,0),(6.18,.27,5.68),'DBC09C',.12)
    for row in range(8):
        z=-2.70+(row+.5)*.675;cuts=[-3.0]+[x for x in [-3.0+.92*(i+.45*(row%2)) for i in range(1,9)] if x<2.98]+[3.0]
        for a,b in zip(cuts,cuts[1:]):cube('Varied cream stone slab',((a+b)/2,.028,z),(b-a-.014,.051,.660),rng.choice(['E7CCA5','EED6B2','E5CBA6','F0D9B6']),.033)
    for name in ('front_wall_left','front_wall_right','side_low_wall','corner_pier'):r.recolor(name,'E6CBA9');r.recolor(name,'F2DEC0',lambda o:'coping' in o.name.lower() or 'cap' in o.name.lower())
    r.clear('grass_base');cube('Rounded meadow island',(0,0,0),(8.0,.16,8.3),'799C4E',.18,'plaster')
    meadow_material()
    begin('grass_clump',at=(-3.52,-.20,2.9))
    for i in range(7):
        a=i*2.399;dx=math.cos(a)*.07;dz=math.sin(a)*.07;h=.13+(i%3)*.033
        mesh('Curved low-poly grass blade',[(dx-.028,0,dz),(dx+.028,0,dz),(dx+.024,h*.58,dz-.024),(dx+.013,h,dz-.051),(dx-.011,h*.58,dz-.024)],[(0,1,2),(0,2,4),(4,2,3),(2,1,0),(4,2,0),(3,2,4)],['89A541','B0C55A','94B047'][i%3])
    for i in range(41):
        side=i%4
        x=rng.uniform(-3.82,3.82) if side<2 else (-3.6 if side==2 else 3.6)+rng.uniform(-.15,.15)
        z=(-3.44 if side==0 else 4.24)+rng.uniform(-.17,.17) if side<2 else rng.uniform(-3.4,4.3)
        k.instance('grass_clump','grass_clump_%02d'%i,(x,-.20,z),rng.uniform(0,360))
    r.clear('garden_stepping_stones')
    for j in range(10):
        x=(-.25 if j%2 else .28)+rng.uniform(-.10,.10);z=.02+(j//2)*.225
        o=cube('Irregular rounded stepping stone',(x,-.045,z),(.39+rng.uniform(-.05,.07),.12,.28+rng.uniform(-.035,.04)),'E7CEAE',.06);o.rotation_euler.z=rng.uniform(-.3,.3)
    # Source chairs retain real woven rails with white cushions; round tables meet baseline.
    r.clear('chair');k.chair();r.vertical('chair',1.08)
    k.KITS['chair']['collision']=[{'at':[0,.50,0],'size':[.61,1,.62]}]
    r.vertical('round_table',1.22)
    for name in ('blue_vase_flowers','table_cup'):
        rec=k.KITS[name];r.move(name,(rec['at'][0],1.095,rec['at'][2]))
    for p in k.INSTANCES:
        if p['asset']=='blue_vase_flowers':p['position'][1]=1.095
    r.clear('sleeping_cat');cat('sleep','9FA5AA');r.move('sleeping_cat',(.04,.085,2.44))
    r.clear('counter_cat');cat('loaf','D9A558')
    begin('calico_cat',at=(-.38,.065,-.05),yaw=-30);cat('walk','EFE7D9')
    begin('seated_cat',at=(.58,.065,1.97),yaw=115);cat('sit','C1C6C8')
    r.recolor('entry_step','DA9B51',lambda o:'mat' in o.name.lower())
    k.CURRENT=k.KITS['entry_step'];cube('Lower stone entrance tread',(0,-.065,.33),(2.06,.13,.65),'F2DEC0',.045)
    for j in range(9):cube('Mat fine cream stripe',(-.51+j*.125,.160,0),(.009,.003,.41),'F2D5A7',0)
    for j in range(4):cube('Mat fine cross stripe',(0,.162,-.18+j*.12),(1.05,.003,.009),'F2D5A7',0)
    for i,x in enumerate((-2.35,2.38)):
        begin('stone_tree_bed_'+str(i),at=(x,.065,-1.75),collision=[{'at':[0,.25,0],'size':[1.0,.50,1.0]}])
        for dx,dz,sx,sz in [(0,.47,1.05,.12),(0,-.47,1.05,.12),(-.47,0,.12,.85),(.47,0,.12,.85)]:cube('Stone fruit-tree flowerbed',(dx,.22,dz),(sx,.44,sz),'DFC29A',.06)
    for p in k.INSTANCES:
        if p['name']=='chair_2':p['position'][0]=-.72
        if p['name']=='chair_3':p['position'][0]=.72
    k.KITS['side_low_wall']['collision']=[{'at':[0,.38,0],'size':[5.28,.76,.3]}]
    r.sync_instances()

def manifest():
    p=k.OUT/'layout.json';d=json.loads(p.read_text());d['revision']='R1'
    plants=[r.plant('FruitTreeLeft','fruit_tree',(-2.35,.06,-1.75),1.16,30),r.plant('FruitTreeRight','fruit_tree',(2.38,.06,-1.75),1.16,95),r.plant('ArchPeaceLily','peace_lily',(-2.60,.06,-.47),1.12,15,colliders=[{'at':[0,.22,0],'size':[.52,.44,.52]}]),r.plant('ShelfPothos','pothos',(.73,2.08,-2.46),.70)]
    for i,(x,z) in enumerate([(-2.60,2.61),(-1.99,2.61),(-1.35,2.61),(1.55,2.63),(2.18,2.63),(2.8,2.63)]+[(2.9,z) for z in [-2.25,-1.55,-.85,-.15,.55,1.25,1.95]]+[(-2.66,-1.06),(-2.58,-2.10)]):plants.append(r.plant('GardenShrub%02d'%i,'flower_shrub',(x,.73,z),.89,i*29))
    for tree in plants[:2]:tree['cast_shadow']=True
    d['shared_plants']=plants;d['material_overrides']={'floor':{'roughness':.76}}
    r.front_entry(d)
    d['boundaries']=[{'name':'meadow_floor','at':[0,-.32,.42],'size':[8,.20,8.3]}, {'name':'meadow_front_limit','at':[0,.55,4.58],'size':[8.2,1.8,.12]}, {'name':'meadow_back_limit','at':[0,.55,-3.75],'size':[8.2,1.8,.12]}, {'name':'meadow_left_limit','at':[-4.02,.55,.42],'size':[.12,1.8,8.4]}, {'name':'meadow_right_limit','at':[4.02,.55,.42],'size':[.12,1.8,8.4]}]
    r.lighting(d,'B8C879',ambient='BAC6D0',sun='FFE5D0',energy=1.22)
    d['lighting']['sun_position']=[6,9,4];d['review_lighting']['sun_position']=[6,9,4]
    d['camera']={'position':[11,11.3,12],'target':[0,1.08,.42],'size':11.5}
    from courtyard_bench import bench
    bench(d);p.write_text(json.dumps(d,indent=2)+'\n');r.append_plants(d)
