"""Deterministic market placements. Run with ordinary Python; no gameplay writes."""
from pathlib import Path
import json, math
ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/'assets/rooms/market_plaza'
F=.05
STREET='res://assets/landmarks/_shared/street_kit/'
assets=[]
def box(name,size,at):return {'name':name,'size':size,'at':at}
def asset(name,file,position,yaw=0,colliders=None,group='MarketProps',material='matte',scale=None,**kw):
 a={'name':name,'file':file,'position':position,'yaw_degrees':yaw,'colliders':colliders or [],'group':group,'material':material,'cast_shadow':True}
 if scale:a['scale']=scale
 a.update(kw);assets.append(a);return a
asset('ground','mp_ground.glb',[0,0,0],colliders=[box('Floor',[16,.25,16],[0,-.075,0])],group='Ground',material='paving')
asset('surround','mp_surround.glb',[0,0,0],group='Ground',material='grass',cast_shadow=False)
asset('east_sidewalk','mp_sidewalk.glb',[9,0,5],group='Ground',material='paving',cast_shadow=False)
asset('south_sidewalk','mp_sidewalk.glb',[5,0,9],90,group='Ground',material='paving',cast_shadow=False)
for side in ['south','east']:
 for i,t in enumerate(range(-7,18,2)):
  asset(f'outer_curb_{side}_{i}','mp_edge_trim.glb',[t,0,10] if side=='south' else [10,0,t],0 if side=='south' else 90,group='Ground')
for side in ['north','west']:
 for i,t in enumerate([-6,-2,2,6]):
  sf_index=(i+4) if side=='north' else (3-i)
  asset(f'facade_{side}_{i}',f'facade_sf_{sf_index}.glb',[t,F,-9.25] if side=='north' else [-9.25,F,t],0 if side=='north' else 90,
   [box('FacadeBarrier',[4,6.5,2.5],[0,3.25,0]),box('DecorativeDoorSteps',[1.36,.32,.85],[0,.16,1.55])],group='FarFacades',
   variants={'san_francisco':f'facade_sf_{sf_index}.glb','generic':f'facade_generic_{i}.glb'})
for side in ['south','east']:
 for i,t in enumerate([-6.8,-4.6,-2.4,-.2,2,4.2]):
  at=[t,F,7.77] if side=='south' else [7.77,F,t]
  asset(f'edge_planter_{side}_{i}',STREET+'planter_long.glb',at,0 if side=='south' else 90,
   group='NearEdges',material='preserve',scale=[1,.42,1])
 for i,t in enumerate([-7.8,-5.7,-3.5,-1.3,.9,3.1,5.4]):
  at=[t,F,7.76] if side=='south' else [7.76,F,t]
  asset(f'bollard_{side}_{i}',STREET+'bollard.glb',at,group='NearEdges',material='preserve')
for i,at in enumerate([[5.6,F,8],[8,F,5.6]]):
 asset(f'gate_post_{i}','mp_gate_post.glb',at,colliders=[box('GatePier',[.46,1.38,.46],[0,.69,0])],group='NearEdges')
for i,at in enumerate([[4.8,F,7.65],[7.65,F,4.8]]):
 asset(f'entry_low_flowerpot_{i}',STREET+'planter_square.glb',at,group='NearEdges',material='preserve',scale=[.7,.4,.7])
for i,(x,z) in enumerate([(-7.8,-7.8),(-7.8,7.8),(7.8,-7.8)]):
 asset(f'corner_tree_{i}','mp_tree_pot.glb',[x,F,z],i*37,
  [{'name':'TreePot','shape':'cylinder','radius':.52,'height':.75,'at':[0,.375,0]}],group='Garden',occluder=True)
 # Visible support continues under the rim outside the walkable 16 m floor.
 asset(f'corner_tree_pad_{i}','mp_edge_trim.glb',[x,.01,z],group='Ground',scale=[.65,.25,8.1])
