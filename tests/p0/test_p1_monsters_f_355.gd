extends GdUnitTestSuite

const Monsters = preload("res://modules/mining/monsters/monsters.gd")
const Combat = preload("res://modules/mining/p0_mine_combat.gd")
const Layout = preload("res://modules/mining/mine_layout.gd")
const KINDS := ["mob_cave_bat","mob_elite_cave_bat","mob_rock_beetle","mob_elite_rock_beetle",
	"mob_shroomling","mob_elite_shroomling","boss_slime_king","boss_slime_king_iron","boss_slime_king_quartz"]

func _model_file() -> String: return "user://test_f_monster_%d.tscn"%OS.get_process_id()

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_model_file()))

class FightProbe extends RefCounted:
	var invulnerability := 0.0
	var hits := 0
	func touch(_e: Dictionary) -> void: hits += 1; invulnerability=0.5
	func _slide(mover: PlayerMover, offset: Vector3) -> void: mover.position += offset
	func _dash_step(_e: Dictionary, _p: PlayerMover, offset: Vector3) -> Vector3: return offset

func _player() -> PlayerMover:
	var nodes: Array=[]
	for i in Layout.FALLBACK_POSITIONS.size():nodes.append({id=str(i),position=Layout.FALLBACK_POSITIONS[i]})
	var bp: FarmBlueprint=Layout._navigation(nodes,nodes.map(func(n):return n.id))
	var p:=PlayerMover.new(bp,BlueprintGrid.new(bp))
	p.position=Layout.SPAWN
	return p

func _enemy(kind: String, player: PlayerMover, distance := 1.8) -> Dictionary:
	var spec:=Monsters.spec(kind)
	spec.hp=50
	var node: Node3D=auto_free(Monsters.view(kind,spec))
	var mover:=PlayerMover.new(player.bp,player.grid)
	mover.position=player.position+Vector3(0,0,-distance)
	mover.speed=float(spec.move_speed)
	node.position=mover.position
	node.meta=node.meta.duplicate(true)
	return {id="f_test",node=node,mover=mover,brain=Monsters.brain(kind),spec=spec,phase="idle",timer=0.0,repath=0.0,
		direction=Vector3.BACK,flash=0.0,did_hit=false,hp=50,elite=Monsters.is_elite(kind)}

func _tick(e: Dictionary, fight, player: PlayerMover, dt: float, may_path := true) -> bool:
	e.timer=maxf(0,float(e.timer)-dt)
	fight.invulnerability=maxf(0,float(fight.invulnerability)-dt)
	return e.brain.step(e,fight,player,dt,may_path)

