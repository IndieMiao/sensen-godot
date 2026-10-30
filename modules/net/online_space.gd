class_name OnlineSpace
extends Node
## One live scene connection. The server selects mine instances; callers never supply an instance ID.

signal world_changed(world: Dictionary)
signal enemies_changed(monsters: Array)
signal rescued
signal connection_changed
signal travel_confirmed(accepted: bool)

const ACTIONS := ["idle", "run", "walk", "labour_sow", "labour_water", "labour_harvest", "labour_drain", "labour_shelter", "emote_wave", "attack", "mine", "labour_till", "labour_clear", "fishing_wait", "fishing_reel"]
var session: FarmSession
var kind := ""
var join_args: Dictionary = {}
var mover_source: Callable
var animation_source: Callable
var input_enabled: Callable
var socket: WebSocketPeer
var joined := false
var active := false
var epoch := 0
var self_id := 0
var floor_number := 0
var room := ""
var world: Dictionary = {}
var self_state: Dictionary = {}
var members: Dictionary = {}
var directory: Dictionary = {}
var count := 0
var error := ""
var crowd: Node3D
var hud: CanvasLayer
var _badge_count: Label
var badge: Button
var panel: PanelContainer
var travel_busy := false
var _party_refreshing := false
var _party_refresh_again := false
var _party_poll_at := 0.0
var _selected_member := ""
var _departed := false
var _modal_shield: Control
var _copy_toast: PanelContainer
var _copy_toast_timer: Timer
var _voice_status: Label
var _voice_join: Button
var _voice_mic: Button
var _voice_listen: Button
var _voice_speakers: Label
var _voice_badge: Button
var _travel_confirmation: ConfirmationDialog
var _travel_notice := ""
var _arrival_position := Vector3.ZERO
var _arrival_pending := false
var _seq := 0
var _command_seq := 0
var _pending: Dictionary = {}
var _sent_at := 0.0
var _ping_at := 0.0
var _retry_at := 0.0
var _attempt := 0
var _auth_sent := false
var _refreshing := false
var _refresh_again := false
var _last_received := 0.0
var _suspended := false
var _generation := 0
var _prediction_history: Dictionary = {}
var _last_snapshot_tick := -1
var _resume_ticket := ""
var _appearance_supported := false
var _appearance_dirty := false
var _appearance_at := 0.0

static func attach(host: Node3D, farm_session: FarmSession, space_kind: String, args: Dictionary,
		get_mover: Callable, get_animation: Callable, can_input := Callable()) -> OnlineSpace:
	var online := OnlineSpace.new()
	online.session = farm_session
	online.kind = space_kind
	online.join_args = args
	online.mover_source = get_mover
	online.animation_source = get_animation
	online.input_enabled = can_input
	host.add_child(online)
	return online

func _ready() -> void:
	process_priority = 100
	Avatar.outfit_saved.connect(_outfit_saved)
	Voice.changed.connect(_update_voice_controls)
	crowd = preload("res://modules/net/online_crowd.gd").new()
	get_parent().add_child(crowd)
	hud = CanvasLayer.new()
	hud.layer = 25
	add_child(hud)
	badge = _button("", "users-round")
	badge.theme = GameUi.theme()
	badge.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.custom_minimum_size = Vector2(44, 44)
	badge.size = Vector2(44, 44)
	_style_round_badge(badge, 22)
	hud.add_child(badge)
	var count_chip := PanelContainer.new()
	count_chip.name = "OnlineCount"
	count_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_chip.add_theme_stylebox_override("panel", GameUi.card_style(false, 2))
	count_chip.position = Vector2(26, 29)
	badge.add_child(count_chip)
	_badge_count = GameUi.label("…", 10, GameUi.BLUE)
	_badge_count.custom_minimum_size = Vector2(16, 12)
	_badge_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_chip.add_child(_badge_count)
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_layout_badge()
	badge.pressed.connect(_open_party)
	_voice_badge = _button("", "mic-off")
	_voice_badge.name = "PartyVoiceBadge"
	_voice_badge.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_voice_badge.theme = GameUi.theme()
	_voice_badge.add_theme_font_size_override("font_size", 11)
	_voice_badge.custom_minimum_size = Vector2(44, 44)
	_voice_badge.size = Vector2(44, 44)
	_style_round_badge(_voice_badge, 22)
	_voice_badge.tooltip_text = L10n.text("Manage party voice")
	_voice_badge.pressed.connect(_open_party)
	hud.add_child(_voice_badge)
	_layout_badge()
	_update_voice_controls()
	_update_badge()
	get_viewport().size_changed.connect(_layout_badge)
	var farm_root := get_parent().get_node_or_null("HUD/SafeArea/Root") as Control
	if farm_root != null:
		farm_root.item_rect_changed.connect(_layout_badge)
	# Containers settle their safe-area rect after children enter the tree.
	_layout_badge.call_deferred()
	if session and session.logged_in() and ((Net.online_available and not Net.is_test_process()) or bool(ProjectSettings.get_setting("sensen/network/online_qa", false))):
		start()

func _layout_badge() -> void:
	if not is_inside_tree() or not is_instance_valid(badge): return
	var area := _safe_ui_rect()
	badge.position = Vector2(area.end.x - 44, area.position.y + (56 if kind == "farm" else 62))
	badge.size = Vector2(44, 44)
	if is_instance_valid(_voice_badge):
		_voice_badge.position = Vector2(area.end.x - 44, badge.position.y + 52)
		_voice_badge.size = Vector2(44, 44)
	if is_instance_valid(panel): _layout_party()