lamp_points=[(-7.3,-4.5),(-7.3,2.5),(-4.5,-7.3),(2.5,-7.3)]
for i,(x,z) in enumerate(lamp_points):
 asset(f'lamp_{i}',STREET+'lamp_single.glb',[x,F,z],group='LightingDecor',material='preserve',
  colliders=[{'name':'LampPost','shape':'cylinder','radius':.11,'height':2.9,'at':[0,1.45,0]}])

# Segmented catenaries between lamps. No interactable anchors on decoration.
def string_run(prefix,file,a,b,height):
 dx,dz=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dz);count=max(1,round(length/2))
 yaw=math.degrees(math.atan2(-dz,dx))
 for i in range(count):
  t=(i+.5)/count
  asset(f'{prefix}_{i}',file,[a[0]+dx*t,F+height-.12*math.sin(t*math.pi),a[1]+dz*t],yaw,
   group='LightingDecor',scale=[length/count/2,1,1],cast_shadow=False)
for i,(a,b) in enumerate([(lamp_points[0],lamp_points[1]),(lamp_points[2],lamp_points[3])]):
 string_run(f'string_light_{i}','mp_string_lights.glb',a,b,3.08)
string_run('cross_string','mp_string_lights.glb',(-7.3,2.5),(2.5,-7.3),3.3)
string_run('market_bunting','mp_bunting.glb',(-7.3,2.5),(2.5,-7.3),2.93)

stall_positions=[('stall_fish',-6.6,4.5),('stall_bread',-6.6,.5),('stall_spice',-6.6,-3.5),('stall_vegetable',-3.5,-6.6),('stall_tools',.5,-6.6),('stall_flower_cart',4.5,-6.6)]
for name,x,z in stall_positions:
 model={'stall_bread':'stall_bakery','stall_vegetable':'stall_veg','stall_flower_cart':'flower_cart'}.get(name,name)
 depth=1.4 if model=='flower_cart' else 1.6
 asset(name,model+'.glb',[x,F,z],45,[box('StallReserved',[2,1.45,depth],[0,.725,0]),
  box('RearServiceGapBoundary',[2.0,3.0,2.4],[0,1.5,-2.0])],
  fallback_file='mp_stall_placeholder.glb',dependency_pr=877,pending_owner='黄忠 #877',footprint_m=[2,depth],occluder=True,material='preserve')
asset('stall_keeper','stall_keeper.glb',[2.2,F,2.2],45,
 [box('KeeperStallReserved',[3.2,1.45,1.6],[0,.725,0])],fallback_file='mp_keeper_placeholder.glb',dependency_pr=877,pending_owner='黄忠 #877',footprint_m=[3.2,1.6],anchor_module=True,occluder=True,material='preserve')
asset('market_board','market_board.glb',[1.1,F,4.2],45,[box('Board',[1.2,1.8,.3],[0,.9,0])],fallback_file='mp_board_placeholder.glb',dependency_pr=877,pending_owner='黄忠 #877',anchor_module=True,material='preserve')
asset('fountain','fountain.glb',[-.8,F,-.8],colliders=[{'name':'FountainBasin','shape':'cylinder','radius':1.5,'height':2.03,'at':[0,1.015,0]}],fallback_file='mp_fountain_placeholder.glb',dependency_pr=877,pending_owner='黄忠 #877',material='preserve')
asset('keeper_rear_flowerbed','mp_keeper_flowerbed.glb',[1.156/math.sqrt(2),F,1.156/math.sqrt(2)],45,
 [box('VisibleGardenBed',[3.4,.445,2.312],[0,.2225,0])],group='Garden',height_m=.445,
 purpose='approved low flowerbed closes keeper rear strip; circulation goes around other fountain sides')
asset('floor_fig_crate','res://assets/rooms/fruit_shop/floor_fig_crate.glb',[4.2,F,1.1],45,
 [box('SpecialtyCrate',[.9,.54,.7],[0,.27,0])],material='fruit',anchor_module=True)