func test_new_kinds_share_family_metadata_and_keep_hp_nodes_shadow_and_no_realtime_shadows() -> void:
	var p:=_player()
	for kind in KINDS:
		assert_bool(Monsters.known(kind)).is_true()
		var e:=_enemy(kind,p)
		for path in ["Body","Health","HealthTrack","HealthFill","Band","blob_shadow"]:
			assert_object(e.node.get_node_or_null(path)).override_failure_message(kind+":"+path).is_not_null()
		for geometry in e.node.find_children("*","GeometryInstance3D",true,false):
			assert_int(geometry.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_bool(e.node.meta.has("hit_at")).is_true()
	assert_str(Monsters.entry("mob_cave_bat").json).is_equal(Monsters.entry("mob_elite_cave_bat").json)
	assert_str(Monsters.entry("boss_slime_king").json).is_equal(Monsters.entry("boss_slime_king_iron").json)

func test_bat_is_hittable_only_during_its_dive_and_returns_to_high_flight() -> void:
	var p:=_player()
	var e:=_enemy("mob_cave_bat",p)
	var fight:=FightProbe.new()
	_tick(e,fight,p,0.01)
	assert_str(e.phase).is_equal("fly_high")
	assert_bool(e.brain.can_be_hit(e)).is_false()
	_tick(e,fight,p,float(e.node.meta.durations.fly_high))
	assert_str(e.phase).is_equal("windup")
	assert_bool(e.brain.can_be_hit(e)).is_false()
	_tick(e,fight,p,float(e.node.meta.durations.windup))
	assert_str(e.phase).is_equal("dash")
	assert_bool(e.brain.can_be_hit(e)).is_true()
	_tick(e,fight,p,float(e.node.meta.durations.attack))
	assert_str(e.phase).is_equal("recover")
	assert_bool(e.brain.can_be_hit(e)).is_false()
	_tick(e,fight,p,float(e.node.meta.durations.recover))
	assert_str(e.phase).is_equal("fly_high")

func test_beetle_is_stunned_for_metadata_duration_even_when_its_charge_misses() -> void:
	var p:=_player()
	var e:=_enemy("mob_rock_beetle",p)
	var fight:=FightProbe.new()
	e.node.meta.durations.stunned=3.25   # calibration must change the data, not the brain
	e.phase="dash"
	e.timer=0.01
	e.direction=Vector3.FORWARD
	_tick(e,fight,p,0.02)
	assert_int(fight.hits).is_equal(0)
	assert_str(e.phase).is_equal("stunned")
	assert_float(e.timer).is_equal(3.25)
	assert_bool(e.brain.stunned(e)).is_true()
	e.brain.on_hit(e,0.2)
	assert_float(e.timer).is_equal(3.25)
	_tick(e,fight,p,3.0)
	assert_bool(e.brain.stunned(e)).is_true()
	_tick(e,fight,p,0.25)
	assert_bool(e.brain.stunned(e)).is_false()

func test_shroom_hide_excludes_every_swing_until_the_metadata_window_ends() -> void:
	var p:=_player()
	var e:=_enemy("mob_shroomling",p)
	e.node.meta.durations.hide=1.3
	e.brain.on_hit(e,0.01)
	assert_str(e.phase).is_equal("hide")
	assert_bool(e.brain.can_be_hit(e)).is_false()
	var fight:=FightProbe.new()
	_tick(e,fight,p,0.9)
	e.brain.on_hit(e,0.01)
	assert_float(e.timer).is_equal_approx(0.4,0.00001)
	_tick(e,fight,p,0.41)
	assert_bool(e.brain.can_be_hit(e)).is_true()

func test_spore_hits_once_at_spore_at_and_not_during_a_hide() -> void:
	var p:=_player()
	var e:=_enemy("mob_shroomling",p,1.0)
	var fight:=FightProbe.new()
	e.phase="spore"
	e.node.meta.spore_at=0.6
	e.timer=float(e.node.meta.durations.spore)
	_tick(e,fight,p,0.59)
	assert_int(fight.hits).is_equal(0)
	_tick(e,fight,p,0.02)
	assert_int(fight.hits).is_equal(1)
	fight.invulnerability=0
	_tick(e,fight,p,0.1)
	assert_int(fight.hits).is_equal(1)
	e.brain.on_hit(e,0.01)
	_tick(e,fight,p,0.2)
	assert_int(fight.hits).is_equal(1)

func test_all_charges_use_hit_at_instead_of_immediate_contact() -> void:
	var p:=_player()
	for kind in ["mob_cave_bat","mob_rock_beetle","boss_slime_king"]:
		var e:=_enemy(kind,p,0.3)
		var fight:=FightProbe.new()
		e.phase="dash"
		e.timer=float(e.node.meta.durations.attack)
		e.direction=Vector3.ZERO
		var at:=float(e.node.meta.hit_at)
		_tick(e,fight,p,at-0.01)
		assert_int(fight.hits).is_equal(0)
		_tick(e,fight,p,0.02)
		assert_int(fight.hits).is_equal(1)
		fight.invulnerability=0
		_tick(e,fight,p,0.01)
		assert_int(fight.hits).is_equal(1)

func test_path_budget_is_respected_and_king_variants_differ_only_in_paint_and_ornaments() -> void:
	var p:=_player()
	for kind in ["mob_cave_bat","mob_rock_beetle","mob_shroomling","boss_slime_king"]:
		var e:=_enemy(kind,p,3.0)
		e.phase="fly_high" if kind=="mob_cave_bat" else "chase"
		var fight:=FightProbe.new()
		assert_bool(_tick(e,fight,p,0.02,false)).is_false()
		assert_bool(_tick(e,fight,p,0.02,true)).is_true()
	var colors:=[]
	for kind in ["boss_slime_king","boss_slime_king_iron","boss_slime_king_quartz"]:
		var e:=_enemy(kind,p)
		colors.append(e.node.get_meta("color"))
		assert_object(e.node.get_node_or_null("Body/GuardOrnament")).is_not_null()
	assert_bool(colors[0]!=colors[1] and colors[1]!=colors[2] and colors[0]!=colors[2]).is_true()

func test_real_swing_uses_bat_hide_and_beetle_stunned_flags_in_targets() -> void:
	var c: Node3D=auto_free(Combat.new())
	add_child(c)
	var p:=_player()
	var mobs: Array=[]
	for kind in ["mob_cave_bat","mob_rock_beetle","mob_shroomling"]:mobs.append({kind=kind,hp=50,max=50})
	c.sync_p0({mine={weapon={attack=3,speed=2},run={id=1,floors=[{floor=3,mobs=mobs}]}}},3,p)
	var ids: Array=c.enemies.keys()
	for id in ids:
		c.enemies[id].node.position=p.position+Vector3(0,0,-0.9)
		c.enemies[id].mover.position=c.enemies[id].node.position
	c.enemies[ids[0]].phase="fly_high"
	c.enemies[ids[1]].phase="stunned"
	c.enemies[ids[1]].timer=2.0
	c.enemies[ids[2]].phase="hide"
	p.facing=Vector3.FORWARD
	assert_array(c.swing({},p)).is_equal([ids[1]])
	assert_array(c.last_stunned).is_equal([ids[1]])

func test_placeholder_actions_are_tweened_and_die_stops_the_view() -> void:
	for kind in KINDS:
		var node: Node3D=auto_free(Monsters.view(kind,Monsters.spec(kind)))
		add_child(node)
		node.play("windup")
		node._motion.pause()
		node._motion.custom_step(node.duration("windup")*0.8)
		var scaled: Vector3=node.get_node("Body").scale if kind.begins_with("boss_") else node.visual.scale
		assert_float(scaled.y).is_less(1.0)
		node.play("die")
		node._motion.pause()
		node._motion.custom_step(node.duration("die")+0.01)
		assert_bool(node.visible).is_false()

func test_placeholder_elite_keeps_the_same_meshes_and_uses_its_own_color() -> void:
	var common: Node3D=auto_free(Monsters.view("mob_cave_bat",Monsters.spec("mob_cave_bat")))
	var elite: Node3D=auto_free(Monsters.view("mob_elite_cave_bat",Monsters.spec("mob_elite_cave_bat")))
	assert_int(common.find_children("*","MeshInstance3D",true,false).size()).is_equal(elite.find_children("*","MeshInstance3D",true,false).size())
	var a: MeshInstance3D=common.find_child("Torso",true,false)
	var b: MeshInstance3D=elite.find_child("Torso",true,false)
	assert_bool(a.material_override.albedo_color!=b.material_override.albedo_color).is_true()
	assert_that(a.scale).is_equal(b.scale)
	assert_bool(common.using_model).is_false()
	assert_object(common.get_node("blob_shadow")).is_not_null()

func _write_test_model() -> void:
	var root:=Node3D.new()
	var mesh:=MeshInstance3D.new()
	mesh.name="ModelMesh"
	mesh.mesh=SphereMesh.new()
	root.add_child(mesh)
	mesh.owner=root
	var player:=AnimationPlayer.new()
	root.add_child(player)
	player.owner=root
	var library:=AnimationLibrary.new()
	for name in ["idle","move","windup","attack","recover","hit","die","fly_high"]:
		var clip:=Animation.new()
		clip.length=0.2
		library.add_animation(name,clip)
	player.add_animation_library("",library)
	var packed:=PackedScene.new()
	assert_int(packed.pack(root)).is_equal(OK)
	assert_int(ResourceSaver.save(packed,_model_file())).is_equal(OK)
	root.free()

func test_model_path_switch_uses_animation_player_json_timing_and_per_instance_masked_material() -> void:
	_write_test_model()
	var View=load("res://modules/mining/monsters/bat_view.gd")
	var node: Node3D=auto_free(View.new())
	node.kind="mob_elite_cave_bat"
	node.meta=Monsters.meta("mob_cave_bat").duplicate(true)
	node.meta.model=_model_file()
	node.meta.durations.attack=0.6
	node.build(Monsters.spec("mob_cave_bat"),true)
	add_child(node)
	assert_bool(node.using_model).is_true()
	assert_object(node.find_child("Torso",true,false)).is_null()
	assert_object(node.find_child("ModelMesh",true,false)).is_not_null()
	assert_int(node._player.get_animation("fly_high").loop_mode).is_equal(Animation.LOOP_LINEAR)
	assert_int(node._player.get_animation("attack").loop_mode).is_equal(Animation.LOOP_NONE)
	node.play("attack")
	assert_str(node._player.current_animation).is_equal("attack")
	assert_float(node._player.get_playing_speed()).is_equal_approx(1.0/3.0,0.00001)
	node.set_tint({color="80a0ff",strength=0.8})
	assert_float(node._model_material.get_shader_parameter("tint_strength")).is_equal(0.8)
	node.set_tint({color=Color("80a0ff"),strength=0.5})
	assert_that(node._model_material.get_shader_parameter("tint")).is_equal(Color("80a0ff"))
	var original: Node=auto_free((load(_model_file()) as PackedScene).instantiate())
	var player: AnimationPlayer=original.find_children("*","AnimationPlayer",true,false)[0]
	assert_int(player.get_animation("fly_high").loop_mode).is_equal(Animation.LOOP_NONE)   # shared imported resources stay untouched

func test_spore_visual_releases_at_the_same_metadata_timestamp_as_the_brain() -> void:
	var node: Node3D=auto_free(Monsters.view("mob_shroomling",Monsters.spec("mob_shroomling")))
	add_child(node)
	node.play("spore")
	node._motion.pause()
	node._motion.custom_step(float(node.meta.spore_at)-0.01)
	assert_object(node._spores).is_null()
	node._motion.custom_step(0.02)
	assert_object(node._spores).is_not_null()
	assert_bool(node.get_meta("spore_released")).is_true()

func test_slow_frames_and_pause_do_not_advance_attack_animation_ahead_of_the_brain_clock() -> void:
	var p:=_player()
	for kind in ["mob_cave_bat","mob_rock_beetle","mob_shroomling","boss_slime_king"]:
		var e:=_enemy(kind,p)
		add_child(e.node)
		e.phase="windup"
		e.timer=float(e.node.meta.durations.windup)
		e.node.update(e,"idle",0.5,true,0.0)
		assert_float(e.node.action_time).is_equal(0.0)   # the new phase starts at this frame's end
		e.node.update(e,"windup",0.5,true,0.1)
		assert_float(e.node.action_time).is_equal_approx(0.1,0.00001)
		e.node.update(e,"windup",0.5,false,0.1)
		assert_float(e.node.action_time).is_equal_approx(0.1,0.00001)
		for i in 30:e.node.update(e,"windup",0.1,true,0.2+i*0.1)
		assert_bool(e.node._motion_done).is_true()   # a held finished pose is never replayed/restarted
