extends SceneTree
## q(252) selling screens at 360 × 800 from the counter fixture with view.shops[role].distance added as the q(251)
## server sends it (亚瑟): Seattle's Tackle Shop away, the home Market with two things Mei takes, an away Market with
## one, the Homestead Stall, and an older server's Tackle Shop. A drawer on its own (no world, no server), each with a sell card open.
##   godot --path . --resolution 720x1600 -s tools/dev/p0_sell_price_shots.gd   (OUT=dir)

var out := OS.get_environment("OUT") if OS.has_environment("OUT") else "user://sell_shots"

const SEATTLE := {"home": false, "factor": 0.8, "km": 1093.4, "trip": 4, "band": "Long Haul"}
const LA := {"home": false, "factor": 0.8, "km": 559.2, "trip": 4, "band": "Long Haul"}
const HOME := {"home": true, "factor": 1}

func _initialize() -> void: _run.call_deferred()

func _view() -> Dictionary:
	var v: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/p0/fixtures/counter_view.json"))
	v.items.fish_rainbow_trout = {"name": "Rainbow Trout", "kind": "fish", "sell": 8, "cook": true, "family": "W", "rarity": 2}
	v.items.fish_arctic_char = {"name": "Arctic Char", "kind": "fish", "sell": 7, "cook": true, "family": "W", "rarity": 1}
	v.items.crop_pumpkin = {"name": "Pumpkin", "kind": "crop", "sell": 6, "cook": true, "family": "F", "rarity": 1}
	for id in ["fish_rainbow_trout", "fish_arctic_char", "crop_pumpkin"]: v.names[id] = v.items[id].name
	v.shops.homestead.distance = HOME
	v.shops.tackle.sell = [{"kind": "fish", "rate": 1, "quota": null}]
	v.shops.tackle.distance = HOME
	for e in v.shops.market.sell:
		e.rate = 1
		e.quota = null
	v.shops.market.distance = HOME
	v.quotas.erase("fish_tackle")
	v.quotas.erase("regional_market")
	return v

func _away(v: Dictionary, role: String, d: Dictionary) -> void:
	v.shops[role].distance = d
	for e in v.shops[role].sell: e.rate = float(d.factor)

func _shot(name: String, v: Dictionary, role: String, ctx: Dictionary, select: String) -> void:
	var top := CanvasLayer.new()
	root.add_child(top)
	var host := ColorRect.new()
	host.color = Color("9CC3B4")
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	top.add_child(host)
	var d := P0CounterDrawer.new(v, role, ctx, "buy")
	d.animate = false
	host.add_child(d)
	for i in 4: await process_frame
	d.grid.selected_id = select   # the cell as the finger leaves it
	d.select(select)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out)
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name, " · ", d._quota.text.replace("\n", " | "), " · ", d.keeper_bar.line if d.keeper_bar else "")
	top.queue_free()
	for i in 2: await process_frame

func _run() -> void:
	await process_frame
	var v := _view()
	_away(v, "tackle", SEATTLE)
	v.bag.slots = [{"id": "fish_rainbow_trout", "qty": 3}, {"id": "fish_crucian", "qty": 2}, {"id": "fish_carp", "qty": 2}, {"id": "crop_radish", "qty": 4}]
	await _shot("SGODOT-252-tackle-away-seattle", v, "tackle", {"keeper": "Ezra", "place": "Cedar Tackle Shop"}, "fish_rainbow_trout")
	v = _view()
	v.bag.slots = [{"id": "fish_arctic_char", "qty": 6}, {"id": "crop_pumpkin", "qty": 2}, {"id": "fish_crucian", "qty": 3}]
	await _shot("SGODOT-252-market-home-two", v, "market", {"keeper": "Mei", "place": "Mission Market Square"}, "fish_arctic_char")
	v = _view()
	_away(v, "market", LA)
	v.bag.slots = [{"id": "crop_pumpkin", "qty": 2}, {"id": "fish_crucian", "qty": 3}, {"id": "crop_radish", "qty": 4}]
	await _shot("SGODOT-252-market-away-one", v, "market", {"keeper": "Mei", "place": "Venice Market Square"}, "crop_pumpkin")
	v = _view()
	await _shot("SGODOT-252-homestead-home-price", v, "homestead", {}, "crop_radish")
	# an older server (the fixture as it is): quotas, no distance — the quota line as before, nothing breaks
	v = JSON.parse_string(FileAccess.get_file_as_string("res://tests/p0/fixtures/counter_view.json"))
	await _shot("SGODOT-252-tackle-older-server", v, "tackle", {"keeper": "Finn", "place": "Mission Tackle Shop"}, "fish_crucian")
	quit()
