extends Control
## The market (Jasmine) and the carpenter (Scott) of the dynamic farm (C-59, the C-30 0.4.3 plan). Since C-115 they
## stand in the Washington Square room (parcel_outpost.gd), which opens this greeting over itself when one is tapped.
## Each keeper greets first in the UI v3 NPC card (UiNpcCard, C-105; the main farm's KeeperGreeting before); their looks are built from the
## existing avatar parts and their portraits drawn from them (P0KeeperPortraits), with no painted art or new model
## (C-30#29 question 6).
## - Jasmine introduces coins in a line the first time she is met (kept on this device per parcel), then says hello;
##   Trade opens her counter (parcel_counter.gd), which sells through the parcel save's `sell` command (C-58) and,
##   since C-149, sells carrot seeds through `buy` (the P0 keeper greeting's Trade, LOCK-16).
## - Scott gives one Coop Blueprint once the parcel has sold something (`claim_blueprint`, C-58 rules: C-30#29
##   question 5); it only goes into the bag, building comes later (0.4.4).
## - Since C-152 Scott also upgrades the farm: his greeting's `Upgrade Farm` opens the upgrade sheet (parcel_upgrade.gd,
##   P0's HOME-1 in the kit), whose Upgrade sends `upgrade_farm` (coins, Timber and Stone; more Max Energy and wells).
## - Since C-181 Scott sells the blueprints the rules price in coins (`economy.blueprints.<id>.coins`, the barn's 600):
##   one key each, `Buy Barn Blueprint · 600 coins`, until it is bought; below the blueprint's farm level (`min_level`,
##   the barn's 2, C-192) it reads `Farm Lv2 needed`, short of coins P0's `Need N more coins` (LOCK-10), and a tap says
##   so. It sends `claim_blueprint`, which takes the coins on the server. C-182: the sheep pen's (1,200) also waits for 15
##   delivered requests (`min_requests`), read `Need N more requests` before the level.
## - Since C-191 the room's Request Board opens here too (who = BOARD): no keeper and no greeting, the board drawer
##   (parcel_board.gd) straight away; its keys send `accept_request` / `deliver_request` / `drop_request`, and closing
##   it leaves.
## - C-197 seed aid (owner SEN-Q-281): when her greeting opens and the read save has no coins for a seed, no seeds and no
##   crops, the town sends `claim_seed_aid` once (ParcelFarm.seed_aid_refusal decides whether to ask; the server decides);
##   given, her greeting line says so and the existing `Received … ×N` toast names the seeds. Nothing else on the card
##   changes (LOCK-16: Trade stays the one key). A refusal is silent: the greeting stays as it was.
## C-186 (C-185 §3.3–3.4, MS-13–17): a read done within `motion/delay/loadingGrace` (300) opens the greeting with its
## line; a slower one opens it at 300 with the portrait and name and three dots looping, then the line fades in and the
## keys follow. Greeting → counter / sheet hands over (the card leaves by M-05, the drawer rises 80 later); drawers leave
## sinking. Toasts sit 8 over the greeting card (its portrait and name tag included), over a drawer's fixed decision area,
## or at the foot of a drawer without one (q(16)). A grey key's tap shakes it; its toast only when the reason differs from
## the key's text (MS-02). A sale or a delivery flies its coins; an upgrade hands its needs in and shows the level-up card
## (M-12) instead of a toast, the sheet moving on to the next level when the card closes.
## The parcel save (store: read / send, parcel_farm_remote_store.gd or the local stand-in) is authoritative; this
## node draws what it answers. Coins are the parcel's own, separate from the main farm's.
signal closed

