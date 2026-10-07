extends Node
## Authored route uses real CharacterBody3D motion, never position interpolation.
var room: Node3D
var checks: Array = []
var route_results: Array = []

func check(name:String,passed:bool,details:Variant=null)->void:
	checks.append({"name":name,"passed":passed,"details":details})
	print("PASS " if passed else "FAIL ",name," ",details)

func wait_seconds(seconds:float)->void:await get_tree().create_timer(seconds).timeout

func walk_to(target:Vector3,limit:float=3.0)->Dictionary:
	var begin:=Time.get_ticks_msec()
	var start:Vector3=room.player.position
	room.automatic=true;room.collided_paths.clear()
	var reached:=false
	while float(Time.get_ticks_msec()-begin)/1000.0<limit:
		var delta:Vector3=target-room.player.position
		var flat:=Vector3(delta.x,0,delta.z)
		if flat.length()<.105 and absf(delta.y)<.23:reached=true;break
		room.drive_direction=flat.normalized()*minf(1,flat.length()/.16)
		await get_tree().physics_frame
	room.drive_direction=Vector3.ZERO
	await get_tree().physics_frame
	return {"reached":reached,"seconds":float(Time.get_ticks_msec()-begin)/1000.0,
		"from":[start.x,start.y,start.z],"target":[target.x,target.y,target.z],
		"final":[room.player.position.x,room.player.position.y,room.player.position.z],
		"remaining_m":room.player.position.distance_to(target),"collisions":room.collided_paths.duplicate()}

func run(benchmark:Node3D)->void:
	room=benchmark
	if DisplayServer.get_name()=="headless":
		check("Real rendered viewport required",false,"Run without --headless")
		finish();return
	var deadline:=Time.get_ticks_msec()+20000
	while not room.ready_for_capture and Time.get_ticks_msec()<deadline:await wait_seconds(.05)
	await wait_seconds(.6)
	check("Default Avatar fixture assembles",room.ready_for_capture and not room.rig.is_busy())
	var data:Dictionary=room.bench
	var valid:bool=data.has("route") and data.route.size()>=6 and data.route.size()<=10 and data.has("blocked") and data.has("gaps")
	check("Bench route/probe schema",valid)
	if not valid:finish();return
	if room.mode=="record":await record_route();return
	room.phase="spawn"
	check("Spawn stands on authored floor",room.player.is_on_floor() and absf(room.player.position.y-float(data.get("floor_y",.08)))<.04,room.player.position.y)
	check("Spawn capsule clear",capsule_clear(room.player.position),room.player.position)
	await room.capture("spawn.png")
	room.phase="route"
	for waypoint in data.route:
		var result:=await walk_to(room.vec(waypoint.position))
		result["name"]=waypoint.name;route_results.append(result)
		check("Route: "+str(waypoint.name),result.reached and result.seconds<=3.05,result)
		if waypoint.has("capture"):await room.capture(str(waypoint.capture)+".png")
	room.phase="blocked"
	for probe in data.blocked:
		room.teleport(room.vec(probe.from));await wait_seconds(.12)
		var result:=await walk_to(room.vec(probe.to),float(probe.get("seconds",.85)))
		var matched:bool=false
		for path in result.collisions:
			if str(probe.get("target","")).is_empty() or str(probe.target) in path:matched=true
		# A capsule may stop on a bevel with an upward recovery normal, without
		# a lateral slide report. Confirm the authored blocker with a torso ray.
		var ray:=PhysicsRayQueryParameters3D.create(room.vec(probe.from)+Vector3.UP*.65,room.vec(probe.to)+Vector3.UP*.65)
		ray.exclude=[room.player.get_rid()]
		var hit:Dictionary=room.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			result["torso_ray_blocker"]=str(hit.collider.get_path())
			matched=matched or str(probe.get("target","")) in result.torso_ray_blocker
		check("Blocked: "+str(probe.name),not result.reached and matched and room.player.is_on_floor(),result)
	room.phase="gaps"
	for gap in data.gaps:
		var width:=measure_gap(gap)
		check("Gap width: "+str(gap.name),width>=float(gap.get("minimum",.70)) and width<=float(gap.get("width",width))+.15,
			{"measured_m":width,"minimum_m":gap.get("minimum",.70),"authored_width":gap.get("width",null)})
		room.teleport(room.vec(gap.from));await wait_seconds(.1)
		var result:=await walk_to(room.vec(gap.to))
		check("Traverse: "+str(gap.name),result.reached,result)
	if data.has("entrance"):
		var entry:Dictionary=data.entrance
		room.teleport(room.vec(entry.inside));await wait_seconds(.1)
		var outward:=await walk_to(room.vec(entry.outside))
		var inward:=await walk_to(room.vec(entry.inside))
		check("Entrance gap allows exit and reentry",outward.reached and inward.reached,{"exit":outward,"entry":inward})
	elif room.slug!="basic_room":check("Entrance definition required",false)
	if data.has("slide"):
		var slide:Dictionary=data.slide
		room.teleport(room.vec(slide.from));await wait_seconds(.1)
		room.automatic=true;room.drive_direction=room.vec(slide.direction).normalized()
		room.collided_paths.clear();var before:Vector3=room.player.position
		await wait_seconds(float(slide.get("seconds",.6)))
		room.drive_direction=Vector3.ZERO;await wait_seconds(.08)
		var displacement:Vector3=room.player.position-before
		var tangent:Vector3=room.vec(slide.tangent).normalized()
		check("Diagonal collision preserves wall sliding",displacement.dot(tangent)>.45 and not room.collided_paths.is_empty(),
			{"delta":[displacement.x,displacement.y,displacement.z],"collisions":room.collided_paths})
	else:check("Wall-slide probe defined",false)
	await input_and_animation()
	measure_scale()
	room.teleport(room.vec(data.get("spawn",room.layout.get("spawn",[0,.09,1.5]))));await wait_seconds(.15)
	room.show_colliders();await room.capture("collisions.png");room.collision_overlay.queue_free()
	finish()

