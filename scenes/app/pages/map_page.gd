extends AppPage
## 地图主页占位：B5 把 Mapbox 垫底 + 好友位置 + 3D 角色接进来。
## on_tab_shown / on_tab_hidden 就是将来 bridge.set_map_visible 的挂点。

func _init() -> void:
	page_title = "Map"

func _build_body() -> void:
	placeholder(tr("Map home lands in B5: Mapbox underlay, friends' positions and 3D avatars. This tab stays resident so the native map view can be shown/hidden instead of rebuilt."))
	var dress := GameUi.button("shirt", tr("Dressing room"), "avatar module (existing)")
	dress.name = "Dressing"
	dress.pressed.connect(AppRouter.go_to_dressing)
	body.add_child(dress)