const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const ParcelItems = preload("res://modules/dynamic_farm/parcel_items.gd")
const Counter = preload("res://scenes/dynamic_farm/parcel_counter.gd")
const Upgrade = preload("res://scenes/dynamic_farm/parcel_upgrade.gd")
const Board = preload("res://scenes/dynamic_farm/parcel_board.gd")
const Portraits = preload("res://modules/p0/p0_keeper_portraits.gd")
const MARKET := "market"
const CARPENTER := "carpenter"
## C-191: the Request Board, a facility rather than a keeper.
const BOARD := "board"
const BLUEPRINT := "coop"
## Looks from catalogue parts (no NPC-only part of another keeper, no hairHat + cloth pair another NPC wears).
const NPCS := {
	MARKET: {"name": "Jasmine", "role": "Market", "title": "Jasmine's Market", "look": "parcel:jasmine",
		"slots": {"hairHat": "hairhat41", "cloth": "cloth11", "shoes": "shoes2"}},
	CARPENTER: {"name": "Scott", "role": "Carpenter", "title": "Scott's Workshop", "look": "parcel:scott",
		"slots": {"hairHat": "hairhat51", "cloth": "cloth42", "shoes": "shoes3"}},
}
## Player-visible lines, as finalised by PM in C-59#31 (C-45 / Q-61).
const LINES := {
	"intro": "Hi, I'm Jasmine! Bring me crops and wild finds, and I'll pay you in coins.",
	"hello": "Got something to sell?",
	"thanks": "Thanks! +%d coins",
	"scott_wait": "Sell something to Jasmine first.",
	"scott_give": "Here's a coop blueprint for your first sale.",
	"scott_done": "Hope the coop plans come in handy.",
	"scott_none": "Come back later.",
	"unreachable": "Could not reach your farm.",
	# C-152, as PM finalised them on SEN-C-152#29 (C-45): the greeting's key and the toast after an upgrade.
	"upgrade_key": "Upgrade Farm",
	"upgraded": "Farm Lv%d",
	"upgraded_gift": "Farm Lv%d · +%d %s",
	# C-197 seed aid: Jasmine's line when she gives the seeds (count, seed name), awaiting PM's C-45 final on SEN-C-197.
	"seed_aid": "Out of coins and seeds? Here are %d %s, on me.",
	# C-186 level-up card (C-185 §3.4): its one button, the copy PM settled on SEN-C-186#44 (C-45).
	"level_ok": "OK",
}
const MET_PATH := "user://dynamic_farm_local/town.json"

var who := MARKET
var store: RefCounted
var parcel_id := ""
var farm := {}
var farm_version := -1
var busy := false
var stack: ModalStack
var card: UiNpcCard
var counter: Counter
var upgrade_sheet: Upgrade
var board: Board
## Server time minus this device's clock at the last answer (the board's countdowns and day run on the server's clock).
var server_offset := 0
var toast: ToastLayer
## A greeting's keys, by name (tests and the map read them).
var keys := {}
var _switching := false   # the card closes because the counter opens over it
## C-197: what the seed aid gave this visit ({item, amount}); her greeting line says so while it is set.
var aid_given := {}
var _met_path := MET_PATH
## C-186: the greeting opened before the read came back (MS-13): the line and keys reveal when it lands.
var _waited := false
var _dots: Tween
## C-186 M-12: the level-up card over everything while it shows (tests read it), and its layer.
var level_card: UiRewardMoment
var _level_layer: Control
var _handing_in := false   # MS-17: the needs are going in; a second tap does nothing

## who: MARKET, CARPENTER or BOARD; store answers read() and send(); parcel_id names the player's parcel (the met record).
static func open(parent: Node, who_: String, store_: RefCounted, parcel_id_: String, met_path := MET_PATH) -> Control:
	var town: Control = load("res://scenes/dynamic_farm/parcel_town.gd").new()
	town.who = who_
	town.store = store_
	town.parcel_id = parcel_id_
	town._met_path = met_path
	parent.add_child(town)
	return town

static func npc(role: String) -> Dictionary:
	var data: Dictionary = NPCS[role]
	Portraits.register_look(data.look, data.slots)
	return data

static func portrait(role: String, card_ := true) -> Texture2D:
	return Portraits.texture(npc(role).look, card_)

func _ready() -> void:
	name = "ParcelTown"
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	stack = ModalStack.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.closed.connect(_on_layer_closed)
	add_child(stack)
	toast = ToastLayer.new()
	add_child(toast)
	toast.shown.connect(func(_t: String, _s: int): _place_toast())
	stack.opened.connect(func(_l: int, c: Control): _follow(c))
	await reload()

## Reads the parcel save and greets again; a failed read says so and offers Retry.
func reload() -> void:
	if who == BOARD:
		await _reload_board()
		return
	busy = true
	# MS-13: the greeting waits up to `motion/delay/loadingGrace` for the read; past it, it opens with the dots.
	if card != null and is_instance_valid(card): _greet()
	else: _open_late.call_deferred()
	var result: Dictionary = await store.read()
	busy = false
	if not is_inside_tree(): return
	if card == null or not is_instance_valid(card): _greet()
	if not _adopt(result) and farm.is_empty():
		_stop_dots()
		card.line = LINES.unreachable
		var retry := UiCommandButton.new("Retry", UiCommandButton.Kind.SECONDARY)
		retry.name = "Retry"
		retry.activated.connect(reload)
		card.content.add_child(retry)
		keys.retry = retry
		return
	_greet()
	if who == MARKET and aid_given.is_empty() and ParcelFarm.seed_aid_refusal(ParcelFarm.rules(), farm, server_now()).code == "":
		await claim_seed_aid()

