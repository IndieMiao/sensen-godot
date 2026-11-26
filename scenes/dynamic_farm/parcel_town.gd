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
## - Since C-181 Scott sells the blueprints the rules price in coins (`economy.blueprints.<id>.coins`, the barn's 150):
##   one key each, `Buy Barn Blueprint · 150 coins`, until it is bought; short of coins it reads P0's `Need N more coins`
##   (LOCK-10) and a tap says so. It sends `claim_blueprint`, which takes the coins on the server.
## - Since C-191 the room's Request Board opens here too (who = BOARD): no keeper and no greeting, the board drawer
##   (parcel_board.gd) straight away; its keys send `accept_request` / `deliver_request` / `drop_request`, and closing
##   it leaves.
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
var _met_path := MET_PATH

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
	await reload()

## Reads the parcel save and greets again; a failed read says so and offers Retry.
func reload() -> void:
	if who == BOARD:
		await _reload_board()
		return
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
	stack.open_drawer(board)
	toast.anchor_above(board)

## A board key's command. A delivery floats its coins up from its key; a drop shows BOARD-DROPPED. A refusal toasts
## what the server said (the keys already carry the gaps it checks).
func board_command(command: Dictionary) -> Dictionary:
	if busy or board == null or not is_instance_valid(board): return {}
	var at := board.key_point(int(command.get("request", 0)))
	var coins := int(farm.get("coins", 0))
	var result := await _send(command)
	if not result.get("ok", false) or board == null or not is_instance_valid(board): return result
	match str(command.type):
		"deliver_request": if at != Vector2.INF: board.float_coins(int(farm.coins) - coins, at)
		"drop_request": board.dropped()
	return result

## The keeper's greeting card: a fresh one each time it is shown (the read, a sale, the blueprint).
func _greet() -> void:
	var data := npc(who)
	keys = {}
	if card == null or not is_instance_valid(card):
		card = UiNpcCard.new(portrait(who), "%s · %s" % [data.role, data.name])
		card.place_centred()
		card.close_requested.connect(close)
		stack.open_card(card)
		card.play_in(stack.get_node_or_null(^"ScrimCard"))
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
		var price := int(ParcelFarm.rules().economy.blueprints[id].coins)
		var short := price - int(farm.get("coins", 0))
		var lead := keys.is_empty() and short <= 0
		var buy_key := UiCommandButton.new(buy_label(id), UiCommandButton.Kind.PRIMARY if lead else UiCommandButton.Kind.SECONDARY)
		buy_key.name = "Buy_" + id
		buy_key.sends = true
		buy_key.reason = "Need %d more coins" % short if short > 0 else ""
		buy_key.activated.connect(claim_blueprint.bind(id))
		buy_key.unavailable_pressed.connect(func(reason: String): toast.show_toast(reason, ToastLayer.Severity.INFO))
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
	counter.keeper_bar.line = LINES.hello
	counter.close_requested.connect(func(): stack.close_drawer())
	counter.sell_requested.connect(sell)
	counter.buy_requested.connect(buy)
	_switching = true
	stack.open_drawer(counter, {"scrim": UiTokens.OPACITY_SCRIM_COUNTER})
	_switching = false
	toast.anchor_above(counter)

## C-152: Scott's upgrade sheet over the greeting, as Jasmine's counter opens over hers.
func open_upgrade() -> void:
	if farm.is_empty(): return
	upgrade_sheet = Upgrade.new(farm)
	upgrade_sheet.close_requested.connect(func(): stack.close_drawer())
	upgrade_sheet.upgrade_requested.connect(upgrade)
	upgrade_sheet.button.unavailable_pressed.connect(func(reason: String): toast.show_toast(reason, ToastLayer.Severity.INFO))
	_switching = true
	stack.open_drawer(upgrade_sheet)
	_switching = false
	toast.anchor_above(upgrade_sheet)

## C-152: `upgrade_farm` at the rules' price (the server's own; none is sent). The sheet follows the answer, now the
## next level's (or the top's); a toast names the new level and any blueprint it gave.
func upgrade() -> Dictionary:
	if busy: return {}
	var before := ParcelFarm.farm_level(farm)
	var gift: Dictionary = ParcelFarm.next_level(ParcelFarm.rules(), before).get("gift", {})
	var result := await _send({"type": "upgrade_farm"})
	if result.get("ok", false):
		var level := ParcelFarm.farm_level(farm)
		if gift.is_empty(): toast.show_toast(LINES.upgraded % level, ToastLayer.Severity.SUCCESS)
		else:
			var item: String = gift.keys()[0]
			toast.show_toast(LINES.upgraded_gift % [level, int(gift[item]), ParcelItems.name_of(item)], ToastLayer.Severity.SUCCESS)
	return result

func sell(item: String, count: int) -> Dictionary:
	if busy or count <= 0: return {}
	var before := int(farm.get("coins", 0))
	var result := await _send({"type": "sell", "item": item, "count": count})
	if result.get("ok", false) and counter != null and is_instance_valid(counter):
		counter.keeper_bar.line = LINES.thanks % (int(farm.coins) - before)
	return result

## C-149: buys `count` of `item` at the rules' price (the server's own; none is sent). The row's `Bag ×N` and the
## coins follow the answer; a toast says what came in.
func buy(item: String, count: int) -> Dictionary:
	if busy or count <= 0: return {}
	var result := await _send({"type": "buy", "item": item, "count": count})
	if result.get("ok", false):
		toast.show_toast("Received %s ×%d" % [ParcelItems.name_of(item), count], ToastLayer.Severity.SUCCESS)
	return result

## C-181: the economy's blueprints with a price in coins this farm has not bought yet, in the rules' order.
func priced_blueprints() -> Array:
	var out := []
	var all: Dictionary = ParcelFarm.rules().get("economy", {}).get("blueprints", {})
	for id: String in all:
		if int(all[id].get("coins", 0)) > 0 and not farm.get("blueprints_claimed", {}).has(id): out.append(id)
	return out

## A priced blueprint's key: `Buy Barn Blueprint · 150 coins`.
static func buy_label(id: String) -> String:
	var rule: Dictionary = ParcelFarm.rules().economy.blueprints[id]
	return "Buy %s · %d coins" % [ParcelItems.name_of(str(rule.item)), int(rule.coins)]

## Takes Scott's free blueprint (the coop's), or buys a priced one (C-181, the barn's: the server takes the coins).
func claim_blueprint(id := BLUEPRINT) -> Dictionary:
	if busy: return {}
	var rule: Dictionary = ParcelFarm.rules().economy.blueprints[id]
	var result := await _send({"type": "claim_blueprint", "blueprint": id})
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
	if board != null and is_instance_valid(board) and board.page != "list":
		if board.page == "drop": board.open_request(int(board.focus.get("id", 0)))
		else: board.back_to_list()
		return true
	return stack.back()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"ui_cancel"):
		if not step_back(): close()
		get_viewport().set_input_as_handled()
