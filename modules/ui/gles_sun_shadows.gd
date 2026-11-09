extends Node
## Under the Compatibility renderer (OpenGL ES: phones and emulators without Vulkan) no sun — no DirectionalLight3D —
## casts a shadow (SGODOT-456, the user 11-09:「1. gles关闭阴影」). There a shadowed sun is drawn as a pass of its own and
## each pass is encoded to sRGB before they add up: sRGB(ambient) + sRGB(sun) where Mobile has sRGB(ambient + sun), so
## whatever the sun lit came out paler and yellower (周瑜 on 456: Godot 4.7.2 scene.glsl; 亚瑟 on 456: with the sun's
## shadow off the cathedral, farm and market match Metal). A sun without a shadow is lit in the base pass. The players'
## blob shadows are meshes and stay. Every other renderer: nothing changes.

var active := RenderingServer.get_current_rendering_method() == "gl_compatibility"

func _ready() -> void:
	if active: get_tree().node_added.connect(_on_node_added)

func _on_node_added(n: Node) -> void:
	if n is DirectionalLight3D:
		_off(n)
		_off.call_deferred(n)   # a sun its owner switches on just after adding it, in the same frame

func _off(light: DirectionalLight3D) -> void:
	if is_instance_valid(light): light.shadow_enabled = false
