class_name P0LoadingLayer
extends CanvasLayer
## SYS-LOADING-SCENE (1245:87648; §10.7.1, SGODOT-233) for AppRouter.open_instance into a P0 world: the screen being
## left, blurred under the scrim, the spinner and where the player is going. It takes every touch at once but only
## shows after MOTION_PENDING_DELAY_MS (F-08: a quick load never flashes it); 8 s in it adds `Taking longer than
## usual…`. AppRouter's loading contract: failed() and close_button (the PLACE_FAIL card's Go back).

const SLOW_S := 8.0

var screen: P0SysScreen
var close_button: Button
var _age := 0.0

func _init(place: String, shot: Texture2D = null) -> void:
	layer = 120   # over every world and P0Ui, like AppRouter's own loading overlay
	process_mode = Node.PROCESS_MODE_ALWAYS
	screen = P0SysScreen.new()
	screen.show_kind(P0SysScreen.Kind.SCENE, {place = place, shot = shot})
	screen.modulate.a = 0.0
	add_child(screen)
	close_button = screen.card.primary
	close_button.visible = false   # AppRouter's Back reads it: only a failed load can be backed out of

func _process(dt: float) -> void:
	_age += dt
	if screen.modulate.a < 1.0 and _age * 1000.0 >= UiTokens.MOTION_PENDING_DELAY_MS: screen.modulate.a = 1.0
	if not screen.slow and screen.kind == P0SysScreen.Kind.SCENE and _age >= SLOW_S: screen.taking_longer()

## The place would not load: a card with Go back (AppRouter clears the transition on it).
func failed() -> void:
	screen.show_kind(P0SysScreen.Kind.PLACE_FAIL)
	screen.modulate.a = 1.0

## Where an AppRouter.open_instance into a P0 world goes, as the place chip will read there (`Shanghai · Reed Pond`);
## "" for a scene that is not a P0 world (AppRouter keeps its own overlay).
static func destination(path: String, args: Dictionary) -> String:
	const CITY := "Shanghai · "
	match path.get_file():
		"p0_farm.tscn": return CITY + "Homestead"
		"p0_pond.tscn": return CITY + str(SystemPonds.location(str(args.get("pond_id", ""))).get("name", "Pond"))
		"p0_outpost.tscn": return CITY + str(P0Outposts.find(str(args.get("outpost_id", ""))).get("name", "Outpost"))
		"p0_mine.tscn": return CITY + "Mine · Floor %d" % int(args.get("floor", 1))
	return ""