func _safe_ui_rect() -> Rect2:
	var farm_root := get_parent().get_node_or_null("HUD/SafeArea/Root") as Control
	if farm_root != null and farm_root.size.x >= 44 and farm_root.size.y >= 152:
		return farm_root.get_global_rect()
	var viewport := get_viewport().get_visible_rect().size
	var safe := DisplayServer.get_display_safe_area() if OS.has_feature("android") or OS.has_feature("ios") else Rect2i()
	var margins := UIMetrics.safe_margins(safe, DisplayServer.window_get_size(), viewport, 16)
	return Rect2(margins.x, margins.y, maxf(1, viewport.x - margins.x - margins.z), maxf(1, viewport.y - margins.y - margins.w))

func _style_round_badge(button: Button, radius: int) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var color := GameUi.MINT if state == "pressed" else GameUi.PAPER
		var surface := GameUi.surface(color, 0, radius)
		surface.border_color = GameUi.BLUE
		surface.set_border_width_all(2)
		surface.shadow_color = Color(GameUi.BLUE, 0.22)
		surface.shadow_offset = Vector2(0, 3 if state != "pressed" else 1)
		surface.shadow_size = 1
		button.add_theme_stylebox_override(state, surface)
	button.add_theme_constant_override("icon_max_width", 25 if radius > 20 else 21)
	button.add_theme_color_override("icon_normal_color", GameUi.BLUE)

func _sync_badge_visibility() -> void:
	if not is_instance_valid(badge) or not is_inside_tree(): return
	var covered := GameUi.modal_is_open(get_parent())
	badge.visible = not covered
	badge.disabled = covered
	if is_instance_valid(_voice_badge):
		_voice_badge.visible = Voice.active() and not covered
		_voice_badge.disabled = covered

func _layout_party() -> void:
	if not is_instance_valid(panel): return
	var area := _safe_ui_rect()
	var width := minf(560, maxf(1, area.size.x - 8))
	var height := minf(560, maxf(180, area.size.y - 100))
	panel.position = Vector2(area.position.x + (area.size.x - width) * 0.5, area.end.y - height - 4)
	panel.size = Vector2(width, height)

func start() -> void:
	if active or session == null or not session.logged_in(): return
	active = true
	_attempt = 0
	_connect()

func stop() -> void:
	_generation += 1
	active = false
	_suspended = false
	_resume_ticket = ""
	joined = false
	if socket:
		socket.close(1000, "LEAVING")
		socket.poll()
	socket = null
	_pending.clear()
	members.clear()
	if crowd: crowd.clear()
	_update_badge()
	connection_changed.emit()

func suspend() -> void:
	var resume_later := active or _suspended
	stop()
	_suspended = resume_later
	hud.hide()
	if crowd: crowd.hide()

func resume() -> void:
	hud.show()
	if crowd: crowd.show()
	if _suspended:
		_suspended = false
		start()

func _exit_tree() -> void:
	if is_instance_valid(_travel_confirmation): travel_confirmed.emit(false)
	stop()
	if is_instance_valid(crowd): crowd.queue_free()

func _connect() -> void:
	joined = false
	_seq = 0
	_command_seq = 0
	_auth_sent = false
	_appearance_supported = false
	error = ""
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 1024 * 1024
	socket.outbound_buffer_size = 64 * 1024
	socket.max_queued_packets = 256
	var url := session.client.base_url.replace("https://", "wss://").replace("http://", "ws://") + "/online"
	var result := socket.connect_to_url(url)
	_last_received = _seconds()
	if result != OK: _disconnected("ONLINE_UNAVAILABLE")
	_update_badge()

func _process(delta: float) -> void:
	_sync_badge_visibility()
	if is_instance_valid(panel) and not travel_busy and directory.get("party") is Dictionary and _seconds() >= _party_poll_at:
		_party_poll_at = _seconds() + 3
		_refresh_party()
	if not active: return
	var now := _seconds()
	if socket == null:
		if now >= _retry_at: _connect()
		return
	socket.poll()
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		var reason := socket.get_close_reason()
		if reason in ["SESSION_REPLACED", "UNAUTHENTICATED", "ACCESS_REVOKED"]:
			error = reason
			if reason in ["SESSION_REPLACED", "UNAUTHENTICATED"]: Voice.leave()
			stop()
			if reason == "ACCESS_REVOKED": _access_revoked.call_deferred()
			return
		_disconnected(reason)
		return
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		if now - _last_received > 10: _disconnected("ONLINE_UNAVAILABLE")
		return
	if not _auth_sent:
		_auth_sent = true
		_send({"t": "auth", "token": session.client.token})
	var packets := 0
	while socket and socket.get_available_packet_count() > 0 and packets < 128:
		packets += 1
		var data := socket.get_packet()
		_last_received = now
		if socket.was_string_packet():
			var message = JSON.parse_string(data.get_string_from_utf8())
			if message is Dictionary: _message(message)
		else: _frame(data)
	if socket == null: return
	if now - _last_received > 15:
		_disconnected("TIMEOUT")
		return
	if now - _ping_at > 5:
		_ping_at = now
		_send({"t": "ping", "at": now})
	if joined and now - _sent_at >= .05:
		_sent_at = now
		_send_input()
	if joined and _appearance_supported and _appearance_dirty and now >= _appearance_at:
		_appearance_at = now + 1
		_appearance_dirty = false
		_send({"t": "appearance", "appearance": OnlineAppearance.payload(Avatar.load_outfit())})
	if crowd:
		var mover: PlayerMover = mover_source.call() if mover_source.is_valid() else null
		crowd.step(delta, mover.position if mover else Vector3.ZERO)

