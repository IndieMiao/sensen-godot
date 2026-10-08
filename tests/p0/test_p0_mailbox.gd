extends GdUnitTestSuite
## The farmhouse Mailbox (SGODOT-234 C; §12.5.2, q(24), LOCK-14; WORLD-HINT-6a / 6b): a placeholder red post box by
## the farmhouse. Its icon button wears the small `Parcel` tag while parcels are in the list (the bell's rule), its
## strip says `Mailbox`, and tapping it opens the same Inbox as the bell.

const STORE := "user://test_p0_mailbox.json"

func _view(parcels := 2, free := 6, waiting := 0) -> Dictionary:
	var ps: Array = []
	for i in parcels: ps.append({"key": "p%d" % i, "id": "seed_carrot", "qty": 2, "source": "Welcome gift", "left": 3_900_000.0})
	return {"coins": 230, "energy": {"value": 142, "max": 210}, "bag": {"capacity": 25, "free": free, "slots": []},
		"inbox": {"limit": 8, "badge": ps.size(), "waiting": waiting, "claim_slots": mini(free, ps.size()), "parcels": ps, "updates": []}}

func before_test() -> void:
	UiCommandButton.offline = false   # a runtime left by an earlier suite may have gone offline (no server in tests)

func test_the_prompt_is_mailbox_and_wears_parcel_while_parcels_are_in_the_list() -> void:
	var p := P0WorldPrompts.mailbox(_view(2))
	assert_array([p.text, p.fact, p.count, p.status, p.dimmed]).is_equal(["Mailbox", "", "Parcel", -1, false])
	assert_str((p.icon as Texture2D).resource_path).is_equal("res://assets/p0/icons/mailbox.svg")   # i-mailbox 1822:104445
	assert_str(str(P0WorldPrompts.mailbox(_view(2, 0)).count)).is_equal("Parcel")     # a full bag still counts (q(79))
	assert_str(str(P0WorldPrompts.mailbox(_view(0, 6, 2)).count)).is_equal("")        # queued ones never
	assert_str(str(P0WorldPrompts.mailbox(_view(0)).count)).is_equal("")

func test_with_parcel_it_shows_from_anywhere_like_a_state_else_within_8_m() -> void:
	var tagged := P0WorldPrompts.mailbox(_view(2))
	var plain := P0WorldPrompts.mailbox(_view(0))
	assert_int(P0WorldPrompts.show("mailbox", "", 30.0, tagged)).is_equal(P0WorldPrompts.Show.ICON)
	assert_int(P0WorldPrompts.show("mailbox", "", 8.1, plain)).is_equal(P0WorldPrompts.Show.NONE)
	assert_int(P0WorldPrompts.show("mailbox", "", 7.9, plain)).is_equal(P0WorldPrompts.Show.ICON)
	assert_int(P0WorldPrompts.show("mailbox", "mailbox", 1.0, tagged)).is_equal(P0WorldPrompts.Show.BAR)

func test_it_stands_by_the_farmhouse_on_a_free_cell_and_blocks_it() -> void:
	var bp := P0Garden.blueprint()
	var c := P0Garden.MAILBOX_CELL
	assert_bool(bp.is_walkable(c)).is_true()   # nothing else stands there: no facility, plot or path cell taken
	assert_int(P0Garden.id_of(c)).is_equal(-1)
	var at := P0Garden.mailbox_point(bp)
	for other in [P0Garden.sign_point(bp), bp.cell_to_world(bp.anchor("storage")), bp.cell_to_world(bp.anchor("bench"))]:
		assert_float(at.distance_to(other)).is_greater(1.4)   # its own tap target, clear of the sign and the stall
	for p in P0Garden.fence_block_points(bp): assert_bool(bp.world_to_cell(p) == c).is_false()
	P0Garden.block_points(bp, [at])
	assert_bool(bp.is_walkable(c)).is_false()
	var grid := BlueprintGrid.new(bp)
	assert_bool(grid.path(bp.anchor("spawn"), c + Vector2i(0, -1)).is_empty()).is_false()   # reachable from the front

## The real farm scene without its _ready: the tap through the Mailbox's button or strip (by id) opens the Inbox.
func test_tapping_the_mailbox_opens_the_inbox() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, _p, _b, _c): pass
	add_child(rt)
	await get_tree().process_frame
	rt.ui.set_view(_view(2))
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_farm.gd\"\nfunc _ready() -> void: pass\nfunc _exit_tree() -> void: pass\nfunc _process(_d) -> void: pass\n"
	stub.reload()
	var farm: Node3D = load("res://scenes/p0/p0_farm.tscn").instantiate()
	farm.set_script(stub)
	add_child(farm)
	auto_free(farm)
	farm.rt = rt
	farm.bp = P0Garden.blueprint()
	farm.actor = P0Actor.new()
	farm.add_child(farm.actor)
	farm.actor.setup(farm.bp, BlueprintGrid.new(farm.bp), farm.cam)
	farm._mailbox = P0Garden.mailbox_point(farm.bp)
	assert_bool(farm._tap_card("mailbox")).is_true()
	assert_str(rt.ui.modal_kind).is_equal("inbox")
	assert_str(rt.ui.inbox().tab).is_equal("parcels")
	rt.ui.close_modal()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