func _adopt(result: Dictionary) -> bool:
	var next := ParcelFarm.normalize(result.get("farm"))
	if next.is_empty(): return false
	farm = next
	farm_version = int(result.get("farm_version", farm_version))
	if result.has("server_time"): server_offset = int(result.server_time) - _device_ms()
	if counter != null and is_instance_valid(counter): counter.refresh(farm)
	if upgrade_sheet != null and is_instance_valid(upgrade_sheet): upgrade_sheet.refresh(farm)
	if board != null and is_instance_valid(board): board.refresh(farm)
	return true

func _device_ms() -> int: return int(Time.get_unix_time_from_system() * 1000.0)

## The server's clock now (the last answer's server_time carried forward on this device's clock).
func server_now() -> int: return _device_ms() + server_offset

# ---------------------------------------------------------------- the Request Board (C-191)
## The board drawer at once (`…` until the save is read), then the save; a failed read says so and offers Retry.
func _reload_board() -> void:
	if board == null or not is_instance_valid(board): _open_board()
	busy = true
	if farm.is_empty(): board.show_status(Board.COPY.loading)
	var result: Dictionary = await store.read()
	busy = false
	if not is_inside_tree() or board == null or not is_instance_valid(board): return
	if not _adopt(result) and farm.is_empty(): board.show_status(Board.COPY.unreachable, reload)

func _open_board() -> void:
	board = Board.new(farm)
	board.now_ms = server_now
	board.close_requested.connect(func(): stack.close_drawer())
	board.command_requested.connect(board_command)
	board.refill_due.connect(func(): if not busy: _reload_board())
	board.rise = true
	stack.open_drawer(board, {"animate_out": true})
	_place_toast()

## A board key's command. A delivery floats its coins up from its key; a drop shows BOARD-DROPPED. A refusal toasts
## what the server said (the keys already carry the gaps it checks).
func board_command(command: Dictionary) -> Dictionary:
	if busy or board == null or not is_instance_valid(board): return {}
	var at := board.key_point(int(command.get("request", 0)))
	var coins := int(farm.get("coins", 0))
	var delivering := str(command.type) == "deliver_request"
	# MS-16: the list stays as drawn while the delivery plays (the answer's refilled slot comes in after it).
	if delivering: board.hold_for_delivery()
	var result := await _send(command)
	if board == null or not is_instance_valid(board): return result
	if not result.get("ok", false):
		if delivering: board.release()
		return result
	match str(command.type):
		"deliver_request": board.celebrate_delivery(int(command.get("request", 0)), coins, int(farm.coins), at)
		"drop_request": board.dropped()
	return result

## MS-13: still reading after the grace: open the greeting now, the dots looping in its line.
func _open_late() -> void:
	if not is_inside_tree() or not busy or (card != null and is_instance_valid(card)): return
	await get_tree().create_timer(UiKit.secs(UiTokens.MOTION_DELAY_LOADING_GRACE), true).timeout
	if not is_inside_tree() or not busy or (card != null and is_instance_valid(card)) or who == BOARD: return
	_waited = true
	_greet()

## The keeper's greeting card: a fresh one each time it is shown (the read, a sale, the blueprint).
func _greet() -> void:
	var data := npc(who)
	keys = {}
	if card == null or not is_instance_valid(card):
		card = UiNpcCard.new(portrait(who), "%s · %s" % [data.role, data.name])
		card.place_centred()
		card.close_requested.connect(close)
		stack.open_card(card, {"animate_out": true})
		card.play_in(stack.get_node_or_null(^"ScrimCard"))
		card.resized.connect(_place_toast)
		_place_toast()
	for c in card.content.get_children():
		c.hide()
		c.queue_free()
	if farm.is_empty():
		card.line = "…" if busy else card.line
		if busy: _start_dots()
		return
	var reveal := _waited
	_waited = false
	_stop_dots()
	if who == MARKET: _greet_market()
	else: _greet_carpenter()
	if reveal: _reveal()

