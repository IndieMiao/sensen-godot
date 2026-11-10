extends Node3D
## P0 homestead: the old polished farm presentation (cottage, well, seed box, garden dressing, thick
## soil beds, procedural crops, rig and labour clips, 43° ortho camera) driven by the P0 server view
## and the new UI flow (joystick, main action, quick bar, cards) from P0Runtime.
## Ponds are on the map; the kitchen is inside the farmhouse (P0Room, SGODOT-226); nothing here is greybox.

const P0City := preload("res://modules/p0/p0_city.gd")   # the P0 home city (SGODOT-270)
const P0FarmTemplate := preload("res://modules/p0/p0_farm_template.gd")   # the starting template by region (SGODOT-342)
const P0NoticeBoardLogic := preload("res://modules/p0/p0_notice_board.gd")   # the stall's Notice Board (q(164))
const FarmProps = preload("res://modules/farm/farm_props.gd")
const FarmCamera = preload("res://modules/farm/farm_camera.gd")
const FarmArt = preload("res://modules/farm/farm_art.gd")
const GardenScenery = preload("res://scenes/p0/p0_garden_scenery.gd")
const FarmWoods = preload("res://scenes/p0/p0_farm_woods.gd")
const GroundShade = preload("res://modules/render/ground_shade.gd")
const StripClear = preload("res://modules/p0/p0_strip_clear.gd")
const Fence = preload("res://scenes/p0/p0_fence.gd")
const FarmGuide = preload("res://scenes/p0/p0_farm_guide.gd")
const Looks = preload("res://scenes/p0/p0_looks.gd")
const HomePanel = preload("res://scenes/p0/home/p0_home_panel.gd")
const SIGN_BADGE := Vector3(0, 1.15, 0)   # the Homestead sign's mark, just above the board
const SIGN_NEAR := 2.6                    # metres: the sign's and the plaque's finger cards show this close
## The Home Badge (q(287); 赵云's homestead_badge.glb, its README's contract): its four tier faces under BadgeFace, the
## number and `Lv` written by Label3Ds on its BadgeNumber / BadgeLv sockets (tilted with the face), the root turned
## 14.5° on the farm. The tap at the face's centre (1.0 m up); the strip above the badge's top (1.38 m).
const BADGE := preload("res://assets/farm/art/homestead_badge.glb")
const BADGE_YAW := 14.5
## The whole badge 1.1 times the model, so its number stays ≥ 14 px on the 0.8 follow camera (q(287): it measured 13;
## 上官婉儿 401 60e493d5, 不知火舞 b3d362ee: the font fills the face already, the badge grows, not the number).
const BADGE_SCALE := 1.1
const BADGE_HIT := Vector3(0, 1.0 * BADGE_SCALE, 0)
const BADGE_MARK := Vector3(0, 1.95 * BADGE_SCALE, 0)   # the strip clear above the face's top (1.4 m), not over its number
const BADGE_NUMBER_CAP := 0.315   # metres of a digit's cap height (the model's review renders)
const BADGE_LV_CAP := 0.080
const BADGE_INK := Color("3B2F25")
const BADGE_FONT := preload("res://assets/ui/fonts/nunito_w800.tres")
const FARMHOUSE := "res://scenes/p0/rooms/p0_farmhouse.tscn"
## Walking into the doorway goes in (mirror of a room's door): inside the walkway cell in front of the door
## (DOOR_HALF either side; the camera-relative joystick drifts sideways), pushing towards the house, after
## having been DOOR_ARM_M away (so stepping out of the farmhouse does not walk straight back in).
const DOOR_HALF := Vector2(0.6, 0.4)
const DOOR_ARM_M := 1.5

var _style := "cottage"   # the home band's template style (P0FarmTemplate): every band wears the orange-roof cottage for now
var PLACE := P0City.chip("Home")
const BENCH_TAP_PX := 44.0   # a 44 px touch target around the bench seat (engineering default)
const BENCH_NEAR_M := 2.6    # the bench's finger card shows within this distance (stall 3.2, house 4.2)
const LABOUR_CLIP := {"till": "till", "sow": "sow", "water": "water", "harvest": "harvest"}
const MAILBOX_DIR := "res://assets/props/mailbox_placeholder/"
const MAILBOX_SCALE := 0.65
const MAILBOX_MARK := Vector3(0, 1.45, 0)   # its icon button, just over the 1.16 m post box
const MAILBOX_HIT := Vector3(0, 0.6, 0)     # its own tap point, the box's middle (use_mailbox is the slot)
const MAILBOX_TAP_PX := 40.0

@onready var cam: Camera3D = $Camera3D
@onready var ground: MeshInstance3D = $Ground
@onready var world_env: WorldEnvironment = $WorldEnvironment

var _guide: Node3D
var rt: P0Runtime
var bp: FarmBlueprint
var grid: BlueprintGrid
var actor: P0Actor
var crops: CropField
var _saved_env: Environment   # handed over while a room (the farmhouse) is on top, see suspend()
var beds: MultiMeshInstance3D
var _hi: MeshInstance3D
var _house := Vector3.ZERO
var _stall := Vector3.ZERO   # the Homestead Stall (unattended, p(6)); the seed box stands in until its model
var _bench := Vector3.ZERO   # the rest bench by the farmhouse (FARM-7, q(30)): Basic Room's bench.glb
var _materials: P0FarmMaterials   # SGODOT-231: gathering spots and the workbench (the mine mouth left in 355 b1)
var _facilities: P0FarmFacilities   # P1 SGODOT-241: sprinklers, placement mode, Coverage
var _decor: P0FarmDecor             # P1 SGODOT-284: the yard's decor, Decorate
var _card := ""   # LOCK-07 v2: the one facility whose name strip is open this frame (P0Garden.pick_card)
var _strip_side := UiWorldNameBar.Dir.RIGHT   # the side the strip opens to: the way the character faces on screen
var _focus := Vector3.ZERO
var _cam_follow := P0Follow.new()
var _opening := false   # the opening shot waits for the HUD's area to keep the farmhouse mark clear of it (_fit_opening)
## The farm's resting zoom (农场林地 A, 上官婉儿 on the woodland board, pending the user's pick): 0.8 — wide enough that the
## woods round a small yard show. The opening starts here and zooms out only as far as its beds need (min(fit, 0.8):
## Lv1's 8 beds open at it, more beds wider — Lv3 ~0.62, Lv8 ~0.53); walking eases back to it; a pinch is the player's
## until they next come in.
const REST_ZOOM := 0.8
var _zoom := REST_ZOOM
## A step of the walk back from a zoomed-out opening: toward REST_ZOOM at 1.5 a second, never past it.
static func ease_to_rest(zoom: float, dt: float) -> float: return move_toward(zoom, REST_ZOOM, dt * 1.5)
const ElasticZoom = preload("res://modules/p0/p0_elastic_zoom.gd")
var _pinch = ElasticZoom.new(0.8, 1.4, REST_ZOOM)   # rubber band past 0.8 / 1.4; a first pinch picks up at the rest zoom
var _zoom_at := Vector2.INF            # the last pinch centre (screen)
var _dev_yaw := -1.0
var _hold_until := 0.0
var _front: Dictionary = {}
var _row: Array = []   # plots a Row Hoe sows from _front (P0Logic.row_plots)
var _front_cell := Vector2i(-1, -1)
var _plot_sig := ""
var _sync_t := 0.0
var _fence: Node3D   # p0_fence.gd: front stretch always, the ring from Homestead Lv3
## Yard v2 (v4q(12) ③ ④): the yard grew to the level's (P0Garden.yard_at: Lv13 row 19, Lv14 columns 19–20) — the walk
## grid, the fence ring and the ground's yard have moved this frame. animate: the level came in this session (the
## fence drops in again); false for the level the farm was opened at. 盘古's woods give way with it.
signal yard_grown(level: int, animate: bool)
var _yard_walk := P0Garden.WALK_RECT          # the walk the grid has open (the plan's own until the first view)
var _yard_ring: Dictionary = P0Garden.FENCE_RING
var _yard_seen := false                        # a view has been read: a later grow is this session's
var _fixed_blocks := {}                        # cells shut at build (rocks, the front fence, sign, mailbox): a grown yard never opens them
var _looks: Node3D   # p0_looks.gd: Porch, Kitchen Wing and the Lv10 house by the view's looks
var _sign := Vector3.ZERO   # Homestead sign right of the farmhouse door (WorldBadges · Farm 1135:79267): HOME-1
var _plaque := Vector3.ZERO   # the Home Badge left of the door (where the Upgrade Plaque stood), from Lv2: its card
var _plaque_node: Node3D   # the Home Badge (homestead_badge.glb, whole: its tiers and number sockets)
var _badge_number: Label3D
var _badge_level := -1   # the level the badge shows (its tier and number are set when this changes)
var _scenery: Node3D   # p0_garden_scenery.gd: the sand under the field grows over Lv7's front row
var _woods: FarmWoods  # p0_farm_woods.gd: woods round the yard, clumps on the beds still to open
var _shade: GroundShade   # the shade under Compatibility (SGODOT-457)
var _shade_key := ""   # the level and the looks on show the shade was last drawn for
## q(303) ⑨: a save past Lv8 whose wing's cells are held says so once a launch, on the first farm view (the app's run).
static var _wing_said := false
var _held_wanted := false
var _chef_sign := Vector3.ZERO   # the Chef's Sign's post foot (Homestead Lv10), left of the door path: P0Garden.CHEF_SIGN_CELL
var _chef_sign_node: Node3D
var _chef_sign_look := ""        # the model shown: "a" timber / "b" stone
## 刘备's chef_sign_a / _b (#356 / #376; 上官婉儿 v1.3): pivot at the post's foot, +Z front, its arm out to −X. The post
## stands right of the anchor cell's centre — v1.3 asked about 0.18 m, but in the default camera the board then covered
## the bench's left edge by 3 px and its middle fell inside the bench's 44 px tap (42.5 px from the seat), so a tap on the
## board opened the bench; at 0.08 m the board clears the bench by about 2 px and its middle is 47 px from the seat (the
## spec's rule: less shift until the bench is clear, the board reaching further into the mine path (4,14), 0.177 m). The
## cell stays solid (the post's collider is all that blocks).
const CHEF_SIGN_SHIFT := Vector3(0.08, 0, 0)
const CHEF_SIGN_MARK := Vector3(-0.332, 1.95, 0)   # its strip over the board (board top 1.51, arm 1.70)
const CHEF_SIGN_HIT := Vector3(-0.332, 1.285, 0)   # the board's centre (the model's board_center socket)
const CHEF_SIGN_TAP_PX := 40.0
var _notice := Vector3.ZERO   # the Notice Board's foot (Homestead Lv5, q(164)) beside the stall: P0Garden.NOTICE_BOARD_CELL
var _notice_node: Node3D
const NOTICE_MARK := Vector3(0, 1.75, 0)   # its strip over the board (the model's `mark` socket)
const NOTICE_HIT := Vector3(0, 1.17, 0)    # the board's centre (the model's `board_center` socket, c8ab943e)
const NOTICE_TAP_PX := 40.0
const CHEF_SIGN_BOARD := AABB(Vector3(-0.582, 1.06, -0.025), Vector3(0.5, 0.45, 0.06))   # the board with its emblem (manifest)
var _mailbox := Vector3.ZERO   # the farmhouse Mailbox (§12.5.2; SGODOT-234 C): opens the Inbox, as the bell does
var _door := Vector3.ZERO     # the walkway cell in front of the farmhouse door
## The farm's way out to the map (SGODOT-443, the user 11-07: "a sign; tapped, the player walks to the exit and goes
## into the map"; q(298); 不知火舞's spec v1.2): a map pin on the open grass the user marked, its `Map` prompt (the
## rooms' door strip with the pin's icon, P0WorldPrompts.farm_exit). A tap on it walks to the ring's middle and the
## arrival goes to the map as the place chip does; the joystick, a tap elsewhere or a panel opening stops the walk where
## it is. Walked into the ring with the joystick it goes too: within EXIT_RADIUS_M, moving, once armed — never armed on
## coming into the farm (the start, back from the map, out of the farmhouse), only after having been EXIT_ARM_M away
## (不知火舞 443 603fe5ea: armed by the spawn's distance, a step left from a landing went in). Beside every way to the map.
## EXIT_AT: the ring's middle, 5.4 m left of the spawn (the user 11-07, bot 389: "further from the spawn", not two steps
## out of the farm; off the opening shot, its icon shows the way). V4 review C7 (上官婉儿 / 诸葛亮, 奕星 11-10; 0.3.6): at
## (1.6, 0) its ring took bed 62 (cell (2, −1), the last to open, Lv17), so it moved to the open grass in the yard's
## front-left corner, 0.21 m off that bed's edge, its ring drawn smaller (EXIT_RING_R) inside the Lv3 fence (west x 0.38,
## front z 1.4), its trigger EXIT_RADIUS_M. EXIT_ICON: its prompt's icon, 安其拉's pin in its ring (d9e7a52a); EXIT_PIECE:
## 赵云's pin and ring, its origin the ring's middle — its `bob` loop played from the start, always (the user: "it
## floats"), else its pin bobbed the same way here.
const EXIT_AT := P0Garden.MAP_EXIT   # (0.8, 0, 1.0): the Lv3 fence opens there (P0Garden.fence_ring)
const EXIT_ICON := "exit_pin"
const EXIT_PIECE := "res://assets/farm/art/farm_exit_pin.glb"
const EXIT_ARM_M := 2.5
const EXIT_RADIUS_M := 0.4
const EXIT_RING_NODE := "ring"   # the piece's ring (0.6 m round as drawn), scaled on the ground to EXIT_RING_R; the pin as it is
const EXIT_RING_R := 0.38
## 不知火舞 443 d3ff5572 (上官婉儿 agreeing): the player within EXIT_FADE_M of the exit (behind its pin, at the front row's
## west end), the pin fades out over EXIT_FADE_S (as ACTOR_FADE_S), its shadow off while faded — at 0.3 its red read
## pink on the player; the strip and the ring tell the exit near. Its `Map` strip never fades: open at its mark over the
## player's head and upper body on screen (at any distance), it rises clear of the head, its bottom EXIT_STRIP_HEAD_PX
## over the head's top, and eases back to its mark over EXIT_STRIP_BACK_S once it would not be (不知火舞 / 上官婉儿 443;
## LOCK-07 note: this strip only for now).
const EXIT_FADE_M := 1.0
const EXIT_FADE_ALPHA := 0.0
const EXIT_FADE_S := 0.2
const EXIT_STRIP_HEAD_PX := StripClear.HEAD_PX
const EXIT_STRIP_BACK_S := StripClear.BACK_S
const EXIT_PIN_NODE := "pin"   # the piece's pin, bobbed when the piece has no `bob` loop
const EXIT_BOB_M := 0.1   # either way of where it stands (0.2 m in all; 不知火舞)
const EXIT_BOB_S := 1.6
const EXIT_MARK := Vector3(0, 2.1, 0)   # its strip (centred here, 32 px) clear of the pin's top at its highest bob, about 1.475 m (不知火舞 / 上官婉儿 on 443)
const EXIT_HIT := Vector3(0, 0.4, 0)
const EXIT_TAP_PX := 40.0
var _exit := Vector3.INF
var _exit_armed := false
var _exit_walk := false   # walking there after a tap on its prompt
var _exit_pin_mat: StandardMaterial3D   # the pin's own copy of the farm art material, faded near the exit
var _exit_pin_meshes: Array[MeshInstance3D] = []
var _exit_lift := 0.0        # px the exit's strip is raised now (≤ 0, screen up)
var _exit_clear := StripClear.new()
var _door_armed := false
var _inside := false          # the farmhouse is open above this farm