func _disconnected(reason: String) -> void:
	_generation += 1
	if socket: socket.close()
	socket = null
	joined = false
	error = reason
	_pending.clear()
	members.clear()
	if crowd: crowd.clear()
	_attempt += 1
	_retry_at = _seconds() + minf(10, pow(2, mini(_attempt - 1, 4))) + randf() * .25
	_update_badge()
	connection_changed.emit()

func _send(data: Dictionary) -> void:
	if socket and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if socket.get_current_outbound_buffered_amount() > 32 * 1024:
			_disconnected("SLOW_CLIENT")
			return
		socket.send_text(JSON.stringify(data))

func _send_input() -> void:
	var mover: PlayerMover = mover_source.call() if mover_source.is_valid() else null
	if mover == null: return
	var target := mover.position
	var enabled := not input_enabled.is_valid() or bool(input_enabled.call())
	if enabled and not is_instance_valid(panel):
		if mover.joystick != Vector2.ZERO:
			target += Vector3(mover.joystick.x, 0, mover.joystick.y).limit_length() * mover.speed * .25
		elif not mover.remaining_path().is_empty(): target = mover.remaining_path()[0]
	var animation := str(animation_source.call()) if animation_source.is_valid() else "idle"
	_seq += 1
	_prediction_history[_seq] = mover.position
	_prediction_history.erase(_seq - 128)
	var message := {"t": "input", "seq": _seq, "epoch": epoch, "x": target.x, "z": target.z,
		"yaw": atan2(mover.facing.x, mover.facing.z), "action": animation}
	var fishing: FishingPanel = get_parent().get("fishing_panel") if kind in ["farm", "street", "pond"] else null
	if fishing and fishing.visible:
		var direction := fishing.landing - mover.position
		message.yaw = atan2(direction.x, direction.z)
		message.fishing = {"sequence": fishing._sequence(), "held": fishing.held, "fish": float(fishing.model.get("fish", 0.5))}
	_send(message)

func _outfit_saved(_config: AvatarConfig) -> void:
	_appearance_dirty = true

func act(action: String, node := "") -> bool:
	if not joined: return false
	_command_seq += 1
	var sequence := _command_seq
	var generation := _generation
	var started := _seconds()
	_pending[sequence] = null
	_send_input()
	_send({"t": "act", "seq": sequence, "epoch": epoch, "action": action, "node": node})
	while is_inside_tree() and joined and generation == _generation and _seconds() - started < 8:
		if _pending.get(sequence) is Dictionary:
			var result: Dictionary = _pending[sequence]
			_pending.erase(sequence)
			error = str(result.get("code", ""))
			return bool(result.get("ok", false))
		await get_tree().process_frame
	if generation == _generation: _pending.erase(sequence)
	# Actions are never replayed across connections; the new full snapshot resolves the result.
	if joined and generation == _generation: _disconnected("TIMEOUT")
	return false

func _message(message: Dictionary) -> void:
	match str(message.get("t", "")):
		"authenticated":
			_appearance_supported = int(message.get("appearance_version", 0)) == 1
			var request := join_args.duplicate()
			request.merge({"t": "join", "kind": kind}, true)
			if _appearance_supported:
				request.appearance = OnlineAppearance.payload(Avatar.load_outfit())
				_appearance_dirty = false
			if kind == "mine" and not _resume_ticket.is_empty(): request.resume = _resume_ticket
			_send(request)
		"joined":
			joined = true
			_attempt = 0
			self_id = int(message.self)
			room = str(message.room)
			join_args.erase("travel_ticket")
			_set_floor(message)
			error = ""
			_update_badge()
			connection_changed.emit()
			_refresh_farm()
		"floor": _set_floor(message)
		"appearance_result":
			if message.get("code") == "APPEARANCE_RATE_LIMIT": _appearance_dirty = true
		"departed":
			_departed = true
			joined = false
		"pong":
			if message.get("resume") is String: _resume_ticket = str(message.resume)
		"world":
			if int(message.get("epoch", -1)) != epoch: return
			world = message
			world_changed.emit(world)
			if _arrival_pending:
				var arrived_mover: PlayerMover = mover_source.call() if mover_source.is_valid() else null
				if arrived_mover:
					arrived_mover.stop()
					arrived_mover.position = _arrival_position
				_arrival_pending = false
		"roster":
			count = int(message.count)
			members.clear()
			for member in message.members:
				if int(member.id) != self_id: members[int(member.id)] = member
			crowd.roster(members)
			_update_badge()
		"left":
			members.erase(int(message.id))
			count = int(message.count)
			crowd.roster(members)
			_update_badge()
		"peer":
			count = int(message.count)
			var peer = message.get("member")
			if peer is Dictionary and int(peer.id) != self_id: members[int(peer.id)] = peer
			crowd.roster(members)
			_update_badge()
		"fishing":
			if int(message.get("epoch", -1)) == epoch: crowd.fishing_snapshot(message.get("members", []))
		"enemies":
			if int(message.floor) == floor_number: enemies_changed.emit(message.monsters)
		"result":
			var sequence := int(message.seq)
			if _pending.has(sequence): _pending[sequence] = message
		"farm_changed": _refresh_farm()
		"party_changed":
			if is_instance_valid(panel): _refresh_party()
		"voice_changed": Voice.invalidate_membership()
		"rescued":
			floor_number = 0
			rescued.emit()
		"error":
			var travel_failed := join_args.has("travel_ticket")
			error = str(message.get("code", "ONLINE_UNAVAILABLE"))
			# A full/private room is a decision, not an unbounded automatic retry loop.
			stop()
			_update_badge()
			if travel_failed or (get_parent().has_meta("party_travel") and error in ["NOT_FOUND", "PARTY_CHANGED", "PARTY_ACCESS_REQUIRED"]):
				_access_revoked.call_deferred(error)