## MS-13: three dots loop in the line slot (one cycle per `motion/duration/dotsLoop`, 1600); reduced: still dots.
func _start_dots() -> void:
	if card == null or (_dots != null and _dots.is_valid()): return
	var l := card.line_label()
	l.text = "···"
	if UiMotion.reduced: return
	_dots = UiMotion.tween(l, UiTokens.MOTION_EASING_LINEAR)
	_dots.set_loops()
	_dots.tween_method(func(v: float): l.text = "·".repeat(1 + int(v) % 3), 0.0, 2.999,
		UiKit.secs(UiTokens.MOTION_DURATION_DOTS_LOOP_MS))

func _stop_dots() -> void:
	if _dots != null and _dots.is_valid(): _dots.kill()
	_dots = null

## MS-13: the line fades in (120) and the keys follow (160), once the read lands on a card opened early.
func _reveal() -> void:
	if card == null or UiMotion.reduced: return
	for part: CanvasItem in [card.line_label(), card.content]:
		part.modulate.a = 0.0
	UiMotion.tween(card.line_label(), UiTokens.MOTION_EASING_STANDARD) \
		.tween_property(card.line_label(), ^"modulate:a", 1.0, UiKit.secs(UiTokens.MOTION_DURATION_FAST_MS))
	var keys_in := UiMotion.tween(card.content, UiTokens.MOTION_EASING_STANDARD)
	keys_in.tween_interval(UiKit.secs(UiTokens.MOTION_DURATION_FAST_MS))
	keys_in.tween_property(card.content, ^"modulate:a", 1.0, UiKit.secs(UiTokens.MOTION_DURATION_QUICK_MS))

## q(16) / C-185 §3.5 (C-186#9): where the toast sits. Over an open drawer's fixed decision area, or at its foot (232 wide)
## without one; over the centred greeting, 8 above its top edge (`size/toast/aboveCard`) — the portrait and name tag that
## stand over the card included — so it never covers her line, head or name; else the default.
func _place_toast() -> void:
	if toast == null or not toast.is_inside_tree(): return
	var d: Control = stack.drawer() if stack != null else null
	if d is UiDrawer and is_instance_valid(d):
		var area := (d as UiDrawer).action_area()
		if area != null: toast.anchor_above(area)
		else:
			var foot := d.get_global_rect().end.y - (d as UiDrawer).pad - (d as UiDrawer).safe_bottom
			toast.anchor_bottom(_toast_y(foot), ToastLayer.NARROW_WIDTH)
		return
	if card != null and is_instance_valid(card) and card.is_inside_tree():
		toast.anchor_bottom(_toast_y(card_top()) - UiTokens.SIZE_TOAST_ABOVE_CARD)
		return
	toast.anchor_above(null)

## The greeting's top edge on screen: the card's, or its portrait's or name tag's where they stand over it.
func card_top() -> float:
	var top := card.get_global_rect().position.y
	for part: Control in [card.find_child("Portrait", false, false) as Control, card.name_tag()]:
		if part != null and part.visible: top = minf(top, part.get_global_rect().position.y)
	return top

func _toast_y(global_y: float) -> float:
	return (toast.get_global_transform().affine_inverse() * Vector2(0.0, global_y)).y

## A layer opened: the toast follows it, as it moves (a drawer rising) and changes (its decision area appearing).
func _follow(c: Control) -> void:
	if c == null: return
	if not c.item_rect_changed.is_connected(_place_toast): c.item_rect_changed.connect(_place_toast)
	_place_toast()

## MS-02: a grey key was tapped. It shakes; the toast only when `reason` is not already the key's text.
func refused(key: Control, reason: String) -> void:
	UiMotion.shake(key)
	var shown := (key as Button).text if key is Button else ""
	if reason != shown: toast.show_toast(reason, ToastLayer.Severity.INFO)

func _greet_market() -> void:
	if not aid_given.is_empty():
		var seed := ParcelItems.name_of(str(aid_given.item))
		var amount := int(aid_given.amount)
		card.line = LINES.seed_aid % [amount, P0Logic.plural(seed) if amount > 1 else seed]
	elif not met(MARKET):
		card.line = LINES.intro
		mark_met(MARKET)
	elif card.line == "" or card.line == "…" or card.line == LINES.intro: card.line = LINES.hello
	var trade := UiCommandButton.new("Trade")
	trade.name = "Trade"
	trade.activated.connect(open_counter)
	card.content.add_child(trade)
	keys.trade = trade

