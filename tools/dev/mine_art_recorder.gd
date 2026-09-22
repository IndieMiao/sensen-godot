extends Node
## Observes the real online mine scene; all gameplay settles in the isolated real gateway.
const OUT := "user://mine-art"
var elapsed := 0.0
var serial := 0
var last_command := ""
var session: FarmSession
var ready_for_input := false
var command_busy := false
func _enter_tree() -> void:
	Net.booting = true
	Net.booted_once = true
func _ready() -> void:
	Engine.max_fps = 60
	call_deferred("_start")
func _start() -> void:
	Localization.select_language("zh_CN")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if FileAccess.file_exists(OUT.path_join("command.json")): DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT.path_join("command.json")))
	var account: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://mine_art_account.json"))
	Net.use_transport(ApiClient.make_http_transport(self), "http://10.0.2.2:3172/v1")
	Net.client.token = str(account.token)
	session = Net.session
	session.player_id = str(account.player)
	Net.online_available = true
	assert(await session.refresh())
	# Isolated local outfit for visible character silhouette; no account or wardrobe save.
	var config = Avatar.load_outfit()
	config.slots[&"cloth"] = "cloth28"
	config.slots[&"hairHat"] = "hairhat41"
	config.slots[&"shoes"] = "shoes3"
	Avatar.save_outfit(config)
	AppRouter.push_instance(AppRouter.FARM, {"session":session})
	await get_tree().create_timer(2).timeout
	ready_for_input = true
func rect(control: Control) -> Array:
	var r: Rect2 = get_viewport().get_screen_transform() * control.get_global_rect()
	return [r.position.x,r.position.y,r.size.x,r.size.y]
func command(body: Dictionary) -> void:
	if command_busy: return
	last_command = str(body.id)
	command_busy = true
	var scene = AppRouter.top_instance()
	match str(body.op):
		"rescue": scene.show_mine_rescue()
		"close_farm_bag": scene.hud.close_modal()
		"enter": scene._go_mine()
		"target": scene.select_target(str(body.target))
		"move": scene.mover.set_target_position(Vector3(float(body.x),0,float(body.z)))
		"attack": scene.attack.set_pressed(bool(body.enabled)); scene._attack_held = bool(body.enabled)
		"bag": scene._open_bag()
		"page":
			if scene.bag_sheet: scene.bag_sheet.active.select_page(str(body.page))
		"item":
			if scene.bag_sheet:
				for item in session.state.bag.slots:
					if item.item_id == str(body.item): scene.bag_sheet.active.select_stack(str(item.id)); break
		"reveal":
			var button = scene.find_child(str(body.name),true,false)
			if button:
				var parent = button.get_parent()
				while parent and not parent is ScrollContainer: parent = parent.get_parent()
				if parent: parent.ensure_control_visible(button)
		"close_bag":
			if scene.bag_sheet: scene.bag_sheet.close()
		"back": AppRouter.pop_instance()
	command_busy = false
func _process(delta: float) -> void:
	elapsed += delta
	if not ready_for_input or elapsed < 0.12: return
	elapsed = 0.0
	if FileAccess.file_exists(OUT.path_join("command.json")):
		var cmd = JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("command.json")))
		if cmd is Dictionary and str(cmd.get("id","")) != last_command: command(cmd)
	var scene = AppRouter.top_instance()
	if not is_instance_valid(scene): return
	var controls := []
	for c in scene.find_children("*","BaseButton",true,false):
		if c.is_visible_in_tree(): controls.append({"name":str(c.name),"text":c.text,"rect":rect(c),"disabled":c.disabled})
	var data := {"scene":scene.scene_file_path,"ticks":Time.get_ticks_msec(),"controls":controls,"last_command":last_command,"version":session.version}
	if scene.scene_file_path == AppRouter.ONLINE_MINE:
		var mine: Dictionary = scene.mine_state()
		var enemies := []
		for id in scene.combat.enemies:
			var e: Dictionary = scene.combat.enemies[id]
			enemies.append({"id":id,"hp":e.hp,"x":e.node.position.x,"z":e.node.position.z,"phase":e.phase})
		var targets := []
		for id in scene.targets:
			var p: Vector2 = get_viewport().get_screen_transform() * scene.cam.unproject_position(scene.targets[id].body)
			targets.append({"id":id,"point":[p.x,p.y],"x":scene.targets[id].body.x,"z":scene.targets[id].body.z})
		data.merge({"floor":scene.current_floor(),"mine":mine,"targets":targets,"enemies":enemies,"hp":scene.online.self_state.get("hp",0),"joined":scene.online.joined,"moving":scene.mover.is_moving(),"busy":scene.busy,"can_act":scene._can_act(),"bag_open":scene.bag_sheet!=null and scene.bag_sheet.visible,"player":[scene.mover.position.x,scene.mover.position.z],"feedback":scene.feedback.text,"navigation":scene.online.world.get("navigation",{}),"bag":session.state.bag})
	else:
		data.hp = session.state.character.hp
		if scene.scene_file_path == AppRouter.FARM:
			var r: Rect2 = get_viewport().get_screen_transform() * scene._mine_pick_rect()
			data.entrance = [r.position.x,r.position.y,r.size.x,r.size.y]
	FileAccess.open(OUT.path_join("state.json"),FileAccess.WRITE).store_string(JSON.stringify(data))