func _set_floor(message: Dictionary) -> void:
	if message.get("resume") is String: _resume_ticket = str(message.resume)
	epoch = int(message.epoch)
	_prediction_history.clear()
	_last_snapshot_tick = -1
	floor_number = int(message.floor)
	_arrival_position = Vector3(float(message.spawn[0]), 0, float(message.spawn[1]))
	_arrival_pending = true
	world = {}
	members.clear()
	crowd.clear()
	var mover: PlayerMover = mover_source.call() if mover_source.is_valid() else null
	if mover:
		mover.stop()
		mover.position = Vector3(float(message.spawn[0]), 0, float(message.spawn[1]))

func _frame(data: PackedByteArray) -> void:
	if data.size() < 12 or data.decode_u16(0) != 1 or int(data.decode_u32(6)) != epoch: return
	var tick := int(data.decode_u32(2))
	if tick <= _last_snapshot_tick: return
	_last_snapshot_tick = tick
	var size := int(data.decode_u16(10))
	if size > 300 or data.size() != 12 + size * 26: return
	for index in size:
		var at := 12 + index * 26
		var id := int(data.decode_u16(at))
		var position := Vector3(data.decode_float(at + 2), 0, data.decode_float(at + 6))
		if not position.is_finite(): continue
		var state := {"position": position, "yaw": data.decode_float(at + 10), "hp": int(data.decode_u16(at + 14)),
			"max_hp": int(data.decode_u16(at + 16)), "action": int(data[at + 18]), "serial": int(data.decode_u16(at + 24))}
		if id == self_id:
			self_state = state
			var mover: PlayerMover = mover_source.call() if mover_source.is_valid() else null
			# 私有农场里不回滚自身位置。街道与矿井是共享空间，服务端驱动移动、回传权威
			# 位置，这套预测-校正才成立；农场是单人空间，服务端那边的位置基本不动，
			# 校正就变成了和本地寻路对着拉：真机实测本地每帧推进 0.031m（3.75 m/s @120fps），
			# 每个快照又把人按 25% 拉回去，净位移只剩约 3%，路径永远走不完，于是
			# mover.is_moving() 恒真、runner.paused 永远清不掉，劳作队列卡死在「正在前往…」。
			# 断线时校正停了，人反而自己走到了——这正是 2026-09-17 真机现场的表现。
			# 仍然照常上报位置（见 _send_input），访客与队友看到的我们不受影响。
			if mover and kind != "farm":
				var acknowledged := int(data.decode_u32(at + 20))
				var corrected := position
				if _prediction_history.has(acknowledged): corrected += mover.position - (_prediction_history[acknowledged] as Vector3)
				if not mover.bp.is_walkable(mover.bp.world_to_cell(corrected)): corrected = position
				var difference := mover.position.distance_to(corrected)
				if difference > 1.5: mover.position = corrected
				elif difference > .12: mover.position = mover.position.lerp(corrected, .25)
				for sequence in _prediction_history.keys():
					if int(sequence) <= acknowledged: _prediction_history.erase(sequence)
		elif members.has(id): crowd.sample(id, state)

func _refresh_farm() -> void:
	if _refreshing:
		_refresh_again = true
		return
	_refreshing = true
	await session.refresh()
	_refreshing = false
	if _refresh_again and is_inside_tree():
		_refresh_again = false
		_refresh_farm()

func _update_badge() -> void:
	if not is_instance_valid(badge): return
	badge.text = ""
	if is_instance_valid(_badge_count): _badge_count.text = str(count) if joined else "…"
	badge.tooltip_text = error_text(error) if not error.is_empty() else (L10n.format_text("Online %d / 300", count) if joined else L10n.text("Connecting party" if active else "Party & online"))
	_sync_badge_visibility()

func consume_back() -> bool:
	if is_instance_valid(_travel_confirmation):
		_travel_confirmation.canceled.emit()
		return true
	if travel_busy: return true
	if not is_instance_valid(panel): return false
	panel.queue_free()
	panel = null
	_travel_notice = ""
	if is_instance_valid(_copy_toast):
		_copy_toast.hide()
		_copy_toast_timer.stop()
	if is_instance_valid(_modal_shield): _modal_shield.queue_free()
	_modal_shield = null
	return true