func _greet_carpenter() -> void:
	var rule: Dictionary = ParcelFarm.rules().get("economy", {}).get("blueprints", {}).get(BLUEPRINT, {})
	if rule.is_empty(): card.line = LINES.scott_none
	elif farm.blueprints_claimed.has(BLUEPRINT):
		card.line = LINES.scott_done
	elif int(farm.sales) < int(rule.min_sales):
		card.line = LINES.scott_wait
	else:
		card.line = LINES.scott_give
		var take := UiCommandButton.new("Take Blueprint")
		take.name = "Take"
		take.sends = true
		take.activated.connect(claim_blueprint)
		card.content.add_child(take)
		keys.take = take
	# C-181: the blueprints he sells for coins (the barn's), each until bought: the primary key when it can be bought and
	# nothing comes before it, else secondary (a short one reads its gap and leaves Upgrade Farm the primary key).
	for id: String in priced_blueprints():
		var gap := buy_gap(id)
		var lead := keys.is_empty() and gap.is_empty()
		var buy_key := UiCommandButton.new(buy_label(id), UiCommandButton.Kind.PRIMARY if lead else UiCommandButton.Kind.SECONDARY)
		buy_key.name = "Buy_" + id
		buy_key.sends = true
		buy_key.reason = gap
		buy_key.activated.connect(claim_blueprint.bind(id))
		buy_key.unavailable_pressed.connect(func(reason: String): refused(buy_key, reason))
		card.content.add_child(buy_key)
		keys["buy_" + id] = buy_key
	# C-152: the farm's upgrade, at Scott's whatever his blueprint line says (none in rules without farm levels).
	if ParcelFarm.rules().get("farm_levels", []).is_empty(): return
	var primary := keys.values().any(func(k: UiCommandButton): return k.kind == UiCommandButton.Kind.PRIMARY)
	var up := UiCommandButton.new(LINES.upgrade_key, UiCommandButton.Kind.SECONDARY if primary else UiCommandButton.Kind.PRIMARY)
	up.name = "UpgradeFarm"
	up.activated.connect(open_upgrade)
	card.content.add_child(up)
	keys.upgrade = up

func open_counter() -> void:
	if farm.is_empty(): return
	var data := npc(MARKET)
	var economy: Dictionary = ParcelFarm.rules().get("economy", {})
	counter = Counter.new(farm, economy.get("sell_prices", {}), data, portrait(MARKET, false), economy.get("buy_prices", {}))
	counter.now_ms = server_now   # C-232: the day's bait limit runs on the server's day
	counter.refresh(farm)
	counter.keeper_bar.line = LINES.hello
	counter.close_requested.connect(func(): stack.close_drawer())
	counter.sell_requested.connect(sell)
	counter.buy_requested.connect(buy)
	_hand_over(counter)
	_switching = true
	stack.open_drawer(counter, {"scrim": UiTokens.OPACITY_SCRIM_COUNTER, "animate_out": true})
	_switching = false
	_place_toast()

## C-152: Scott's upgrade sheet over the greeting, as Jasmine's counter opens over hers.
func open_upgrade() -> void:
	if farm.is_empty(): return
	upgrade_sheet = Upgrade.new(farm)
	upgrade_sheet.close_requested.connect(func(): stack.close_drawer())
	upgrade_sheet.upgrade_requested.connect(upgrade)
	# MS-02: the sheet shakes its key and flashes the short need itself; the toast only when it says something else.
	var sheet := upgrade_sheet
	sheet.button.unavailable_pressed.connect(func(reason: String):
		if reason != sheet.button.text: toast.show_toast(reason, ToastLayer.Severity.INFO))
	_hand_over(upgrade_sheet)
	_switching = true
	stack.open_drawer(upgrade_sheet, {"animate_out": true})
	_switching = false
	_place_toast()

## MS-14: a drawer replacing the greeting rises in `motion/delay/handoff` (80) after the card starts leaving (M-05).
func _hand_over(drawer: UiDrawer) -> void:
	drawer.rise = true
	drawer.enter_delay = UiTokens.MOTION_DELAY_HANDOFF if stack.has_card() else 0.0

