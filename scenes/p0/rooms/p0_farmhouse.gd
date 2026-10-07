extends P0Room
## The farmhouse interior (plan §7.7 / q(14)): Homestead Lv1–4 live in the Basic Room, whose stove corner is the
## P0 kitchen; the place chip reads "Shanghai · Farmhouse" (LOCK-06 K-1). Entered from the farm (the door card's
## Kitchen row, or walking into the doorway); its door leaves back to the farm.
## Placeholder period: the accepted Basic Room art with assets/p0/rooms/farmhouse.anchors.json; the final
## farmhouse_lv1 (SGODOT-213) swaps the art and brings the anchors in its own layout.json.
## The stove still opens the interim cooking panel and 2D pot until the 3D stove stage lands (SGODOT-226 B).

const STOVE := "use_stove_1"

var _cooking: P0Cooking

func _init() -> void:
	anchors_path = "res://assets/p0/rooms/farmhouse.anchors.json"
	place_name = "Farmhouse"
	exit_text = "Door · Back to farm"

## The space commands are sent from (SGODOT-228 PR #16, Rest needs ≥ 2 h away, q(41)): the farmhouse is home.
func p0_space() -> String: return "home"

# ---------------------------------------------------------------- stove (COOK-1)
## Finger card and STATE-ICONS badge over the stove: Empty / countdown / Ready (plan §7.2.2 step 1).
func _marker(n: String, v: Dictionary) -> Dictionary:
	if _cooking != null: return {}   # the pot fills the screen
	if n != STOVE: return super(n, v)
	var st = v.get("cooking", {}).get("stove", null)
	if st == null: return {text = "Stove 1/1 · Empty · Tap to cook", badge = "available", icon = P0Logic.icon("stove")}
	var left := float(st.get("ready_in", 0))
	if left <= 0.0:
		var dish = st.get("dish", null)
		return {text = "Stove · Ready · " + (P0Logic.item_name(v, str(dish)) if dish != null else "Unknown dish"), badge = "ready"}
	var clock := P0Logic.duration(left)
	return {text = "Stove 1/1 · Cooking " + clock, badge = "countdown", caption = clock}

func _on_facility(n: String) -> void:
	if n == STOVE: open_stove()

## Empty → the cooking panel; cooking → watch the pot; ready → collect (COOK-1 interactions).
func open_stove() -> void:
	if rt == null or _cooking != null: return
	var st = rt.session.current().get("cooking", {}).get("stove", null)
	if st == null: rt.ui.open_kitchen()
	elif float(st.get("ready_in", 0)) <= 0.0: rt.session.send({"type": "collect", "taps": []}, P0Session.ui_key({"type": "collect"}))
	else: _watch_pot(st)

func p0_event(ev: Dictionary, v: Dictionary) -> void:
	if str(ev.get("kind", "")) == "pot":
		var st = v.get("cooking", {}).get("stove", null)
		if st is Dictionary: _watch_pot(st)

func _watch_pot(st: Dictionary) -> void:
	if _cooking != null: return
	var v := rt.session.current()
	var dish = st.get("dish", null)
	var heats: Array = st.get("heats", [])
	var teach := not heats.is_empty() and float(heats[0].get("width", 0)) >= 0.5
	_cooking = P0Cooking.new(rt.ui, st, P0Logic.item_name(v, str(dish)) if dish != null else "Unknown dish", teach)
	_cooking.finished.connect(func(taps: Array):
		_cooking = null
		rt.session.send({"type": "collect", "taps": taps}))
	_cooking.left.connect(func():
		_cooking = null
		rt.ui.toast("The pot keeps cooking · tap the stove to collect"))
	rt.ui.root.add_child(_cooking)

func p0_tap(screen: Vector2) -> void:
	if _cooking != null: return
	super(screen)

## Back while the pot is on screen leaves the pot (it keeps cooking, plan §7.2.3); then the room's own Back.
func is_back_navigation_locked() -> bool:
	if _cooking != null:
		var pot := _cooking
		_cooking = null
		pot.left.emit()
		pot.queue_free()
		return true
	return super()

func _exit_tree() -> void:
	if _cooking != null:
		_cooking.queue_free()
		_cooking = null
	super()

func p0_dev(step: PackedStringArray) -> bool:
	if step[0] == "stove":
		open_stove()
		return true
	return super(step)

func p0_until(n: String) -> bool:
	match n:
		"cooking": return _cooking != null
		"idle": return _cooking == null and super(n)
	return super(n)