func _open_party() -> void:
	if is_instance_valid(panel): return
	if GameUi.modal_is_open(get_parent()): return
	var mover: PlayerMover = mover_source.call() if mover_source.is_valid() else null
	if mover: mover.stop()
	# Close on a completed backdrop click. Keep its press/release above the world
	# so dismissing the panel cannot also move the character or start an action.
	var backdrop := Button.new()
	backdrop.name = "PartyBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.focus_mode = Control.FOCUS_NONE
	for style in ["normal", "hover", "pressed", "focus"]:
		var shade := StyleBoxFlat.new()
		shade.bg_color = Color(GameUi.INK, 0.26)
		backdrop.add_theme_stylebox_override(style, shade)
	backdrop.pressed.connect(consume_back)
	_modal_shield = backdrop
	hud.add_child(_modal_shield)
	panel = PanelContainer.new()
	panel.name = "PartyPanel"
	panel.theme = GameUi.theme()
	panel.add_theme_stylebox_override("panel", GameUi.panel_style(14))
	GameUi.register_modal(panel)
	hud.add_child(panel)
	_layout_party()
	_draw_party()
	await _refresh_party()

func _refresh_party() -> void:
	if session == null or session.client == null: return
	if _party_refreshing:
		_party_refresh_again = true
		return
	_party_refreshing = true
	var response := await session.client.request("GET", "/online/status")
	_party_refreshing = false
	if not is_instance_valid(panel): return
	var changed := true
	if response.is_success():
		changed = JSON.stringify(directory) != JSON.stringify(response.json)
		directory = response.json
		Net.online_available = int(directory.get("protocol", 0)) == 1
	else: error = str(response.json.get("code", "ONLINE_UNAVAILABLE"))
	if changed or not error.is_empty() or panel.get_child_count() == 0: _draw_party()
	if _party_refresh_again:
		_party_refresh_again = false
		_refresh_party.call_deferred()

func _draw_party() -> void:
	if not is_instance_valid(panel): return
	var scroll_position := 0
	var previous_scroll := panel.find_child("PartyScroll", true, false) as ScrollContainer
	if previous_scroll: scroll_position = previous_scroll.scroll_vertical
	for child in panel.get_children():
		panel.remove_child(child)
		child.queue_free()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 9)
	column.add_child(header)
	header.add_child(GameUi.picture(GameUi.icon("users-round"), 28))
	var heading := GameUi.label(L10n.text("Party & online"), 18)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(heading)
	var close := _button("", "x")
	close.name = "CloseParty"
	close.tooltip_text = L10n.text("Close")
	close.pressed.connect(consume_back)
	header.add_child(close)
	var scroll := TouchScrollContainer.new()
	scroll.name = "PartyScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	scroll.set_deferred("scroll_vertical", scroll_position)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	var information := GameUi.label("", 12, GameUi.MUTED)
	information.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	information.text = L10n.text("Use Go to leader to meet across neighbourhoods. Owners can allow party farm visits.") if int(directory.get("travel_version", 0)) >= 1 else L10n.text("Join a party, then re-enter the mine to follow its leader. The leader must be inside.")
	box.add_child(information)
	if travel_busy:
		var preparing := Label.new()
		preparing.text = L10n.text("Preparing to meet your party...")
		box.add_child(preparing)
	if not error.is_empty() or not _travel_notice.is_empty():
		var warning := Label.new()
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warning.text = _travel_notice if error.is_empty() else error_text(error)
		box.add_child(warning)
	var instance := str(directory.get("instance", ""))
	if not instance.is_empty():
		var saved := Label.new()
		saved.text = L10n.format_text("Mine instance: %s", instance.substr(0, 8))
		box.add_child(saved)
	var party = directory.get("party")
	if not party is Dictionary and Voice.active(): _add_voice_controls(box)
	if party is Dictionary:
		var members_card := _party_section(box)
		var copy := _button(L10n.format_text("Invite code: %s", party.code), "clipboard-list")
		copy.name = "CopyInviteCode"
		copy.pressed.connect(_copy_invite_code.bind(str(party.code)))
		members_card.add_child(copy)
		var summary := Label.new()
		summary.text = L10n.format_text("Party members: %d / 300", party.members.size())
		members_card.add_child(summary)
		var selector := OptionButton.new()
		for member in party.members:
			selector.add_item((L10n.text("Leader") + " · " if member == party.leader else "") + str(member).substr(0, 8))
		members_card.add_child(selector)
		if _selected_member in party.members: selector.select(party.members.find(_selected_member))
		else: _selected_member = str(party.members[selector.selected])
		selector.item_selected.connect(func(index):
			_selected_member = str(party.members[index])
			_draw_party.call_deferred())
		if int(directory.get("travel_version", 0)) >= 1:
			_add_travel_controls(members_card, party)
		if party.leader == session.player_id:
			var transfer := _button(L10n.text("Make leader"), "users-round")
			transfer.pressed.connect(func(): _party_action("leader", str(party.members[selector.selected])))
			members_card.add_child(transfer)
			var kick := _button(L10n.text("Remove member"), "minus")
			kick.pressed.connect(func(): _party_action("kick", str(party.members[selector.selected])))
			members_card.add_child(kick)
			var disband := _button(L10n.text("Disband party"), "x")
			disband.pressed.connect(func(): _party_action("disband"))
			members_card.add_child(disband)
		var leave := _button(L10n.text("Leave party"), "arrow-left")
		leave.pressed.connect(func(): _party_action("leave"))
		members_card.add_child(leave)
		if directory.get("voice", {}).get("available", false) or Voice.active(): _add_voice_controls(box)
	else:
		var join_card := _party_section(box)
		var create := _button(L10n.text("Create party"), "users-round")
		create.pressed.connect(func(): _party_action("create"))
		join_card.add_child(create)
		var code := LineEdit.new()
		code.custom_minimum_size.y = 46
		code.clear_button_enabled = true
		code.placeholder_text = L10n.text("Enter invite code")
		code.max_length = 12
		join_card.add_child(code)
		var join := _button(L10n.text("Join party"), "users-round")
		join.pressed.connect(func(): _party_action("join", code.text.strip_edges()))
		join_card.add_child(join)
	if kind != "mine":
		var travel_card := _party_section(box)
		var reset := _button(L10n.text("Reset mine"), "refresh-cw")
		reset.pressed.connect(func():
			var confirmation := ConfirmationDialog.new()
			confirmation.title = L10n.text("Reset mine")
			confirmation.dialog_text = L10n.text("Reset all mine progress and unclaimed resources? Everyone must be outside.")
			confirmation.confirmed.connect(_reset_mine)
			confirmation.canceled.connect(confirmation.queue_free)
			confirmation.confirmed.connect(confirmation.queue_free)
			add_child(confirmation)
			_show_confirmation(confirmation))
		travel_card.add_child(reset)
		var line := SpinBox.new()
		line.min_value = 1
		line.max_value = 100
		line.value = int(join_args.get("channel", 1))
		line.prefix = L10n.text("Channel") + " "
		travel_card.add_child(line)
		var change := _button(L10n.text("Switch channel"), "refresh-cw")
		change.pressed.connect(func():
			join_args.channel = int(line.value)
			stop()
			consume_back()
			start())
		travel_card.add_child(change)
	if not active:
		var reconnect := _button(L10n.text("Reconnect"), "refresh-cw")
		reconnect.pressed.connect(func(): consume_back(); start())
		box.add_child(reconnect)
	if travel_busy:
		for button in panel.find_children("*", "BaseButton", true, false): button.disabled = true
	_update_voice_controls()

