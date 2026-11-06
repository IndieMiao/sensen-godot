"""Editable proposal furnishings and planting; all generated files stay in output/.

Run Blender under ~/gs66-render.lock. These are named editable mockups,
not production resources or new walkable geometry.
"""
from pathlib import Path
import json, math, sys
import bpy
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sys.path.insert(0,str(ROOT/'tools/art'))
from landmark_kit import Kit, reset_scene
OUT=ROOT/'output/alcatraz-v10-433/v2/prototypes'
reset_scene()
kit=Kit(OUT,{'stone':'CBB48F','cream':'F0E1C2','rock':'AD9D86','rock_light':'C0B099',
             'bronze':'526B68','water':'66B8C7','water_light':'B9E2E2',
             'ice':'6F8E62','ice_light':'99AE78','pink':'CA74A3','pink_light':'E0A0BD','pollen':'E5C476'})
kit.begin('v10_demo_deck_connector',ao=False)
kit.box('Cantilever joining strip',(0,.06,0),(.6,.12,2),'cream',.012)
kit.begin('v10_demo_ice_cushion',ao=False)
kit.ellipsoid('Thick succulent cushion',(0,.13,0),(.72,.26,.48),'ice',seg=10,rings=5)
for i,(x,z) in enumerate([(-.22,-.10),(.03,-.12),(.23,-.03),(-.14,.10),(.12,.12)]):
 kit.ellipsoid('Succulent leaf pad %d'%i,(x,.21,z),(.30,.17,.24),'ice_light',seg=8,rings=4)
 for j in range(7):
  a=j*math.tau/7
  kit.ellipsoid('Pink petal %d %d'%(i,j),(x+math.sin(a)*.075,.30,z+math.cos(a)*.075),(.10,.035,.10),
                'pink_light' if (i+j)%3==0 else 'pink',seg=5,rings=3)
 kit.cylinder('Flower centre %d'%i,(x,.322,z),.027,.018,'pollen',seg=7)
kit.begin('v10_demo_bird_rock',ao=False)
kit.slab('Low natural rock shelf',[(-1,-.35),(-.7,-.55),(.65,-.5),(1,-.15),(.85,.45),(-.6,.5)],0,.18,'rock',bevel=.025)
kit.cylinder('West flat bird perch',(-.45,.27,-.05),.38,.20,'rock_light',seg=7,smooth=False)
kit.cylinder('East flat bird perch',(.45,.225,.12),.33,.11,'rock_light',seg=7,smooth=False)
kit.begin('v10_demo_anchor',ao=False)
base=kit.cylinder('Small maritime exhibit footing',(0,.06,0),.44,.12,'stone',seg=8,smooth=False)
base.scale.y=.7
kit.beam('Anchor shaft',(0,.30,0),(0,.76,0),.065,'bronze')
kit.beam('Anchor stock',(-.27,.65,0),(.27,.65,0),.055,'bronze')
for side in [-1,1]:
 for j,(a,b) in enumerate([((0,.34,0),(side*.18,.25,0)),((side*.18,.25,0),(side*.36,.39,0))]):
  kit.beam('Curved anchor arm %s %s'%(side,j),a,b,.065,'bronze')
 points=[(side*.27,.36,-.035),(side*.43,.51,-.035),(side*.43,.33,-.035),
         (side*.27,.36,.035),(side*.43,.51,.035),(side*.43,.33,.035)]
 faces=[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)]
 if side<0:faces=[tuple(reversed(face)) for face in faces]
 kit.mesh('Broad anchor fluke %s'%side,points,faces,'bronze')
for j in range(12):
 a=j*math.tau/12;b=(j+1)*math.tau/12
 kit.beam('Anchor top ring %02d'%j,(math.cos(a)*.085,.79+math.sin(a)*.085,0),
          (math.cos(b)*.085,.79+math.sin(b)*.085,0),.024,'bronze')
kit.begin('v10_demo_sundial',ao=False)
kit.cylinder('Octagonal stone footing',(0,.06,0),.43,.12,'stone',seg=8,smooth=False)
kit.cylinder('Limestone pedestal',(0,.34,0),.19,.50,'cream',top=.25,seg=8,smooth=False)
kit.cylinder('Round stone dial rim',(0,.63,0),.44,.10,'cream',seg=24)
kit.cylinder('Bronze face without lettering',(0,.687,0),.39,.014,'bronze',seg=24)
for i in range(12):
 a=i*math.tau/12
 kit.box('Unlettered hour notch %02d'%i,(math.sin(a)*.32,.700,math.cos(a)*.32),(.025,.009,.07),'cream',0,rot_y=a)
v=[(x,y,z) for x in [-.025,.025] for y,z in [(.71,.19),(.71,-.20),(1.02,-.20)]]
kit.mesh('Triangular gnomon',v,[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)],'bronze')
kit.begin('v10_demo_fountain',ao=False)
kit.cylinder('Octagonal ground plinth',(0,.055,0),.58,.11,'stone',seg=8,smooth=False)
kit.lathe('Open lower stone bowl',[(.36,.11),(.55,.16),(.57,.32),(.48,.34),(.44,.23),(0,.23)],'cream',seg=20)
kit.cylinder('Quiet blue lower water',(0,.24,0),.445,.008,'water',seg=24)
kit.cylinder('Short central stem',(0,.45,0),.09,.42,'stone',seg=12)
kit.lathe('Small upper bowl',[(.10,.58),(.26,.63),(.28,.72),(.22,.74),(0,.67)],'cream',seg=16)
kit.cylinder('Quiet blue upper water',(0,.687,0),.225,.008,'water',seg=20)
kit.ellipsoid('Small stone finial',(0,.82,0),(.13,.18,.13),'stone',seg=8,rings=4)
for i in range(3):
 a=i*math.tau/3
 points=[(math.sin(a)*r,y,math.cos(a)*r) for r,y in [(.24,.72),(.29,.62),(.34,.42),(.36,.26)]]
 for j in range(len(points)-1):kit.beam('Static water ribbon %d %d'%(i,j),points[j],points[j+1],.018,'water_light')
report={name:kit.export(name) for name in kit.assets}
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'proposal_props.blend'))
(OUT/'manifest.json').write_text(json.dumps({'scope':'Proposal mockups only; no text, collision or gameplay',
    'assets':report,'bird_landings':[[-.45,.37,-.05],[.45,.28,.12]]},indent=2)+'\n')
print('PROPOSAL_PROPS',json.dumps(report))
