extends P0Room
## The farmhouse interior (plan §7.7 / q(14)): Homestead Lv1–4 live in the Basic Room, whose stove corner is the
## P0 kitchen; the place chip reads "Shanghai · Farmhouse" (LOCK-06 K-1). Entered from the farm (the door card's
## Kitchen row, or walking into the doorway); its door leaves back to the farm.
## Placeholder period: the accepted Basic Room art with assets/p0/rooms/farmhouse.anchors.json; the final
## farmhouse_lv1 (SGODOT-213) swaps the art and brings the anchors in its own layout.json.
## Cooking is the 3D stove stage (P0Kitchen, LOCK-20 v5): tap the stove → walk there → the cooking drawer.

const STOVE := "use_stove_1"

var kitchen: P0Kitchen

func _init() -> void:
	anchors_path = "res://assets/p0/rooms/farmhouse.anchors.json"
	place_name = "Farmhouse"
	exit_text = "Door · Back to farm"

## The space commands are sent from (SGODOT-228 PR #16, Rest needs ≥ 2 h away, q(41)): the farmhouse is home.
func p0_space() -> String: return "home"

func _room_ready() -> void:
	kitchen = P0Kitchen.new(self)
	add_child(kitchen)

# ---------------------------------------------------------------- stove (COOK-1)
## Finger card and STATE-ICONS badge over the stove: Empty / countdown / Ready (plan §7.2.2 step 1).
func _marker(n: String, v: Dictionary) -> Dictionary:
	if kitchen and kitchen.busy(): return {}   # the drawer or the pot owns the screen
	if n != STOVE: return super(n, v)
	var st = P0KitchenLogic.stove(v)
	if st == null: return {text = "Stove 1/1 · Empty · Tap to cook", badge = "available", icon = P0Logic.icon("stove")}
	var left := float(st.get("ready_in", 0))
	if left <= 0.0:
		var dish = st.get("dish", null)
		return {text = "Stove · Ready · " + (P0Logic.item_name(v, str(dish)) if dish != null else "Unknown dish"), badge = "ready"}
	var clock := P0Logic.duration(left)
	return {text = "Stove 1/1 · Cooking " + clock, badge = "countdown", caption = clock}

func _on_facility(n: String) -> void:
	if n == STOVE: open_stove()

## Empty → the cooking drawer; cooking → watch the pot; ready → the dish comes out (COOK-1 interactions).
func open_stove(tab := "cookbook") -> void:
	if rt == null or kitchen == null or kitchen.busy(): return
	var st = P0KitchenLogic.stove(rt.session.current())
	if st == null: kitchen.open(tab)
	elif float(st.get("ready_in", 0)) <= 0.0: kitchen.serve([])
	else: kitchen.watch(st)

## The cooking drawer from elsewhere (the Energy card's Cook tile, dev steps): walk to the stove first.
func p0_open_kitchen(tab := "cookbook") -> void:
	walk_to(STOVE, func(): open_stove(tab))

func p0_event(ev: Dictionary, v: Dictionary) -> void:
	match str(ev.get("kind", "")):
		"pot":
			var st = P0KitchenLogic.stove(v)
			if st is Dictionary: kitchen.on_pot(st)
		"dish": kitchen.on_collected()

func _room_frame(v: Dictionary, _dt: float) -> void:
	if kitchen == null: return
	var st = P0KitchenLogic.stove(v)
	var cooking: bool = st != null and float(st.get("ready_in", 0)) > 0.0
	if kitchen.phase == "idle" and kitchen.stage.is_cooking() != cooking: kitchen.stage.set_cooking(cooking)
	if kitchen.phase == "serve" and st == null: kitchen.on_collected()   # collected (or refused as empty)

func p0_tap(screen: Vector2) -> void:
	if kitchen and kitchen.tap(): return
	super(screen)

## Walking away from the pot stops watching it; the pot keeps cooking (§7.2.3).
func _on_joystick(v: Vector2) -> void:
	if v != Vector2.ZERO and kitchen and kitchen.phase == "watch": kitchen.stop_watching()

## Back while watching the pot steps back from it; then the room's own Back (drawer, then the door).
func is_back_navigation_locked() -> bool:
	if kitchen and kitchen.phase == "watch":
		kitchen.stop_watching()
		return true
	if kitchen and kitchen.phase == "serve": return true
	return super()

func p0_dev(step: PackedStringArray) -> bool:
	match step[0]:
		"stove": open_stove(step[1] if step.size() > 1 else "cookbook")
		"kitchen": p0_open_kitchen(step[1] if step.size() > 1 else "cookbook")
		"put":
			if kitchen.phase != "compose": kitchen.open("experiment")
			if kitchen.drawer and kitchen.drawer.tab != "experiment": kitchen.drawer.tab = "experiment"
			kitchen._on_ingredient(step[1], Vector2.INF)
		_: return super(step)
	return true

func p0_until(n: String) -> bool:
	match n:
		"cooking": return kitchen != null and kitchen.phase == "watch"
		"compose": return kitchen != null and kitchen.phase == "compose"
		"idle": return (kitchen == null or not kitchen.busy()) and super(n)
	return super(n)