func _party_section(parent: VBoxContainer) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", GameUi.card_style(false, 11))
	parent.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	card.add_child(body)
	return body

func _add_voice_controls(box: VBoxContainer) -> void:
	box = _party_section(box)
	_voice_status = GameUi.label("", 13, GameUi.GREEN)
	_voice_status.name = "PartyVoiceStatus"
	_voice_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_voice_status)
	_voice_join = _button("", "users-round")
	_voice_join.name = "PartyVoiceJoin"
	_voice_join.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_voice_join.pressed.connect(func():
		if Voice.active(): Voice.leave()
		else: Voice.join(session))
	box.add_child(_voice_join)
	var controls := HFlowContainer.new()
	controls.add_theme_constant_override("h_separation", 8)
	controls.add_theme_constant_override("v_separation", 6)
	box.add_child(controls)
	_voice_mic = _button("", "")
	_voice_mic.name = "PartyVoiceMic"
	_voice_mic.pressed.connect(func(): Voice.set_microphone(not Voice.microphone))
	_voice_listen = _button("", "")
	_voice_listen.name = "PartyVoiceListen"
	_voice_listen.pressed.connect(func(): Voice.set_listening(not Voice.listening))
	for button in [_voice_mic, _voice_listen]:
		button.add_theme_font_size_override("font_size", 12)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		controls.add_child(button)
	_voice_speakers = GameUi.label("", 12, GameUi.MUTED)
	_voice_speakers.name = "PartyVoiceSpeakers"
	_voice_speakers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_voice_speakers)

func _update_voice_controls() -> void:
	if is_instance_valid(_voice_badge):
		_voice_badge.text = ""
		_voice_badge.icon = GameUi.icon("mic" if Voice.microphone else "mic-off")
		_voice_badge.tooltip_text = L10n.text("Voice: mic on" if Voice.microphone else "Voice: muted")
		_layout_badge()
		_sync_badge_visibility()
	if not is_instance_valid(_voice_status) or not is_instance_valid(_voice_join): return
	_voice_status.text = Voice.status_text() if Voice.supported() else PartyVoiceSession.error_text("VOICE_UNSUPPORTED")
	_voice_join.text = L10n.text("Leave voice" if Voice.active() else "Join voice")
	_voice_join.disabled = travel_busy or not Voice.supported()
	_voice_mic.text = L10n.text("Mute microphone" if Voice.microphone else "Unmute microphone")
	_voice_listen.text = L10n.text("Stop listening" if Voice.listening else "Resume listening")
	_voice_mic.disabled = travel_busy or Voice.state != "connected"
	_voice_listen.disabled = _voice_mic.disabled
	var speakers: Array = Voice.participants.filter(func(p): return p is Dictionary and p.get("speaking", false)).map(func(p): return str(p.get("name", str(p.get("id", "")).substr(0, 8))))
	_voice_speakers.text = L10n.format_text("Speaking: %s", ", ".join(speakers)) if not speakers.is_empty() else ""

