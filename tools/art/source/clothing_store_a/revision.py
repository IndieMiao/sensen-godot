"""SGODOT-186: concrete, royal-blue streetwear panels, dark fixtures and local lamps."""
import json,math,random
import kit as k
import boutique as b
import series_revision as r
from kit import begin,cube,cylinder,tube,ellipsoid

def split(source,target,match):
 rec=k.KITS[source];begin(target,at=rec['at'],yaw=rec['yaw']);dst=k.CURRENT
 for o in list(rec['objects']):
  if match(o):
   rec['objects'].remove(o);rec['collection'].objects.unlink(o);dst['collection'].objects.link(o);o.parent=dst['root'];dst['objects'].append(o)

def square_pot(name,at,size,height):
 begin(name,at=at)
 for axis in (0,2):
  for side in (-1,1):
   pos=[0,height/2,0];pos[axis]=side*(size/2-.016)
   dims=[size,height,size];dims[axis]=.032
   cube('Hollow square charcoal planter',pos,dims,'272A2E',.012)
 cube('Recessed soil',(0,height+.007,0),(size-.04,.015,size-.04),'403B35',.008)

def brush(name,at,yaw,color,seed):
 begin(name,at=at,yaw=yaw);rng=random.Random(seed)
 # Irregular ribbons and tapered dry edges, baked into the room atlas.
 points=[(-.45,-.31),(-.13,.10),(-.22,.04),(.22,.42),(.10,.07),(.42,.30),(.17,-.13),(.26,.02),(-.18,-.21)]
 for j in range(4):
  shift=(j-1.5)*.010
  poly=[(x+shift+rng.uniform(-.013,.013),y+rng.uniform(-.022,.022)) for x,y in points]
  o=b.extruded('Dry paint brush ribbon',poly,.004,color,0,'matte');o.location.y=-.0005*j
 for j in range(12):
  x=rng.uniform(-.44,.42);y=rng.uniform(-.30,.42)
  tube('Thin dry-brush fleck',[(x,y,.036),(x+.014,y+.05,.036)],.003,color,3)

