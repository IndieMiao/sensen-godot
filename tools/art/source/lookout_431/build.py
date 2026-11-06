"""SGODOT-431 lookout extension. All Blender runs require the shared flock.
Reuses street-kit modelling/export helpers; only new GLBs/blends and catalogue.
"""
from pathlib import Path
import math,json,importlib.util,sys
import bpy,bmesh
from mathutils import Vector

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
KIT=ROOT/'assets/landmarks/_shared/street_kit'
spec=importlib.util.spec_from_file_location('street',SRC.parent/'street_kit_429/build.py')
s=importlib.util.module_from_spec(spec);spec.loader.exec_module(s)
s.SRC=SRC;s.PAL=dict(s.PAL)
for role in ['wood','wood_light','wood_dark']:s.PAL[role]=s.PAL['furniture_'+role]
p=s.p;box=s.box;rod=s.rod;lathe=s.lathe;mesh=s.mesh

def axial(name,profile,role,n,at,axis=(0,0,-1),wide=1):
 o=lathe(name,profile,role,n);o.rotation_mode='QUATERNION'
 o.rotation_quaternion=Vector((0,0,1)).rotation_difference(p.v(axis).normalized())
 o.location=p.v(at);o.scale.x=wide;return o

def top_poly(name,outline,y,role):
 area=sum(a[0]*b[1]-a[1]*b[0] for a,b in zip(outline,outline[1:]+outline[:1]))
 order=tuple(reversed(range(len(outline)))) if area>0 else tuple(range(len(outline)))
 o=mesh(name,[(x,y,z) for x,z in outline],[order],role)
 # A disconnected floor graphic has no enclosed volume: set its exterior +Y.
 bm=bmesh.new();bm.from_mesh(o.data)
 for f in bm.faces:
  if f.normal.z<0:f.normal_flip()
 bm.to_mesh(o.data);bm.free();o.data.update();return o

def telescope():
 lathe('Heavy but compact pedestal base',[(0,.20),(.055,.22),(.11,.17),(.18,.12),(1.08,.085)],'metal',10)
 lathe('Pedestal warm stone collar',[(.10,.175),(.16,.15)],'cream',10)
 box('Head pivot transverse support',(0,1.10,0),(.39,.10,.14),'metal',.018)
 for x in [-.20,.20]:box('U-shaped telescope cradle',(x,1.25,0),(.075,.30,.13),'metal',.012)
 axis=(0,.14,-1)
 axial('Rounded broad viewer head',[(-.22,.145),(-.18,.175),(.20,.175),(.27,.14)],'teal',12,(0,1.43,0),axis,1.55)
 axial('Front cream lens surround',[(0,.145),(.045,.145)],'cream',12,(0,1.468,-.272),axis,1.55)
 axial('Quiet dark front optic',[(0,.118),(.007,.118)],'teal_light',12,(0,1.475,-.320),axis,1.55)
 for x in [-.095,.095]:
  axial('Two rear eyepieces',[(0,.058),(.08,.048)],'metal',8,(x,1.40,.21),(0,0,1))
  axial('Dark recessed eyepiece',[(0,.035),(.004,.035)],'drain',8,(x,1.40,.293),(0,0,1))
 axial('Side pivot knob',[(0,.06),(.055,.06)],'wood_light',8,(.23,1.34,0),(1,0,0))
 box('Narrow vertical coin box',(0,.89,.125),(.14,.32,.08),'metal',.014)
 box('Single horizontal coin slot',(0,.92,.168),(.10,.018,.006),'drain')
 return {'view_direction':'-Z, slightly up','eye_height_m':1.40,'content':'Vertical coin box matching pedestal; single horizontal slot, no dots/arrows/letters','coin_box_dimensions_m':[.14,.32,.08],'coin_box_center_m':[0,.89,.125],'coin_box_srgb':'5D4C38','coin_slot_dimensions_m':[.10,.018,.006],'placement_cell_m':[2,2]}