func _copy_invite_code(code: String) -> void:
	DisplayServer.clipboard_set(code)
	if not is_instance_valid(_copy_toast):
		_copy_toast = PanelContainer.new()
		_copy_toast.name = "InviteCodeToast"
		_copy_toast.theme = GameUi.theme()
		_copy_toast.theme_type_variation = &"ToastPanel"
		_copy_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := GameUi.label(L10n.text("Invite code copied"), 14, GameUi.PAPER)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_copy_toast.add_child(label)
		hud.add_child(_copy_toast)
		_copy_toast_timer = Timer.new()
		_copy_toast_timer.one_shot = true
		_copy_toast_timer.wait_time = 2.0
		_copy_toast_timer.timeout.connect(_copy_toast.hide)
		_copy_toast.add_child(_copy_toast_timer)
	var size := get_viewport().get_visible_rect().size
	# Keep the short toast above the panel, clear of Android's clipboard overlay.
	_copy_toast.position = Vector2(24, maxf(24, panel.position.y - 60))
	_copy_toast.size = Vector2(size.x - 48, 48)
	(_copy_toast.get_child(0) as Label).text = L10n.text("Invite code copied")
	hud.move_child(_copy_toast, -1)
	_copy_toast.show()
	_copy_toast_timer.start()

func _party_action(action: String, value := "") -> void:
	var response := await session.client.request("POST", "/online/party", {"action": action, "value": value})
	error = "" if response.is_success() else str(response.json.get("code", "ONLINE_UNAVAILABLE"))
	if is_instance_valid(panel): await _refresh_party()

func _add_travel_controls(box: VBoxContainer, party: Dictionary) -> void:
	var permission := CheckButton.new()
	permission.text = L10n.text("Allow my party to visit my farm")
	permission.set_pressed_no_signal(bool(directory.get("farm_access", false)))
	permission.toggled.connect(func(allowed): _party_action("farm_access", "allow" if allowed else "deny"))
	box.add_child(permission)
	var rows: Array = directory.get("roster", [])
	var leader: Dictionary = {}
	var selected: Dictionary = {}
	for row in rows:
		if str(row.player) == str(party.leader): leader = row
		if str(row.player) == _selected_member: selected = row
	var follow := _button(L10n.text("Go to leader"), "users-round", true)
	follow.disabled = str(party.leader) == session.player_id or not bool(leader.get("online", false))
	follow.pressed.connect(func(): request_travel("", "leader"))
	box.add_child(follow)
	var position_label := Label.new()
	position_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	position_label.text = L10n.text("Selected member") + ": " + PartyTravel.scene_label(selected.get("scene"))
	box.add_child(position_label)
	var meet := _button(L10n.text("Go to this member"), "route")
	meet.visible = _selected_member != str(party.leader)
	var scene = selected.get("scene")
	meet.disabled = _selected_member == session.player_id or not bool(selected.get("online", false)) or (scene is Dictionary and scene.kind == "mine" and _selected_member != str(party.leader))
	meet.pressed.connect(func(): request_travel(_selected_member, "follow"))
	box.add_child(meet)
	var visit := _button(L10n.text("Visit member farm"), "sprout")
	visit.disabled = _selected_member == session.player_id or not bool(selected.get("can_visit_farm", false))
	visit.pressed.connect(func(): request_travel(_selected_member, "farm"))
	box.add_child(visit)
	if not bool(selected.get("can_visit_farm", false)):
		var hint := Label.new()
		hint.text = L10n.text("Ask the owner to allow party farm visits")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(hint)

func request_travel(target: String, mode: String) -> void:
	if travel_busy or session == null: return
	if kind == "mine" and not joined:
		_travel_failed("TRAVEL_BUSY")
		return
	travel_busy = true
	_travel_notice = ""
	var generation := _generation
	_draw_party()
	var host := get_parent()
	var mover: PlayerMover = mover_source.call() if mover_source.is_valid() else null
	if mover: mover.stop()
	if host.has_method("_cancel_work"): host.call("_cancel_work")
	if is_instance_valid(panel):
		for button in panel.find_children("*", "BaseButton", true, false): button.disabled = true
	# Let already-issued farm/attack/mining operations settle before leaving their scene.
	var started := _seconds()
	while is_inside_tree() and _seconds() - started < 8 and not _travel_ready(host):
		await get_tree().process_frame
	if not is_inside_tree(): return
	if not _travel_ready(host) or session.has_unconfirmed_command():
		_travel_failed("TRAVEL_BUSY")
		return
	var response := await session.client.request("POST", "/online/travel", {"target": target, "mode": mode})
	if not is_inside_tree(): return
	if not response.is_success():
		_travel_failed(str(response.json.get("code", "ONLINE_UNAVAILABLE")))
		return
	var manifest := response.json
	# Reject incompatible admission before refreshing, leaving or replacing our scene.
	if str(manifest.get("kind", "")) == "street":
		_travel_failed("FARM_UPDATE_REQUIRED")
		return
	if joined and str(manifest.room) == room and int(manifest.floor) == floor_number:
		_travel_failed("ALREADY_THERE")
		return
	if bool(manifest.get("replaces_instance", false)):
		_travel_confirmation = ConfirmationDialog.new()
		_travel_confirmation.title = L10n.text("Join leader's mine")
		_travel_confirmation.dialog_text = L10n.text("Use the leader's mine progress? Your previous mine entry will be replaced.")
		_travel_confirmation.confirmed.connect(func(): travel_confirmed.emit(true), CONNECT_ONE_SHOT)
		_travel_confirmation.canceled.connect(func(): travel_confirmed.emit(false), CONNECT_ONE_SHOT)
		add_child(_travel_confirmation)
		_show_confirmation(_travel_confirmation)
		var accepted: bool = await travel_confirmed
		if not is_inside_tree(): return
		_travel_confirmation.queue_free()
		_travel_confirmation = null
		if not accepted:
			travel_busy = false
			_draw_party()
			return
	# Reconcile the inventory journal, then acknowledge an explicit departure (not a reconnect).
	if not await session.refresh() or session.has_unconfirmed_command():
		_travel_failed("TRAVEL_BUSY")
		return
	if generation != _generation:
		_travel_failed("TRAVEL_BUSY")
		return
	if joined:
		_departed = false
		_send({"t": "leave"})
		started = _seconds()
		while is_inside_tree() and active and not _departed and _seconds() - started < 10:
			await get_tree().process_frame
		if not _departed:
			_travel_failed("ONLINE_UNAVAILABLE")
			return
	var resume_origin := active
	stop()
	_suspended = resume_origin
	travel_busy = false
	consume_back()
	AppRouter.open_party_destination(manifest, session, host)