anchors=[]
def anchor(name,at,yaw=None,module=None,**extra):
 a={'name':name,'position':at}
 if yaw is not None:a['yaw_degrees']=yaw
 if module:a['module']=module
 a.update(extra);anchors.append(a)
anchor('use_counter',[2.6,1.05,2.6],module='stall_keeper')
anchor('stand_counter',[3.25,F,3.25],45)
anchor('npc_keeper',[1.75,F,1.75],225)
anchor('badge_keeper',[1.75,2.5,1.75])
anchor('stand_keeper',[3.25,F,3.25],45)
anchor('use_market_board',[1.1,1.8,4.2],module='market_board')
anchor('stand_market_board',[1.6,F,4.7],45)
anchor('use_specialty_shelf',[4.2,.7,1.1],module='floor_fig_crate')
anchor('stand_specialty_shelf',[4.7,F,1.6],45)
for who,npc,stand in [('nadia',[-1.2,F,1.6],[-.7,F,2.1]),('theo',[1.5,F,-4.4],[2,F,-3.9]),('tomo',[-1.2,F,1.6],[-.7,F,2.1])]:
 anchor('npc_'+who,npc,225);anchor('stand_'+who,stand,45)
anchor('spawn',[5.8,F,5.8],45)
anchor('exit',[7.2,F,7.2],225)
anchor('badge_exit',[5.6,1.1,8],label='Map',icon='i-door')
for i,(x,z) in enumerate([(-3.6,1),(1,-3.6)],1):
 dx,dz=-.8-x,-.8-z;length=math.hypot(dx,dz);dx/=length;dz/=length
 yaw=math.degrees(math.atan2(dx,dz))
 name=f'bench_{i}'
 asset(name,STREET+'bench_wood.glb',[x,F,z],yaw,[box('Bench',[1.8,1.28,.672],[0,.64,0])],material='preserve',anchor_module=True)
 anchor(f'seat_{i}',[x,F+.718,z],(yaw+180)%360,name,approach=[round(x+dx*.8,4),F,round(z+dz*.8,4)])

# Entire city strip is the replacement unit; far cards retain their shared
# shader/material, positive scale and extra_cull_margin from the import script.
city_backdrop={'scene':'res://scenes/market_plaza/market_city_backdrop.tscn','default_variant':'san_francisco','variants':['san_francisco','generic'],'source':'SGODOT-434','screen_anchor_below_hud':True}

boundaries=[box('NorthBoundary',[16.1,3,.12],[0,1.55,-8]),box('WestBoundary',[.12,3,16.1],[-8,1.55,0]),
 box('SouthBoundary',[13.6,3,.12],[-1.2,1.55,8]),box('EastBoundary',[.12,3,13.6],[8,1.55,-1.2]),
 # Invisible terminal at the diagonal corner, beyond the exit trigger.
 box('EntryEndBoundary',[3.4,3,.12],[7.95,1.55,7.95])]
boundaries[-1]['rotation_degrees']=[0,45,0]
pitch=math.radians(33);d=28;h=d*math.cos(pitch)/math.sqrt(2)
camera={'position':[h,1.4+d*math.sin(pitch),h],'target':[0,1.4,0],'size':6.72,'near':.1,'far':110,'yaw_degrees':45,'pitch_degrees':33}
route=[{'name':'spawn','position':[5.8,F,5.8],'capture':'opening'},
 {'name':'keeper','position':[3.25,F,3.25]}, {'name':'board','position':[1.6,F,4.7]},
 {'name':'ring_west','position':[-3.8,F,-.8],'capture':'ring'}, {'name':'far_west','position':[-5,F,-3.2]},
 {'name':'far_north','position':[-3.2,F,-5]}, {'name':'north_east','position':[4.7,F,-4.8]},
 {'name':'east_side','position':[5.2,F,2.6]}, {'name':'exit','position':[7.2,F,7.2]}]
