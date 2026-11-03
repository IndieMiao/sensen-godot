"""N4 white blockout. Dimensions follow R3 placement intent and the P0 actor scale."""
from pathlib import Path
import json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
KIT=ROOT/"assets/rooms/poi_classroom"
FLOOR=.08
DESK=[1.02,1.745*.65,.58]
STOOL=[.48,.715,.48]

def main():
    placements=[]
    def put(name,model,at,size,role,collidable=True,owner="zhaoyun",support=None):
        row={"name":name,"model":model,"position":at,"size":size,"yaw_degrees":0,
             "role":role,"collidable":collidable,"owner":owner}
        if support:row["support"]=support
        placements.append(row)
        return row
    seats=[]
    for row,z in enumerate([-.95,.30,1.55]):
        for col,x in enumerate([-.55,1.60]):
            n=row*2+col+1
            put(f"desk_{n}","blockout_student_desk",[x,FLOOR,z],DESK,"student desk")
            put(f"stool_{n}","blockout_student_stool",[x,FLOOR,z+.53],STOOL,"student stool")
            seats.append({"name":f"seat_desk_{n}","position":[x,FLOOR+.715,z+.53],
                "yaw_degrees":0,"module":f"stool_{n}","desk_module":f"desk_{n}",
                "stand":[x+(.75 if col==0 else -.75),FLOOR,z+.60]})
    put("rear_bookcase","blockout_box",[-2.65,FLOOR,-2.50],[.90,2.15,.65],"rear tall bookcase")
    put("right_storage","blockout_box",[2.55,FLOOR,-2.67],[1.10,1.16,.50],"right storage bookcase")
    for i,z in enumerate([.85,1.70],1):
        put(f"low_cabinet_{i}","blockout_box",[-2.91,FLOOR,z],[.48,.90,.80],"left low cabinet")
    for i,y in enumerate([1.66,2.28],1):
        put(f"display_shelf_{i}","blockout_box",[2.55,FLOOR+y,-2.82],[1.12,.10,.32],"right display shelf",False)
    put("proxy_teacher_desk","blockout_box",[.38,FLOOR,-2.38],[1.30,1.13425,.723],"teacher desk body envelope",True,"huangzhong")
    put("proxy_blackboard","blockout_box",[.38,1.42,-2.91],[1.90,1.10,.16],"blank blackboard envelope",False,"huangzhong")
    put("proxy_globe","blockout_ball",[.06,FLOOR+1.13425,-2.3815],[.36886,.46943,.32],"globe_mount envelope",False,"huangzhong","proxy_teacher_desk")
    for n in [1,6]:
        desk=next(p for p in placements if p["name"]==f"desk_{n}")
        x,y,z=desk["position"]
        put(f"proxy_stationery_{n}","blockout_box",[x,y+DESK[1],z],[.545,.255,.27],"book and pencil cup envelope",False,"huangzhong",desk["name"])
    study=put("proxy_study","blockout_box",[-2.91,FLOOR+.90,.85],[.677514,.505,.23818],"combined study object envelope",False,"huangzhong","low_cabinet_1")
    study["yaw_degrees"]=90
    for i,x in enumerate([-2.82,-2.10],1):
        put(f"proxy_cushion_{i}","blockout_cylinder",[x,FLOOR,-.73],[.60,.16,.60],"decorative cushion",True,"huangzhong")
    put("proxy_sign","blockout_box",[.38,3.00,-2.967],[1.45,.38,.046],"blank runtime sign envelope",False,"huangzhong")
    for i,x in enumerate([-1.35,2.05],1):
        put(f"pendant_{i}","blockout_ball",[x,2.76,-1.40],[.40,.38,.40],"shared pendant envelope",False)
    for i,z in enumerate([-.55,.55],1):
        put(f"wall_sconce_{i}","blockout_ball",[-3.02,2.05,z],[.25,.27,.25],"shared wall sconce envelope",False)
    for i,(x,y,z) in enumerate([(-3.03,1.20,-2.03),(-3.03,1.20,-1.53),(-3.03,1.20,1.53),(-3.03,1.20,2.03),
                               (-2.65,FLOOR+2.15,-2.50),(2.84,FLOOR+2.38,-2.82)],1):
        put(f"plant_{i}","blockout_ball",[x,y,z],[.26,.36,.26],"shared potted plant envelope",False)
    spawn=[2.90,FLOOR,2.50]
    anchors=[{"name":"spawn","position":spawn,"yaw_degrees":180,"module":"hall_floor"},
             {"name":"exit","position":[.50,FLOOR,2.88],"yaw_degrees":180,"module":"hall_floor"},
             {"name":"badge_exit","position":[.50,.55,3.0],"yaw_degrees":0,"module":"hall_floor"},
             {"name":"cam_default","position":spawn,"yaw_degrees":45,"module":"hall_floor","role":"camera_follow_target","pitch_degrees":43,"orthographic_width":6.72},
             {"name":"sign_door","position":[.38,3.19,-2.938],"yaw_degrees":0,"module":"proxy_sign","size":[1.30,.28]}]+seats
    anchors += [{"name":s["name"].replace("seat_","stand_"),"position":s["stand"],"yaw_degrees":0,"module":"hall_floor"} for s in seats]
    hall=json.loads((ROOT/"assets/rooms/_shared/shell_hall/layout.json").read_text())
    plan={"task":"SGODOT-322","design":"SGODOT-317 R3","stage":"white_blockout",
        "units":"metres","floor_y":FLOOR,"footprint":[6.8,6.4],"wall_height":3.7,
        "inner_floor":[-3.18,-2.98,3.34,3.14],"reference_svg_scale_px_m":120,
        "placements":placements,"anchors":anchors,"spawn":spawn,"exit":[.50,FLOOR,2.88],
        "main_target":[.50,FLOOR,-1.55],"camera":hall["camera"],
        "review_lighting":dict(hall["review_lighting"],background="DDE2E3",ambient_color="F2F1EC",ambient=.55,sun_color="FFF8F0",sun=1.0),
        "shared_shell":"res://scenes/shell_hall/shell_hall_art.tscn",
        "source_ownership":{"zhaoyun":["layout.json","asset_stats.json","blockout_*.glb*","scenes/poi_classroom/*"],
          "huangzhong":"assets/rooms/poi_classroom/props/ from 350bd1f1 / PR #689. Seven final modules are not copied or overwritten during white blockout."},
        "prop_interface":{"source_commit":"350bd1f1","source_pr":689,"manifest":"assets/rooms/poi_classroom/props/prop_manifest.json",
          "globe_mount_local":[-.32,1.13425,-.0015],"stationery_size":[.545,.255,.27],
          "teacher_proxy_note":"Body to desktop height; the final asset's extra .05m top book is excluded from the simple gray volume."},
        "proposed_reuse":{"desk":"basic_room/dining_table.glb","stool":"basic_room/chair.glb source adapted after blockout approval",
          "shelving":"basic_room/wall_shelf.glb source adapted after blockout approval","lighting":"shared catalogue to be resolved in v1","plants":"_shared/plants"}}
    KIT.mkdir(parents=True,exist_ok=True)
    (KIT/"layout.json").write_text(json.dumps(plan,indent=2)+"\n")
    (HERE/"layout_plan.json").write_text(json.dumps(plan,indent=2)+"\n")
    print("CLASSROOM_PLAN",len(placements),"placements",len(seats),"seats")

if __name__=="__main__":main()
