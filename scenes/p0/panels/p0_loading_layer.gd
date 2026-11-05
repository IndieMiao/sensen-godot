class_name P0LoadingLayer
extends CanvasLayer
## SYS-LOADING-SCENE (§10.7.1, SGODOT-233; the town map with a progress bar, 不知火舞's spec v1 / L123v2, the user
## 11-06) for AppRouter.open_instance into a P0 world: the destination's pin, where the player is going and the bar.
## It takes every touch at once but only shows after MOTION_PENDING_DELAY_MS (F-08: a quick load never flashes it),
## fading in over FADE_IN_S with the pin dropping in; 8 s in it adds `Taking longer than usual…`. The bar: the
## scene's threaded load 0–LOADED_AT (AppRouter's progress()), the rest when it is built (finish()), eased to catch up
## in at most CATCH_UP_S, never back; full, it holds HOLD_S and fades out over FADE_OUT_S, shown MIN_SHOWN_S at least.
## No made-up progress for the server's answer: that wait is the world's own cover (P0Runtime's arrival).
## AppRouter's loading contract: failed(), close_button (the PLACE_FAIL card's Go back), and progress() / finish().

const P0City := preload("res://modules/p0/p0_city.gd")   # the P0 home city (SGODOT-270)
const SLOW_S := 8.0
const LOADED_AT := 0.85
const CATCH_UP_S := 0.25
const FADE_IN_S := 0.15
const HOLD_S := 0.15
const FADE_OUT_S := 0.2
const MIN_SHOWN_S := 0.4
const P0PondCard := preload("res://modules/p0/p0_pond_card.gd")
const P0WildSites := preload("res://modules/p0/p0_wild_sites.gd")
const P0Ponds := preload("res://modules/p0/p0_ponds.gd")   # pond names for the chip (SGODOT-270)

var screen: P0SysScreen
var close_button: Button
## Opens the place again after a failure (AppRouter.open_instance; tests replace it).
var reopen := func(path: String, args: Dictionary): AppRouter.open_instance(path, args)
var _age := 0.0
var _shot: Texture2D
var _path := ""
var _args := {}
var _target := 0.0      # where the bar is going (0–1)
var _shown_at := -1.0   # _age when the cover first showed, -1 before
var _leaving := false

func _init(place: String, shot: Texture2D = null, path := "", args := {}) -> void:
	layer = 120   # over every world and P0Ui, like AppRouter's own loading overlay
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shot = shot
	_path = path
	_args = args
	screen = P0SysScreen.new()
	screen.show_kind(P0SysScreen.Kind.SCENE, {place = place, icon = icon_for(path, args)})
	screen.modulate.a = 0.0
	screen.primary_pressed.connect(func(k: P0SysScreen.Kind): if k == P0SysScreen.Kind.PLACE_FAIL: _retry())
	add_child(screen)
	close_button = screen.card.secondary
	close_button.visible = false   # AppRouter's Back reads it: only a failed load can be backed out of

func _ready() -> void:
	GameUi.register_modal(self)   # like AppRouter's own overlay

## Retry: AppRouter's Go back clears this transition (close_button), then the same place opens again.
func _retry() -> void:
	close_button.pressed.emit()
	if _path != "": reopen.call_deferred(_path, _args)

func _process(dt: float) -> void:
	_age += dt
	if _shown_at < 0.0 and not _leaving and _age * 1000.0 >= UiTokens.MOTION_PENDING_DELAY_MS: _show()
	if not screen.slow and screen.kind == P0SysScreen.Kind.SCENE and _age >= SLOW_S: screen.taking_longer()
	if screen.progress < _target: screen.progress = move_toward(screen.progress, _target, dt / CATCH_UP_S)

## Past the pending delay: in over FADE_IN_S, the pin dropping into place.
func _show() -> void:
	_shown_at = _age
	if not is_inside_tree():
		screen.modulate.a = 1.0
		return
	create_tween().tween_property(screen, ^"modulate:a", 1.0, FADE_IN_S)
	screen.drop_pin()

## AppRouter, while the scene loads: `f` the threaded load's own progress (0–1), the bar's first LOADED_AT.
func progress(f: float) -> void:
	_target = maxf(_target, clampf(f, 0.0, 1.0) * LOADED_AT)

## AppRouter, the scene built and in: the bar fills, holds HOLD_S and the cover fades out (MIN_SHOWN_S on screen at
## least), then goes. Never shown (a quick load): it goes at once. It takes no touch from now — the new scene has them.
func finish() -> void:
	if _leaving: return
	_leaving = true
	_target = 1.0
	remove_from_group(GameUi.MODAL_GROUP)   # no longer a modal over the new scene (its Back works)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in screen.find_children("*", "Control", true, false): (c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _shown_at < 0.0 or not is_inside_tree():
		queue_free()
		return
	var tw := create_tween()
	tw.tween_interval(maxf(CATCH_UP_S * (1.0 - screen.progress), 0.0) + HOLD_S)
	var shown := _age - _shown_at + CATCH_UP_S * (1.0 - screen.progress) + HOLD_S
	if shown < MIN_SHOWN_S: tw.tween_interval(MIN_SHOWN_S - shown)
	tw.tween_property(screen, ^"modulate:a", 0.0, FADE_OUT_S)
	tw.tween_callback(queue_free)

## The place would not load: a card with Go back (AppRouter clears the transition on it).
func failed() -> void:
	screen.show_kind(P0SysScreen.Kind.PLACE_FAIL, {})
	screen.modulate.a = 1.0
	_shown_at = maxf(_shown_at, 0.0)

## The destination's pin icon, as its map pin has it: the farm's home, a pond's site (pond / river / coast), an
## outpost's role, a mine's type (quarry / vein …).
static func icon_for(path: String, args: Dictionary) -> Texture2D:
	match path.get_file():
		"p0_farm.tscn": return P0Logic.icon("home")
		"p0_pond.tscn": return P0Logic.icon(P0PondCard.pin_icon(str(args.get("pond_id", ""))))
		"p0_outpost.tscn":
			var role := str(P0Outposts.find(str(args.get("outpost_id", ""))).get("role", ""))
			if role == "casino": return P0Outposts.cards_icon()
			return P0Logic.icon(str({"tea": "pot", "tackle": "rod", "market": "board", "post": "travel", "mine_hut": "mine_hut"}.get(role, "travel")))
		"p0_mine.tscn":
			var t := str(P0WildSites.site(str(args.get("mine", ""))).get("type", "quarry"))
			return P0Logic.icon(str({"quarry": "quarry", "vein": "vein", "geode": "geode", "abyss": "abyss", "ruin": "ruins"}.get(t, "quarry")))
	return null

## Where an AppRouter.open_instance into a P0 world goes, as the place chip will read there (`San Francisco · Fern Pond`);
## "" for a scene that is not a P0 world (AppRouter keeps its own overlay).
static func destination(path: String, args: Dictionary) -> String:
	match path.get_file():
		"p0_farm.tscn": return P0City.chip("Homestead")
		"p0_pond.tscn": return P0City.chip_for(str(P0Ponds.location(str(args.get("pond_id", ""))).get("name", "Pond")), str(args.get("pond_id", "")))
		"p0_outpost.tscn": return P0City.chip_for(str(P0Outposts.find(str(args.get("outpost_id", ""))).get("name", "Outpost")), str(args.get("outpost_id", "")))
		"p0_mine.tscn": return P0City.chip("Mine · Floor %d" % int(args.get("floor", 1)))
	return ""
