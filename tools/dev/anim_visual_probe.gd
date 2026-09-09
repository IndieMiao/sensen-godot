## 把动画库里的 clip 在穿好默认装的角色上逐帧渲成 PNG，并拼成一张联系表。
## 用途：Mixamo 重定向结果的目视验收（数字对了不代表胳膊没反）。
##
## 必须带窗口跑（headless 拿不到图像）：
##   godot --path . --script res://tools/dev/anim_visual_probe.gd -- \
##       [--lib=res://tmp/mixamo_fixture/probe_lib.res] [--clips=a,b] [--frames=5] [--out=output/anim-probe]
## 不给 --lib 就渲 base_rig 自带的 animations.res；不给 --clips 就渲该库全部 clip。
extends SceneTree

const DEFAULT_LIB := "res://assets/avatar/base/animations.res"
const W := 360
const H := 560
const FOV := 35.0

var _lib_path := DEFAULT_LIB
var _clips: PackedStringArray = []
var _frames := 5
var _out := "output/anim-probe"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lib="):
			_lib_path = a.trim_prefix("--lib=")
		elif a.begins_with("--clips="):
			_clips = a.trim_prefix("--clips=").split(",", false)
		elif a.begins_with("--frames="):
			_frames = maxi(1, int(a.trim_prefix("--frames=")))
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	if DisplayServer.get_name() == "headless":
		printerr("需要带窗口运行：去掉 --headless")
		quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var out_abs := ProjectSettings.globalize_path(_out) if _out.begins_with("res://") else _out
	DirAccess.make_dir_recursive_absolute(out_abs)

	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.84, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 35.0, 0.0)
	vp.add_child(light)
	var cam := Camera3D.new()
	cam.fov = FOV
	vp.add_child(cam)
	# 角色零旋转面朝 +Z，相机放右前方 3/4 视角，整身入镜。
	cam.look_at_from_position(Vector3(1.3, 1.0, 2.9), Vector3(0.0, 0.85, 0.0), Vector3.UP)
	# 地面参考线：一块薄板，看脚有没有穿地/悬空。
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 0.02, 1.6)
	floor_mesh.mesh = box
	floor_mesh.position.y = -0.01
	vp.add_child(floor_mesh)

	# --script 模式下 Autoload 名不能当标识符用，得从 root 取节点。
	var avatar: Node = root.get_node("Avatar")
	var rig: AvatarRig = avatar.create_rig()
	for c in rig.get_children():
		if c is RigActivity:
			c.free()  # 它会抢 AnimationPlayer 的播放权，探针要手动 seek
	rig.assembler = AvatarAssemblerMerged.new()
	vp.add_child(rig)
	rig.apply_config(avatar.slot_table.default_config())
	var waited := 0
	while rig.is_busy() and waited < 900:
		await process_frame
		waited += 1
	await process_frame
	var ap := rig.get_node("AnimationPlayer") as AnimationPlayer
	var prefix := ""
	if _lib_path != DEFAULT_LIB:
		var lib := load(_lib_path) as AnimationLibrary
		if lib == null:
			printerr("动画库加载失败: " + _lib_path)
			quit(1)
			return
		ap.add_animation_library("probe", lib)
		prefix = "probe/"
		if _clips.is_empty():
			_clips = lib.get_animation_list()
	elif _clips.is_empty():
		_clips = ap.get_animation_library("").get_animation_list()

	var failed := 0
	for clip in _clips:
		var full := prefix + clip
		if not ap.has_animation(full):
			printerr("库里没有 clip: " + full)
			failed += 1
			continue
		var anim := ap.get_animation(full)
		var imgs: Array[Image] = []
		for i in _frames:
			var t := 0.0 if _frames == 1 else anim.length * float(i) / float(_frames - 1)
			t = minf(t, maxf(anim.length - 0.001, 0.0))
			ap.play(full)
			ap.seek(t, true)
			ap.pause()
			await process_frame
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			if img == null or img.is_empty():
				printerr("[%s] 第 %d 帧拿不到图像" % [clip, i])
				failed += 1
				continue
			imgs.append(img)
		if imgs.is_empty():
			continue
		var sheet := Image.create_empty(W * imgs.size(), H, false, imgs[0].get_format())
		for i in imgs.size():
			sheet.blit_rect(imgs[i], Rect2i(0, 0, W, H), Vector2i(W * i, 0))
		var path := out_abs.path_join("%s.png" % clip)
		if sheet.save_png(path) != OK:
			printerr("[%s] 保存失败" % clip)
			failed += 1
			continue
		print("渲出 %s  (%d 帧, clip 长 %.2fs, %d 轨)" % [path, imgs.size(), anim.length, anim.get_track_count()])
	quit(1 if failed > 0 else 0)
