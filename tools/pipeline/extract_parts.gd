## Headless 提取器：recipes.json → AvatarPartDef .res / socket .tscn / thumbs / parts_manifest.json
## 用法: godot --headless --path . --script res://tools/pipeline/extract_parts.gd -- <recipes.json路径> [--append]
## 默认整份重写 parts_manifest.json。--append（SGODOT-229）只提取清单里还没有的 id，新条目按文本插到
## parts 数组的 ] 之前：已有条目逐字节不变，它们的 .res / 场景 / 缩略图也不会重写。
extends SceneTree

const PARTS_DIR := "res://assets/avatar/parts"
const THUMBS_DIR := "res://assets/avatar/thumbs"
const MANIFEST_PATH := "res://assets/avatar/parts_manifest.json"

var _errors: PackedStringArray = []

func _initialize() -> void:
	var raw := OS.get_cmdline_user_args()
	var append := raw.has("--append")
	var args := PackedStringArray(Array(raw).filter(func(a): return a != "--append"))
	if args.is_empty():
		push_error("缺少参数: recipes.json 路径")
		quit(2)
		return
	var recipes_text := FileAccess.get_file_as_string(args[0])
	var recipes = JSON.parse_string(recipes_text)
	if typeof(recipes) != TYPE_DICTIONARY:
		push_error("recipes.json 解析失败: %s" % args[0])
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PARTS_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(THUMBS_DIR))
	if append:
		_append(recipes)
		return
	var manifest_parts: Array = []
	for recipe in recipes.parts:
		var entry = _process_part(recipe)
		if entry != null:
			manifest_parts.append(entry)
	var manifest := {"version": 1, "parts": manifest_parts}
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t"))
	f.close()
	for e in _errors:
		printerr("ERROR: " + e)
	print("提取完成: %d 部件, %d 错误" % [manifest_parts.size(), _errors.size()])
	quit(1 if _errors.size() > 0 else 0)

## --append: extract only the new ids and insert their entries into the manifest text.
func _append(recipes: Dictionary) -> void:
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	var current = JSON.parse_string(text)
	if typeof(current) != TYPE_DICTIONARY or typeof(current.get("parts")) != TYPE_ARRAY:
		push_error("parts_manifest.json 解析失败，--append 需要一份现有清单")
		quit(2)
		return
	var todo := pending(recipes.parts, current.parts)
	var added: Array = []
	for recipe in recipes.parts:
		if not todo.has(recipe):
			print("跳过已在清单里的 %s（条目与 .res 不动）" % recipe.id)
			continue
		var entry = _process_part(recipe)
		if entry != null:
			added.append(entry)
	var out := append_entries(text, added)
	if out == "":
		push_error("parts_manifest.json 找不到 parts 数组的结尾")
		quit(2)
		return
	if not added.is_empty():
		var f := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
		f.store_string(out)
		f.close()
	for e in _errors:
		printerr("ERROR: " + e)
	print("追加完成: %d 部件, %d 错误" % [added.size(), _errors.size()])
	quit(1 if _errors.size() > 0 else 0)

## The recipes whose id the manifest does not have yet, in recipe order.
static func pending(recipes: Array, manifest_parts: Array) -> Array:
	var have := {}
	for p in manifest_parts:
		have[str(p.get("id", ""))] = true
	return recipes.filter(func(r): return not have.has(str(r.get("id", ""))))

## The manifest text with these entries inserted before the parts array's closing bracket, each serialised as the
## default mode does (JSON.stringify with tabs, two levels in). The text before them is kept byte for byte.
## "" when the text has no parts array ending "\n\t]".
static func append_entries(text: String, entries: Array) -> String:
	if entries.is_empty(): return text
	# The first top-level "]" after "parts": [ closes it; nested arrays sit deeper, other top-level arrays come later.
	var open := text.find("\"parts\": [")
	var close := text.find("\n\t]", open) if open >= 0 else -1
	if close < 0: return ""
	var block := ""
	for e in entries:
		block += ",\n" + "\n".join(Array(JSON.stringify(e, "\t").split("\n")).map(func(l): return "\t\t" + l))
	return text.substr(0, close) + block + text.substr(close)