func capsule_clear(at:Vector3)->bool:
	var shape:=CapsuleShape3D.new();shape.radius=room.RADIUS-.005;shape.height=room.HEIGHT-.02
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape
	query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*(room.HEIGHT/2+.025));query.exclude=[room.player.get_rid()]
	return room.get_world_3d().direct_space_state.intersect_shape(query).is_empty()

func measure_gap(gap:Dictionary)->float:
	# Ray endpoints describe solid faces, not a claimed number. Query live physics.
	var a:Vector3=room.vec(gap.measure[0]);var b:Vector3=room.vec(gap.measure[1]);var mid:Vector3=(a+b)/2
	var direction:Vector3=(b-a).normalized();var distances:Array[float]=[]
	for side in [-1.0,1.0]:
		var query:=PhysicsRayQueryParameters3D.create(mid,mid+direction*side*(a.distance_to(b)/2+.25))
		query.exclude=[room.player.get_rid()]
		var hit:Dictionary=room.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():return -1
		distances.append(mid.distance_to(hit.position))
	return distances[0]+distances[1]

func input_and_animation()->void:
	room.phase="input"
	room.teleport(room.vec(room.bench.get("input_start",room.layout.get("spawn",[0,.09,1.5]))))
	await wait_seconds(.1);room.automatic=false
	var press:=InputEventScreenTouch.new();press.index=0;press.pressed=true;press.position=Vector2(400,420)
	Input.parse_input_event(press);await wait_seconds(.05)
	var drag:=InputEventScreenDrag.new();drag.index=0;drag.position=Vector2(460,440)
	Input.parse_input_event(drag);await wait_seconds(.14)
	var animation:AnimationPlayer=room.rig.get_node("AnimationPlayer")
	var time1:=animation.current_animation_position;var run_name:=animation.current_animation
	await wait_seconds(.16)
	check("Run animation advances in rendered viewport",run_name=="run" and absf(animation.current_animation_position-time1)>.01,
		[run_name,time1,animation.current_animation_position])
	var release:=InputEventScreenTouch.new();release.index=0;release.pressed=false;release.position=drag.position
	Input.parse_input_event(release);await wait_seconds(.08)
	check("Input release stops horizontal motion",Vector2(room.player.velocity.x,room.player.velocity.z).length()<.01)
	check("Release returns to idle",animation.current_animation=="idle",animation.current_animation)
	room.input_value=Vector2(.5,.1);await wait_seconds(.1)
	room._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT);room.controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await wait_seconds(.08)
	check("Focus loss cancels movement",Vector2(room.player.velocity.x,room.player.velocity.z).length()<.01)
	room.automatic=true

