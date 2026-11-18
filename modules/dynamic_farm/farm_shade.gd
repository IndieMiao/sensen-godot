extends Node
const GroundShade = preload("res://modules/render/ground_shade.gd")
const CHUNK := 32
const MAX_MASKS := 64
const SUN_DEGREES := Vector3(-51,-38,0)
var entries: Array = []
var complete := false
var metrics := {"mask_count":0,"mask_r8_bytes":0,"mode":"hardware"}

static func _chunks(data: Dictionary, walk: RefCounted) -> Dictionary:
	var out := {}
	for cell: Dictionary in data.cells:
		var chunk := Vector2i(int(cell.x)/CHUNK,int(cell.y)/CHUNK)
		if out.has(chunk): continue
		var low: Vector2 = Vector2(chunk*CHUNK)-walk.center_grid
		var high: Vector2 = Vector2((chunk+Vector2i.ONE)*CHUNK).min(Vector2(data.grid_size))-walk.center_grid
		out[chunk] = Rect2(Vector2(low.x,-high.y)*data.cell_m,(high-low)*data.cell_m)
	return out

static func affected(layout: Array, chunks: Dictionary) -> Dictionary:
	var selected := {}
	var to_sun := Basis.from_euler(SUN_DEGREES * PI / 180.0).z.normalized()
	for item: Dictionary in layout:
		if not item.shadow or item.box.end.y < GroundShade.MIN_H:
			continue
		var caster := GroundShade.caster_of(item.box)
		if caster.w > GroundShade.MAX_R: continue
		var shade := GroundShade.shade_of(caster,to_sun)
		var radius: float = maxf(shade[1],shade[2]) + GroundShade.BLUR_M * 0.5
		var bounds := Rect2(shade[0]-Vector2.ONE*radius,Vector2.ONE*radius*2)
		for key: Vector2i in chunks:
			if chunks[key].intersects(bounds): selected[key] = true
	return selected

static func enforce_budget(plan: Dictionary, data: Dictionary, walk: RefCounted) -> void:
	var chunks := _chunks(data,walk)
	var rejected := 0
	while affected(plan.layout,chunks).size() > MAX_MASKS:
		var removed := false
		for i in range(plan.layout.size()-1,-1,-1):
			var item: Dictionary = plan.layout[i]
			if not item.shadow or item.box.end.y < GroundShade.MIN_H: continue
			if item.solid:
				for cell: Vector2i in item.cells: walk.blocked.erase(cell)
			plan.roles[item.role].accepted -= 1
			plan.roles[item.role].rejected += 1
			plan.layout.remove_at(i)
			rejected += 1
			removed = true
			break
		if not removed: break
	plan.shadow_budget_rejected = rejected
	var signature := PackedStringArray()
	for item: Dictionary in plan.layout:
		signature.append(str(item.asset)+":"+str(item.transform))
	plan.layout_sha256 = "\n".join(signature).sha256_text()

func setup(ground_root: Node3D, props: Node3D, plan: Dictionary, data: Dictionary, walk: RefCounted) -> void:
	if DisplayServer.get_name() == "headless":
		metrics.mode = "headless-no-render"
		complete = true
		return
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		complete = true
		return
	metrics.mode = "ground_shade"
	var selected := affected(plan.layout,_chunks(data,walk))
	for chunk: Dictionary in ground_root.get_meta("shade_chunks",[]):
		# Match the frozen ground chunk by its position, not an old pond rectangle.
		var matching := false
		for key: Vector2i in selected:
			var low: Vector2 = Vector2(key*CHUNK)-walk.center_grid
			if is_equal_approx(chunk.rect.position.x,low.x*data.cell_m) and is_equal_approx(chunk.rect.end.y,-low.y*data.cell_m):
				matching = true
				break
		if not matching: continue
		var shade := GroundShade.new()
		shade.ground = chunk.meshes[0]
		shade.casters_root = props
		shade.rect = chunk.rect
		shade.draw_on_ready = false
		add_child(shade)
		entries.append({"shade":shade,"meshes":chunk.meshes,"applied":false})
		metrics.mask_count += 1
		metrics.mask_r8_bytes += roundi(chunk.rect.size.x*GroundShade.PX_M)*roundi(chunk.rect.size.y*GroundShade.PX_M)
		shade.redraw()
	if entries.is_empty(): complete = true

func _process(_dt: float) -> void:
	if complete: return
	var done := true
	for entry: Dictionary in entries:
		if entry.applied: continue
		var shade: Node = entry.shade
		if shade.mask == null:
			done = false
			continue
		for mesh: MeshInstance3D in entry.meshes:
			var material := mesh.material_override as ShaderMaterial
			material.set_shader_parameter("shade_mask",shade.mask)
			material.set_shader_parameter("shade_rect",Vector4(shade.rect.position.x,shade.rect.position.y,shade.rect.size.x,shade.rect.size.y))
			material.set_shader_parameter("shade_opacity",shade.opacity)
		entry.applied = true
	complete = done
