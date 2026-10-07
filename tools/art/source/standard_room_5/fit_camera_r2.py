"""Orthographic fit to declared visible plinth-corner intersections; no image warp."""
from pathlib import Path
import json,math
ROOT=Path(__file__).resolve().parents[4]
# Coordinates on the full reference resized proportionally to 1440x1080.
# These are rounded-plinth edge intersections, not the protruding wall caps.
left=(198.,683.);front=(737.,945.);right=(1240.,699.)
dx=(front[0]-left[0],front[1]-left[1]);dz=(front[0]-right[0],front[1]-right[1])
pitch=math.asin(math.sqrt((dx[1]/dx[0])*(dz[1]/-dz[0])))
yaw=math.atan2(-dz[0],dx[0]);width=6.6
pixel_scale=dx[0]/(width*math.cos(yaw));span=1440/pixel_scale
origin=((left[0]+right[0])/2,(left[1]+right[1])/2)
focus_y=(origin[1]-540)/(math.cos(pitch)*pixel_scale)-.15
distance=15.0
camera={'position':[distance*math.sin(yaw),focus_y+distance*math.tan(pitch),distance*math.cos(yaw)],'target':[0,focus_y,0],'size':span}
result={'method':'Three visible rounded plinth edge intersections; rectangular ground-plane constraint. No image warp.',
        'reference_canvas':[1440,1080],'reference_source_size':[3402,2561],
        'anchors':{'left':left,'front':front,'right':right,'back_inferred':[left[0]+right[0]-front[0],left[1]+right[1]-front[1]]},
        'back_corner_visibility':'Occluded by room; inferred by parallelogram, not measured from visible pixels.',
        'pitch_degrees':math.degrees(pitch),'yaw_degrees':math.degrees(yaw),'camera':camera,
        'limits':'Hand-selected intersections on a stylized perspective reference. Wall caps and furniture are independent visual checks, not claimed pixel-perfect.'}
path=Path(__file__).with_name('camera-r2.json');path.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