func collect_top(node:Node)->float:
	var top:=0.0
	if node is MeshInstance3D and node.visible:
		var bounds:AABB=node.get_aabb()
		for i in 8:top=maxf(top,(node.global_transform*bounds.get_endpoint(i)).y-room.player.position.y)
	for child in node.get_children():top=maxf(top,collect_top(child))
	return top

func measure_scale()->void:
	var top:=collect_top(room.rig)
	var scale:Dictionary=room.bench.get("scale",{})
	var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/dev/scene_bench/fixtures/basic_room.json")).scale
	var result:Dictionary={"avatar_top_H":top,"capsule_radius":room.RADIUS,"capsule_height":room.HEIGHT,"speed":room.SPEED,"measurements":{}}
	check("Fixture head-top height measurable",top>1.0 and top<2.5,top)
	for key in baseline:
		if not scale.has(key):check("Scale measurement present: "+key,false);continue
		if not bool(scale[key].get("applicable", true)):
			var reason := str(scale[key].get("reason", ""))
			result.measurements[key] = {"applicable":false,"reason":reason}
			check("Scale category absent: "+key,not reason.is_empty(),result.measurements[key])
			continue
		if not scale[key].has("height"):
			check("Scale height present: "+key,false)
			continue
		var current:float=float(scale[key].height);var base:float=float(baseline[key].height)
		var difference:float=absf(current/base-1)
		result.measurements[key]={"height":current,"ratio_to_H":current/top,"baseline_ratio":base/top,"difference":difference,"reason":scale[key].get("reason","")}
		check("Scale ±15%: "+key,difference<=.15 or not str(scale[key].get("reason","")).is_empty(),result.measurements[key])
	room.save_json("scale-measurements.json",result)

func record_route()->void:
	room.phase="record-ready";room.write_state()
	var timeout:=Time.get_ticks_msec()+15000
	while not FileAccess.file_exists(room.output_dir+"/record-go") and Time.get_ticks_msec()<timeout:await wait_seconds(.05)
	if not FileAccess.file_exists(room.output_dir+"/record-go"):check("Recorder handshake",false);finish();return
	var started:=Time.get_ticks_msec();room.phase="recording-route"
	for waypoint in room.bench.route:
		var result:=await walk_to(room.vec(waypoint.position));result["name"]=waypoint.name;route_results.append(result)
		check("Recorded route: "+str(waypoint.name),result.reached,result)
		await wait_seconds(.25)
	var duration:=float(Time.get_ticks_msec()-started)/1000.0
	check("Full route fits unaccelerated 15s clip",duration<14.5,duration)
	room.phase="record-hold"
	await wait_seconds(maxf(.5,15.3-duration));finish()

func finish()->void:
	var passed:=not checks.is_empty()
	for item in checks:passed=passed and bool(item.passed)
	room.phase="finished";room.write_state()
	room.save_json("record-result.json" if room.mode=="record" else "result.json",{
		"passed":passed,"slug":room.slug,"pid":OS.get_process_id(),"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),"checks":checks,"route":route_results,
		"scope":"Rendered desktop fixture motion and injected Godot input events; no physical device claim"})
	print("SCENE_BENCH_RESULT ",room.slug," passed=",passed)
	get_tree().quit(0 if passed else 1)