## C-152: `upgrade_farm` at the rules' price (the server's own; none is sent). The sheet follows the answer, now the
## next level's (or the top's); a toast names the new level and any blueprint it gave.
## C-186 (MS-17): the sheet holds its level while the command is out; on success its needs go in and the level-up card
## shows what changed (M-12); the sheet moves on when the card closes. A refusal: the sheet as it is, the reason toast.
func upgrade() -> Dictionary:
	if busy or level_card != null or _handing_in: return {}
	var rules := ParcelFarm.rules()
	var before := ParcelFarm.farm_level(farm)
	var gift: Dictionary = ParcelFarm.next_level(rules, before).get("gift", {})
	var rows := Upgrade.level_rows(rules, farm)
	var sheet: Upgrade = null
	if upgrade_sheet != null and is_instance_valid(upgrade_sheet): sheet = upgrade_sheet
	if sheet != null: sheet.hold = true
	var result := await _send({"type": "upgrade_farm"})
	if not result.get("ok", false):
		if sheet != null and is_instance_valid(sheet): sheet.release()
		return result
	var level := ParcelFarm.farm_level(farm)
	if not gift.is_empty():
		var item: String = gift.keys()[0]
		rows.append({"icon": ParcelItems.icon_of(item), "label": Upgrade.COPY.gift % [int(gift[item]), ParcelItems.name_of(item)],
			"value": "", "gift": true})
	_handing_in = true
	var ms := sheet.hand_in() if sheet != null and is_instance_valid(sheet) else 0.0
	if ms > 0.0 and is_inside_tree(): await get_tree().create_timer(UiKit.secs(ms), true).timeout
	_handing_in = false
	if is_inside_tree(): show_level_card(level, rows, sheet)
	return result

## M-12: the level-up card over the scene — scrim, the light turning behind, `hero_home` over the card, `Farm LvN`, what
## changes, the gift as the strip, the one button. The button or the scrim closes it (M-05); then `sheet` (if still open)
## fades its next level in.
func show_level_card(level: int, rows: Array, sheet = null) -> void:
	close_level_card()
	_level_layer = Control.new()
	_level_layer.name = "LevelUp"
	_level_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_level_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_level_layer)
	move_child(toast, -1)
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = UiTokens.COLOR_SCRIM_MODAL
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	# Nothing shows until the card is measured and centred next frame (C-186#82: it flashed at (0,0) over a full scrim).
	scrim.modulate.a = 0.0
	_level_layer.add_child(scrim)
	var glow: Control = null
	if not UiMotion.reduced:
		glow = UiRewardMoment.Glow.new()
		glow.name = "Glow"
		glow.modulate.a = 0.0
		_level_layer.add_child(glow)
	var m := UiRewardMoment.new()
	m.name = "LevelCard"
	m.modulate.a = 0.0
	m.tone = UiRewardMoment.Tone.MILESTONE
	m.event = LINES.upgraded % level
	m.hero = UiArt.hero("home")
	var plain: Array = rows.filter(func(r: Dictionary): return not r.get("gift", false))
	var gifts: Array = rows.filter(func(r: Dictionary): return r.get("gift", false))
	m.rows = plain
	if not gifts.is_empty():
		m.strip = str(gifts[0].label)
		m.strip_icon = gifts[0].icon
	m.primary = LINES.level_ok
	_level_layer.add_child(m)
	level_card = m
	var done := func() -> void: close_level_card(sheet)
	m.primary_pressed.connect(done)
	scrim.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and not e.pressed) or (e is InputEventScreenTouch and not e.pressed): done.call())
	await get_tree().process_frame
	if not is_instance_valid(m) or not m.is_inside_tree() or level_card != m or _level_layer == null: return
	m.reset_size()
	m.position = level_card_place(_level_layer.size, m.size)
	if glow != null:
		var side := maxf(m.size.x, m.size.y) * 2.2
		glow.size = Vector2(side, side)
		glow.position = m.position + Vector2(m.size.x * 0.5, 0) - glow.size * 0.5
		UiMotion.tween(glow, UiTokens.MOTION_EASING_LINEAR).tween_property(glow, ^"modulate:a", 1.0, UiKit.secs(UiTokens.MOTION_DURATION_FAST_MS))
	m.play_level_in(scrim)

## Where the level-up card stands on a `screen`-sized layer: centred across, its middle at `size/levelCard/centreY` of
## the height (C-211, C-186#82: figure 6 has it at about 27–58 %, higher than the middle, leaving room for its hero and
## light above), kept clear of the top for the hero (HERO_OVER over its edge).
static func level_card_place(screen: Vector2, card_size: Vector2) -> Vector2:
	var y := screen.y * UiTokens.SIZE_LEVEL_CARD_CENTRE_Y - card_size.y * 0.5
	y = clampf(y, UiRewardMoment.HERO_OVER + UiTokens.SPACE_PAGE, maxf(0.0, screen.y - card_size.y))
	return Vector2((screen.x - card_size.x) * 0.5, y)

