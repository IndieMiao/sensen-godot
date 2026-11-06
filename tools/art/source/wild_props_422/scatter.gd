extends RefCounted
## Executable review proposal, not a runtime patch. All data go to placement-report.json.
const Art = preload("res://modules/farm/farm_art.gd")
var pond
var stats: Dictionary
var config: Dictionary
var used: Array
var rng := RandomNumberGenerator.new()
var rows: Array = []
var nodes: Array = []
var group_count := 0
var root := Node3D.new()
func _init(p, active_slots: Array) -> void:
	pond=p; used=active_slots
	stats=JSON.parse_string(FileAccess.get_file_as_string("res://wild_asset_stats.json")).assets
	config=JSON.parse_string(FileAccess.get_file_as_string("res://density.json"))
	rng.seed=int(pond.entry.decoration_seed)+int(config.seed)
	root.name="Wild422Decor";pond.add_child(root)
func radius(name: String, scale_value: float) -> float:
	var b: Array=stats[name].bounds
	return Vector2(float(b[1][0]),float(b[1][2])).length()*scale_value
func screen_box(name: String, at: Vector3, scale_value: float, angle: float) -> Rect2:
	var b: Array=stats[name].bounds
	var rect:=Rect2(pond.cam.unproject_position(at),Vector2.ZERO)
	var basis:=Basis(Vector3.UP,angle).scaled(Vector3.ONE*scale_value)
	for ix in 2:
		for iy in 2:
			for iz in 2:rect=rect.expand(pond.cam.unproject_position(at+basis*Vector3(b[ix][0],b[iy][1],b[iz][2])))
	return rect
func slot_gap(at: Vector3, r: float) -> float:
	var gap:=INF
	for slot in used:gap=minf(gap,Vector2(at.x-slot.x,at.z-slot.z).length()-r)
	return gap
func valid(name: String, at: Vector3, scale_value: float, angle: float, group:=false) -> bool:
	var r:=radius(name,scale_value)
	if slot_gap(at,r)<1.5:return false
	for slot in used:
		if Vector2(at.x-slot.stand[0],at.z-slot.stand[1]).length()<r+.45:return false
	var water:=name=="wild_cattail_water"
	# Foreground scenery extends on the existing ground plane; nav and MEADOW camera clamp stay native.
	if not Rect2(-2.65,-18.65,17.3,23.3).has_point(Vector2(at.x,at.z)):return false
	# Whole footprint check, not just the stem/pivot. The circumscribed circle is conservative.
	for i in 9:
		var offset:=Vector3.ZERO if i==8 else Vector3(cos(i*TAU/8)*r,0,sin(i*TAU/8)*r)
		if FishingModel.contains(str(pond.entry.id),at+offset,0,pond.site_spec)!=water:return false
	if not water and at.z > -3 and absf(at.x-6.0)<.55:return false
	var box:=screen_box(name,at,scale_value,angle)
	if box.intersects(Rect2(278,420,82,300)) and name!="wild_clover":return false
	if group and (box.end.y>720 or box.position.x<6 or box.end.x>354 or box.position.y<85):return false
	for row in rows:
		if group and row.group==group_count+1:continue
		var other:=Vector2(row.position[0],row.position[2])
		if other.distance_to(Vector2(at.x,at.z))<(r+row.radius)*.75:return false
	return true
func put(name: String, at: Vector3, scale_value:=1.0, angle:=0.0, group_id:=0) -> void:
	var node:=Art.instance(name,at,scale_value);node.rotation.y=angle;root.add_child(node)
	if name.begins_with("wild_flower") or name in ["wild_clover","wild_pebbles_a","wild_pebbles_b"]:node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nodes.append(node)
	var box:=screen_box(name,at,scale_value,angle)
	rows.append({"asset":name,"position":[at.x,at.y,at.z],"scale":scale_value,"yaw_degrees":rad_to_deg(angle),"group":group_id,"radius":radius(name,scale_value),"slot_gap_m":slot_gap(at,radius(name,scale_value)),"screen_rect":[box.position.x,box.position.y,box.size.x,box.size.y]})
func group_at(at: Vector3, visible: bool) -> bool:
	var parts=[["wild_log_moss",Vector3.ZERO,.95,.3],["wild_mushrooms",Vector3(.35,0,.32),.90,0.0],["wild_fern",Vector3(-.36,0,-.23),.95,-.3],["wild_fern",Vector3(.42,0,-.17),.85,.4]]
	for part in parts:
		if not valid(part[0],at+part[1],part[2],part[3],visible):return false
	group_count+=1
	for part in parts:put(part[0],at+part[1],part[2],part[3],group_count)
	return true
func build() -> Dictionary:
	# Place the foreground corner group by actual opening projection, keeping its entire bounds above y=720.
	var placed:=false
	for sy in [650,630,670,610,690]:
		for sx in [60,78,95,112]:
			var screen:=Vector2(sx,sy)
			var origin: Vector3=pond.cam.project_ray_origin(screen);var direction: Vector3=pond.cam.project_ray_normal(screen)
			var at:=origin-direction*(origin.y/direction.y)
			if group_at(at,true):placed=true;break
		if placed:break
	for at in [Vector3(1.4,0,-15.6),Vector3(10.7,0,-16.8),Vector3(1.6,0,-10.5),Vector3(13,0,-11.7)]:
		if group_count>=3:break
		group_at(at,false)
	# Dry pieces: denser banks/sides, sparse open meadow and path edges.
	var targets={"wild_flower_white":12,"wild_flower_yellow":12,"wild_flower_lilac":12,"wild_clover":24,"wild_pebbles_a":7,"wild_pebbles_b":7,"wild_bush_dark":5,"wild_bush_olive":5}
	for name in targets:
		var added:=0
		for attempt in 1400:
			if added>=targets[name]:break
			var at:=Vector3(rng.randf_range(-1.5,13.5),.004,rng.randf_range(-18,4.6))
			var edge: Vector3=FishingModel.nearest_water(str(pond.entry.id),at,pond.site_spec)
			var distance:=Vector2(at.x-edge.x,at.z-edge.z).length()
			var side:=at.x<2.8 or at.x>9.3 or at.z < -15 or (at.z>1.5 and (at.x<4.6 or at.x>8))
			var bank:=distance>.5 and distance<1.2
			if not side and not bank and rng.randf()>.15:continue
			if name.begins_with("wild_bush") and not side:continue
			var scale_value:=rng.randf_range(.85,1.1);var angle:=rng.randf_range(0,TAU)
			if valid(name,at,scale_value,angle):put(name,at,scale_value,angle);added+=1
	# Cattails sit entirely inside the shallow water; two thin stems per clump, wide gaps.
	var water_count:=0
	var polygon:=FishingModel._polygon(pond.site_spec)
	for i in range(0,polygon.size(),5):
		if water_count>=7:break
		var edge:=polygon[i];var next:=polygon[(i+1)%polygon.size()];var tangent: Vector2=(next-edge).normalized()
		for sign in [-1,1]:
			var p: Vector2=edge+Vector2(-tangent.y,tangent.x)*(.40*sign);var at:=Vector3(p.x,-.06,p.y)
			var spaced:=true
			for row in rows:
				if row.asset=="wild_cattail_water" and Vector2(row.position[0]-p.x,row.position[2]-p.y).length()<2.2:spaced=false
			if spaced and valid("wild_cattail_water",at,1.0,0):put("wild_cattail_water",at);water_count+=1;break
	return {"seed":rng.seed,"placements":rows,"corner_groups":group_count,"foreground_group_placed":placed,"used_slots":used}
