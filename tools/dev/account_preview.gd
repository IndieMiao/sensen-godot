extends Node
## 账号与选城界面的桌面截图（SGODOT-135 / 137）。不联网：用 SENSEN_OFFLINE=1 启动。
##
##   ACCOUNT_SHOTS=/tmp/out SENSEN_OFFLINE=1 SENSEN_LANGUAGE=zh_CN godot --path . --resolution 360x800 \
##     tools/dev/ui_preview.tscn -- res://tools/dev/account_preview.tscn notch
##
## 挂在 ui_preview 下面，由它注入手机安全区。
##
## 依次渲染：选城页（含 IP 建议卡、搜索结果）、登录、注册（登录墙文案）、找回密码、验证邮箱、我的账号。

const TOKYO := {"id": "gn-1850147", "name": "Tokyo", "country": "Japan", "center": [35.6895, 139.69171], "radius_km": 45,
	"placement_bounds": [35.2853, 139.1953, 36.0937, 140.1881], "timezone": "Asia/Tokyo", "farm_count": 3}

func _ready() -> void:
	var out := OS.get_environment("ACCOUNT_SHOTS") if OS.has_environment("ACCOUNT_SHOTS") else "/tmp/account_preview"
	DirAccess.make_dir_recursive_absolute(out)
	var city: Control = (load("res://scenes/city_select/city_select.tscn") as PackedScene).instantiate()
	add_child(city)
	await _frames(4)
	city.show_suggestion(TOKYO)
	city._show_popular([{"id": "shanghai", "name": "Shanghai", "curated": true, "farm_count": 12},
		{"id": "los_angeles", "name": "Los Angeles", "curated": true, "farm_count": 7}, TOKYO,
		{"id": "gn-2643743", "name": "London", "country": "United Kingdom", "farm_count": 1}])
	await _shot(out + "/city_select.png")
	city.find_child("Search", true, false).text = "lond"
	city.show_results([{"id": "gn-2643743", "name": "London", "country": "United Kingdom"},
		{"id": "gn-6058560", "name": "London", "country": "Canada", "admin": "Ontario"},
		{"id": "gn-4298960", "name": "London", "country": "United States", "admin": "Kentucky"}])
	await _shot(out + "/city_search.png")
	for spec in [["sign_in", ""], ["sign_up", "Sign in to create your farm."], ["forgot", ""], ["verify", ""], ["account", ""]]:
		if spec[0] in ["verify", "account"]:
			Net.account.token = "preview"
			Net.account.user_id = "preview"
			Net.account.email = "ada@example.com"
		var panel := AccountPanel.open(self, spec[0], L10n.text(spec[1]) if not spec[1].is_empty() else "")
		await _frames(2)
		if spec[0] == "sign_in": (panel.find_child("Email", true, false) as LineEdit).text = "ada@example.com"
		await _shot("%s/account_%s.png" % [out, spec[0]])
		panel.queue_free()
		await _frames(1)
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _shot(path: String) -> void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("account_preview: ", path)
