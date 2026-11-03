"""N3 white plan: R3 SVG measurements plus the approved 323 proposal."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];KIT=ROOT/"assets/rooms/poi_culture_hall"
FLOOR=.08
def main():
    svg=ET.parse(HERE/"reference/SGODOT-318_R3_topdown.svg").getroot()
    rectangles=[e for e in svg if e.tag.endswith("rect")]
    circles=[e for e in svg if e.tag.endswith("circle")]
    def rectangle(element):
        x,y,w,d=[float(element.get(k)) for k in ["x","y","width","height"]]
        return [(x+w/2-80)/120-3.2,(y+d/2-175)/120-3.0],[w/120,d/120]
    def circle(element):
        return [(float(element.get("cx"))-80)/120-3.2,(float(element.get("cy"))-175)/120-3.0],2*float(element.get("r"))/120
    placements=[]
    def put(name,model,at,size,role,collision=False,owner="zhaoyun",**extra):
        row=dict(name=name,model=model,position=at,size=size,yaw_degrees=0,role=role,collidable=collision,owner=owner,**extra)
        placements.append(row);return row
    cases=[]
    for i,element in enumerate([r for r in rectangles if r.get("fill")=="#d6cbbb"],1):
        (x,z),(w,d)=rectangle(element)
        if i==2:z+=.20
        case=put("glass_case_%d"%i,"blockout_case",[x,FLOOR,z],[w,1.46,d],"display case envelope",True,"huangzhong",support_height=1.04)
        cases.append(case)
        for j,dz in enumerate([-.54,0,.54]):
            model=["blockout_ball","blockout_vase","blockout_fossil"][(i+j)%3]
            size=[.29,.26,.29] if model!="blockout_fossil" else [.30,.30,.14]
            put("case_%d_exhibit_%d"%(i,j+1),model,[x,FLOOR+1.04,z+dz],size,"replaceable exhibit envelope",False,"huangzhong",support=case["name"])
    bench_element=next(r for r in rectangles if r.get("fill")=="#9aac8d")
    (bx,bz),(bw,bd)=rectangle(bench_element)
    put("bench","blockout_bench",[bx,FLOOR,bz],[bw,.715,bd],"one bench with three seats",True)
    (sx,sz),_=circle(next(c for c in circles if c.get("fill")=="#d6bd90"))
    put("stool","blockout_stool",[sx,FLOOR,sz],[.48,.715,.48],"one round stool",True,shape="circle")
    (px,pz),diameter=circle(next(c for c in circles if c.get("fill")=="#a4b18d"))
    put("plant_pot","blockout_cylinder",[px,FLOOR,pz],[diameter,.43,diameter],"shared plant pot envelope",True,shape="circle")
    put("plant_canopy","blockout_ball",[px,FLOOR+.43,pz],[.68,.75,.60],"shared foliage envelope")
    (mx,mz),diameter=circle(next(c for c in circles if c.get("fill")=="#e9d4b0"))
    put("floor_mosaic","blockout_mosaic",[mx,FLOOR+.0005,mz],[diameter,.002,diameter],"flush decorative mosaic",False,"huangzhong",shape="circle")
    # Proposal plinth: .70 m square, .708 m in front of case 2. No rear plinth.
    put("display_plinth","blockout_box",[2.30,FLOOR,1.97],[.70,1.15,.70],"front-right display plinth",True,"huangzhong",support_height=1.15)
    put("plinth_exhibit","blockout_fossil",[2.30,FLOOR+1.15,1.97],[.46,.48,.17],"single upright fossil envelope",False,"huangzhong",support="display_plinth")
    (ax,_),(aw,_)=rectangle(next(r for r in rectangles if r.get("fill")=="#cfb69b"))
    columns=[ax-.85,ax,ax+.85]
    for row,y in enumerate([1.30,2.18]):
        for col,x in enumerate(columns):
            put("artwork_%d"%(row*3+col+1),"blockout_frame",[x,y,-2.95],[.75,.78,.06],"abstract artwork envelope",False,"huangzhong")
    (nx,_),_=rectangle(next(r for r in rectangles if r.get("fill")=="#faf2de"))
    put("name_sign","blockout_box",[nx,3.08,-2.95],[1.45,.30,.05],"blank runtime sign envelope",False,"huangzhong")
    put("spot_track","blockout_box",[ax,3.49,-2.57],[2.80,.06,.06],"one continuous ceiling track")
    lights=[]
    for i,x in enumerate(columns,1):
        at=[x,3.40,-2.57];target=[x,2.10,-2.95]
        put("spot_head_%d"%i,"blockout_box",at,[.14,.12,.22],"track spotlight envelope",target=target)
        lights.append(dict(name="art_spot_%d"%i,position=at,target=target,color="FFE5BB",energy=2.4,range=3.0,angle=48))
    for i,z in enumerate([-.55,.55],1):
        put("wall_sconce_%d"%i,"blockout_ball",[-3.02,2.10,z],[.20,.30,.23],"shared wall light envelope")
    seats=[]
    for i,c in enumerate([c for c in circles if c.get("r")=="17"][:3],1):
        (x,z),_=circle(c)
        seats.append(dict(name="seat_bench_%d"%i,position=[x,FLOOR+.715,z],yaw_degrees=-90,module="bench",stand=[-1.96,FLOOR,z]))
    seats.append(dict(name="seat_stool_1",position=[sx,FLOOR+.715,sz],yaw_degrees=-90,module="stool",stand=[-1.96,FLOOR,sz]))
    spawn=[.20,FLOOR,2.75];exit_=[.20,FLOOR,2.86]
    anchors=[dict(name="spawn",position=spawn,yaw_degrees=180,module="hall_floor"),
        dict(name="exit",position=exit_,yaw_degrees=180,module="hall_floor"),
        dict(name="badge_exit",position=[.20,.55,3.0],yaw_degrees=0,module="hall_floor"),
        dict(name="cam_default",position=spawn,yaw_degrees=45,module="hall_floor",pitch_degrees=43,orthographic_width=6.72),
        dict(name="sign_door",position=[nx,3.23,-2.918],yaw_degrees=0,module="name_sign",size=[1.30,.22])]+seats
    anchors += [dict(name=s["name"].replace("seat_","stand_"),position=s["stand"],yaw_degrees=-90,module="hall_floor") for s in seats]
    hall=json.loads((ROOT/"assets/rooms/_shared/shell_hall/layout.json").read_text())
    plan=dict(task="SGODOT-323",design="SGODOT-318 R3 plus approved proposal 1f4f9753 / 55522cef",stage="white_blockout",
        units="metres",floor_y=FLOOR,footprint=[6.8,6.4],wall_height=3.7,inner_floor=[-3.18,-2.98,3.34,3.14],
        reference_transform=dict(svg_origin_px=[80,175],pixels_per_metre=120,runtime_inner_wall_origin_xz=[-3.2,-3.0],
            note="Place proposal's rear-left datum on inner wall planes; the SVG is schematic, not a survey."),
        rear_clear_band=[-3.18,-2.89,3.34,-.89],rear_wall_plane_z=-3.0,rear_skirting_front_z=-2.89,
        placements=placements,anchors=anchors,spawn=spawn,exit=exit_,
        review_targets=[dict(name="mosaic",position=[mx,FLOOR,mz],direct=True),
            dict(name="glass_case_2",position=[1.28,FLOOR,.30],direct=True),
            dict(name="display_plinth",position=[1.40,FLOOR,1.97],direct=True),
            dict(name="view_artwork",position=[.65,FLOOR,-1.70],direct=False)],
        shared_shell="res://scenes/shell_hall/shell_hall_art.tscn",camera=hall["camera"],
        review_lighting=dict(hall["review_lighting"],background="DCE3E5",ambient_color="ECEFF0",ambient=.45,sun_color="FFF7EC",sun=.85,shadow_bias=.04,shadow_normal_bias=.12),
        lighting=dict(angular_distance=.4),local_lights=lights,
        height_assumptions=dict(case_top=1.46,case_display_surface=1.04,plinth_top=1.15,artwork_lower_bottom=1.30,artwork_upper_bottom=2.18,artwork_height=.78,sign_bottom=3.08,track_y=3.49),
        models={"blockout_bench":[.68,.715,1.728],"blockout_stool":[.48,.715,.48]},
        source_ownership=dict(zhaoyun="blockout_* only, room layout and assembly",huangzhong="Final cases, plinth, six frames, exhibit set, mosaic and sign. No final props copied or modified during white stage."))
    KIT.mkdir(parents=True,exist_ok=True)
    (KIT/"layout.json").write_text(json.dumps(plan,indent=2)+"\n")
    (HERE/"layout_plan.json").write_text(json.dumps(plan,indent=2)+"\n")
    print("CULTURE_PLAN",len(placements),"placements; four seats; rear case edge",cases[1]["position"][2]-cases[1]["size"][2]/2)
if __name__=="__main__":main()