func _ready() -> void:
	P0Runtime.mark("%s _ready start" % name)
	bp = P0Garden.blueprint()
	grid = BlueprintGrid.new(bp)
	var first := P0Runtime.ensure().session
	_style = P0FarmTemplate.style(first.view if first != null else null)
	get_viewport().transparent_bg = false   # pushed above the map, whose tiles show through a transparent root
	cam.make_current()
	_build_world()
	rt = P0Runtime.ensure()
	rt.attach(self)
	rt.ui.set_mode("farm")
	rt.ui.set_place(PLACE)

func _exit_tree() -> void:
	if rt: rt.detach(self)

## Android Back: the UI's top layer (a dragged slot, radial, a card or drawer) closes first, one per press; with nothing
## open, back to the map: AppRouter pops a farm stacked on the map, a farm that is the root scene leaves by itself
## (int5 hand test 012–013 / 023–024, int5b test 2; rooms do the same, p0_room).
func is_back_navigation_locked() -> bool:
	return rt != null and (rt.ui.close_top_layer() or rt.root_back())

## AppRouter stacking: the map below us hands back its camera and environment on resume. Going under a room we hand
## ours over as well: the viewport uses the first WorldEnvironment in the tree, so the farmhouse otherwise lit with the
## farm's cool ambient and green backdrop (SGODOT-249; farm.gd and P0Room.suspend() do the same). The canvas layers
## go too: FarmBackground (layer −1) is the farm's backdrop only under its BG_CANVAS environment; under the room's
## colour background it would cover the room, and hiding the farm does not hide a CanvasLayer. They leave the tree
## while we are suspended: hidden is not enough — a hidden CanvasLayer at −1 still took part in the dressing room's
## canvas background (BG_CANVAS, max layer −1), which then drew its backdrop over its 3D character (SGODOT-256 ⑥).
var _held_layers: Array = []   # [CanvasLayer, its index], out of the tree while suspended

func suspend() -> void:
	if _guide != null: _guide.leave()
	set_process(false)
	visible = false
	if world_env.environment: _saved_env = world_env.environment
	world_env.environment = null
	if _held_layers.is_empty():
		for c in get_children():
			if c is CanvasLayer: _held_layers.append([c, c.get_index()])
		for held in _held_layers: remove_child(held[0])

## Freed while suspended (the root swapped away under the dressing room): the layers out of the tree go with us.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for held in _held_layers:
			if is_instance_valid(held[0]): (held[0] as Node).free()
		_held_layers.clear()

func resume() -> void:
	get_viewport().transparent_bg = false
	_exit_armed = false   # out of the farmhouse: back in the farm, the exit not armed (443 603fe5ea)
	_exit_walk = false
	if _saved_env: world_env.environment = _saved_env
	for held in _held_layers:   # back in their places, in the order they were taken
		add_child(held[0])
		move_child(held[0], mini(int(held[1]), get_child_count() - 1))
	_held_layers.clear()
	visible = true
	set_process(true)
	cam.make_current()
	if rt:
		rt.attach(self)
		rt.ui.set_mode("farm")   # back from a layer above (SGODOT-231): seeds on the bar, the farm's chip
		rt.ui.set_place(PLACE)   # back from the farmhouse
	if _inside:
		# Out through the farmhouse door: stand on the doorstep facing the field.
		_inside = false
		actor.teleport(_door)
		actor.face(_door + Vector3(0, 0, 1))
		_opening = false
		_focus = _door
		_cam_follow.hold()
		_place_camera()
	_door_armed = false

func p0_surface() -> String: return "farm"

# ---------------------------------------------------------------- world
func _build_world() -> void:
	var lawn := PlaneMesh.new()
	lawn.size = Vector2.ONE * 96.0
	ground.mesh = lawn
	ground.position = Vector3(bp.play_area_m * 0.5, -0.008, -bp.play_area_m * 0.5)
	_house = bp.cell_to_world(bp.anchor("house"))
	_door = bp.cell_to_world(bp.anchor("house") + Vector2i(0, -2))
	_exit = EXIT_AT
	_exit_piece()
	var grass := ShaderMaterial.new()
	grass.shader = preload("res://modules/farm/shaders/meadow.gdshader")
	grass.set_shader_parameter("meadow_texture", preload("res://assets/farm/art/meadow.png"))
	grass.set_shader_parameter("woodland_start", -_house.z + 3.75)
	ground.material_override = grass
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	var house := FarmProps.build("house", _house, 1.0, _style)
	props.add_child(house)
	props.add_child(FarmProps.build("storage", bp.cell_to_world(bp.anchor("storage")), 1.0, _style))
	props.add_child(FarmProps.build("well", bp.cell_to_world(bp.anchor("well")), 1.0, _style))
	# The bench is two cells wide: its centre sits half a cell right of its anchor cell, facing the field (+z).
	_bench = bp.cell_to_world(bp.anchor("bench")) + Vector3(bp.cell_m * 0.5, 0, 0)
	props.add_child(_bench_prop(_bench))
	# No mine mouth on the farm since 355 b1 (v4q(5) ①): the mines are wild sites, entered from the map.
	_materials = P0FarmMaterials.new().setup(self)
	add_child(_materials)
	_scenery = GardenScenery.new()
	add_child(_scenery)
	_scenery.build(bp, _style)
	_woods = FarmWoods.new()   # the farm ringed by pine woods (the user 11-09, SGODOT-422 0.3.5): nothing in it collides
	add_child(_woods)
	_woods.build(bp)
	yard_grown.connect(_woods.give_way)   # the pieces in the way of a grown yard move with the fence (v4q(12) ⑤)
	grass.shader = preload("res://modules/farm/shaders/meadow_woods.gdshader")
	_block(_scenery.rock_points)   # rocks collide; crops and bushes don't
	_fence = Fence.new()
	add_child(_fence)
	_fence.build(bp)
	_block(P0Garden.fence_block_points(bp))   # the yard fence in front of the house collides
	_looks = Looks.new()   # the Homestead looks beside and as the farmhouse (LOOK-PICK, SGODOT-282)
	add_child(_looks)
	_looks.build(bp, house, _style, _fence, P0Runtime.ensure().ui)   # before rt is set (_ready builds the world first)
	_looks.wing_cleared.connect(_on_wing_cleared)
	# the trees' and the farmhouse's shade under Compatibility (SGODOT-457): 2 m and up only, so no facility, fence or player;
	# the exit's ring kept clear (上官婉儿 on 457); drawn again when the house changes with the level (_sync_shade)
	_shade = GroundShade.new()
	_shade.name = "GroundShade"
	_shade.ground = ground
	_shade.casters_root = props
	for r: Node in [_woods, _scenery]: _shade.more_roots.append(r)
	for r: Node in [house, _looks]: _shade.box_roots.append(r)   # the farmhouse's shade is a box's, its whole side (上官婉儿 on 457)
	_shade.rect = FarmWoods.AREA
	_shade.clear_spots = [[Vector2(EXIT_AT.x, EXIT_AT.z), 0.7]]
	_shade.draw_on_ready = false   # drawn once, on the first view, with the looks the save has (_sync_shade): one read-back
	add_child(_shade)
	# The Homestead sign: its own tap target beside the door, not the door (LOCK-11 / LOCK-07).
	_sign = P0Garden.sign_point(bp)
	props.add_child(FarmArt.instance("sign", _sign, 0.8))
	_block([_sign])
	# The Home Badge (q(287), 赵云's model, 401): where the Upgrade Plaque stood. Not solid: it appears only after the
	# first upgrade, and an invisible block before then would stop the player for no visible reason.
	_plaque = P0Garden.plaque_point(bp)
	_plaque_node = BADGE.instantiate()   # whole, not FarmArt.instance's meshes: BadgeNumber / BadgeLv are its Marker3Ds
	_plaque_node.name = "HomeBadge"
	_plaque_node.position = _plaque
	_plaque_node.rotation.y = deg_to_rad(BADGE_YAW)
	_plaque_node.scale = Vector3.ONE * BADGE_SCALE
	_plaque_node.visible = false
	props.add_child(_plaque_node)
	_badge_number = badge_label(_plaque_node.find_child("BadgeNumber", true, false), "", BADGE_NUMBER_CAP)
	badge_label(_plaque_node.find_child("BadgeLv", true, false), "Lv", BADGE_LV_CAP)
	# The Chef's Sign (Homestead Lv10): its model put in by the look it shows (_chef_sign_model).
	_chef_sign = P0Garden.chef_sign_point(bp) + CHEF_SIGN_SHIFT
	_chef_sign_node = Node3D.new()
	_chef_sign_node.name = "ChefSign"
	_chef_sign_node.position = _chef_sign
	_chef_sign_node.visible = false
	props.add_child(_chef_sign_node)
	# The Notice Board (Homestead Lv5, q(164)): 刘备's model (#395) at the `notice_board` anchor.
	_notice = P0Garden.notice_board_point(bp)
	_notice_node = notice_board_prop(_notice)
	_notice_node.visible = false
	props.add_child(_notice_node)
	_mailbox = P0Garden.mailbox_point(bp)
	props.add_child(_mailbox_prop(_mailbox))
	_block([_mailbox])
	grid = BlueprintGrid.new(bp)
	_looks.grid = grid   # a shown porch, wing or whole house stands on cells one walks round (亚瑟 on #896)
	# One thick soil bed per plot (plot.glb), tinted per state (watered beds read darker).
	var xfs: Array = []
	var tints := PackedColorArray()
	for id in P0Garden.plot_count():
		xfs.append(Transform3D(Basis.IDENTITY, bp.cell_to_world(P0Garden.cell_of(id))))
		tints.append(Color.WHITE)
	beds = FarmArt.batch("plot", xfs, true, tints)
	beds.multimesh.visible_instance_count = P0Garden.max_plots()   # all laid out; the view's garden.plots shows them
	beds.name = "Beds"
	add_child(beds)
	crops = CropField.new(bp)
	crops.ground_y = P0Garden.BED_H
	crops.ground_layers = true
	crops.plant_scale = 0.94 / bp.cell_m   # size plants to the 0.94 m bed, as the old 1.3 m-pitch garden did
	add_child(crops)
	_hi = _bed_highlight()
	add_child(_hi)
	_stall = bp.cell_to_world(bp.anchor("storage"))
	actor = P0Actor.new()
	add_child(actor)
	actor.setup(bp, grid, cam)
	# never on a cell one cannot walk (q(145) ④: the yard shrank inside the fence ring): the nearest free one by walking
	var stand := landing_cell(grid, bp.world_to_cell(actor.position))
	if stand != bp.world_to_cell(actor.position): actor.teleport(bp.cell_to_world(stand))
	# The beds the homestead has (garden.plots, 30 or 40): read from the session's last view, never current() — that
	# copies the whole view, and this runs every frame (亚瑟 on #215; the map's heat in 260 was the same copy).
	actor.ground_height = func(p: Vector3) -> float:
		return P0Garden.BED_H if P0Garden.on_bed(bp, p, rt.session.view if rt != null and rt.session != null else null) else 0.0
	# Opening shot like the polished farm: cottage on top, beds below, the player at the front edge. Framed from the old
	# walk-in point, so the picture is the one it was (q(172) A moved the spawn 1.3 m nearer the camera: framed from it the
	# farmhouse's mark rose 9 px into the HUD; this way the player just stands 46 px lower, well above the quick bar).
	_focus = opening_point(bp, _house)
	_cam_follow.hold()   # the opening shot stays until the player first moves
	_opening = true
	_place_camera()

## A soft mint rounded-square outline on top of the bed in front of the player.
func _bed_highlight() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := _rounded_square(0.50, 0.14)
	var inner := _rounded_square(0.43, 0.09)
	for i in outer.size():
		var j := (i + 1) % outer.size()
		var a := Vector3(outer[i].x, 0, outer[i].y)
		var b := Vector3(outer[j].x, 0, outer[j].y)
		var c := Vector3(inner[i].x, 0, inner[i].y)
		var d := Vector3(inner[j].x, 0, inner[j].y)
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(b); st.add_vertex(d); st.add_vertex(c)
	var mi := MeshInstance3D.new()
	mi.name = "BedHighlight"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.86, 0.98, 0.80, 0.9)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi

