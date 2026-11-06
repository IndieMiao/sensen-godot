extends SceneTree
## Asset-only AnimationPlayers, no autoplay, root movement or runtime script.
const DIR="res://assets/landmarks/alcatraz_island/"
var owner_root:Node3D
func _initialize():build.call_deferred()
func child(n:Node,parent:Node,label:String):
	n.name=label;parent.add_child(n);n.owner=owner_root;return n
func imported(path:String,parent:Node,label:String):
	var n=load(DIR+path).instantiate();child(n,parent,label);owner_root.set_editable_instance(n,true);return n
func first_mesh(n):
	if n is MeshInstance3D:return n
	return n.find_children("*","MeshInstance3D",true,false)[0]
func smooth(a:float,b:float,t:float):
	var q=clampf(t,0,1);q=q*q*(3-2*q);return lerpf(a,b,q)
func curve(keys:Array,t:float):
	for i in range(keys.size()-1):
		if t<=float(keys[i+1][0]):return smooth(keys[i][1],keys[i+1][1],(t-keys[i][0])/(keys[i+1][0]-keys[i][0]))
	return keys[-1][1]
func track(anim:Animation,path:String,values:Array):
	var index=anim.add_track(Animation.TYPE_VALUE);anim.track_set_path(index,NodePath(path));anim.track_set_interpolation_type(index,Animation.INTERPOLATION_LINEAR)
	for sample in values:anim.track_insert_key(index,sample[0],sample[1])
func animation_player(anim:Animation,reset:Animation):
	var library=AnimationLibrary.new();library.add_animation("idle",anim);library.add_animation("RESET",reset)
	var ap=AnimationPlayer.new();child(ap,owner_root,"AnimationPlayer");ap.add_animation_library("",library)
	assert(ap.autoplay.is_empty());return ap
func save_scene(name:String):
	var library=owner_root.get_node("AnimationPlayer").get_animation_library("")
	var library_name=name.get_basename()+"_animations.tres"
	var library_path=DIR+library_name
	var library_uid=ResourceLoader.get_resource_uid(library_path) if FileAccess.file_exists(library_path) else ResourceUID.INVALID_ID
	if library_uid==ResourceUID.INVALID_ID:library_uid=ResourceUID.create_id()
	assert(ResourceSaver.save(library,library_path)==OK);assert(ResourceSaver.set_uid(library_path,library_uid)==OK)
	var path=DIR+name;var uid=ResourceLoader.get_resource_uid(path) if FileAccess.file_exists(path) else ResourceUID.INVALID_ID
	if uid==ResourceUID.INVALID_ID:uid=ResourceUID.create_id()
	var text="[gd_scene format=3 uid=\"%s\"]\n\n"%ResourceUID.id_to_text(uid)
	if name=="gull.tscn":
		text+='[ext_resource type="PackedScene" path="'+DIR+'gull.glb" id="1"]\n'
		text+='[ext_resource type="AnimationLibrary" path="'+library_path+'" id="2"]\n\n'
		text+='[node name="Gull" type="Node3D"]\n\n[node name="Model" parent="." instance=ExtResource("1")]\n\n'
	else:
		text+='[ext_resource type="PackedScene" path="'+DIR+'ferry.glb" id="1"]\n'
		text+='[ext_resource type="PackedScene" path="'+DIR+'ferry_far.glb" id="2"]\n'
		text+='[ext_resource type="PackedScene" path="'+DIR+'ferry_flag.glb" id="3"]\n'
		text+='[ext_resource type="AnimationLibrary" path="'+library_path+'" id="4"]\n\n'
		text+='[node name="Ferry" type="Node3D"]\n\n[node name="BodyRig" type="Node3D" parent="."]\n\n'
		text+='[node name="Near" parent="BodyRig" instance=ExtResource("1")]\n\n[node name="ferry" parent="BodyRig/Near" index="0"]\nvisibility_range_end = 55.0\n\n'
		text+='[node name="Far" parent="BodyRig" instance=ExtResource("2")]\n\n[node name="ferry_far" parent="BodyRig/Far" index="0"]\nvisibility_range_begin = 55.0\n\n'
		text+='[node name="SternFlag" parent="BodyRig" instance=ExtResource("3")]\nposition = Vector3(11.2, 1.48, 2.5)\n\n'
		text+='[node name="ferry_flag" parent="BodyRig/SternFlag" index="0"]\nblend_shapes/flutter = 0.5\n\n'
	var lib_id="2" if name=="gull.tscn" else "4"
	text+='[node name="AnimationPlayer" type="AnimationPlayer" parent="."]\nlibraries = {\n&"": ExtResource("'+lib_id+'")\n}\n'
	if name=="ferry.tscn":text+='\n[editable path="BodyRig/Near"]\n[editable path="BodyRig/Far"]\n[editable path="BodyRig/SternFlag"]\n'
	FileAccess.open(path,FileAccess.WRITE).store_string(text);ResourceUID.add_id(uid,path);owner_root.free()