## The level-up card leaves (M-05, its scrim fading); `sheet` then shows the next level.
func close_level_card(sheet = null) -> void:
	if _level_layer == null or not is_instance_valid(_level_layer):
		_level_layer = null
		level_card = null
		return
	var layer := _level_layer
	var m := level_card
	_level_layer = null
	level_card = null
	layer.propagate_call(&"set_mouse_filter", [Control.MOUSE_FILTER_IGNORE])
	if is_instance_valid(sheet) and sheet.has_method(&"release"): sheet.call(&"release")
	if m != null and is_instance_valid(m): UiMotion.panel_out(m, layer.get_node_or_null(^"Scrim") as CanvasItem, layer.queue_free)
	else: layer.queue_free()

func sell(item: String, count: int) -> Dictionary:
	if busy or count <= 0: return {}
	var before := int(farm.get("coins", 0))
	var result := await _send({"type": "sell", "item": item, "count": count})
	if result.get("ok", false) and counter != null and is_instance_valid(counter):
		# MS-15: the clerk's line cross-fades; `+N` and the coins fly from the key, the Coins row bumps and rolls.
		_swap_line(counter.keeper_bar, LINES.thanks % (int(farm.coins) - before))
		counter.celebrate_sale(before, int(farm.coins))
	return result

## The keeper bar's line, cross-faded (120) as MS-15 asks; at once when reduced.
func _swap_line(bar: UiKeeperBar, text: String) -> void:
	var l: Label = bar._line
	if UiMotion.reduced or l == null or not l.is_inside_tree():
		bar.line = text
		return
	var old := l.text
	bar.line = text   # the bar's state is the new line at once; its label shows the old one until it has faded
	l.text = old
	var half := UiKit.secs(UiTokens.MOTION_DURATION_FAST_MS * 0.5)
	var tw := UiMotion.tween(l, UiTokens.MOTION_EASING_STANDARD)
	tw.tween_property(l, ^"modulate:a", 0.0, half)
	tw.tween_callback(func(): l.text = text)
	tw.tween_property(l, ^"modulate:a", 1.0, half)

## C-149: buys `count` of `item` at the rules' price (the server's own; none is sent). The row's `Bag ×N` and the
## coins follow the answer; a toast says what came in.
func buy(item: String, count: int) -> Dictionary:
	if busy or count <= 0: return {}
	var before := int(farm.get("coins", 0))
	var had := int(farm.get("bag", {}).get(item, 0))
	var result := await _send({"type": "buy", "item": item, "count": count})
	if result.get("ok", false):
		if counter != null and is_instance_valid(counter):
			counter.roll_coins(before)
			counter.roll_bag(item, had)   # C-211 MS-15: the row's `Bag ×N` rolls up
		toast.show_toast("Received %s ×%d" % [ParcelItems.name_of(item), count], ToastLayer.Severity.SUCCESS, "", 0.0, ParcelItems.icon_of(item))
	return result

## C-181: the economy's blueprints with a price in coins this farm has not bought yet, in the rules' order.
func priced_blueprints() -> Array:
	var out := []
	var all: Dictionary = ParcelFarm.rules().get("economy", {}).get("blueprints", {})
	for id: String in all:
		if int(all[id].get("coins", 0)) > 0 and not farm.get("blueprints_claimed", {}).has(id): out.append(id)
	return out

## Why a priced blueprint cannot be bought now, the key's second line and its tap's toast; "" when it can. The delivered
## requests come first (C-182, SEN-Q-282: the sheep pen's after 15), in LOCK-10's `Need N more <thing>` form: `Need 11
## more requests`, as the server names them first; then the farm level (C-192, SEN-Q-282: the barn's from level 2, the
## pen's 3), in P0's `Home Lv2 needed` form: `Farm Lv2 needed`; then the coins, P0's `Need N more coins` (LOCK-10).
func buy_gap(id: String) -> String:
	var rule: Dictionary = ParcelFarm.rules().economy.blueprints[id]
	var requests := int(rule.get("min_requests", 0)) - int(farm.get("requests_done", 0))
	if requests > 0: return "Need %d more %s" % [requests, "request" if requests == 1 else "requests"]
	var level := int(rule.get("min_level", 1))
	if ParcelFarm.farm_level(farm) < level: return "Farm Lv%d needed" % level
	var short := int(rule.coins) - int(farm.get("coins", 0))
	return "Need %d more coins" % short if short > 0 else ""