static func _rounded_square(half: float, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var centres := [Vector2(half - radius, half - radius), Vector2(-half + radius, half - radius),
		Vector2(-half + radius, -half + radius), Vector2(half - radius, -half + radius)]
	for k in 4:
		for s in 5:
			var ang := PI * 0.5 * k + PI * 0.5 * float(s) / 4.0
			pts.append(centres[k] + Vector2(cos(ang), sin(ang)) * radius)
	return pts

# ---------------------------------------------------------------- camera (old farm camera + safe box)
func _place_camera() -> void:
	var vp := get_viewport().get_visible_rect().size
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH   # the old farm frames by width (portrait phones)
	cam.size = FarmCamera.close_view_size(vp) * FarmCamera.P0_VIEW_K / _zoom
	FarmCamera.place(cam, _focus + Vector3.UP * 0.7)
	if _top > 0.0: place_top(cam, _focus, _top_ease(), _top_cell_px, bp.cell_m)   # placement's top-down view (284 v2)
	if _dev_yaw >= 0.0:   # P0_SHOT yaw comparison only (style doc asks 35–45°, the old farm uses 14.5°)
		var c := _focus + Vector3.UP * 0.7
		var pitch := deg_to_rad(FarmCamera.PITCH_DEG)
		var yaw := deg_to_rad(_dev_yaw)
		cam.position = c + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * FarmCamera.DISTANCE
		cam.look_at(c, Vector3.UP)
	FarmCamera.fit_ground_depth(cam)

## The opening shot keeps the farmhouse's mark clear of the HUD (李元芳 int12-pre on 256): framed from the walk-in point
## alone, a phone's status-bar inset brought the HUD down over the roof, and the mark — hidden there, as every mark
## outside the HUD's marker area — only showed after a few steps. Once the HUD has laid out, the picture moves down just
## enough for the mark to sit MARK_ROOM inside that area as it is with the HUD up (P0Ui.open_marker_area: a panel open
## on arrival changes nothing when it closes, 后裔 on #166), never bringing the player's feet within FEET_ROOM of the
## quick bar. Once: a later step, pinch or Show leaves the framing alone.
const HOME_MARK := Vector3(0, 2.6, 0.4)   # the farmhouse prompt's anchor (world_prompt "home")
const HOME_MARK_OVER_ROOF := 0.5           # … that is, 0.5 m over the cottage's 2.1 m roof

## The prompt's anchor over the house on show: the Lv10 Timber Lodge (house_barn) is 0.36 m taller than the cottage,
## and its prompt rises with the roof instead of sitting on its ridge (上官婉儿 on #250).
func home_mark() -> Vector3:
	var mesh: Mesh = _looks._house.mesh if _looks and _looks._house else null
	return HOME_MARK if mesh == null else Vector3(HOME_MARK.x, maxf(HOME_MARK.y, mesh.get_aabb().end.y + HOME_MARK_OVER_ROOF), HOME_MARK.z)
const MARK_ROOM := 24.0   # half the near icon disc (28 × 1.1) and the 8 px edge gap prompts keep
const FEET_ROOM := 16.0
func _fit_opening() -> void:
	if not _opening: return
	if not _cam_follow.held:   # walking already: the safe box has the camera
		_opening = false
		return
	if rt == null or not rt.ui.is_node_ready(): return
	var area := rt.ui.open_marker_area()
	if not area.has_area(): return   # the HUD has not laid out yet
	_opening = false
	_place_camera()
	_focus = opening_focus(cam, _focus, _house + home_mark(), actor.position, area)
	_place_camera()
	# SGODOT-355 b1 (不知火舞 on the grid shots, 11-02): every open bed, the farmhouse door and the player — Pip too while the
	# guide has him here (340 S2) — 16 px clear at the left and right, zoomed out as far as that needs, at most the whole
	# island and a margin (CTRL-1). No later step moves the camera; walking brings the follow camera's own scale back.
	var guided := P0Guide.guide_on(rt.session.view) and bool(P0Guide.pip(rt.session.view).get("here", false))
	# a guided player lands by the starting beds and Pip (q(215) 「落地在首畦旁」), not at the yard's way in: here, where
	# the view is surely in (on _ready it may not be yet)
	if guided: actor.teleport(bp.cell_to_world(landing_cell(grid, FarmGuide.LAND)))
	# the farmhouse's prompt too, so the picture sits with the whole farm in the middle of the area between the HUD and
	# the quick bar, not just the beds (不知火舞 on the Lv17 shot: the field alone framed the farm high)
	var points: Array[Vector3] = [actor.position, actor.position + Vector3.UP * 1.8, _door, _house + home_mark()]
	if guided: points.append(bp.cell_to_world(FarmGuide.STAND) + Vector3(0, 2.2, 0))
	for id in P0Garden.plot_count(rt.session.view):
		var bed := bp.cell_to_world(P0Garden.cell_of(id))
		for d in [Vector3(-0.47, 0, -0.47), Vector3(0.47, 0, -0.47), Vector3(-0.47, 0, 0.47), Vector3(0.47, 0, 0.47)]: points.append(bed + d)
	_frame_opening(points, Rect2(area.position + Vector2(OPEN_SIDE_PX, 0), area.size - Vector2(OPEN_SIDE_PX * 2, 0)))

const OPEN_SIDE_PX := 16.0
const ISLAND_RECT := Rect2i(0, -3, 21, 23)   # the yard (WALK_RECT) and a cell's margin round it: the farthest the opening zooms out

## Shut the cells under these points in the plan (P0Garden.block_points) and keep them shut when the yard grows.
func _block(points: Array) -> void:
	P0Garden.block_points(bp, points)
	for p in points: _fixed_blocks[bp.world_to_cell(p)] = true

## The yard at the view's level (yard v2): when its walk is not the one open, the cells between are opened (or shut),
## the fence ring and the ground follow, pieces and yard facilities on opened cells turn solid, and yard_grown says so.
func _sync_yard(v: Dictionary) -> void:
	var lv := int(v.get("homestead", {}).get("level", 1))
	var yard := P0Garden.yard_at(lv)
	var walk: Rect2i = yard.walk
	var animate := _yard_seen
	_yard_seen = true
	if walk == _yard_walk: return
	for c in yard_cells_between(_yard_walk, walk):
		var on := walk.has_point(c) and not P0Garden._in_footprint(c) and not _fixed_blocks.has(c)
		P0Garden.set_walkable(bp, c, on)
		grid.set_solid(c, not on)
	_yard_walk = walk
	_yard_ring = yard.ring
	_fence.set_level(lv, animate)
	_scenery.show_strips(lv)
	if ground != null and ground.material_override is ShaderMaterial:
		(ground.material_override as ShaderMaterial).set_shader_parameter("yard", Vector4(float(_yard_ring.west), float(_yard_ring.back), float(_yard_ring.east), float(_yard_ring.front)))
	if _decor != null: _decor.walk_changed()
	if _facilities != null: _facilities.walk_changed()
	yard_grown.emit(lv, animate)

## The cells in one walk rect and not the other.
static func yard_cells_between(a: Rect2i, b: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var all := a.merge(b)
	for y in range(all.position.y, all.end.y):
		for x in range(all.position.x, all.end.x):
			var c := Vector2i(x, y)
			if a.has_point(c) != b.has_point(c): out.append(c)
	return out

## The island at the yard's level now (yard v2: as much bigger as the yard grew, ISLAND_RECT up to Lv12).
func island_rect() -> Rect2i:
	return ISLAND_RECT.grow_individual(0, 0, _yard_walk.end.x - P0Garden.WALK_RECT.end.x, _yard_walk.end.y - P0Garden.WALK_RECT.end.y)
var _opening_zoom := false   # the opening zoomed out; walking eases the follow camera back to REST_ZOOM

## Zoom out (never in) until every point fits `inner`, at most to the island and its margin, then centre them in it.
func _frame_opening(points: Array[Vector3], inner: Rect2) -> void:
	var span := _screen_bounds(points)
	var need := maxf(span.size.x / maxf(inner.size.x, 1.0), span.size.y / maxf(inner.size.y, 1.0))
	var island: Array[Vector3] = []
	var isle := island_rect()
	for c in [isle.position, Vector2i(isle.end.x, isle.position.y)]: island.append(bp.cell_to_world(c))
	var most := maxf(1.0, _screen_bounds(island).size.x / maxf(inner.size.x, 1.0))
	var k := clampf(need, 1.0, most)
	if k > 1.0:
		_zoom = _zoom / k
		_opening_zoom = true
		_place_camera()
	_focus = guide_opening_focus(cam, _focus, points, inner)
	_place_camera()

func _screen_bounds(points: Array[Vector3]) -> Rect2:
	var r := Rect2(cam.unproject_position(points[0]), Vector2.ZERO)
	for p in points: r = r.expand(cam.unproject_position(p))
	return r

static func guide_opening_focus(camera: Camera3D, focus: Vector3, points: Array[Vector3], area: Rect2) -> Vector3:
	var bounds := Rect2(camera.unproject_position(points[0]), Vector2.ZERO)
	for point in points: bounds = bounds.expand(camera.unproject_position(point))
	var old = ElasticZoom.ground_at(camera, bounds.get_center(), focus.y)
	var centre = ElasticZoom.ground_at(camera, area.get_center(), focus.y)
	return focus + old - centre if old != null and centre != null else focus

## `focus` moved along the ground, away from the camera, by as much as the mark needs to sit MARK_ROOM below the area's
## top — at most what keeps `feet` FEET_ROOM above its bottom (opening_shift). `cam` is placed at `focus` already.
## Where the opening shot is framed from: the field's front walkway the player used to walk in at (9, 1), 42 % of the way to
## the farmhouse.
const OPENING_CELL := Vector2i(9, 1)
static func opening_point(bp: FarmBlueprint, house: Vector3) -> Vector3:
	return bp.cell_to_world(OPENING_CELL).lerp(house, 0.42)

static func opening_focus(cam: Camera3D, focus: Vector3, mark: Vector3, feet: Vector3, area: Rect2) -> Vector3:
	var dy := opening_shift(cam.unproject_position(mark).y, cam.unproject_position(feet).y, area)
	if dy <= 0.0: return focus
	var px := cam.get_viewport().get_visible_rect().size.x / cam.size   # px per metre (KEEP_WIDTH)
	var ahead := -cam.global_basis.z
	ahead.y = 0.0
	return focus + ahead.normalized() * dy / (px * sin(deg_to_rad(FarmCamera.PITCH_DEG)))

## How far (px) the opening picture moves down: the mark's shortfall below `area`'s top + MARK_ROOM, capped by the room
## the feet have above its bottom − FEET_ROOM; 0 when the mark is clear already.
static func opening_shift(mark_y: float, feet_y: float, area: Rect2) -> float:
	var need := area.position.y + MARK_ROOM - mark_y
	var room := area.end.y - FEET_ROOM - feet_y
	return clampf(need, 0.0, maxf(0.0, room))

func _follow(dt: float) -> void:
	_fit_opening()
	if _opening_zoom and not _cam_follow.held:   # walking: back to the follow camera's own scale (SGODOT-355 b1)
		_zoom = ease_to_rest(_zoom, dt)
		_opening_zoom = _zoom < REST_ZOOM
	_step_actor_fade(dt)
	if _top_left > 0.0:   # turning into / out of the top-down view
		_top_left = maxf(0.0, _top_left - dt)
		_top = _top_to if _top_left == 0.0 else lerpf(_top_from, _top_to, 1.0 - _top_left / PLACE_TURN_S)
	if _fly_left > 0.0:   # placement's 0.3 s camera moves (不知火舞 on 241)
		_fly_left = maxf(0.0, _fly_left - dt)
		var k := smoothstep(0.0, 1.0, 1.0 - _fly_left / _fly_dur)
		_focus = _fly_from.lerp(_fly_to if _fly_to != Vector3.INF else Vector3(actor.position.x, _focus.y, actor.position.z), k)
		if _fly_left == 0.0 and _fly_to == Vector3.INF: _cam_follow.held = false   # back to following the player
	elif _placing_cam: _focus = _yard_clamp(_focus)   # placement: the camera is the player's to pan, in the yard
	else: _focus = _cam_follow.step(cam, _focus, actor.position, actor.mover.is_moving(), dt)
	if _pinch.step(dt): _set_zoom(_pinch.value)   # springing back from past a limit, about the same point
	else: _place_camera()

## Zoom about the last pinch centre: the ground point under the fingers stays put (ScenePan's focal pinch).
func _set_zoom(value: float) -> void:
	_zoom = value
	if cam == null or not is_inside_tree(): return   # not placed yet: the next frame frames it
	var before = ElasticZoom.ground_at(cam, _zoom_at, _focus.y)
	_place_camera()
	var d := ElasticZoom.shift(before, ElasticZoom.ground_at(cam, _zoom_at, _focus.y))
	if d != Vector3.ZERO:
		_focus += d
		_place_camera()

# ---------------------------------------------------------------- placement camera (SGODOT-241; top-down, 用户 on 284 058639c7)
## The shell's camera for every placement — sprinkler, greenhouse, Decorate (不知火舞 284 v2 6a751a9a): entering, it
## turns in 0.35 s (ease-in-out) to straight down with no yaw (cells square on screen, the farmhouse still at the top),
## centred on the preview at about 36 px a cell; two fingers zoom (17–56 px a cell) and pan inside the yard plus one
## cell, never rotate; a finger at a screen edge pans. Leaving (done or cancel), it turns back to 43° / 14.5° in 0.35 s
## and follows the player again.
const PLACE_FLY_S := 0.35
const PLACE_TURN_S := 0.35
const PICK_FLY_S := 0.3     # Decorate's pick-up of a piece (284 v2 §1)
const TOP_CELL_PX := 36.0
const TOP_CELL_MIN := 17.0
const TOP_CELL_MAX := 56.0
var _placing_cam := false
var _fly_left := 0.0
var _fly_from := Vector3.ZERO
var _fly_to := Vector3.INF   # INF: fly back to the player
var _fly_dur := PLACE_FLY_S
var _top := 0.0              # 0 the farm's view … 1 straight down
var _top_from := 0.0
var _top_to := 0.0
var _top_left := 0.0
var _top_cell_px := TOP_CELL_PX

## Into the top-down view, centred on `spot`, at `cell_px` pixels a cell (Decorate opens on the whole yard: 17).
func placement_camera_begin(spot: Vector3, cell_px := TOP_CELL_PX) -> void:
	_placing_cam = true
	_opening = false
	_cam_follow.hold()
	_actor_fade_to = 1.0   # no character while placing (user on 284 14e11a67): 0.2 s out, back on Done or Cancel
	_top_cell_px = clampf(cell_px, TOP_CELL_MIN, TOP_CELL_MAX)
	_turn(1.0)
	_fly(Vector3(spot.x, _focus.y, spot.z))

## Centre on `spot` (and zoom to `cell_px` when given) in 0.3 s while placing: Decorate's pick-up of a piece.
func placement_camera_focus(spot: Vector3, cell_px := 0.0) -> void:
	if not _placing_cam: return
	if cell_px > 0.0: _top_cell_px = clampf(cell_px, TOP_CELL_MIN, TOP_CELL_MAX)
	_fly(Vector3(spot.x, _focus.y, spot.z), PICK_FLY_S)

## Done or Cancel. `taken`: the grid cells the piece just placed covers (none on Cancel); the player fades back in
## where they stood, or on the nearest free cell by walking when it is one of those or now solid (不知火舞 on #261).
func placement_camera_end(taken: Array = []) -> void:
	if not _placing_cam: return
	_placing_cam = false
	var here := bp.world_to_cell(actor.position)
	var to := free_cell_near(grid, here, taken)
	if to != here:
		var w := bp.cell_to_world(to)
		actor.teleport(Vector3(w.x, actor.position.y, w.z))
	_actor_fade_to = 0.0
	_turn(0.0)
	_fly(Vector3.INF)
	placement_grid(Vector3.INF)

func _fly(to: Vector3, dur := PLACE_FLY_S) -> void:
	_fly_from = _focus
	_fly_to = to
	_fly_dur = dur
	_fly_left = dur

func _turn(to: float) -> void:
	_top_from = _top
	_top_to = to
	_top_left = PLACE_TURN_S

func _top_ease() -> float: return smoothstep(0.0, 1.0, _top)

## The player while placing (user on 284 14e11a67; 不知火舞 on #261): out in 0.2 s with its shadow, not drawn while
## placing, in again in 0.2 s on leaving. A real-time shadow cannot be half there: it goes at the half-way point.
const ACTOR_FADE_S := 0.2
var _actor_fade := 0.0      # 0 shown … 1 gone
var _actor_fade_to := 0.0
var _actor_shadows := {}    # its meshes' own cast_shadow while faded, restored when it is whole again

func _step_actor_fade(dt: float) -> void:
	if _actor_fade == _actor_fade_to: return
	_actor_fade = move_toward(_actor_fade, _actor_fade_to, dt / ACTOR_FADE_S)
	actor.visible = _actor_fade < 1.0
	for g in actor.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		var id := gi.get_instance_id()
		if not _actor_shadows.has(id): _actor_shadows[id] = gi.cast_shadow
		gi.transparency = _actor_fade   # 0 again leaves the transparent pipeline
		gi.cast_shadow = _actor_shadows[id] if _actor_fade < 0.5 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _actor_fade == 0.0: _actor_shadows.clear()

## Where the player stands on entering the farm (q(145) ④): `from` when one may walk there, else the nearest free cell
## by walking; a spot walled in on every side (the yard's corner past the fence ring) takes the nearest free cell.
static func landing_cell(g: BlueprintGrid, from: Vector2i) -> Vector2i:
	var to := free_cell_near(g, from, [])
	if g.bp.in_bounds(to) and not g.astar.is_point_solid(to): return to
	var dist := INF
	var o := g.bp.grid_origin   # the grid may start before row 0 (q(172) A)
	for y in range(o.y, o.y + g.bp.grid.y):
		for x in range(o.x, o.x + g.bp.grid.x):
			var c := Vector2i(x, y)
			if g.astar.is_point_solid(c) or Vector2(c - from).length_squared() >= dist: continue
			dist = Vector2(c - from).length_squared()
			to = c
	return to

## The free cell nearest `from` by walking (4-way, like the paths): solid cells are walls (fences, the house), `taken`
## ones can be crossed even when solid (Decorate's pieces are, 苏烈 on #261: the player walks out of the piece) but not
## stood on; `from` itself when it is free or nothing free is in reach.
static func free_cell_near(g: BlueprintGrid, from: Vector2i, taken: Array, limit := 4096) -> Vector2i:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	var i := 0
	while i < queue.size() and i < limit:
		var c := queue[i]
		i += 1
		if not taken.has(c) and not g.astar.is_point_solid(c): return c
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var n: Vector2i = c + d
			if seen.has(n) or not g.bp.in_bounds(n) or (g.astar.is_point_solid(n) and not taken.has(n)): continue
			seen[n] = true
			queue.append(n)
	return from

## The camera `k` of the way (0 the farm's 43° / 14.5°, 1 straight down with no yaw) to the top-down view over `focus`,
## at `cell_px` pixels a `cell_m` cell when there: set from its Euler angles, so straight down needs no look_at up.
static func place_top(camera: Camera3D, focus: Vector3, k: float, cell_px: float, cell_m: float) -> void:
	var pitch := deg_to_rad(lerpf(FarmCamera.PITCH_DEG, 90.0, k))
	var yaw := deg_to_rad(lerpf(FarmCamera.YAW_DEG, 0.0, k))
	var c := focus + Vector3.UP * 0.7 * (1.0 - k)
	camera.rotation = Vector3(-pitch, yaw, 0.0)
	camera.position = c + camera.basis.z * FarmCamera.DISTANCE
	var width := camera.get_viewport().get_visible_rect().size.x
	camera.size = lerpf(camera.size, width / cell_px * cell_m, k)   # KEEP_WIDTH: the size is the width in metres

## Pixels a cell after a pinch by `f` (< 1 fingers apart, zoom in), kept to 17–56.
static func top_cell_after(cell_px: float, f: float) -> float:
	return clampf(cell_px / maxf(f, 0.01), TOP_CELL_MIN, TOP_CELL_MAX)

## The placement grid on the ground (284 v2 §2): white cell lines within `radius` cells of `at`, fading out from 50%;
## Vector3.INF hides it. The shell's, so the sprinkler, the greenhouse and Decorate draw the same.
const GRID_RADIUS := 3
var _grid: MeshInstance3D
func placement_grid(at: Vector3, radius := GRID_RADIUS) -> void:
	if at == Vector3.INF:
		if _grid != null: _grid.visible = false
		return
	if _grid == null:
		_grid = MeshInstance3D.new()
		_grid.name = "PlacementGrid"
		var m := PlaneMesh.new()
		_grid.mesh = m
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://scenes/p0/p0_placement_grid.gdshader")
		_grid.material_override = mat
		_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_grid)
	var cell := float(bp.cell_m)
	var c := bp.cell_to_world(bp.world_to_cell(at))   # a cell centre: the lines fall on cell edges
	_grid.visible = true
	_grid.position = Vector3(at.x, P0Garden.BED_H + 0.02, at.z)
	(_grid.mesh as PlaneMesh).size = Vector2.ONE * cell * (radius * 2 + 2)
	var mat := _grid.material_override as ShaderMaterial
	mat.set_shader_parameter("cell", cell)
	mat.set_shader_parameter("origin", Vector2(c.x, c.z))
	mat.set_shader_parameter("centre", Vector2(at.x, at.z))
	mat.set_shader_parameter("radius", cell * radius)

## Decorate's entries (SGODOT-284): Farm Storage's Place and the stall toast's Place now pick a piece; HOME-1's
## Decorate › ("") opens the mode with nothing picked.
## q(303) ④: `Space taken · clear it first`'s Decorate ›, Today's Show and the server's homestead_blocked (P0Logic.
## DECORATE_GO) open it on what holds the Kitchen Wing's cells.
func _on_decor_requested(item: String) -> void:
	if item == "": _decor.begin_decorate()
	elif item == P0Logic.DECORATE_GO: _decor.begin_held(_take_held_detail())
	else: _decor.begin_place(item)

## q(303) ⑨ (SGODOT-450): on the first farm view of this launch, a save past Lv8 whose wing's cells are held is told
## (Error, with Decorate ›); not again until the app opens anew.
func _say_wing(v: Dictionary) -> void:
	if _wing_said or v.get("homestead", null) == null: return
	_wing_said = true
	# once the launch's cover is gone: under it the toast ran out unseen (不知火舞 on #916 B5a)
	if not P0Decor.wing_blocked(v).is_empty(): rt.toast_on_arrival(P0Logic.HOME_BLOCKED_TAP, P0Ui.DECORATE_ACTION)

## The last homestead_blocked's detail, once (P0Runtime.held_detail).
func _take_held_detail() -> Dictionary:
	var d: Dictionary = rt.held_detail
	rt.held_detail = {}
	return d

## The wing came up as its cells cleared (P0Looks.wing_cleared): `Lv8 look · Kitchen Wing` (q(303) ⑨, LOOK-PICK's title).
func _on_wing_cleared(stage: Dictionary) -> void:
	if not stage.is_empty(): rt.ui.toast_success("Lv%d look · %s" % [int(stage.level), str(stage.name)])

## Move the focus by a ground delta (edge pan, two-finger pan), kept in the yard.
func placement_pan(d: Vector3) -> void:
	if not _placing_cam or _fly_left > 0.0: return
	_focus = _yard_clamp(_focus + Vector3(d.x, 0, d.z))

## A finger held in placement mode (the preview's, Vector2.INF when lifted): within EDGE_PX of a screen edge it pans
## the camera that way, faster nearer the edge (up to EDGE_SPEED m/s); the bar's card counts as the bottom edge
## (不知火舞 on 241). Shared by the sprinkler and Decorate; true when the camera moved, so the caller re-snaps its
## preview to the ground now under the finger.
const EDGE_PX := 48.0
const EDGE_SPEED := 6.0

func placement_edge(finger: Vector2, dt: float) -> bool:
	if not _placing_cam or finger == Vector2.INF or dt <= 0.0: return false
	var view := get_viewport().get_visible_rect().size
	var bar := P0Runtime.ensure().ui.placement_bar_rect()
	var bottom := bar.position.y if bar.has_area() else view.y
	var push := Vector2(edge_push(finger.x, 0.0, view.x), edge_push(finger.y, 0.0, bottom))
	if push == Vector2.ZERO: return false
	# Screen right / down as ground directions (the camera's own axes on the ground plane).
	var right := cam.global_basis.x
	var down := -cam.global_basis.y
	right.y = 0.0
	down.y = 0.0
	placement_pan((right.normalized() * push.x + down.normalized() * push.y) * EDGE_SPEED * dt)
	return true

## −1..1 toward the nearer edge of [lo, hi] for a finger within EDGE_PX of it, 0 elsewhere (0 at the band's inner side).
static func edge_push(x: float, lo: float, hi: float) -> float:
	if x < lo + EDGE_PX: return -clampf((lo + EDGE_PX - x) / EDGE_PX, 0.0, 1.0)
	if x > hi - EDGE_PX: return clampf((x - (hi - EDGE_PX)) / EDGE_PX, 0.0, 1.0)
	return 0.0

## The ground shift that moves the picture by `px` on screen (a two-finger drag): the ground under the old point.
func placement_drag(px: Vector2, at: Vector2) -> void:
	var a = ElasticZoom.ground_at(cam, at, _focus.y)
	var b = ElasticZoom.ground_at(cam, at + px, _focus.y)
	if a is Vector3 and b is Vector3: placement_pan(a - b)

func _yard_clamp(f: Vector3) -> Vector3:
	var r := _yard_ring
	var pad := bp.cell_m
	return Vector3(clampf(f.x, r.west - pad, r.east + pad), f.y, clampf(f.z, r.back - pad, r.front + pad))

func p0_zoom(f: float, at := Vector2.INF) -> void:
	if _placing_cam:   # top-down: pixels a cell, 17–56, about the fingers (the ground under them stays put)
		var before = ElasticZoom.ground_at(cam, at, _focus.y)
		_top_cell_px = top_cell_after(_top_cell_px, f)
		_place_camera()
		var d := ElasticZoom.shift(before, ElasticZoom.ground_at(cam, at, _focus.y))
		if d != Vector3.ZERO: _focus = _yard_clamp(_focus + d)
		return
	_opening = false
	_opening_zoom = false   # the player's own zoom from here, walking does not ease it back (上官婉儿, 农场林地 A)
	_zoom_at = at
	_pinch.pinch(f)
	_cam_follow.hold()   # the pinched framing stays until the player walks (the safe box takes over then)
	_set_zoom(_pinch.value)
func p0_zoom_end() -> void: _pinch.release()
func p0_recenter() -> void:
	_opening = false
	_focus = actor.position
	_cam_follow.held = false

func p0_show_spot(where: String) -> void:
	if where == P0Logic.DECORATE_GO:   # q(303): Today's `Homestead Lv8 · Space taken` Show
		if _decor != null: _decor.begin_held(_take_held_detail())
		else: _held_wanted = true   # just out of the farmhouse: once Decorate is up (p0_frame)
		return
	var at := _bench if where == "bench" else (_house if where in ["stove", "home"] else actor.position)
	if where == "stall": at = _stall
	elif where == "sign": at = _sign   # Upgrade to Homestead LvN (q(255))
	elif where == "plots": at = _plots_center()
	elif _materials.spot_at(where) != null: at = _materials.spot_at(where)   # SGODOT-231: spot_*, workbench
	_opening = false
	_focus = at
	_cam_follow.hold()
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.95
	tm.outer_radius = 1.08
	ring.mesh = tm
	ring.position = at + Vector3(0, 0.06, 1.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.83, 0.42)
	ring.material_override = m
	add_child(ring)
	var tw := create_tween().set_loops(2)
	tw.tween_property(ring, "scale", Vector3(1.2, 1, 1.2), 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_property(ring, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_SINE)
	tw.finished.connect(ring.queue_free)

# ---------------------------------------------------------------- frame
func p0_joystick(v: Vector2) -> void:
	if v != Vector2.ZERO:
		stop_exit_walk()   # the joystick takes over the walk out (SGODOT-443)
		_tap_walk = false   # … and a tapped walk: let go, the player does not turn to the bed (周瑜 on #947)
	if actor: actor.set_input(v)

var _dev_aim := Vector3.INF   # aimcell (shots): steer the joystick straight at this point, logging the player each frame

func p0_frame(v: Dictionary, dt: float) -> void:
	if _dev_aim != Vector3.INF:
		var to := Vector3(_dev_aim.x - actor.position.x, 0, _dev_aim.z - actor.position.z)
		if to.length() < 0.05:
			p0_joystick(Vector2.ZERO)
			_dev_aim = Vector3.INF
		else:
			p0_joystick((cam.unproject_position(actor.position + to.normalized()) - cam.unproject_position(actor.position)).normalized())
		print("P0_AIM %d %s" % [Engine.get_frames_drawn(), actor.position])
	actor.step(dt)
	_door_check()
	_exit_check()
	if not is_inside_tree(): return   # out to the map through the exit this frame: nothing left to draw
	_exit_fade(dt)
	_tap_walk_check()
	_follow(dt)
	rt.ui.player_screen = cam.unproject_position(actor.position + Vector3(0, 0.9, 0))   # the radial fans out from here
	_sync_plots(v, dt)
	_sync_yard(v)
	_fence.sync(v)
	_looks.sync(v)
	_sync_shade(v)
	_scenery.show_wing(_looks.wing_model_shown())   # q(303): no grass or flowers through the wing's floor
	_say_wing(v)
	if _facilities == null and bp != null and cam != null and actor != null:
		_facilities = P0FarmFacilities.new().setup(self)
		add_child(_facilities)
	_facilities.frame(v, dt)
	if _decor == null and bp != null and cam != null and actor != null:
		_decor = P0FarmDecor.new().setup(self)
		add_child(_decor)
		rt.ui.decor_requested.connect(_on_decor_requested)
		if _held_wanted: _decor.begin_held.call_deferred(_take_held_detail())
		_held_wanted = false
	_decor.frame(v, dt)
	if not _facilities.placing.is_empty() or not _decor.placing.is_empty():   # placement mode: no bed, key, card or prompt (q(23))
		_hi.visible = false   # the preview's green / red square is the one outline on a bed meanwhile
		if _guide != null: _guide.hide_marks()
		return
	_pick_front(v)
	rt.ui.set_action(P0Logic.main_action(v, _front, rt.ui.selected_seed, _row))
	_card = P0Garden.pick_card(_card_candidates(), actor.position, _card)
	_materials.frame(v, _card)
	_hold_repeat()
	_prompts(v)
	if _guide == null:
		_guide = FarmGuide.new().setup(self)
		add_child(_guide)
	_guide.frame(v, dt)
	_teaching(v)

func _sync_plots(v: Dictionary, dt: float) -> void:
	if _plot_sig == "frozen": return
	_sync_t -= dt
	var sig := ""
	for p in v.get("plots", []): sig += "%s%s;" % [str(p.get("state", "")), str(p.get("crop", ""))]
	if sig == _plot_sig and _sync_t > 0.0: return
	_plot_sig = sig
	_sync_t = 1.0
	var now := Time.get_ticks_msec()
	crops.sync(P0Garden.cells(v, now), now)
	for p in v.get("plots", []):
		var id := int(p.get("id", -1))
		if id >= 0 and id < P0Garden.plot_count(v): beds.multimesh.set_instance_color(id, P0Garden.bed_tint(str(p.get("state", ""))))
	# the beds open now (the view's garden.plots, in the order they open: SGODOT-355 b1); the rest stay grass
	beds.multimesh.visible_instance_count = P0Garden.plot_count(v)
	_scenery.fit_sand(bp, P0Garden.plot_count(v))   # the field's sand under the open beds only
	if _woods: _woods.fit(bp, P0Garden.plot_count(v), _decor.taken_cells() if _decor else [])   # the clumps on beds still to open, none next to an open one or under a piece
	_sync_trees(v)

## The shade drawn when the farmhouse changes (the level, the looks on show, the wing waiting): at once the first time
## (the farm's only drawing on entering: the looks a save has come up with the first view), after a look's pop-in
## (P0Fence.POP_S) later. The woods giving way to the yard (FarmWoods.give_way on yard_grown, Lv13 / Lv14) are drawn by
## the same key: they move only when the level changes, in the same frame, and pop in over the same POP_S — a key
## without the level would leave their shade where they stood (周瑜 on #967).
func _sync_shade(v: Dictionary) -> void:
	if _shade == null: return
	var level := int(v.get("homestead", {}).get("level", 0)) if v.get("homestead") is Dictionary else 0
	var key := "%d %s %s %s %s" % [level, _looks.shown("porch"), _looks.shown(Looks.WING_STAGE), _looks.shown(Looks.HOUSE_STAGE), _looks.waits()]
	if key == _shade_key: return
	if _shade_key == "": _shade.redraw()
	else: get_tree().create_timer(Fence.POP_S + 0.1).timeout.connect(_shade.redraw)
	_shade_key = key

## P1 trees (q(118)): a tree's bed is solid (§5.6: not walkable, as the old woody crop); only the cells that change flip,
## the path grid is never rebuilt for it. A tree planted on the bed the player stands on blocks once they step off it
## (哪吒 on #252: never trap the player; the plot sync runs at least once a second).
var _tree_cells := {}
func _sync_trees(v: Dictionary) -> void:
	if grid == null: return
	var here := bp.world_to_cell(actor.position)
	var now := {}
	for p in v.get("plots", []): if p.get("tree", false): now[int(p.id)] = true
	for id in now.keys():
		if _tree_cells.has(id): continue
		if P0Garden.cell_of(id) == here:
			now.erase(id)   # not solid yet: try again next sync
			_sync_t = minf(_sync_t, 0.25)
			continue
		grid.set_solid(P0Garden.cell_of(id), true)
	for id in _tree_cells: if not now.has(id): grid.set_solid(P0Garden.cell_of(id), false)
	_tree_cells = now

## Middle of the plot beds, for camera-only "Show" from the Today panel and NeedSource (LOCK-08).
func _plots_center() -> Vector3:
	var sum := Vector3.ZERO
	var n := P0Garden.plot_count(rt.session.view if rt != null and rt.session != null else null)
	for id in n: sum += bp.cell_to_world(P0Garden.cell_of(id))
	return sum / maxf(1.0, float(n))

## The bed the player faces from the walkway: nearest bed ahead within reach.
func _pick_front(v: Dictionary) -> void:
	var best := -1
	var best_score := -INF
	var f := actor.facing()
	var taken := {}   # P1: a plot with a facility is no bed to work (the key shows no farming verb there)
	for p in v.get("plots", []): if p.get("facility", null) != null: taken[int(p.id)] = true
	for id in P0Garden.plot_count(v):
		if taken.has(id): continue
		var c := bp.cell_to_world(P0Garden.cell_of(id))
		var to := Vector2(c.x - actor.position.x, c.z - actor.position.z)
		var dist := to.length()
		if dist > 1.05: continue
		var ahead := to.normalized().dot(Vector2(f.x, f.z)) if dist > 0.01 else 1.0
		# Standing on a bed works that bed; otherwise ahead first, and a bed right beside the walkway
		# also counts, so walking a row while holding works.
		var underfoot := dist < 0.42
		if not underfoot and ahead < 0.2 and not (dist < 0.8 and ahead > -0.25): continue
		var score := 10.0 if underfoot else ahead * 0.6 - dist * 0.8
		if score > best_score:
			best_score = score
			best = id
	_front = {}
	if best >= 0:
		for p in v.get("plots", []):
			if int(p.get("id", -1)) == best: _front = p
	# Row Hoe: the bed in front and its tilled neighbours in the row, the way the player faces first (plot ids grow along +x).
	_row = P0Logic.row_plots(v, _front, 0, 1 if f.x >= 0.0 else -1)
	_hi.visible = not _front.is_empty() and not rt.ui.has_modal()
	if _hi.visible:
		_front_cell = P0Garden.cell_of(best)
		_hi.position = bp.cell_to_world(_front_cell) + Vector3(0, P0Garden.BED_H + 0.012, 0)

# ---------------------------------------------------------------- actions
func p0_action(cmd: Dictionary) -> void:
	if _materials.act(cmd): return
	var type := str(cmd.get("type", ""))
	var target := int(cmd.get("plot", (cmd.get("plots", [-1]) as Array)[0] if cmd.has("plots") else -1))
	if LABOUR_CLIP.has(type) and target >= 0:
		actor.labour(LABOUR_CLIP[type], bp.cell_to_world(P0Garden.cell_of(target)))
		_hold_until = Time.get_ticks_msec() + P0Actor.LABOUR_S * 1000.0
	var row: Array = cmd.get("plots", [])
	if row.size() > 1:   # one labour beat for the whole row (289): the row shows it
		if type == "harvest": _record_wave(row)
		elif type in ["sow", "water"]: row_drops(row, type)
	rt.session.send(cmd)

# ---------------------------------------------------------------- a row in one press (SGODOT-289 914bcfea §三 / §四)
## Harvest ×N: the character labours once and the crops pop along the row instead — from the plot in front outward,
## one every WAVE_STEP_S, each up and then shrinking out (程序, no new art); the camera stays. The reply's floats and
## the crops' flights to the Bag wait for the wave (P0Runtime asks p0_harvest_wave). Row Hoe's Sow ×3 / water 3:
## the seeds or the water fall on the three beds one WAVE_STEP_S apart.
const WAVE_STEP_S := 0.08
const WAVE_POP_S := 0.08
const WAVE_OUT_S := 0.2
const WAVE_KEEP_MS := 4000     # a sent row the server refused (bag full) is forgotten after this
const FLY_STEP_S := 0.1        # 289: the crops' ItemFlies, one kind after another
var _wave := {}   # the Harvest ×N sent last: {plots (near to far), crops: {plot: crop id}, at}

func _record_wave(row: Array) -> void:
	var crop_of := {}
	# what each plot is harvested as (a Quick Radish flies as the Radish the reply puts in the bag, q(217))
	for p in rt.session.view.get("plots", []):
		crop_of[int(p.get("id", -1))] = P0Logic.harvest_of(rt.session.view, str(p.get("crop", ""))) if p.get("crop", null) != null else ""
	_wave = {"plots": row.map(func(x): return int(x)), "crops": crop_of, "at": Time.get_ticks_msec()}

## The reply to the Harvest ×N sent last: the wave over the plots it took (all, or up to where the bag filled,
## q(123)) and, as it ends, one ×N flight per kind to the Bag (crops, then Seed Saver's seeds; at most
## UiItemFly.MAX_PER_BATCH). Returns how long the wave plays, for the reply's floats to wait; 0 when it is not one.
func p0_harvest_wave(events: Array) -> float:
	if _wave.is_empty() or Time.get_ticks_msec() - int(_wave.at) > WAVE_KEEP_MS: return 0.0
	var short := events.filter(func(e): return str(e.get("kind", "")) == "harvest_short")
	var got := int(short[0].get("got", 0)) if not short.is_empty() else events.filter(func(e):
		return str(e.get("kind", "")) == "item" and str(e.get("id", "")).begins_with("crop_") and int(e.get("delta", 0)) > 0).size()
	if got <= 0: return 0.0   # another reply (a refresh): the row's is still to come
	var plots: Array = (_wave.plots as Array).slice(0, got)
	var crop_of: Dictionary = _wave.crops
	_wave = {}
	for i in plots.size():
		var code := str(P0Garden.CROP_CODES.get(str(crop_of.get(int(plots[i]), "")), ""))
		if code != "":
			var tint: Color = P0Garden.FAST_TINTS.get(str(crop_of.get(int(plots[i]), "")), Color.WHITE)
			_pop(crops.ghost(P0Garden.cell_of(int(plots[i])), code, CropField.STAGES - 1, tint), i * WAVE_STEP_S)
	var wave := (plots.size() - 1) * WAVE_STEP_S + WAVE_POP_S + WAVE_OUT_S
	_harvest_flights(plots, crop_of, events, wave)
	return wave

## The Harvest ×N sent last was refused as a whole (the bag took not one plot): its wave will not come, so a single
## harvest within WAVE_KEEP_MS is not read as the row's reply (哪吒 on #291).
func p0_harvest_refused() -> void:
	_wave = {}

## One crop's pop: up to ×1.25, then shrinking and fading out, `delay` after the wave starts.
func _pop(g: Node3D, delay: float) -> void:
	var tw := g.create_tween()
	if delay > 0.0: tw.tween_interval(delay)
	tw.tween_property(g, "scale", Vector3.ONE * 1.25, WAVE_POP_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "scale", Vector3.ONE * 0.3, WAVE_OUT_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(func(k: float):
		for m in g.get_children(): (m as GeometryInstance3D).transparency = k, 0.0, 1.0, WAVE_OUT_S)
	tw.tween_callback(g.queue_free)

## As the wave ends: each crop kind of the row (in the order they were taken) and Seed Saver's seeds fly to the Bag,
## ×N, FLY_STEP_S apart, from where that kind's first plot stood; the Bag bumps as each lands. ×N is what the reply put
## in the bag, as the `+3 Radish` float says (a plot may yield more than one, 哪吒 on #291). No Bag on screen, no
## flight (UiItemFly.launch).
func _harvest_flights(plots: Array, crop_of: Dictionary, events: Array, after: float) -> void:
	var kinds := row_flights(plots, crop_of, events)
	var bag: Control = rt.ui.bag_target()
	for i in mini(kinds.size(), UiItemFly.MAX_PER_BATCH):
		var from := cam.unproject_position(bp.cell_to_world(P0Garden.cell_of(int(kinds[i][2]))) + Vector3(0, P0Garden.BED_H + 0.3, 0))
		UiItemFly.launch(rt.ui.root, from, bag, P0Logic.icon(str(kinds[i][0])), int(kinds[i][1]), after + i * FLY_STEP_S,
			func(): UiItemFly.bump(bag))

## The row's flights: [id, ×N, plot it flies from] per crop kind in the order the row took them (×N: what the reply's
## items put in the bag), then Seed Saver's seeds (one each).
static func row_flights(plots: Array, crop_of: Dictionary, events: Array) -> Array:
	var kinds: Array = []
	for id in plots:
		var crop := str(crop_of.get(int(id), ""))
		if crop != "" and not kinds.any(func(x): return x[0] == crop): kinds.append([crop, 0, int(id)])
	for e in events:
		if str(e.get("kind", "")) != "item" or int(e.get("delta", 0)) <= 0: continue
		var k := kinds.map(func(x): return x[0]).find(str(e.get("id", "")))
		if k >= 0: kinds[k][1] += int(e.delta)
	kinds = kinds.filter(func(x): return int(x[1]) > 0)
	for e in events:
		if str(e.get("kind", "")) != "seed_saved": continue
		var k := kinds.map(func(x): return x[0]).find(str(e.id))
		if k < 0: kinds.append([str(e.id), 1, int(e.get("plot", plots[0]))])
		else: kinds[k][1] += 1
	return kinds

## Row Hoe's three beds: a few seeds (sow) or drops (water) fall on each, one WAVE_STEP_S after the other.
func row_drops(row: Array, type: String) -> void:
	var color := Color(0.42, 0.3, 0.16) if type == "sow" else Color(0.45, 0.72, 0.95)
	for i in row.size():
		var top := bp.cell_to_world(P0Garden.cell_of(int(row[i]))) + Vector3(0, P0Garden.BED_H, 0)
		for d in [Vector3(-0.12, 0, -0.08), Vector3(0.1, 0, 0.0), Vector3(-0.02, 0, 0.12)]:
			var drop := MeshInstance3D.new()
			var m := SphereMesh.new()
			m.radius = 0.035 if type == "sow" else 0.045
			m.height = m.radius * (2.0 if type == "sow" else 2.6)
			drop.mesh = m
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			drop.material_override = mat
			drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			drop.position = top + d + Vector3(0, 0.7, 0)
			drop.visible = false
			add_child(drop)
			var tw := drop.create_tween()
			tw.tween_interval(i * WAVE_STEP_S)
			tw.tween_callback(func(): drop.visible = true)
			tw.tween_property(drop, "position", top + d, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_callback(drop.queue_free)

## Into the farmhouse (its stove corner is the kitchen); the farm waits suspended underneath.
func enter_farmhouse() -> void:
	if AppRouter._navigation_pending or (AppRouter.top_instance() != null and AppRouter.top_instance() != self): return
	P0Runtime.nav_started()
	_inside = true
	AppRouter.open_instance(FARMHOUSE, {})

## The farm's exit each frame (SGODOT-443): the walk there after a tap arrives and leaves, or a panel stops it; walked
## into the ring with the joystick, it leaves once armed (as the farmhouse door takes the player in).
func _exit_check() -> void:
	if not _exit.is_finite(): return
	var d := P0FarmMaterials.flat(actor.position, _exit)
	if _exit_walk:
		if rt.ui.has_modal(): stop_exit_walk()
		elif d <= EXIT_RADIUS_M:
			_exit_walk = false
			leave_by_exit()
		elif not actor.mover.is_moving(): _exit_walk = false   # no further to go (the nearest it could reach)
		return
	if d > EXIT_ARM_M: _exit_armed = true
	elif _exit_armed and d <= EXIT_RADIUS_M and actor.mover.is_moving() and not rt.ui.has_modal():
		_exit_armed = false
		leave_by_exit()

## Out to the map as the place chip goes (P0Runtime.leave_world: a world with its back lock asks it first). An open
## layer (the radial, a card) only closes: still here, the ring is armed again, and the next step in it goes (周瑜 on #860).
func leave_by_exit() -> void:
	_exit_armed = false
	if rt: rt.leave_world()
	if is_inside_tree(): _exit_armed = true

## A tap on the exit's icon, strip or piece: walk there (the arrival leaves, _exit_check); out of reach, the nearest.
func walk_to_exit() -> void:
	if not _exit.is_finite(): return
	if P0FarmMaterials.flat(actor.position, _exit) <= EXIT_RADIUS_M:
		leave_by_exit()
		return
	_exit_walk = actor.mover.set_target_position(_exit)

## 赵云's pin and ring at the exit (no collider: the player walks into the ring), once the piece is in this build.
func _exit_piece() -> void:
	if not ResourceLoader.exists(EXIT_PIECE): return
	var piece := (load(EXIT_PIECE) as PackedScene).instantiate() as Node3D
	piece.name = "ExitPin"
	piece.position = _exit
	# its red and yellow are vertex colours (赵云's #862): its glTF materials have no albedo of their own (上官婉儿 /
	# 不知火舞 on 443: white in the game), so the farm art's vertex-colour material on the pin and the ring alike
	_exit_pin_mat = FarmArt.material().duplicate() as StandardMaterial3D   # the pin's own, to fade it (_exit_fade)
	_exit_pin_mat.set_meta(GlesAlbedo.KEEP, true)   # faded here (_exit_fade): the GLES swap leaves it (SGODOT-458)
	var pin := piece.find_child(EXIT_PIN_NODE, true, false) as Node3D
	_exit_pin_meshes.clear()
	for m: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		var of_pin := pin != null and (m == pin or pin.is_ancestor_of(m))
		m.material_override = _exit_pin_mat if of_pin else FarmArt.material()
		if of_pin: _exit_pin_meshes.append(m)
	var ring := piece.find_child(EXIT_RING_NODE, true, false) as MeshInstance3D
	if ring and ring.mesh:
		var k := EXIT_RING_R / maxf(0.01, ring.mesh.get_aabb().size.x * 0.5)
		ring.scale = Vector3(k, 1.0, k)
	add_child(piece)
	var ap := piece.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and ap.has_animation("bob"):
		ap.get_animation("bob").loop_mode = Animation.LOOP_LINEAR   # a glTF clip imports one-shot (周瑜 on #860)
		ap.play("bob")
		return
	# no loop of its own: its pin bobs EXIT_BOB_M either way every EXIT_BOB_S, eased (the user 11-07: "it floats"); the ring stays
	if pin == null: return
	var y := pin.position.y
	pin.position.y = y - EXIT_BOB_M
	var tween := pin.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(pin, "position:y", y + EXIT_BOB_M, EXIT_BOB_S * 0.5)
	tween.tween_property(pin, "position:y", y - EXIT_BOB_M, EXIT_BOB_S * 0.5)

## A tap within EXIT_TAP_PX of the exit is the exit's only when no open bed's middle is nearer it on screen (V4 review
## C7: bed 62 lies beside the ring; a tap on it is the bed's).
func _exit_tapped(screen: Vector2) -> bool:
	if not _exit.is_finite(): return false
	var d := cam.unproject_position(_exit + EXIT_HIT).distance_to(screen)
	if d >= EXIT_TAP_PX: return false
	for id in P0Garden.plot_count(rt.session.view if rt != null and rt.session != null else null):
		if cam.unproject_position(bp.cell_to_world(P0Garden.cell_of(id))).distance_to(screen) < d: return false
	return true

## The pin faded while the player is near the exit (EXIT_FADE_M), back when away; blended only while faded.
func _exit_fade(dt: float) -> void:
	_exit_strip_lift(dt)
	if _exit_pin_mat == null or not _exit.is_finite(): return
	var to := EXIT_FADE_ALPHA if P0FarmMaterials.flat(actor.position, _exit) < EXIT_FADE_M else 1.0
	var a := move_toward(_exit_pin_mat.albedo_color.a, to, dt * (1.0 - EXIT_FADE_ALPHA) / EXIT_FADE_S)
	_exit_pin_mat.albedo_color = Color(1, 1, 1, a)
	_exit_pin_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	for m in _exit_pin_meshes:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if a < 1.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## The exit's strip clear of the player's head while, at its mark, it would cover their head or upper body on screen
## (at once); eased back once it would not.
func _exit_strip_lift(dt: float) -> void:
	var strip := rt.ui.name_bar_rect("exit") if rt != null and _exit.is_finite() else Rect2()
	_exit_lift = _exit_clear.step(dt, strip, cam.unproject_position(_exit + EXIT_MARK).y if _exit.is_finite() else 0.0,
		func(): return actor.screen_box(cam))

## The walk out stopped where the player is (the joystick, a tap elsewhere, a panel).
func stop_exit_walk() -> void:
	if not _exit_walk: return
	_exit_walk = false
	actor.mover.stop()

func _door_check() -> void:
	var off := Vector2(actor.position.x - _door.x, actor.position.z - _door.z)
	if off.length() > DOOR_ARM_M: _door_armed = true
	elif _door_armed and absf(off.x) < DOOR_HALF.x and absf(off.y) < DOOR_HALF.y and actor.mover.is_moving() \
			and actor.facing().z < -0.5 and not rt.ui.has_modal():
		_door_armed = false
		enter_farmhouse()

func p0_energy_verb() -> String: return str(rt.ui.fab_state().get("verb", "Sow ×1"))

## Hold to keep sowing (§14.2): the verb pressed first repeats on each new bed, one labour beat apart.
func _hold_repeat() -> void:
	if not rt.ui.fab_held or rt.ui.has_modal() or actor.busy() or rt.session.busy: return
	if Time.get_ticks_msec() < _hold_until: return
	var a: Dictionary = rt.ui.fab_state()
	var cmd: Dictionary = a.get("cmd", {})
	if not a.get("enabled", false) or cmd.is_empty() or str(cmd.get("type", "")) == "energy_card" or a.get("once", false): return   # a tree is planted one press at a time (q(118))
	if rt.ui.fab_verb == "": rt.ui.fab_verb = str(a.get("verb", ""))
	if str(a.get("verb", "")) != rt.ui.fab_verb: return
	rt.holding_repeat = true   # the observation log's "hold" (S7); the first press went out as a tap
	p0_action(cmd)
	rt.holding_repeat = false

## Facilities respond to taps only (§10.2.2): the stall opens its drawer directly (unattended, p(6)), the farmhouse
## takes the player in (its kitchen is inside since SGODOT-226; the door card is gone, int5 hand test 37).
func p0_tap(screen: Vector2) -> void:
	if rt.ui.has_modal(): return
	if _tap_walk:   # a tap anywhere stops a tapped walk; an open-ground one starts another below (SGODOT-465)
		_tap_walk = false
		actor.mover.stop()
	var card := str(rt.ui.tapped_card)
	if card != "exit": stop_exit_walk()   # a tap elsewhere stops the walk out
	if card == "exit" or (card == "" and _exit_tapped(screen)):
		walk_to_exit()
		return
	if _guide != null and _guide.tap(screen, card): return
	if _tap_card(card): return
	if _facilities != null and _facilities.tap(screen): return   # P1: a sprinkler's status card (SGODOT-241)
	if _sign_hit(screen):
		actor.face(_sign)
		HomePanel.open(rt.ui)
	elif _plaque_node.visible and cam.unproject_position(_plaque + BADGE_HIT).distance_to(screen) < 34:
		actor.face(_plaque)
		HomePanel.plaque(rt.ui)
	# The Mailbox and the bench stand beside the house: before the stall and the house, so the house's wider radius
	# doesn't take them.
	elif cam.unproject_position(_mailbox + MAILBOX_HIT).distance_to(screen) < MAILBOX_TAP_PX:
		actor.face(_mailbox)
		rt.ui.open_inbox()
	elif cam.unproject_position(_bench + Vector3(0, 0.35, 0)).distance_to(screen) < BENCH_TAP_PX:
		actor.face(_bench)
		rt.ui.open_rest_card()
	# the Chef's Sign's board after the bench: where the two overlap on screen the bench takes the tap (不知火舞 on 282)
	elif _chef_sign_node.visible and cam.unproject_position(_chef_sign + CHEF_SIGN_HIT).distance_to(screen) < CHEF_SIGN_TAP_PX:
		open_chef_sign()
	# the Notice Board beside the stall, before it: its board is the smaller target (q(164) ①)
	elif _notice_node.visible and cam.unproject_position(_notice + NOTICE_HIT).distance_to(screen) < NOTICE_TAP_PX:
		open_notice_board()
	elif cam.unproject_position(_stall + Vector3(0, 0.4, 0)).distance_to(screen) < 56:
		actor.face(_stall)
		rt.ui.open_stall()
	elif cam.unproject_position(_house + Vector3(0, 1.0, 0.6)).distance_to(screen) < 80:
		actor.face(_door)
		enter_farmhouse()
	elif _materials.tap(screen): pass   # SGODOT-231: gathering spots, workbench (last: smallest targets)
	else: _walk_tap(screen)

## A tap on the open ground walks there (SGODOT-465; the user 11-10, bot 641 「农场点地 ok」; 不知火舞's spec v1, q(310)), as
## at the pond: the exit, the guide, the cards and every facility above take their taps first. On one of the open beds
## the walk ends on the walkway behind it, facing it across the bed (plotface's stand), and sows nothing (the main key only, LOCK-02); past the walk
## (the woods, outside the fence) it ends at the nearest place it can reach. The joystick (the mover drops its path),
## another tap (p0_tap) or any panel (_tap_walk_check) stops it; Decorate keeps its taps; no marker where it goes.
var _tap_walk := false
var _tap_face := Vector3.INF   # the bed the walk ends facing, INF for open ground
func _walk_tap(screen: Vector2) -> void:
	# Not before the first p0_frame has built the facilities and Decorate (the server's view in): a new account's tap
	# while its farm was still coming crashed iOS 0.3.6 on the null (Release has no null check; 蒙恬's crash log).
	if _facilities == null or _decor == null: return
	if not _facilities.placing.is_empty() or not _decor.placing.is_empty(): return   # Decorate: its taps place
	var origin := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 0.001: return
	var point := origin + dir * (-origin.y / dir.y)
	var to := tap_target(bp, point, P0Garden.plot_count(rt.session.view))
	_tap_face = point if to != point else Vector3.INF
	_tap_walk = actor.mover.set_target_position(to)
	if not _tap_walk: _tap_walk = _walk_near(to)

## Past the walk: the reachable cell nearest `to`, ring by ring out to NEAR_CELLS from the blueprint cell nearest it (a
## tap far into the woods starts at the grid's edge, 周瑜 on #947).
const NEAR_CELLS := 12
func _walk_near(to: Vector3) -> bool:
	var at := bp.world_to_cell(to)
	at = Vector2i(clampi(at.x, bp.grid_origin.x, bp.grid_origin.x + bp.grid.x - 1), clampi(at.y, bp.grid_origin.y, bp.grid_origin.y + bp.grid.y - 1))
	for r in range(1, NEAR_CELLS + 1):
		var ring: Array[Vector2i] = []
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and not grid.is_blocked(at + Vector2i(dx, dy)): ring.append(at + Vector2i(dx, dy))
		ring.sort_custom(func(c1, c2): return bp.cell_to_world(c1).distance_to(to) < bp.cell_to_world(c2).distance_to(to))
		for c in ring:
			if actor.mover.set_target_position(bp.cell_to_world(c)): return true
	return false

## Each frame: a panel stops a tapped walk; at its end it turns to the bed it was for.
func _tap_walk_check() -> void:
	if not _tap_walk: return
	if rt.ui.has_modal():
		_tap_walk = false
		actor.mover.stop()
	elif not actor.mover.is_moving():
		_tap_walk = false
		if _tap_face.is_finite(): actor.face(_tap_face)

## Where a tap on the ground at `point` walks to: there, or for one of the `open` beds, the walkway cell behind it (away
## from the camera, as plotface stands: the bed stays in sight in front of the player); a bed not open yet is grass.
static func tap_target(blueprint: FarmBlueprint, point: Vector3, open: int) -> Vector3:
	var cell := blueprint.world_to_cell(point)
	var id := P0Garden.id_of(cell)
	if id < 0 or id >= open: return point
	return blueprint.cell_to_world(cell + BED_FRONT)
const BED_FRONT := Vector2i(0, 1)

## A finger card's tap goes to its own facility by id, never through the point test: the point of one facility can
## sit under another's mark (the farmhouse card's point under the sign's caption, PR #21 review).
func _tap_card(id: String) -> bool:
	match id:
		"sign":
			actor.face(_sign)
			HomePanel.open(rt.ui)
		"plaque":
			actor.face(_plaque)
			HomePanel.plaque(rt.ui)
		"chef_sign": open_chef_sign()
		"notice_board": open_notice_board()
		"stall":
			actor.face(_stall)
			rt.ui.open_stall()
		"home":
			actor.face(_door)
			enter_farmhouse()
		"bench":
			actor.face(_bench)
			rt.ui.open_rest_card()
		"mailbox":
			actor.face(_mailbox)
			rt.ui.open_inbox()
		_:
			if _facilities and _facilities.tap_card(id): return true   # P1: a greenhouse's strip or button
			return _materials.tap_card(id)   # SGODOT-231: spot_* and workbench cards
	return true

## Existing nearby Gift entry may address the farm's guide, exactly as a resident in an outpost.
func p0_near_resident() -> String:
	return str(_guide.near_resident()) if _guide != null else ""

## A word on the badge's face, as its review renders wrote it: Nunito ExtraBold, flat ink, no outline, unshaded, one
## sided, never turning to the camera; `cap` metres of cap height (0.705 of the font size at pixel_size 0.002). null with
## no socket (a renamed one in a later model): the badge then shows no number, never a null read (iOS Release would crash).
static func badge_label(socket: Node3D, text: String, cap: float) -> Label3D:
	if socket == null: return null
	var l := Label3D.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # `Lv` and digits, as everywhere
	l.font = BADGE_FONT
	l.pixel_size = 0.002
	l.font_size = roundi(cap / (0.705 * l.pixel_size))
	l.outline_size = 0
	l.modulate = BADGE_INK
	l.shaded = false
	l.double_sided = false
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	socket.add_child(l)
	return l

## The badge from Lv2 (the first upgrade; none at Lv1): its tier's face and the level's number, set when the level changes.
func _show_badge(level: int) -> void:
	_plaque_node.visible = level >= 2
	if level == _badge_level: return
	_badge_level = level
	var tier := P0Logic.badge_tier(level)
	for t in ["wood", "bronze", "silver", "gold"]:
		var face := _plaque_node.find_child("Tier_" + t, true, false) as Node3D
		if face: face.visible = t == tier
	if _badge_number: _badge_number.text = str(level)

## The sign itself (its icon button and strip arrive by id, _tap_card); small, so the door beside it stays the house.
## Nothing above the board: with the button hidden (beyond 8 m) that spot is not the sign's (苏烈 on #59).
func _sign_hit(screen: Vector2) -> bool:
	return cam.unproject_position(_sign + Vector3(0, 0.45, 0)).distance_to(screen) < 34

## World prompts (SGODOT-250; LOCK-07 v2 / LOCK-11 / LOCK-17 v2; q(62); WORLD-HINT-1…5): every facility within
## P0WorldPrompts.RANGE shows its icon button (a state shows from anywhere and takes the icon's place); the one nearest
## in reach (_card) opens its name strip toward the way the character faces. No "Tap to …": tapping the button, the
## strip or the object is tapping the facility (_tap_card by id). Anchors are the former finger cards' and marks'.
func _prompts(v: Dictionary) -> void:
	_strip_side = _facing_side()
	world_prompt("stall", P0WorldPrompts.stall(v, rt.ui.stall_has_new()), _stall, Vector3(0, 1.05, 0), Vector3(0, 0.4, 0))
	world_prompt("home", P0WorldPrompts.farmhouse(v), _house, home_mark(), Vector3(0, 1.0, 0.6))
	world_prompt("sign", P0WorldPrompts.sign(v), _sign, SIGN_BADGE, Vector3(0, 0.45, 0))
	_show_badge(int(v.get("homestead", {}).get("level", 1)))
	world_prompt("plaque", P0WorldPrompts.plaque(v), _plaque, BADGE_MARK, BADGE_HIT, _plaque_node.visible)
	_show_chef_sign(bool(v.get("homestead", {}).get("unlocks", {}).get("chefs_sign", false)))
	if _chef_sign_node.visible: _chef_sign_model(_looks.shown(Looks.HOUSE_STAGE) if _looks else "")
	world_prompt("chef_sign", P0WorldPrompts.chef_sign(v), _chef_sign, CHEF_SIGN_MARK, CHEF_SIGN_HIT, _chef_sign_node.visible)
	_show_notice_board(P0NoticeBoardLogic.unlocked(v))
	world_prompt("notice_board", P0WorldPrompts.notice_board(v), _notice, NOTICE_MARK, NOTICE_HIT, _notice_node.visible)
	world_prompt("bench", P0WorldPrompts.bench(v), _bench, Vector3(0, 0.95, 0), Vector3(0, 0.35, 0))
	world_prompt("mailbox", P0WorldPrompts.mailbox(v), _mailbox, MAILBOX_MARK, MAILBOX_HIT)
	world_prompt("exit", P0WorldPrompts.farm_exit(EXIT_ICON), _exit, EXIT_MARK, EXIT_HIT, _exit.is_finite(), -1, _exit_lift)
	if _facilities: _facilities.prompts(v)

## One facility's prompt at `at` + `mark` (the former finger card's / mark's anchor): its strip when it is the open
## one, else its icon button (P0WorldPrompts.show). The button and strip forward their taps to `at` + `hit` by id.
## `side`: the strip's way, the character's facing when −1; a facility strip opens right, its icon on the left, as
## the Fish Trap's (不知火舞 on 241 ba9359df).
func world_prompt(id: String, prompt: Dictionary, at: Vector3, mark: Vector3, hit: Vector3, present := true, side := -1, lift := 0.0) -> void:
	var screen := cam.unproject_position(at + mark) + Vector2(0.0, lift)
	var tap := cam.unproject_position(at + hit)
	var show := P0WorldPrompts.show(id, _card, P0FarmMaterials.flat(actor.position, at), prompt) \
		if present and not rt.ui.has_modal() else P0WorldPrompts.Show.NONE
	if show == P0WorldPrompts.Show.BAR:
		rt.ui.name_bar(id, prompt.icon, str(prompt.text), str(prompt.fact), screen, true, _strip_side if side < 0 else side, bool(prompt.dimmed),
			int(prompt.status), tap)
	else:
		rt.ui.world_icon(id, prompt.icon, screen, show == P0WorldPrompts.Show.ICON, false, int(prompt.status), tap,
			str(prompt.get("count", "")))

## The side a strip opens to: the character's facing on screen; facing the camera or away keeps the last side.
func _facing_side() -> UiWorldNameBar.Dir:
	var from := cam.unproject_position(actor.position)
	var dx := cam.unproject_position(actor.position + actor.facing()).x - from.x
	if absf(dx) < 6.0: return _strip_side
	return UiWorldNameBar.Dir.LEFT if dx < 0.0 else UiWorldNameBar.Dir.RIGHT

## Every facility that can open its name strip on the farm, [id, position, reach m] in a fixed order (LOCK-07 v2: one
## strip, the nearest in reach): the rest bench, and SGODOT-231's five gathering spots and the workbench.
## The exit among the facilities whose strip opens nearest: its `Map` strip (443 v1.2 §3; 周瑜 on #860).
func exit_card() -> Array: return ["exit", _exit, SIGN_NEAR]

func _card_candidates() -> Array:
	var out: Array = [["stall", _stall, 3.2], ["home", _house, 4.2], ["sign", _sign, SIGN_NEAR], ["bench", _bench, BENCH_NEAR_M],
		["mailbox", _mailbox, SIGN_NEAR], exit_card()]
	if _plaque_node.visible: out.append(["plaque", _plaque, SIGN_NEAR])
	if _chef_sign_node.visible: out.append(["chef_sign", _chef_sign, SIGN_NEAR])
	if _notice_node.visible: out.append(["notice_board", _notice, SIGN_NEAR])
	out.append_array(_materials.card_candidates())   # SGODOT-231: the five gathering spots and the workbench
	if _facilities: out.append_array(_facilities.card_candidates())   # P1: greenhouses (`Greenhouse · −25%`)
	return out

## A node's meshes' bounds on screen (shots: what covers what).
func _screen_rect(n: Node) -> Rect2:
	var r := Rect2()
	var first := true
	if n == null: return r
	var meshes: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D: meshes.append(n)
	for m in meshes:
		var box: AABB = (m as MeshInstance3D).get_aabb()
		for i in 8:
			var p: Vector2 = cam.unproject_position((m as MeshInstance3D).global_transform * box.get_endpoint(i))
			if first: r = Rect2(p, Vector2.ZERO)
			else: r = r.expand(p)
			first = false
	return r

## The Chef's Sign up from Homestead Lv10: shown, and its cell solid (a post one walks round) with the cell under its
## board (P0Garden.CHEF_SIGN_BOARD_CELL), back if it ever goes.
func _show_chef_sign(on: bool) -> void:
	if _chef_sign_node.visible == on: return
	_chef_sign_node.visible = on
	for c in [P0Garden.CHEF_SIGN_CELL, P0Garden.CHEF_SIGN_BOARD_CELL]:   # its post's cell and the cell under its board
		if bp.is_walkable(c): grid.set_solid(c, on)   # a cell the plan blocks stays blocked

## The Notice Board up from Homestead Lv5 (q(164) ①): shown, and its cell solid, as the Chef's Sign.
func _show_notice_board(on: bool) -> void:
	if _notice_node.visible == on: return
	_notice_node.visible = on
	if bp.is_walkable(P0Garden.NOTICE_BOARD_CELL): grid.set_solid(P0Garden.NOTICE_BOARD_CELL, on)

## A tap on it opens the board (P0Ui.open_notice_board): read-only, a row flies the map to that pin.
func open_notice_board() -> void:
	actor.face(_notice)
	rt.ui.open_notice_board()

## The Notice Board's model (刘备, #395; 上官婉儿 284 c8ab943e, 不知火舞 48f7ac45): two posts with a cork board, a gable
## roof and four pinned sheets, 1.595 m; its pivot the ground midpoint between the posts, +Z to the camera, at the anchor.
## Inside its cell below the roof (feet ±0.30; the stall's seed crate next door reaches 0.33).
static func notice_board_prop(at: Vector3) -> Node3D:
	return FarmArt.instance("notice_board", at)

## Its card (不知火舞 on 282): the facilities' small card — `Chef's Sign`, `Homestead Lv10`, and HOME-1's
## Lv10 line for what it does.
func open_chef_sign() -> void:
	actor.face(_chef_sign)
	rt.ui.open_facility_card(chef_sign_card(), func(): pass)

static func chef_sign_card() -> Dictionary:
	var note := str(P0Logic.P1_UNLOCKS.chefs_sign.note)
	return {"title": "Chef's Sign", "lead": "Home Lv10", "icon": P0Logic.icon("kitchen"),
		"facts": [note.left(1).to_upper() + note.substr(1)], "button": ""}

## The Chef's Sign's model after the Master Farmhouse look it came with at Lv10 (上官婉儿 on 282: it follows Lv10's a / b),
## LOOK-PICK's preview of it too: stone (b) chef_sign_b, else timber chef_sign_a.
func _chef_sign_model(look: String) -> void:
	var want := "b" if look == "b" else "a"
	if want == _chef_sign_look and _chef_sign_node.get_child_count() > 0: return
	_chef_sign_look = want
	for c in _chef_sign_node.get_children():
		_chef_sign_node.remove_child(c)
		c.free()
	_chef_sign_node.add_child(chef_sign_mesh(want))

## A box's bounds on screen (shots: placement by numbers).
func _box_on_screen(at: Vector3, size: Vector3) -> Rect2:
	var r := Rect2(cam.unproject_position(at), Vector2.ZERO)
	for i in 8: r = r.expand(cam.unproject_position(at + Vector3(size.x * (i & 1), size.y * ((i >> 1) & 1), size.z * ((i >> 2) & 1))))
	return r

static func chef_sign_mesh(look: String) -> MeshInstance3D:
	return FarmArt.instance("chef_sign_b" if look == "b" else "chef_sign_a")

## Basic Room's bench (648 tris; q(30)) with the room's shared atlas material.
func _bench_prop(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Bench"
	root.position = at
	var model := (load("res://assets/rooms/basic_room/bench.glb") as PackedScene).instantiate() as Node3D
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/rooms/basic_room/room_albedo_ao.png")
	mat.roughness = 0.8
	mat.metallic_specular = 0.28
	for m in model.find_children("*", "MeshInstance3D", true, false): (m as MeshInstance3D).material_override = mat
	root.add_child(model)
	return root

## The Mailbox placeholder (SGODOT-234 C; assets/props/mailbox_placeholder): the post office's red post box at 0.65 —
## 0.51 m wide, 1.16 m tall, one cell — with its room atlas; front (local +Z) toward the camera.
func _mailbox_prop(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Mailbox"
	root.position = at
	root.scale = Vector3.ONE * MAILBOX_SCALE
	var model := (load(MAILBOX_DIR + "red_post_box.glb") as PackedScene).instantiate() as Node3D
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(MAILBOX_DIR + "room_albedo_ao.png")
	mat.roughness = 0.9
	for m in model.find_children("*", "MeshInstance3D", true, false): (m as MeshInstance3D).material_override = mat
	root.add_child(model)
	return root

## The landing's teaching card (q(215): `Pick a seed…`). Asked for even under a dialog (Pip's opening line): the TipQueue
## holds it until the dialog closes (方案 §10.3 ⑥, 不知火舞 355 G01); a Sow meanwhile takes it off the queue (TipQueue.did).
func _teaching(v: Dictionary) -> void:
	var firsts: Array = v.get("firsts", [])
	if not firsts.any(func(f): return str(f).begins_with("harvest:")) and not v.get("plots", []).any(func(p): return str(p.state) in ["sown", "growing", "ready"]):
		rt.ui.teach("sow")   # copy in P0Guide.TIPS (q(44))

func p0_anchor() -> Vector2:
	if not _front.is_empty():
		return cam.unproject_position(bp.cell_to_world(_front_cell) + Vector3(0, 0.7, 0))
	return cam.unproject_position(actor.position + Vector3(0, 2.0, 0))

# ---------------------------------------------------------------- dev steps for P0_SHOT
func p0_dev(step: PackedStringArray) -> bool:
	if step[0] in ["goto", "gocell", "near"]: _opening = false   # a teleport frames itself
	match step[0]:
		"yaw": _dev_yaw = float(step[1])
		"goto":
			_dev_aim = Vector3.INF   # a teleport ends any aimed walk (it would walk the player back)
			p0_joystick(Vector2.ZERO)
			actor.teleport(Vector3(float(step[1]), 0, float(step[2])))
			_focus = actor.position
		"plotface":   # plotface:<id> — stand on the walkway in front of a plot, facing it (P1 tree review shots)
			var bed := bp.cell_to_world(P0Garden.cell_of(int(step[1])))
			actor.teleport(bp.cell_to_world(P0Garden.cell_of(int(step[1])) + Vector2i(0, 1)))
			actor.face(bed)
			_focus = actor.position
		"gocell":
			_dev_aim = Vector3.INF   # a teleport ends any aimed walk (it would walk the player back)
			p0_joystick(Vector2.ZERO)
			actor.teleport(bp.cell_to_world(Vector2i(int(step[1]), int(step[2]))))
			_focus = actor.position
		"face":
			actor.face(actor.position + Vector3(float(step[1]), 0, float(step[2])))
		"pathcells":   # pathcells:x0:y0:x1:y1 — the cells the player's path between two cells crosses (282 shots: the Chef's Sign)
			var path := grid.point_path(bp.cell_to_world(Vector2i(int(step[1]), int(step[2]))), bp.cell_to_world(Vector2i(int(step[3]), int(step[4]))))
			var cells: Array = []
			for i in path.size():
				var c := bp.world_to_cell(path[i])
				if cells.is_empty() or cells[-1] != c: cells.append(c)
				if i > 0:   # the cells between points too, sampled every 5 cm
					var a: Vector3 = path[i - 1]
					var n := maxi(1, ceili(a.distance_to(path[i]) / 0.05))
					for k in n:
						var m := bp.world_to_cell(a.lerp(path[i], float(k) / n))
						if cells[-1] != m and not cells.has(m): cells.append(m)
			print("P0_PATHCELLS ", step.slice(1), " ", cells)
		"aimcell": _dev_aim = bp.cell_to_world(Vector2i(int(step[1]), int(step[2])))   # aimcell:x:y — walk straight there (shots)
		"tapcell":   # tapcell:x:y — a tap on the ground there (the player walks to it)
			p0_tap(cam.unproject_position(bp.cell_to_world(Vector2i(int(step[1]), int(step[2])))))
		"farmhouse": enter_farmhouse()
		"democrops":
			# Visual check only: every P0 crop at every stage across the first rows (no server state).
			var fake := {}
			var codes := P0Garden.CROP_CODES.values()
			var now := Time.get_ticks_msec()
			for i in codes.size():
				for stage in 3:
					var id := stage * codes.size() + i
					if id >= P0Garden.plot_count(): continue
					var span := 3600000
					var started := now - int(span * [0.2, 0.55, 1.2][stage])
					fake[P0Garden.cell_id(P0Garden.cell_of(id))] = {"state": "growing", "crop": codes[i], "watered_at": started, "ready_at": started + span}
			crops.sync(fake, now)
			_plot_sig = "frozen"
			_sync_t = 9999.0
		"sign": p0_tap(cam.unproject_position(_sign + Vector3(0, 0.45, 0)))   # HOME-1 through the sign's own tap
		"plaque": p0_tap(cam.unproject_position(_plaque + BADGE_HIT))   # the Home Badge's card
		"pip":   # a tap on the guide's Pip where he is now (SGODOT-411 shots: he stops and turns to the player)
			if _guide != null and _guide.pip_root != null: p0_tap(cam.unproject_position(_guide.pip_root.to_global(Vector3(0, 0.8, 0))))
		"topip":   # walk straight up to 1.2 m short of where Pip is now (SGODOT-411 shots: near him he stands and turns)
			if _guide != null and _guide.pip_root != null:
				var pip: Vector3 = _guide.pip_root.position
				var back := Vector3(actor.position.x - pip.x, 0, actor.position.z - pip.z)
				_dev_aim = pip + (back.normalized() * 1.2 if back.length() > 1.2 else back)
		"chefsign": p0_tap(cam.unproject_position(_chef_sign + CHEF_SIGN_HIT))   # the Chef's Sign's card (282 shots)
		"noticetap": p0_tap(cam.unproject_position(_notice + NOTICE_HIT))   # the Notice Board through its own tap (q(164) shots)
		"chefsignprobe":   # where the Chef's Sign and its neighbours are on screen (282 shots: placement by numbers)
			var at := func(p: Vector3) -> Vector2: return cam.unproject_position(p)
			print("P0_CHEFSIGN ", JSON.stringify({visible = _chef_sign_node.visible, chefs_sign = rt.session.view.get("homestead", {}).get("unlocks", {}).get("chefs_sign", null),
				board = at.call(_chef_sign + CHEF_SIGN_HIT), foot = at.call(_chef_sign), top = at.call(_chef_sign + Vector3(0, 1.7, 0)),
				plaque = at.call(_plaque), sign = at.call(_sign), door = at.call(_door), bench = at.call(_bench), actor = at.call(actor.position),
				board_rect = _box_on_screen(_chef_sign + CHEF_SIGN_BOARD.position, CHEF_SIGN_BOARD.size), bench_rect = _screen_rect(find_child("Bench", true, false)),
				bench_seat = at.call(_bench + Vector3(0, 0.35, 0)), unit_x = at.call(_chef_sign + Vector3.RIGHT) - at.call(_chef_sign),
				shift = CHEF_SIGN_SHIFT.x, look = _chef_sign_look}))
		"mailbox": p0_tap(cam.unproject_position(_mailbox + MAILBOX_HIT))   # the Inbox through the Mailbox's own tap (234 C)
		"exit": walk_to_exit()   # the walk out through the exit's prompt, as a tap on it (443 shots)
		"spawnat": actor.teleport(Vector3(float(step[1]), 0, float(step[2])))   # spawnat:x:z — stood there (443 D: a spawn further right)
		"exitat":   # exitat:x:z — the exit (and its piece) moved there (443: places compared for the user)
			_exit = Vector3(float(step[1]), 0, float(step[2]))
			var piece := get_node_or_null("ExitPin") as Node3D
			if piece: piece.position = _exit
		"zoomto": _zoom = clampf(float(step[1]), 0.8, 1.4)   # zoomto:0.8 (widest) … 1.4 (closest)
		"noui": if rt: rt.ui.visible = false   # the world alone (as P0Room's): a level-up's banner over the woods giving way
		"edges":   # the ground (y 0) under the screen's corners and edge middles (scene art: where the picture ends)
			var view := get_viewport().get_visible_rect().size
			var out := {"zoom": snappedf(_zoom, 0.001), "size": snappedf(cam.size, 0.01)}
			var at := {"tl": Vector2(0, 0), "tr": Vector2(1, 0), "bl": Vector2(0, 1), "br": Vector2(1, 1), "top": Vector2(0.5, 0),
					"bottom": Vector2(0.5, 1), "left": Vector2(0, 0.5), "right": Vector2(1, 0.5)}
			for key in at:
				var px: Vector2 = at[key] * view
				var o := cam.project_ray_origin(px)
				var n := cam.project_ray_normal(px)
				var g := o + n * (-o.y / n.y)
				out[key] = [snappedf(g.x, 0.01), snappedf(g.z, 0.01)]
			print("P0_EDGES ", JSON.stringify(out))
		"rinfo":   # this frame's triangles and draw calls (scene art budgets)
			print("P0_RINFO ", JSON.stringify({"prims": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)}))
		"batches":   # every batch on the farm: instances × triangles, shadows (scene art budgets)
			var rows: Array = []
			var total := 0
			for m: MultiMeshInstance3D in find_children("*", "MultiMeshInstance3D", true, false):
				var mesh := m.multimesh.mesh
				if mesh == null: continue
				var tris := 0
				for si in mesh.get_surface_count():
					var a := mesh.surface_get_arrays(si)
					tris += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3
				var n := m.multimesh.visible_instance_count if m.multimesh.visible_instance_count >= 0 else m.multimesh.instance_count
				total += n * tris
				rows.append("%s|%s|%d|%d|%d|%d" % [str(m.get_parent().name), str(m.name), n, tris, n * tris, int(m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)])
			print("P0_BATCHES total=%d n=%d\n%s" % [total, rows.size(), "\n".join(rows)])
		"walkhash":   # the walk mask and the path grid's solid cells as built (a scenery change must leave both alone)
			var solid: Array = []
			for y in range(bp.grid_origin.y, bp.grid_origin.y + bp.grid.y):
				for x in range(bp.grid_origin.x, bp.grid_origin.x + bp.grid.x):
					if grid.astar.is_in_boundsv(Vector2i(x, y)) and grid.astar.is_point_solid(Vector2i(x, y)): solid.append(Vector2i(x, y))
			print("P0_WALKHASH ", JSON.stringify({"mask": str(bp.masks.walkable).hash(), "solid": str(solid).hash(), "solid_n": solid.size()}))
		"island":   # the whole island in the picture, as far as the opening may zoom out (#624 walkthrough: a farm end to end)
			var corners: Array[Vector3] = []
			var isle := island_rect()
			for c in [isle.position, isle.end, Vector2i(isle.position.x, isle.end.y), Vector2i(isle.end.x, isle.position.y)]:
				corners.append(bp.cell_to_world(c))
			_frame_opening(corners, rt.ui.open_marker_area())
		"actorhide": _actor_fade_to = 1.0   # the yard's pieces alone, the player faded out (上官婉儿 on #276's shots)
		# LOOK-PICK (SGODOT-282): lookpick:<stage>[:home] opens the card as after the level-up (or from HOME-1);
		# lookpick-b / lookpick-a tap a card; lookuse presses Use; lookclose ✕; lookparts prints the stages' parts.
		"lookpick": P0LookPick.open(rt.ui, step[1], not (step.size() > 2 and step[2] == "home"))
		"lookpick-a", "lookpick-b":
			var card := rt.ui.find_children("*", "P0LookPick", true, false)
			if not card.is_empty(): (card[0] as P0LookPick).pick(step[0].right(1))
		"lookuse", "lookclose":
			var card := rt.ui.find_children("*", "P0LookPick", true, false)
			if not card.is_empty():
				if step[0] == "lookuse": (card[0] as P0LookPick).use()
				else: (card[0] as P0LookPick).dismiss()
		"lookparts":
			var out := {"fence": _fence.look, "house": str(_looks._house.mesh.resource_path) if _looks._house.mesh else ""}
			for st in _looks.STAGES: out[st] = [_looks.shown(st), (_looks.parts(st) as Array).map(func(n): return [str(n.name), cam.unproject_position((n as Node3D).global_position)])]
			out["house_screen"] = cam.unproject_position(_house + Vector3(0, 1.0, 0))
			# Lv10 checks (上官婉儿 on #250): the door path, the sign, the roof top and the farmhouse prompt on screen
			var top := (_looks._house.mesh as Mesh).get_aabb().end.y if _looks._house.mesh else 0.0
			out["door_path"] = cam.unproject_position(_door)
			out["sign"] = cam.unproject_position(_sign + Vector3(0, 0.6, 0))
			out["roof_top"] = [top, cam.unproject_position(_house + Vector3(0, top, 0))]
			out["home_mark"] = cam.unproject_position(_house + home_mark())
			var b: UiWorldIconButton = rt.ui._icons.get("home")
			if b and b.visible: out["home_button"] = b.get_global_rect()
			print("P0_LOOKS ", out)
		# P1 placement (SGODOT-241): build:<recipe> opens it as the Facilities card's Build does; placeat:<plot> moves
		# the preview as a finger on that bed would; placeok / placecancel press the bar; placesecond:<label> shows its
		# middle key, placereason:<text> / placeconfirm:<verb> set its reason and main key; factap:<id> taps a sprinkler.
		"build": _facilities.begin_build(step[1] if step.size() > 1 else "craft_sprinkler")
		# a finger lifted there (release): a held one near a screen edge would keep panning the camera
		"placeat": rt.ui.placement_point.emit(cam.unproject_position(bp.cell_to_world(P0Garden.cell_of(int(step[1]))) + Vector3(0, P0Garden.BED_H, 0)), "release")
		"placeok": rt.ui.placement_done.emit(true)
		"placecancel": rt.ui.placement_done.emit(false)
		"placesecond": rt.ui.set_placement({"secondary": step[1] if step.size() > 1 else ""})   # the bar's middle key (Decorate's Rotate)
		"placereason": rt.ui.set_placement({"reason": step[1] if step.size() > 1 else ""})   # a refusal as Decorate's would read
		"placeconfirm": rt.ui.set_placement({"confirm": step[1]})
		# P1 Decorate (SGODOT-284): decor:<item> picks a piece from storage, decorate opens the mode with nothing picked,
		# decorat:<x>:<y> moves the preview to a cell as a finger would, decortap:<x>:<y> taps a cell in Decorate,
		# decorrot presses Rotate.
		"decor": rt.ui.decor_requested.emit(step[1] if step.size() > 1 else "deco_planter")
		"decorate": rt.ui.decor_requested.emit("")
		"decorat", "decortap":
			var at := cam.unproject_position(bp.cell_to_world(Vector2i(int(step[1]), int(step[2]))))
			if step[0] == "decorat":   # a finger put there and lifted (held, the edge pan would carry the camera on)
				rt.ui.placement_point.emit(at, "drag")
				rt.ui.placement_point.emit(at, "release")
			else:
				rt.ui.placement_point.emit(at, "press")
				rt.ui.placement_point.emit(at, "release")
		"decorrot": rt.ui.placement_secondary.emit()
		"factap":
			for f in rt.session.current().get("facilities", []):
				if int(f.get("id", 0)) == int(step[1]): _facilities.open_card(f)
		"binpick":   # binpick:<item> — the Compost Bin's drawer selects that crop (COMPOST-BIN shots)
			if rt.ui.compost_bin() != null: rt.ui.compost_bin().select(step[1])
		"bincompost":   # bincompost:<item>:<qty> — the drawer's Compost, sent as its buttons send it
			rt.session.send({"type": "compost", "item": step[1], "qty": int(step[2]) if step.size() > 2 else 1})
		"near":   # near:<id> — stand 1.2 m in front of a facility, so its name strip opens (250 review shots)
			for c in _card_candidates():
				if str(c[0]) == step[1]:
					actor.teleport((c[1] as Vector3) + Vector3(0, 0, 1.2))
					_focus = actor.position
		"tapprompt":   # tapprompt[:id] — a real tap on a shown world prompt (default: the open strip)
			var r := rt.ui.prompt_rect(step[1] if step.size() > 1 else _card)
			if r.has_area(): rt.ui._tap_at(r.get_center(), false)
		"moment":   # HOME-2 as after Lv2 → Lv3, without spending anything
			HomePanel.moment(rt.ui, P0Logic.home_moment(rt.session.current(), {"level": 3, "unlocks": ["warming_cabinet", "bag_upgrade_1"]}))
		"spot": p0_show_spot(step[1])
		_: return false
	return true

func p0_until(name: String) -> bool:
	match name:
		"idle": return not actor.busy()
	return false