func _process_part(recipe: Dictionary):
	var id: String = recipe.id
	var scene_res = load(String(recipe.fbx))
	if scene_res == null or not (scene_res is PackedScene):
		_errors.append("%s: FBX 未导入或加载失败 %s" % [id, recipe.fbx])
		return null
	var inst: Node = (scene_res as PackedScene).instantiate()
	var def := AvatarPartDef.new()
	def.id = id
	def.slot = StringName(String(recipe.slot))
	def.attach = String(recipe.attach)
	def.tier = int(recipe.get("tier", 0))
	var materials := _build_materials(recipe)
	## recipe.mesh_name 对 socket 部件通常是 JSON null（键存在但值为 null）；Dictionary.get()
	## 的 default 只在键不存在时生效，因此不能直接 String(recipe.get("mesh_name", ""))——
	## 那会对 null 调用 String() 构造器而报错。统一走 _str_or_empty 兜底成空字符串。
	var mesh_name := _str_or_empty(recipe.get("mesh_name"))
	var res_path := ""
	if def.attach == "mesh":
		var mi := _find_mesh_instance(inst, mesh_name)
		if mi == null:
			_errors.append("%s: FBX 内找不到子网格 '%s'" % [id, mesh_name])
			inst.free()
			return null
		var mesh := (mi.mesh as ArrayMesh).duplicate(true) as ArrayMesh
		for s in mesh.get_surface_count():
			mesh.surface_set_material(s, materials[mini(s, materials.size() - 1)])
		def.mesh = mesh
		def.skin = mi.skin.duplicate(true) if mi.skin else null
		res_path = "%s/%s.res" % [PARTS_DIR, id]
	else:
		var scene_path := "%s/%s_scene.tscn" % [PARTS_DIR, id]
		var root := _build_socket_scene(inst, materials, int(recipe.get("tier", 0)), mesh_name, id)
		if root == null:
			_errors.append("%s: socket FBX 内没有网格" % id)
			inst.free()
			return null
		var packed := PackedScene.new()
		packed.pack(root)
		ResourceSaver.save(packed, scene_path)
		root.free()
		def.scene = load(scene_path)
		var off = recipe.get("offset")
		if typeof(off) == TYPE_DICTIONARY:
			def.offset_pos = _v3(off.pos)
			def.offset_rot_deg = _v3(off.rot)
			def.offset_scale = _v3(off.scale, Vector3.ONE)
		res_path = "%s/%s.res" % [PARTS_DIR, id]
	inst.free()
	var err := ResourceSaver.save(def, res_path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		_errors.append("%s: 保存失败 err=%d" % [id, err])
		return null
	var thumb_path := _write_thumb(id, recipe.get("thumb_src"))
	var entry := {"id": id, "slot": String(recipe.slot), "attach": def.attach, "tier": def.tier,
		"pack": "builtin", "res": res_path, "thumb": thumb_path,
		"unity_guid": String(recipe.get("unity_guid", ""))}
	if typeof(recipe.get("offset")) == TYPE_DICTIONARY:
		entry["offset"] = recipe.offset
	return entry

## AMENDMENT (controller ruling): recipes 的 materials 是数组（cloth87 等多材质部件每条 entry
## 一个材质）。空数组时回退到默认材质，避免 mesh/socket 无材质可用。
func _build_materials(recipe: Dictionary) -> Array[ShaderMaterial]:
	var mats: Array = recipe.get("materials", [])
	var result: Array[ShaderMaterial] = []
	for entry in mats:
		var params := {}
		if typeof(entry) == TYPE_DICTIONARY:
			var m: Dictionary = entry
			if m.get("albedo"):
				params["albedo_tex"] = String(m.albedo)
			if m.get("ao"):
				params["ao_tex"] = String(m.ao)
			var floats = m.get("floats", {})
			if typeof(floats) == TYPE_DICTIONARY:
				for k in floats:
					params[k] = floats[k]
		result.append(AvatarMaterialFactory.create(params))
	if result.is_empty():
		result.append(AvatarMaterialFactory.create({}))
	return result

func _str_or_empty(v) -> String:
	## JSON null 在 GDScript 里是 TYPE_NIL；对它调用 String() 构造器会报错（"Nonexistent
	## 'String' constructor"），必须先判空。用于 recipe 里可能是 null 的字符串字段（如
	## socket 部件的 mesh_name）。
	return String(v) if typeof(v) == TYPE_STRING else ""

func _find_mesh_instance(root: Node, mesh_name: String) -> MeshInstance3D:
	var stack: Array = [root]
	var first: MeshInstance3D = null
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			if first == null:
				first = n
			if String(n.name).to_lower() == mesh_name.to_lower():
				return n
		for c in n.get_children():
			stack.append(c)
	return first if mesh_name.is_empty() else null

func _build_socket_scene(fbx_root: Node, materials: Array[ShaderMaterial], tier: int, mesh_name: String, id: String) -> Node3D:
	## 收集 FBX 中的网格烘成静态 MeshInstance3D；tier==1 时保留 AnimationPlayer。
	## mesh_name 非空时只收名字匹配（不区分大小写）的 MeshInstance3D——避免像 glass0/hairhat0
	## 这类 socket 挂载件误配到共享骨架 FBX（如 SK_DtBase.fbx）时，把整套身体网格都打包进
	## socket 场景。mesh_name 为空时保持"全收"的旧行为，但收集数 >3 视为疑似打包了整套 FBX，
	## 报错而非静默产出坏资产——调用方需要为该部件指定 mesh_name 或在 overrides.json 里修正 fbx。
	var root := Node3D.new()
	root.name = "SocketPart"
	var found := false
	var collected := 0
	var stack: Array = [fbx_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null and (mesh_name.is_empty() or String(n.name).to_lower() == mesh_name.to_lower()):
			found = true
			collected += 1
			var mi := MeshInstance3D.new()
			mi.name = n.name
			var mesh := (n.mesh as ArrayMesh).duplicate(true) as ArrayMesh
			for s in mesh.get_surface_count():
				mesh.surface_set_material(s, materials[mini(s, materials.size() - 1)])
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.transform = _global_in_fbx(n as Node3D, fbx_root)
			root.add_child(mi)
			mi.owner = root
		for c in n.get_children():
			stack.append(c)
	if mesh_name.is_empty() and collected > 3:
		_errors.append("%s: socket 场景收集了 %d 个网格，疑似打包了整套 FBX——请为该部件指定 mesh_name 或修正 fbx" % [id, collected])
	if tier == 1:
		var src_player := _find_anim_player(fbx_root)
		if src_player:
			var player := AnimationPlayer.new()
			player.name = "AnimationPlayer"
			var lib := AnimationLibrary.new()
			for anim_name in src_player.get_animation_list():
				lib.add_animation(anim_name, src_player.get_animation(anim_name).duplicate(true))
			player.add_animation_library("", lib)
			root.add_child(player)
			player.owner = root
	return root if found else null

## 网格相对 fbx_root 的全局变换。
##
## 必须走全局而不是 node.transform（历史缺陷）：BoneAttachment3D 那层的变换在场景未进树时
## 读出来是单位阵，真正的值是它所绑骨骼的 global rest。两族源 FBX 因此落在不同坐标系里——
##   SM_*：网格挂在 FBX 自带骨架的 BoneAttachment3D 下，顶点等价于建模在骨骼系；
##   SK_*：网格直挂 Skeleton3D，顶点建模在根坐标系。
## 只取局部变换会把前者那层丢掉，装配时又统一绑到目标骨骼，于是 SK_ 族凭空多吃一次旋转
## （实测 hairhat37 躺倒 90° 并甩出头顶 0.29m）。烘全局后两族统一落在 FBX 根坐标系，
## 再由 assembler 的 socket 帧（骨骼 rest 基的逆）搬回模型系，两边才对齐。
static func _global_in_fbx(node: Node3D, fbx_root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != fbx_root and cur is Node3D:
		var ba := cur as BoneAttachment3D
		if ba != null:
			## BoneAttachment3D 自身 transform 由骨骼姿势驱动，此处用绑定骨骼的 global rest 代替
			var skel := ba.get_parent() as Skeleton3D
			var idx := skel.find_bone(ba.bone_name) if skel != null else -1
			if idx >= 0:
				t = skel.get_bone_global_rest(idx) * t
		else:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

func _find_anim_player(root: Node) -> AnimationPlayer:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func _write_thumb(id: String, thumb_src) -> String:
	var dst := "%s/%s.png" % [THUMBS_DIR, id]
	if thumb_src != null and String(thumb_src) != "" and FileAccess.file_exists(String(thumb_src)):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(String(thumb_src)), ProjectSettings.globalize_path(dst))
		return dst
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.6, 0.6, 0.65))
	img.save_png(ProjectSettings.globalize_path(dst))
	return dst

func _v3(a, fallback := Vector3.ZERO) -> Vector3:
	if typeof(a) == TYPE_ARRAY and a.size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback
