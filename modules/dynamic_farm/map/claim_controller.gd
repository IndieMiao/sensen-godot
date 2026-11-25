extends Node
## C-32 first-home claim on the dynamic farm map. Ownership is the server's answer (C-31); this node only
## mirrors it into the native own/claimed state channel and claimer-name layer, and never decides a claim.
## Colours (q(342); since C-112 on the parcel's buildings only, C-103#18): own green, someone else's red with their
## name, a claimable selection keeps C-28's yellow building fill. Selection itself stays with selection_controller.gd.
## C-130: while the server has a starter zone on, a player without a home can only claim inside it. The zone (from the
## server) is drawn by its own native layer and only hides the claim button outside it; the server still decides.
signal changed
const NO_NAME := "Claimed"
const OUTSIDE_ZONE := "Not in the starter area."
## The zone marker (its own native layer): UI v3 primary green dashed edge, the cream panel tone washing the map
## outside it.
const ZONE_STYLE := {"line_color": "#3E7D43", "line_width": 3.0, "mask_color": "#FBF8F1", "mask_opacity": 0.55}
const SIGNED_OUT := ["LOGIN_REQUIRED", "UNAUTHENTICATED", "OFFLINE"]
## Area reads only add rows. Keep the map well under the native 3000-row state/name limits.
const MAX_OWNERS := 1000
var api # claim_api.gd
var bridge: MapBridge
## Internal test packages set `sensen/dynamic_farm/reselect`; release has no reselect entry (and the server refuses).
var reselect := false
## Playing as this installation's guest (install-and-play, no account). The server refuses a guest's give-up, so
## there is no give-up entry for a guest (Q-156); it appears once the player signs in.
var guest := false
var owners := {} # parcel_id -> {owner, nickname}
var mine := {} # Parcel from the server, or empty.
var mine_known := false
var signed_out := false
var busy := false
var message := ""
var _generation := -1
var _selected := ""
var _pushed := {} # parcel_id -> [selected, claimed, own] last sent for _generation
var _epoch := 0
var _reading_mine := false
## C-130 starter zone: {} when off or not (yet) known; see claim_api.gd parse_zone().
var zone := {}
var zone_known := false
var _reading_zone := false
var _zone_pushed := -1 # Generation the native zone layer was last sent for.

func status(id: String) -> String:
	if id.is_empty() or not owners.has(id): return "unknown"
	return owners[id].owner

## The claimer's display name as the server gave it; "" when the account has none.
func owner_name(id: String) -> String:
	return owners.get(id, {}).get("nickname", "")

## Map label for a claimed parcel.
func nickname(id: String) -> String:
	var name := owner_name(id)
	return name if not name.is_empty() else NO_NAME

func has_home() -> bool:
	return not mine.is_empty()

## Whether a player without a home may claim this parcel. Unknown zone (still reading, or unreachable): the server
## decides, so the button stays.
func in_zone(id: String) -> bool:
	return zone.is_empty() or zone.parcel_ids.has(id)

## Reads the starter zone once per map visit (again after a failed read).
func read_zone() -> void:
	if _reading_zone or zone_known: return
	var epoch := _epoch
	_reading_zone = true
	var r: Dictionary = await api.starter_zone()
	if epoch != _epoch: return
	_reading_zone = false
	if r.ok: zone = r.zone; zone_known = true; _zone_pushed = -1
	_sync(); changed.emit()

## Reads the player's own parcel; call on map entry and again after returning from a preview.
func start() -> void:
	var epoch := _epoch
	_reading_mine = true
	read_zone() # After _reading_mine: a zone answered at once must not let the map frame before the home is known.
	var r: Dictionary = await api.mine()
	if epoch != _epoch: return
	_reading_mine = false
	signed_out = r.code in SIGNED_OUT
	if r.ok:
		mine = r.parcel; mine_known = true
		if has_home(): owners[mine.parcel_id] = {"owner": "mine", "nickname": ""}
	_sync(); changed.emit()

## Selection or source generation changed. A new generation has no native state, so everything is resent.
func attach(generation: int, selected_id: String) -> void:
	if generation != _generation:
		_generation = generation; _pushed = {}
	var reselected := selected_id != _selected
	if reselected and not busy: message = ""
	_selected = selected_id
	_sync()
	if not reselected or selected_id.is_empty(): return
	# A failed first read (network/5xx) is retried when the player picks a parcel.
	if not mine_known and not _reading_mine: start()
	refresh([selected_id])

func refresh(ids: Array) -> void:
	var epoch := _epoch
	var r: Dictionary = await api.owners(ids)
	if epoch != _epoch: return
	signed_out = signed_out or r.code in SIGNED_OUT
	if not r.ok: changed.emit(); return
	_merge(r.owners)
	_sync(); changed.emit()

func refresh_area(bbox: Array) -> void:
	var epoch := _epoch
	var r: Dictionary = await api.owners_in(bbox)
	if epoch != _epoch or not r.ok: return
	# Area answers list claimed parcels only and carry no geometry, so absent rows are not cleared here;
	# claims are permanent, and a selected parcel is always re-read by id.
	_merge(r.owners)
	_sync(); changed.emit()

func claim(selection: Dictionary) -> void:
	if busy or selection.is_empty(): return
	var id := str(selection.block_id)
	busy = true; message = "Claiming…"; changed.emit()
	var epoch := _epoch
	var r: Dictionary = await api.claim(id, selection.center)
	if epoch != _epoch: return
	busy = false; message = ""
	if r.ok:
		mine = r.parcel; mine_known = true
		owners[id] = {"owner": "mine", "nickname": ""}
	else:
		match r.code:
			"ALREADY_CLAIMED":
				mine = r.parcel; mine_known = true
				if has_home(): owners[mine.parcel_id] = {"owner": "mine", "nickname": ""}
				message = "You already have a home."
			"PARCEL_TAKEN":
				owners[id] = {"owner": "other", "nickname": ""}
				message = "Someone just claimed this parcel."
				refresh([id])
			"OUTSIDE_STARTER_ZONE":
				message = OUTSIDE_ZONE
				zone_known = false; read_zone() # The server's zone changed under the map: read it again.
			"LOGIN_REQUIRED", "UNAUTHENTICATED", "OFFLINE": signed_out = true
			_: message = "Could not claim. Try again."
	_sync(); changed.emit()

## Whether the give-up entry is offered: an internal package, an account, a home.
func can_give_up() -> bool:
	return reselect and not guest and has_home()

func abandon() -> void:
	if busy or not can_give_up(): return
	busy = true; message = ""; changed.emit()
	var epoch := _epoch
	var r: Dictionary = await api.abandon()
	if epoch != _epoch: return
	busy = false
	if r.ok or r.code == "NO_PARCEL":
		owners[str(mine.parcel_id)] = {"owner": "none", "nickname": ""}
		mine = {}
	else: message = "Could not give up this home. Try again."
	_sync(); changed.emit()

## The player signed in (or switched account): "mine"/"other" were relative to the old identity.
func forget() -> void:
	_epoch += 1; busy = false; _reading_mine = false
	owners = {}; mine = {}; mine_known = false; signed_out = false; message = ""
	_reading_zone = false # The zone is the same for every account; a read cut off here starts again below.
	_sync(); changed.emit()
	start()
	if not _selected.is_empty(): refresh([_selected])

## Leaving the map retires in-flight answers; native layers are cleared with the selector's generation.
func pause() -> void:
	_epoch += 1; busy = false; _reading_mine = false; _generation = -1; _pushed = {}; _selected = ""
	_reading_zone = false; _zone_pushed = -1

func _merge(rows: Dictionary) -> void:
	for id in rows:
		owners.erase(id) # Re-insert so the newest answers sit last.
		owners[id] = rows[id]
	var keep := [str(mine.get("parcel_id", "")), _selected]
	for id in owners.keys():
		if owners.size() <= MAX_OWNERS: break
		if not id in keep: owners.erase(id)

func _sync() -> void:
	if bridge == null or _generation <= 0: return
	var batch: Array = []
	var next := {}
	for id in owners:
		var owner: String = owners[id].owner
		if owner == "none" and id != _selected: continue
		next[id] = [id == _selected and owner != "none", owner == "other", owner == "mine"]
	for id in _pushed:
		if not next.has(id): next[id] = [false, false, false]
	for id in next:
		if _pushed.get(id) != next[id]:
			batch.append({"block_id": id, "selected": next[id][0], "claimed": next[id][1], "own": next[id][2]})
	_pushed = {}
	for id in next:
		if next[id] != [false, false, false]: _pushed[id] = next[id]
	if not batch.is_empty(): bridge.set_parcel_states(_generation, JSON.stringify(batch))
	var names: Array = []
	for id in owners:
		if owners[id].owner == "other": names.append({"block_id": id, "nickname": nickname(id).left(80)})
	bridge.set_parcel_claims(_generation, JSON.stringify(names))
	# Yellow means claimable: a selected parcel that is already owned shows its own colour instead.
	if status(_selected) in ["mine", "other"]: bridge.set_parcel_building_highlight(_generation, "")
	show_zone(_generation)

## The starter zone marker for this map generation, once. It does not wait for the parcel layers (attach), which load
## only from the selectable zoom: the map is entered below it at the starter zone's landing view (C-130 V-362).
func show_zone(generation: int) -> void:
	if bridge == null or generation <= 0 or _zone_pushed == generation: return
	_zone_pushed = generation
	bridge.set_starter_zone(generation, zone_payload(zone))

## Native starter zone layer: the boundary ring and its style; "" clears it.
static func zone_payload(z: Dictionary) -> String:
	if z.is_empty(): return ""
	var payload := ZONE_STYLE.duplicate()
	payload["boundary"] = z.boundary
	return JSON.stringify(payload)