layout={'units':'metres','axes':'Godot Y-up; +Z front; camera from +X+Z; object meshes face +Z; P0 facing anchors use -Z',
 'reference':{'card':'SGODOT-218','revision':'v2.1 + a2-a9: 33 degrees, scheme C, counter names, three trees, service-gap exclusions','source':'~/incoming/market-45-1108/SGODOT-218_market_room45_v2.1.png'},
 'assets':assets,'instances':[],'camera':camera,'camera_contract':{'yaw_degrees':45,'pitch_degrees':33,'width_m':6.72,'pitch_status':'user approved 33 degrees, 2026-11-08'},'city_backdrop':city_backdrop,
 'review_lighting':{'background':'DDE8E7','ambient_color':'FFF0DC','ambient':.70,'sun_color':'FFF1D8','sun':1.0,'sun_position':[-6,9,3],'sun_target':[0,0,0],'points':[]},
 'sun_direction':[-6,9,3],'anchors':anchors,'spawn':[5.8,F,5.8],'floor_y':F,'footprint_m':[16,16],'boundaries':boundaries,'local_lights':[],
 'preflight':{'routes':[{'name':'entry_to_keeper','points_xz':[[7.2,7.2],[5.8,5.8],[3.25,3.25]]},
 {'name':'entry_to_fountain_left','points_xz':[[5.8,5.8],[1.6,4.7],[-1.8,3.0],[-3.4,-.8],[-.8,-3.4]]},
 {'name':'entry_to_fountain_right','points_xz':[[5.8,5.8],[4.7,1.6],[3.0,-1.8],[-.8,-3.4]]}],
 'main_routes':[{'name':'entry_to_keeper','points_xz':[[7.2,7.2],[5.8,5.8],[3.25,3.25]]}],
 'standing_positions_xz':[[3.25,3.25],[1.6,4.7],[4.7,1.6],[-.7,2.1],[2,-3.9]],'ring':{'center':[-.8,-.8],'basin_radius_m':1.5,'nominal_outer_radius_m':4.5,'keeper_rear_strip':'closed by visible low flowerbed per a8/a9; left and right approaches stay open'}},
 'bench':{'floor_y':F,'route':route,'blocked':[{'name':'fountain','from':[1.2,F,-.8],'to':[-.8,F,-.8],'target':'FountainBasin'}],'entrance':{'inside':[5.8,F,5.8],'outside':[7.2,F,7.2]},'gaps':[]},
 'navigation':{'source':'P0RoomNav.build(P0RoomNav.shapes_from(art))','cell_m':.15,'actor_radius_m':.21,'runtime_rebuilt':True,'snapshot':'navigation_snapshot.json'},
 'integration':{'outpost_id':'sh_market_1','art':'market_plaza','bounds':[-8,8,-8,8],'anchors_override':'must clear old market.anchors.json override or replace with this anchors list','seats':['seat_1','seat_2'],'server_room_bounds':'must update to match; program-owned'},
 'facade_variants':{'default':'san_francisco','bone_contract':'same4m bays/door/window/steps/flowerboxes/collision placement; wall6m+roof0.5m; depth2.5m',
  'san_francisco':{'files':[f'facade_sf_{i}.glb' for i in range(8)],'style':'pastel Victorian row houses','due':'2026-11-11 18:00'},
  'generic':{'files':[f'facade_generic_{i}.glb' for i in range(4)],'style':'shared bone, neutral palette and simplified trim','due':'2026-11-12 18:00'}},
 'pending':{'huangzhong_props':'#877 finished kit 288b47b94f966981603b3d132552d6b16f923303 technically accepted; assembled visual acceptance pending; integrate dependency before this scene ships'},
 'author':'马可波罗','virtual_user_id':'5a7c76bc-19d2-47e1-9406-4f4e0feeefb4'}
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2)+'\n')
print('MARKET_LAYOUT',len(assets),'assets;',len(anchors),'anchors; seats',layout['integration']['seats'])