def revise():
 for name in ('checkout_plant','front_square_plant','entrance_square_plant','left_trailing_plant'):r.remove(name)
 rec=k.KITS['boutique_floor'];k.CURRENT=rec
 for o in list(rec['objects']):
  if 'Concrete floor tile' in o.name:rec['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)
 for i in range(5):
  for j in range(5):cube('Large mottled concrete slab',(-2.4+i*1.2,.031,-2.16+j*1.08),(1.196,.054,1.076),['88848B','908B91','868289'][(i+2*j)%3],.004,'plaster')
 rec['collision']=[{'at':[0,-.08,0],'size':[6.1,.276,5.68]}]
 r.recolor('boutique_floor','77787B',lambda o:'Boutique slab' in o.name,kind='plaster')
 for name in ('boutique_left_wall','boutique_back_wall'):
  r.recolor(name,'27448F',lambda o:'inset' in o.name.lower() or 'Rear wall panel'==o.name.split('.')[0])
  r.recolor(name,'292C32',lambda o:any(w in o.name.lower() for w in ('crown','moulding','stile','rail','skirting')))
 r.recolor('brand_wall_panel','27448F',lambda o:'Blue brand' in o.name)
 brush('orange_brush_left',(-2.85,1.86,-1.79),90,'C67633',186)
 brush('purple_brush_right',(2.34,2.66,-2.55),0,'7643B1',187)
 brush('orange_brush_brand',(-.82,1.24,-2.50),0,'CD7B33',188)
 brush('purple_brush_arch',(-2.85,2.74,-2.21),90,'6B43AC',189)
 r.recolor('display_rug','383C44',lambda o:'rug' in o.name.lower(),kind='cloth')
 r.recolor('central_display_table','684733',lambda o:'wood' in o.name.lower(),kind='wood')
 r.recolor('display_storage_crate','594735',kind='wood')
 r.vertical('central_display_table',1.085);r.move('central_display_table',(-.21,.087,.16));r.move('display_rug',(-.21,.074,.16))
 for name in ['graphic_fold_black','graphic_fold_ivory','graphic_fold_blue','black_cap','blue_sneaker_pair','folded_black_trousers']:
  at=k.KITS[name]['at'];r.move(name,(at[0],at[1]+.074,at[2]-.28))
 at=k.KITS['display_storage_crate']['at'];r.move('display_storage_crate',(at[0],at[1]+.017,at[2]-.28))
 for p in k.INSTANCES:
  if p['name'].startswith(('lower_fold','lower_sneaker')):p['position'][1]+=.017;p['position'][2]-=.28
 # Keep original bench footprint, replace the cylindrical lobes with stitched slabs.
 r.clear('black_tufted_bench')
 for x in (-1.04,1.04):
  for z in (-.22,.22):cube('Black steel bench leg',(x,.27,z),(.065,.54,.065),'282C32',.012)
  cube('Bench steel end foot',(x,.045,0),(.065,.07,.50),'282C32',.012)
 cube('Bench black steel frame',(0,.47,0),(2.29,.09,.54),'292C31',.025)
 cube('Leather continuous cushion',(0,.57,0),(2.28,.20,.55),'454347',.040,'cloth')
 for j in range(1,6):
  x=-1.14+j*2.28/6
  tube('Recessed leather cross seam',[(x,.673,-.23),(x,.675,.23)],.003,'20242B',4)
  for z in [-.21+n*.035 for n in range(13)]:tube('Leather double stitch',[(x+.009,.676,z),(x+.009,.676,z+.015)],.0015,'64666B',3)
 for z in (-.23,.23):tube('Leather edge stitching',[(-1.08,.674,z),(1.08,.674,z)],.002,'62676D',4)
 k.KITS['black_tufted_bench']['collision']=[{'at':[0,.335,0],'size':[2.29,.67,.55]}]
 r.move('black_tufted_bench',(-.82,.07,2.32))
 # Mirror uses a separate luminous trim, preserving the nonreflecting stylized inset.
 r.recolor('standing_mirror','292C32',lambda o:'frame' in o.name.lower())
 begin('mirror_led',at=(-1.77,.07,-1.68),yaw=15)
 k.arch_trim('Warm LED mirror inner rim',.63,.14,1.68,.315,.019,.013,.068,'FFF0D2')
 # Four broad garment variants; right side includes two real printed T-shirts.
 for name in ('street_top_gray','street_top_black','street_top_ivory','street_top_blue','street_top_purple','street_top_varsity'):
  for o in k.KITS[name]['objects']:
   if 'garment body' in o.name.lower():o.scale.y*=1.25
 for name,color in [('printed_tee_black','33363C'),('printed_tee_white','DEDFDF')]:
  begin(name,at=(1.39 if 'black' in name else 1.81,2.23,-2.23));b.garment(color,'shirt')
  for j in range(6):tube('Original tee screenprint',[(-.13+j*.045,-.43,.085),(-.06+j*.041,-.55,.086),(-.14+j*.045,-.59,.085)],.006,'D9DCDD' if 'black' in name else '363A42',4)
 for p in list(k.INSTANCES):
  if p['name'] in ('right_black_hoodie','right_ivory_hoodie'):
   root=k.bpy.data.objects[p['name']]
   for o in list(root.children):k.bpy.data.objects.remove(o,do_unlink=True)
   k.bpy.data.objects.remove(root,do_unlink=True);k.INSTANCES.remove(p)
 # Purple hoodie belongs on left; blue varsity keeps its separate B letter asset.
 r.recolor('street_top_blue','674797',lambda o:'body' in o.name.lower() or 'sleeve' in o.name.lower(),kind='cloth')
 split('black_pendant','pendant_diffuser',lambda o:'diffuser' in o.name.lower())
 for p in list(k.INSTANCES):
  if p['asset']=='black_pendant':k.instance('pendant_diffuser',p['name']+'_diffuser',p['position'],p['yaw_degrees'])
 r.clear('street_wall_sconce')
 cube('Black bar-light backplate',(0,0,0),(.115,.60,.04),'282C32',.02)
 cube('Warm opal vertical light',(0,0,.046),(.068,.50,.037),'FFF0D3',.019)
 split('street_wall_sconce','bar_light_glow',lambda o:'opal' in o.name.lower())
 for p in list(k.INSTANCES):
  if p['asset']=='street_wall_sconce':k.instance('bar_light_glow',p['name']+'_glow',p['position'],p['yaw_degrees'])
 square_pot('front_black_pot',(2.49,.07,2.13),.58,.44)
 square_pot('entry_black_pot',(-2.62,.07,2.55),.50,.38)
 square_pot('checkout_black_pot',(.92,1.27,-2.02),.31,.25)
 square_pot('left_shelf_black_pot',(-2.59,2.48,.14),.43,.31)
 square_pot('right_shelf_black_pot',(2.74,2.48,-2.29),.43,.31)
 begin('entrance_tree_view',at=(-3.18,.06,1.96),yaw=90)
 k.arch_solid('Cool outdoor sky',1.34,.025,2.13,.34,.012,0,'92BFCE')
 for j in range(10):ellipsoid('Outdoor tree silhouette',(-.65+j*.145,.66+(j%3)*.22,.018),(.43,.57,.024),['728E75','94AD8D','A4BCA0'][j%3],8,4)
 r.sync_instances()

def manifest():
 p=k.OUT/'layout.json';d=json.loads(p.read_text());d['revision']='R1';d['botanical_assets']=['entrance_tree_view']
 # Original shared pot meshes sit inside the authored square outer planters.
 d['shared_plants']=[r.plant('FrontFoliage','peace_lily',(2.49,.10,2.13),1.05,25,colliders=[{'at':[0,.24,0],'size':[.49,.48,.49]}]),r.plant('EntryFoliage','peace_lily',(-2.62,.10,2.55),.90,-10,colliders=[{'at':[0,.22,0],'size':[.43,.44,.43]}]),r.plant('CheckoutFoliage','monstera',(.92,1.28,-2.02),.42),r.plant('LeftTrailing','pothos',(-2.59,2.50,.14),.90,90),r.plant('RightTrailing','pothos',(2.74,2.50,-2.29),.90),r.plant('LeftPlantCrown','monstera',(-2.59,2.50,.14),.48,90),r.plant('RightPlantCrown','monstera',(2.74,2.50,-2.29),.48)]
 d['material_overrides']={'entrance_tree_view':{'unshaded':True},'entrance_glass':{'alpha':.08},'mirror_led':{'emission':'FFE2B9','emission_energy':.9},'pendant_diffuser':{'emission':'FFE2B7','emission_energy':1.0},'bar_light_glow':{'emission':'FFE5C0','emission_energy':.8},'boutique_floor':{'roughness':.42}}
 r.lighting(d,'9A929B',ambient='B4BAC9',sun='EDF1FF',energy=.78,lamps=[{'position':v,'color':'FFDFC0','energy':.52,'range':1.5} for v in [[-1.58,1.1,-1.40],[-.92,2,-2.25],[-2.58,1.69,2.65],[-2.35,2.05,-2.25],[2.70,1.89,-2.25]]])
 d['lighting']['ambient_energy']=.55;d['review_lighting']['ambient']=.55;d['lighting']['sun_position']=[6,9,4];d['review_lighting']['sun_position']=[6,9,4]
 d['boundaries']=[{'name':'front_edge','at':[0,.6,2.94],'size':[6.2,1.8,.12]}, {'name':'right_edge','at':[3.06,.6,0],'size':[.12,1.8,5.9]}, {'name':'left_door_limit','at':[-3.12,1.4,1.96],'size':[.10,2.8,1.4]}]
 d['camera']={'position':[10,10,12],'target':[0,1.28,.08],'size':10.4}
 from street_bench import bench
 bench(d);p.write_text(json.dumps(d,indent=2)+'\n');r.append_plants(d)