func _show_confirmation(dialog: ConfirmationDialog) -> void:
	# Embedded window titles and unwrapped labels otherwise force phone dialogs
	# wider than the viewport. Keep the complete progress warning in the body.
	dialog.borderless = true
	dialog.unresizable = true
	dialog.dialog_autowrap = true
	dialog.theme = GameUi.theme()
	dialog.theme.set_stylebox("panel", "AcceptDialog", GameUi.panel_style(18))
	GameUi.register_modal(dialog)
	dialog.dialog_text = dialog.title + "\n\n" + dialog.dialog_text
	dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.get_ok_button().text = dialog.title
	dialog.get_ok_button().theme_type_variation = &"AccentButton"
	dialog.get_cancel_button().text = L10n.text("Cancel")
	var width := mini(320, int(get_viewport().get_visible_rect().size.x) - 32)
	dialog.popup_centered(Vector2i(width, 220))

func _travel_ready(host: Node) -> bool:
	if not _pending.is_empty(): return false
	if host.has_method("party_travel_ready"): return bool(host.call("party_travel_ready"))
	return true

func _travel_failed(code: String) -> void:
	travel_busy = false
	error = code
	_draw_party()

func _access_revoked(code := "ACCESS_REVOKED") -> void:
	if AppRouter.top_instance() == get_parent(): AppRouter.pop_instance()
	var source := AppRouter.top_instance()
	if source and source.get("online"):
		var previous: OnlineSpace = source.get("online")
		previous.error = code
		previous._travel_notice = error_text(code)
		previous._open_party()

func _reset_mine() -> void:
	var response := await session.client.request("POST", "/online/reset", {"confirm": true})
	error = "" if response.is_success() else str(response.json.get("code", "ONLINE_UNAVAILABLE"))
	if is_instance_valid(panel): await _refresh_party()

static func error_text(code: String) -> String:
	var messages := {"ROOM_FULL": "This space is full. Choose another channel or wait.",
		"NOT_LEADER": "Only the party leader can do that.", "PARTY_NOT_FOUND": "Party not found. Check the invite code.",
		"ALREADY_IN_PARTY": "Leave your current party first.", "INSTANCE_OCCUPIED": "Everyone must leave the mine before resetting.",
		"INSTANCE_NOT_EXHAUSTED": "Unclaimed mine resources remain.", "OUT_OF_RANGE": "Move closer first.",
		"SESSION_REPLACED": "This account connected on another device.", "PARTY_FULL": "This party has 300 members.",
		"UNAUTHENTICATED": "Please reconnect your account.", "NOT_FOUND": "This farm is not open to visitors."}
	messages["RESUME_EXPIRED"] = "Recovery expired. Re-enter the mine to continue."
	messages["POND_UPDATE_REQUIRED"] = "This pond needs an app update."
	messages["POND_NOT_FOUND"] = "This pond is unavailable. Return to the map."
	messages.merge({"PARTY_CHANGED": "The party changed. Choose your destination again.",
		"FARM_UPDATE_REQUIRED": "This server needs the farm update before you can join that teammate.",
		"TARGET_OFFLINE": "This teammate is offline or outside an online space.",
		"DESTINATION_CHANGED": "Your teammate moved. Choose the destination again.",
		"TRAVEL_EXPIRED": "The travel invitation expired. Try again.",
		"PARTY_ACCESS_REQUIRED": "Ask the owner to allow party farm visits",
		"ACCESS_REVOKED": "Party farm access ended. You have returned.",
		"FOLLOW_LEADER_MINE": "Mine progress follows the party leader.",
		"TRAVEL_BUSY": "Wait for the current action to finish syncing.",
		"ALREADY_THERE": "You are already in the same scene."})
	return L10n.text(str(messages.get(code, "Could not connect. Try again.")))

static func _seconds() -> float:
	return Time.get_ticks_msec() / 1000.0

static func _button(text: String, icon: String, accent := false) -> Button:
	var button := GameUi.button(icon, text, text, accent)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return button