## A priced blueprint's key: `Buy Barn Blueprint · 600 coins`.
static func buy_label(id: String) -> String:
	var rule: Dictionary = ParcelFarm.rules().economy.blueprints[id]
	return "Buy %s · %d coins" % [ParcelItems.name_of(str(rule.item)), int(rule.coins)]

## C-197: Jasmine's seed aid, asked once as her greeting opens when the save qualifies. Given: her line says so and a toast
## names what came in. Refused (another device took it, or the save changed): nothing is said; the greeting stays.
func claim_seed_aid() -> Dictionary:
	if busy: return {}
	var aid: Dictionary = ParcelFarm.rules().get("seed_aid", {})
	if aid.is_empty(): return {}
	busy = true
	var result: Dictionary = await store.send(farm_version, [{"type": "claim_seed_aid"}])
	busy = false
	if not is_inside_tree(): return result
	_adopt(result)
	if not result.get("ok", false): return result
	aid_given = {"item": aid.item, "amount": int(aid.amount)}
	toast.show_toast("Received %s ×%d" % [ParcelItems.name_of(str(aid.item)), int(aid.amount)], ToastLayer.Severity.SUCCESS, "", 0.0, ParcelItems.icon_of(str(aid.item)))
	if card != null and is_instance_valid(card): _greet()
	return result

## Takes Scott's free blueprint (the coop's), or buys a priced one (C-181, the barn's: the server takes the coins).
func claim_blueprint(id := BLUEPRINT) -> Dictionary:
	if busy: return {}
	var rule: Dictionary = ParcelFarm.rules().economy.blueprints[id]
	var result := await _send({"type": "claim_blueprint", "blueprint": id})
	if result.get("ok", false):
		toast.show_toast("Received %s ×%d" % [ParcelItems.name_of(str(rule.item)), int(rule.amount)], ToastLayer.Severity.SUCCESS, "", 0.0, ParcelItems.icon_of(str(rule.item)))
	_greet()
	return result

func _send(command: Dictionary) -> Dictionary:
	busy = true
	var result: Dictionary = await store.send(farm_version, [command])
	busy = false
	if not is_inside_tree(): return result
	_adopt(result)
	if result.get("ok", false): return result
	if result.get("code") == "VERSION_CONFLICT": toast.show_toast("Your farm was updated. Try again.", ToastLayer.Severity.INFO)
	else: toast.show_toast("That didn't work.", ToastLayer.Severity.REFUSED)
	return result

## Whether this parcel's player has met the keeper on this device.
func met(role: String) -> bool:
	return bool(_met().get(parcel_id, {}).get(role, false))

func mark_met(role: String) -> void:
	var all := _met()
	var mine: Dictionary = all.get(parcel_id, {})
	mine[role] = true
	all[parcel_id] = mine
	DirAccess.make_dir_recursive_absolute(_met_path.get_base_dir())
	var file := FileAccess.open(_met_path, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(all))
	file.close()

func _met() -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(_met_path)) if FileAccess.file_exists(_met_path) else null
	return raw if raw is Dictionary else {}

## The counter closing goes back to the greeting; the greeting closing leaves. The board has no greeting: closing it leaves.
func _on_layer_closed(layer: int, _content: Control) -> void:
	if layer == ModalStack.Layer.DRAWER:
		counter = null
		upgrade_sheet = null
		board = null
		if who == BOARD: close()
		elif is_inside_tree(): _greet_again.call_deferred()
	elif layer == ModalStack.Layer.CARD:
		card = null
		if not _switching and not stack.has_drawer(): close()

func _greet_again() -> void:
	if not stack.has_card() and is_inside_tree(): _greet()

func close() -> void:
	if is_queued_for_deletion(): return
	queue_free()
	closed.emit()

## Back: a board sheet goes back a page (BOARD-3 to its request, the others to the list), else the top layer closes;
## false when nothing was open.
func step_back() -> bool:
	if level_card != null:
		close_level_card(upgrade_sheet)
		return true
	if board != null and is_instance_valid(board) and board.page != "list":
		if board.page == "drop": board.open_request(int(board.focus.get("id", 0)))
		else: board.back_to_list()
		return true
	return stack.back()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"ui_cancel"):
		if not step_back(): close()
		get_viewport().set_input_as_handled()
