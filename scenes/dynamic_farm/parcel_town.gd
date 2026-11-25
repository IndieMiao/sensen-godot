extends Control
## The market (Jasmine) and the carpenter (Scott) of the dynamic farm (C-59, the C-30 0.4.3 plan). Since C-115 they
## stand in the Washington Square room (parcel_outpost.gd), which opens this greeting over itself when one is tapped.
## Each keeper greets first, as on the main farm (UiDialogueCard, KeeperGreeting); their looks are built from the
## existing avatar parts and their portraits drawn from them (P0KeeperPortraits), with no painted art or new model
## (C-30#29 question 6).
## - Jasmine introduces coins in a line the first time she is met (kept on this device per parcel), then says hello;
##   Sell opens her counter (parcel_counter.gd), which sells through the parcel save's `sell` command (C-58).
## - Scott gives one Coop Blueprint once the parcel has sold something (`claim_blueprint`, C-58 rules: C-30#29
##   question 5); it only goes into the bag, building comes later (0.4.4).
## The parcel save (store: read / send, parcel_farm_remote_store.gd or the local stand-in) is authoritative; this
## node draws what it answers. Coins are the parcel's own, separate from the main farm's.
signal closed

const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const ParcelItems = preload("res://modules/dynamic_farm/parcel_items.gd")
const Counter = preload("res://scenes/dynamic_farm/parcel_counter.gd")
const Portraits = preload("res://modules/p0/p0_keeper_portraits.gd")
const MARKET := "market"
const CARPENTER := "carpenter"
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
}
const MET_PATH := "user://dynamic_farm_local/town.json"

var who := MARKET
var store: RefCounted
var parcel_id := ""
var farm := {}
var farm_version := -1
var busy := false
var stack: ModalStack
var card: UiDialogueCard
var counter: Counter
var toast: ToastLayer
## A greeting's keys, by name (tests and the map read them).
var keys := {}
var _close: UiCloseButton
var _switching := false   # the card closes because the counter opens over it
var _met_path := MET_PATH

## who: MARKET or CARPENTER; store answers read() and send(); parcel_id names the player's parcel (the met record).
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
	await reload()

## Reads the parcel save and greets again; a failed read says so and offers Retry.
func reload() -> void:
	busy = true
	_greet()
	var result: Dictionary = await store.read()
	busy = false
	if not is_inside_tree(): return
	if not _adopt(result) and farm.is_empty():
		card.line = LINES.unreachable
		var retry := UiCommandButton.new("Retry", UiCommandButton.Kind.SECONDARY)
		retry.name = "Retry"
		retry.activated.connect(reload)
		card.content.add_child(retry)
		keys.retry = retry
		return
	_greet()

func _adopt(result: Dictionary) -> bool:
	var next := ParcelFarm.normalize(result.get("farm"))
	if next.is_empty(): return false
	farm = next
	farm_version = int(result.get("farm_version", farm_version))
	if counter != null and is_instance_valid(counter): counter.refresh(farm)
	return true

## The keeper's greeting card: a fresh one each time it is shown (the read, a sale, the blueprint).
func _greet() -> void:
	var data := npc(who)
	keys = {}
	if card == null or not is_instance_valid(card):
		card = UiDialogueCard.new(portrait(who), "%s · %s" % [data.role, data.name])
		card.portrait_size = UiDialogueCard.KEEPER_PORTRAIT
		card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		card.offset_left = UiTokens.SIZE_QUICK_BAR_X
		card.offset_right = -UiTokens.SIZE_QUICK_BAR_X
		card.offset_bottom = -UiTokens.SPACE_PAGE - 24
		card.grow_vertical = Control.GROW_DIRECTION_BEGIN
		stack.open_card(card)
		_close_above(card)
		toast.anchor_above(card)
	for c in card.content.get_children():
		c.hide()
		c.queue_free()
	if farm.is_empty():
		card.line = "…" if busy else card.line
		return
	if who == MARKET: _greet_market()
	else: _greet_carpenter()

func _greet_market() -> void:
	if not met(MARKET):
		card.line = LINES.intro
		mark_met(MARKET)
	elif card.line == "" or card.line == "…" or card.line == LINES.intro: card.line = LINES.hello
	var sell := UiCommandButton.new("Sell")
	sell.name = "Sell"
	sell.activated.connect(open_counter)
	card.content.add_child(sell)
	keys.sell = sell

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

func open_counter() -> void:
	if farm.is_empty(): return
	var data := npc(MARKET)
	counter = Counter.new(farm, ParcelFarm.rules().get("economy", {}).get("sell_prices", {}), data, portrait(MARKET, false))
	counter.keeper_bar.line = LINES.hello
	counter.close_requested.connect(func(): stack.close_drawer())
	counter.sell_requested.connect(sell)
	_switching = true
	stack.open_drawer(counter, {"scrim": UiTokens.OPACITY_SCRIM_COUNTER})
	_switching = false
	toast.anchor_above(counter)

func sell(item: String, count: int) -> Dictionary:
	if busy or count <= 0: return {}
	var before := int(farm.get("coins", 0))
	var result := await _send({"type": "sell", "item": item, "count": count})
	if result.get("ok", false) and counter != null and is_instance_valid(counter):
		counter.keeper_bar.line = LINES.thanks % (int(farm.coins) - before)
	return result

func claim_blueprint() -> Dictionary:
	if busy: return {}
	var rule: Dictionary = ParcelFarm.rules().economy.blueprints[BLUEPRINT]
	var result := await _send({"type": "claim_blueprint", "blueprint": BLUEPRINT})
	if result.get("ok", false):
		toast.show_toast("Received %s ×%d" % [ParcelItems.name_of(str(rule.item)), int(rule.amount)], ToastLayer.Severity.SUCCESS)
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

## A Close 44 sits 8 above the card's top-right corner, as on the main farm's keeper greeting.
func _close_above(content: Control) -> void:
	_close = UiCloseButton.new()
	_close.size = Vector2(UiTokens.SIZE_CLOSE, UiTokens.SIZE_CLOSE)
	var follow := func():
		if is_instance_valid(_close) and is_instance_valid(content):
			_close.position = content.position + Vector2(content.size.x - UiTokens.SIZE_CLOSE, -8.0 - UiTokens.SIZE_CLOSE)
	content.item_rect_changed.connect(follow)
	_close.pressed.connect(close)
	stack.add_child(_close)
	follow.call()

## The counter closing goes back to the greeting; the greeting closing leaves.
func _on_layer_closed(layer: int, _content: Control) -> void:
	if layer == ModalStack.Layer.DRAWER:
		counter = null
		if is_inside_tree(): _greet_again.call_deferred()
	elif layer == ModalStack.Layer.CARD:
		if is_instance_valid(_close): _close.queue_free()
		card = null
		if not _switching and not stack.has_drawer(): close()

func _greet_again() -> void:
	if not stack.has_card() and is_inside_tree(): _greet()

func close() -> void:
	if is_queued_for_deletion(): return
	queue_free()
	closed.emit()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"ui_cancel"):
		if not stack.back(): close()
		get_viewport().set_input_as_handled()