def lookout_railing():
 rod('Cast iron round handrail',(-1,.93,0),(1,.93,0),.032,'metal',6)
 rod('Dark lower railing',(-1,.23,0),(1,.23,0),.032,'metal',6)
 for x in [-.75,-.375,0,.375,.75]:rod('Open vertical bar',(x,.23,0),(x,.93,0),.024,'metal',6)
 for x in [-.75,.75]:rod('Short anchored foot',(x,0,0),(x,.23,0),.024,'metal',6)
 return {'grid_m':2,'connectors':{'left':[-1,0,0],'right':[1,0,0]},'rail_centres_y_m':[.23,.93],'rail_radius_m':.032,'rail_srgb':'5D4C38','endpost':'Use existing railing_endpost; one per shared seam'}

def semi_deck():
 n=12;arc=[(math.cos(i*math.pi/n),-math.sin(i*math.pi/n)) for i in range(n+1)]
 verts=[(x,y,z) for y in [0,.12] for x,z in arc];count=len(arc)
 faces=[tuple(reversed(range(count))),tuple(range(count,2*count))]
 faces += [(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
 mesh('Semicircular limestone deck',verts,faces,['stone_shade','stone_light']+['stone']*count)
 # Match the existing street railing's radius/colour, with standard endposts
 # covering the final5cm from the curve centreline to the2m chord endpoints.
 for y,label in [(1.05,'handrail'),(.35,'lower rail')]:
  # A fixed vertical/radial frame keeps the horizontal half-circle untwisted.
  pts=[((.95+.032*math.cos(j*math.tau/6))*x,y+.032*math.sin(j*math.tau/6),(.95+.032*math.cos(j*math.tau/6))*z) for x,z in arc for j in range(6)]
  fs=[(i*6+j,i*6+(j+1)%6,(i+1)*6+(j+1)%6,(i+1)*6+j) for i in range(n) for j in range(6)]
  fs += [tuple(reversed(range(6))),tuple(range(n*6,(n+1)*6))]
  mesh('Curved cast iron '+label,pts,fs,'metal',True)
 for i in range(1,8):
  a=i*math.pi/8;x=.95*math.cos(a);z=-.95*math.sin(a)
  rod('Curved-deck railing baluster',(x,.35,z),(x,1.05,z),.024,'metal',5)
 return {'grid_m':2,'chord_width_m':2,'outward_extent_m':1,'outward':'-Z','deck_top_y_m':.12,
  'pivot':'chord midpoint at underside; floor undersideY0',
  'connectors':{'left':[-1,.12,0],'right':[1,.12,0]},'rail_centres_y_m':[.35,1.05],'rail_radius_m':.032,'rail_srgb':'5D4C38',
  'endpost':'Existing railing_endpost at both connector points covers5cm rail-centre offset','collisions':'None; scene owner supplies deck/navigation/collision at integration'}

def compass_disc():
 lathe('Flat cream orientation disc',[(0,.77),(.004,.80),(.009,.80),(.012,.77)],'cream',32)
 # Broad quiet sectors; map cues are drawn as solid planar coloured geometry.
 for quadrant in range(4):
  angles=[(quadrant+i/8)*math.pi/2 for i in range(9)]
  outline=[(0,0)]+[(.71*math.cos(a),.71*math.sin(a)) for a in angles]
  top_poly('Warm stone quarter',outline,.0125,'stone_light' if quadrant%2==0 else 'stone')
 arrow=[(-.045,-.10),(.045,-.10),(.045,-.26),(.12,-.26),(0,-.49),(-.12,-.26),(-.045,-.26)]
 for i in range(4):
  a=i*math.pi/2;outline=[(x*math.cos(a)-z*math.sin(a),x*math.sin(a)+z*math.cos(a)) for x,z in arrow]
  top_poly('Direction arrow without letters',outline,.013,'teal' if i==0 else 'wood_dark')
 def icon(poly,cx,cz,role):top_poly('No-text coastal pictogram',[(x+cx,z+cz) for x,z in poly],.014,role)
 # Small passenger boat, left lower quadrant.
 cx,cz=-.34,.33
 icon([(-.16,-.01),(.16,-.01),(.11,.055),(-.10,.055)],cx,cz,'teal')
 icon([(-.09,-.09),(.09,-.09),(.09,-.02),(-.09,-.02)],cx,cz,'teal')
 icon([(-.02,-.14),(.03,-.14),(.03,-.09),(-.02,-.09)],cx,cz,'wood_dark')
 # Small lighthouse, right lower quadrant; cream lantern cutout stays readable.
 cx,cz=.34,.42
 icon([(-.075,.10),(.075,.10),(.045,-.12),(-.045,-.12)],cx,cz,'teal')
 icon([(-.08,-.12),(.08,-.12),(.08,-.20),(-.08,-.20)],cx,cz,'teal')
 icon([(-.10,-.20),(0,-.27),(.10,-.20)],cx,cz,'wood_dark')
 top_poly('Lighthouse lantern light',[(cx-.045,cz-.14),(cx+.045,cz-.14),(cx+.045,cz-.18),(cx-.045,cz-.18)],.0145,'cream')
 return {'diameter_m':1.6,'height_m':.0145,'content':'Four arrows, passenger boat and lighthouse only; no lettering','placement_cell_m':[2,2]}

def sheltered_bench():
 for x in [-.82,.82]:
  for z in [-.45,.45]:box('Pergola timber post',(x,1.16,z),(.12,2.32,.12),'wood_dark',.018)
 for z in [-.45,.45]:box('Pergola long upper beam',(0,2.32,z),(2,.16,.14),'wood',.025)
 for j in range(7):box('Separated shade slat',((j-3)*.29,2.43,0),(.20,.06,1.4),'wood_light' if j%2 else 'wood')
 for x in [-.82,.82]:
  for z in [-.45,.45]:rod('Short diagonal knee brace',(x,2.03,z),(x*.65,2.27,z),.035,'wood_dark',4)
 for x in [-.56,.56]:box('Warm stone bench trestle',(x,.31,0),(.20,.62,.43),'stone',.028)
 for j in range(3):box('Muted wood bench seat board',(0,.6825,(j-1)*.17),(1.58,.065,.16),'wood_light' if j==1 else 'wood',.012)
 for x in [-.65,.65]:rod('Bench back support',(x,.64,-.22),(x,1.19,-.27),.026,'metal',4)
 for j in range(2):box('Muted wood back board',(0,.94+j*.17,-.26),(1.58,.13,.06),'wood' if j==0 else 'wood_light',.012)
 return {'grid_m':2,'placement_cell_m':[2,2],'seat_height_m':.715,'seat_width_m':1.58,'front':'+Z','content':'One bench and open slatted shade frame; decorative, no seat anchors'}

BUILDERS=[('lookout_telescope',telescope),('lookout_railing_2m',lookout_railing),('lookout_semicircle_2m',semi_deck),('lookout_compass_disc',compass_disc),('lookout_sheltered_bench',sheltered_bench)]

def main():
 m=json.loads((KIT/'kit_manifest.json').read_text());only=sys.argv[sys.argv.index('--only')+1] if '--only' in sys.argv else None
 for name,builder in BUILDERS:
  if only and name!=only:continue
  row=s.export(name,builder);row['source']=str((SRC/(name+'.blend')).relative_to(ROOT));row['task']='SGODOT-431';m['assets'][name]=row
  folder=SRC/'modules'/name;folder.mkdir(parents=True,exist_ok=True)
  (folder/'reuse_provenance.json').write_text(json.dumps({'author':'黄忠','virtual_user_id':m['virtual_user_id'],'task':'SGODOT-431','module':name,'geometry':'New geometry; existing street-kit assets unchanged','palette':'street_kit v1.2, muted #830 wood, Alcatraz cream/teal/metal','source':row['source'],'generator':'tools/art/source/lookout_431/build.py'},ensure_ascii=False,indent=2)+'\n')
 m['extension_tasks']={'SGODOT-431':{'revision':'v1.1','assets':[n for n,b in BUILDERS],'scope':'Lookout kit only; no Alcatraz integration/layout'}}
 m['unique_triangles']=sum(x['triangles'] for x in m['assets'].values());m['unique_surfaces']=len(m['assets'])
 (KIT/'kit_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__':main()
