extends Control
## The game simulation stays unchanged; interpolation and glyphs are presentation only.

var model: Dictionary = {}:
	set(value):
		var reset := model.is_empty() or value.is_empty()
		model = value
		if reset:
			_display_progress = float(value.get("progress", 0))
			_last_progress = _display_progress
			_particles.clear()
			_feedback_cooldown = 0
			_direction = 0
		queue_redraw()
var bar_size := 0.34
var fish_texture: Texture2D
var feedback_active := false
var _display_progress := 0.0
var _last_progress := 0.0
var _direction := 0
var _feedback_cooldown := 0.0
var _particles: Array[Dictionary] = []
var _styles: Dictionary = {}
var _font: Font
var _clock := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(64, 170)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	_styles.frame = _surface(GameUi.PAPER, GameUi.BLUE, 10)
	_styles.water = _surface(Color("cce9f4"), Color("a5bedf"), 7)
	_styles.zone = _surface(Color("65d9ce"), GameUi.PAPER, 7)
	_styles.meter = _surface(Color("e4e8fa"), GameUi.BLUE, 7)
	_styles.fill = _surface(GameUi.GREEN, Color.TRANSPARENT, 4)
	_styles.fill.set_border_width_all(0)

func _surface(color: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := GameUi.surface(color, 0, radius)
	style.border_color = border
	style.shadow_size = 0
	return style

func _process(dt: float) -> void:
	if not is_visible_in_tree() or model.is_empty(): return
	_clock += dt
	_feedback_cooldown = maxf(0, _feedback_cooldown - dt)
	var progress := float(model.get("progress", 0))
	var change := progress - _last_progress
	if absf(change) > 0.0001:
		var direction := 1 if change > 0 else -1
		if feedback_active and (_feedback_cooldown <= 0 or direction != _direction):
			var meter := meter_rect()
			_particles.append({"age": 0.0, "symbol": "+" if direction > 0 else "−", "direction": direction,
				"origin": Vector2(meter.get_center().x, meter.end.y - meter.size.y * progress)})
			if _particles.size() > 6: _particles.pop_front()
			_feedback_cooldown = 0.24
		_direction = direction
	_last_progress = progress
	_display_progress = lerpf(_display_progress, progress, 1.0 - exp(-dt * 18.0))
	for particle in _particles: particle.age = float(particle.age) + dt
	_particles = _particles.filter(func(p): return float(p.age) < 0.72)
	queue_redraw()

func meter_rect() -> Rect2:
	return Rect2(size.x - 17, 20, 14, size.y - 27)

func _draw() -> void:
	if _styles.is_empty(): return
	var area := Rect2(3, 20, size.x - 28, size.y - 27)
	draw_style_box(_styles.frame, area.grow(3))
	draw_style_box(_styles.water, area)
	# Quiet depth lines make the fish track easier to read without hiding the water behind it.
	for i in range(1, 5):
		var y := area.position.y + area.size.y * float(i) / 5.0
		draw_line(Vector2(area.position.x + 5, y), Vector2(area.end.x - 5, y), Color(0.85, 1, 0.93, 0.12), 1, true)
	if model.is_empty(): return
	var height := area.size.y * bar_size
	var bar := Rect2(area.position.x + 3, area.end.y - float(model.bar) * area.size.y - height * 0.5, area.size.x - 6, height)
	draw_style_box(_styles.zone, bar)
	draw_line(bar.position + Vector2(6, 3), Vector2(bar.end.x - 6, bar.position.y + 3), Color("efffdf"), 1.5, true)
	var center := Vector2(area.get_center().x, area.end.y - float(model.fish) * area.size.y)
	if fish_texture: draw_texture_rect(fish_texture, Rect2(center - Vector2(17, 13), Vector2(34, 26)), false)
	else: draw_circle(center, 8, Color("e5a055"))
	var meter := meter_rect()
	draw_style_box(_styles.meter, meter)
	var inner := meter.grow(-2)
	var fill := clampf(_display_progress, 0, 1)
	var color := GameUi.GREEN if _direction >= 0 else GameUi.CORAL
	if fill < 0.16 and _direction < 0: color = GameUi.CORAL.darkened(0.12)
	_styles.fill.bg_color = color
	var filled := Rect2(inner.position.x, inner.end.y - inner.size.y * fill, inner.size.x, inner.size.y * fill)
	if filled.size.y > 0.5:
		draw_style_box(_styles.fill, filled)
		draw_line(Vector2(filled.position.x + 2, filled.end.y - 3), Vector2(filled.position.x + 2, filled.position.y + 3), Color(1, 1, 0.84, 0.3), 2, true)
		var cap := Vector2(meter.get_center().x, filled.position.y + 2)
		draw_circle(cap, 5, Color(color, 0.15 + 0.07 * sin(_clock * 5)), true, -1, true)
		draw_line(cap - Vector2(3, 0), cap + Vector2(3, 0), Color("fff5cc"), 2, true)
	var percentage := "%d%%" % roundi(float(model.get("progress", 0)) * 100)
	var label_width := _font.get_string_size(percentage, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var label_at := Vector2(meter.get_center().x - label_width * 0.5, 12)
	draw_string_outline(_font, label_at, percentage, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, GameUi.PAPER)
	draw_string(_font, label_at, percentage, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, GameUi.INK)
	for particle in _particles:
		var age := float(particle.age)
		var alpha := 1.0 - smoothstep(0.22, 0.72, age)
		var offset := Vector2(7 + sin(age * 5) * 8, -age * 37)
		var point: Vector2 = particle.origin + offset
		var ink := GameUi.GREEN if int(particle.direction) > 0 else GameUi.CORAL
		ink.a = alpha
		var symbol := str(particle.symbol)
		draw_string_outline(_font, point, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 3, Color(GameUi.PAPER, alpha))
		draw_string(_font, point, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ink)
		for i in 2:
			draw_circle(point + Vector2(-4 - i * 3, 5 + i * 5), (1.2 - i * 0.3) * alpha, Color(ink, alpha * 0.55), true, -1, true)