func build_gull():
	owner_root=Node3D.new();owner_root.name="Gull"
	var model=imported("gull.glb",owner_root,"Model");var mi=first_mesh(model)
	var prefix=str(owner_root.get_path_to(mi))+":blend_shapes/"
	var idle=Animation.new();idle.resource_name="Gull_QuietIdle_8p5s";idle.length=8.5;idle.loop_mode=Animation.LOOP_LINEAR
	var reset=Animation.new();reset.length=.001
	var curves={
		"turn_head":[[0,0],[1.25,0],[1.52,1],[1.78,1],[2.05,0],[8.5,0]],
		"preen":[[0,0],[3.5,0],[3.85,1],[4.02,1],[4.14,.82],[4.27,1],[4.48,1],[4.82,0],[8.5,0]],
		"spread":[[0,0],[6.32,0],[6.48,.9],[6.64,.12],[6.80,.72],[7.02,0],[8.5,0]]}
	for shape in curves:
		var values=[]
		for i in range(256):
			var t=float(i)/30;values.append([t,curve(curves[shape],t)])
		track(idle,prefix+shape,values);track(reset,prefix+shape,[[0,0.0]])
	animation_player(idle,reset);save_scene("gull.tscn")
func build_ferry():
	owner_root=Node3D.new();owner_root.name="Ferry"
	var body=child(Node3D.new(),owner_root,"BodyRig")
	var near=imported("ferry.glb",body,"Near");var far=imported("ferry_far.glb",body,"Far")
	var near_mesh=first_mesh(near);var far_mesh=first_mesh(far)
	near_mesh.visibility_range_end=55;far_mesh.visibility_range_begin=55
	near_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;far_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flag=imported("ferry_flag.glb",body,"SternFlag");flag.position=Vector3(11.2,1.48,2.5)
	var flag_mesh=first_mesh(flag);flag_mesh.set_blend_shape_value(0,.5)
	var flag_path=str(owner_root.get_path_to(flag_mesh))+":blend_shapes/flutter"
	var idle=Animation.new();idle.resource_name="Ferry_QuietBob_4s";idle.length=4.0;idle.loop_mode=Animation.LOOP_LINEAR
	var reset=Animation.new();reset.length=.001;var positions=[];var waves=[]
	for i in range(121):
		var t=float(i)/30;positions.append([t,Vector3(0,.02*sin(TAU*t/4),0)]);waves.append([t,.5+.5*sin(TAU*t/2)])
	track(idle,"BodyRig:position",positions);track(idle,flag_path,waves)
	track(reset,"BodyRig:position",[[0,Vector3.ZERO]]);track(reset,flag_path,[[0,.5]])
	animation_player(idle,reset);save_scene("ferry.tscn")
func build():
	build_gull();build_ferry();print("ANIM_SCENES_BUILT");quit()
