class_name FriendCard
extends RefCounted
## 地图上点好友（3D 角色或底部好友条）弹出的小卡：头像 + 昵称 / @handle + 距离 + 位置新鲜度 + 两个动作。
## 直接跳进主页太重——在地图上多数时候只是想看一眼这人在哪、顺手发条消息，看完还要留在地图上。
## 节点名：FriendCard / Avatar / Who / Meta / Profile / Message / Close。
##
## ctx: {now_ms: Callable, me_lat: float, me_lng: float, has_me: bool,
##       on_profile(user_id), on_message(user_id), on_close()}

## 文案键单列一行：抽取器只认 tr("…") 或带 ## i18n 尾注的行，静态方法里没有 self.tr()。
const T_CLOSE := "Close" ## i18n
const T_PROFILE := "Profile" ## i18n
const T_MESSAGE := "Message" ## i18n
const T_NEARBY := "nearby" ## i18n
const T_M_AWAY := "%d m away" ## i18n
const T_KM_AWAY := "%.1f km away" ## i18n
const T_KM_AWAY_ROUND := "%d km away" ## i18n

static func _text(v: Variant) -> String:
	return "" if v == null else str(v)

static func build(f: Dictionary, ctx: Dictionary) -> PanelContainer:
	var uid := _text(f.get("user_id", ""))
	var panel := PanelContainer.new()
	panel.name = "FriendCard"
	panel.add_theme_stylebox_override("panel", GameUi.surface())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	col.add_child(head)
	var thumb := AvatarThumb.new(56.0)
	thumb.name = "Avatar"
	head.add_child(thumb)
	thumb.show_avatar(f.get("avatar"))
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", DesignTokens.SPACE_1)
	head.add_child(texts)
	var handle := _text(f.get("handle", ""))
	var name := _text(f.get("display_name", ""))
	var who := GameUi.label(name if not name.is_empty() else "@" + handle, DesignTokens.UI_FONT_BODY)
	who.name = "Who"
	texts.add_child(who)
	var meta := GameUi.label(meta_text(f, ctx), DesignTokens.UI_FONT_CAPTION, GameUi.MUTED)
	meta.name = "Meta"
	texts.add_child(meta)
	var close := GameUi.button("x", "", tr_s(T_CLOSE))
	close.name = "Close"
	close.theme_type_variation = &"SecondaryButton"
	close.focus_mode = Control.FOCUS_NONE
	_on(close, ctx.get("on_close", Callable()))
	head.add_child(close)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	col.add_child(actions)
	var profile := GameUi.button("user-round", tr_s(T_PROFILE), "AppRoutes.USER")
	profile.name = "Profile"
	profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_on_id(profile, ctx.get("on_profile", Callable()), uid)
	actions.add_child(profile)
	var message := GameUi.button("message-circle", tr_s(T_MESSAGE), "POST /im/dm")
	message.name = "Message"
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_on_id(message, ctx.get("on_message", Callable()), uid)
	actions.add_child(message)
	return panel

static func _on(b: Button, cb: Variant) -> void:
	if cb is Callable and (cb as Callable).is_valid():
		b.pressed.connect(cb as Callable)

static func _on_id(b: Button, cb: Variant, user_id: String) -> void:
	if cb is Callable and (cb as Callable).is_valid():
		b.pressed.connect((cb as Callable).bind(user_id))

## 「1.2 km 外 · 5 分钟前」；不知道自己在哪就只说新鲜度。
static func meta_text(f: Dictionary, ctx: Dictionary) -> String:
	var now_ms: int = int((ctx.now_ms as Callable).call()) if ctx.get("now_ms") is Callable and (ctx.now_ms as Callable).is_valid() \
		else int(Time.get_unix_time_from_system() * 1000.0)
	var fresh := PostCard.age_text(now_ms, int(f.get("updated_at", 0)) if f.get("updated_at") != null else 0)
	if not bool(ctx.get("has_me", false)):
		return fresh
	var m := distance_m(f, float(ctx.get("me_lat", 0.0)), float(ctx.get("me_lng", 0.0)))
	return "%s · %s" % [distance_text(m), fresh]

## 到某个好友的地面距离（米）。用地图同一套局部投影，短距离足够准，跨洲也不会算出负数。
static func distance_m(f: Dictionary, me_lat: float, me_lng: float) -> float:
	return MapGeoMath.geo_to_world(float(f.get("lat", 0.0)), float(f.get("lng", 0.0)), me_lat, me_lng).length()

## 距离文案：百米以内说「就在附近」，一公里以内给整米，再远给公里（超过 100 km 不要小数）。
static func distance_text(meters: float) -> String:
	if meters < 100.0:
		return tr_s(T_NEARBY)
	if meters < 1000.0:
		return tr_s(T_M_AWAY) % int(round(meters / 10.0) * 10)
	var km := meters / 1000.0
	if km < 100.0:
		return tr_s(T_KM_AWAY) % km
	return tr_s(T_KM_AWAY_ROUND) % int(round(km))

static func tr_s(s: String) -> String:
	return TranslationServer.translate(s)
