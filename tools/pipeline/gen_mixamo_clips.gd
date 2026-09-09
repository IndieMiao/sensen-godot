## 用法:
##   godot --headless --path . --script res://tools/pipeline/gen_mixamo_clips.gd \
##       [-- --manifest=res://assets/avatar/source/mixamo/clips.json] [--out=res://assets/avatar/base/animations.res] [--no-register]
## 读清单，把 Mixamo 源动画重定向到 base_rig 骨架，写进动画库；默认顺手把新 clip 登记进
## anim_placeholders.json 的 real_clips。源 FBX/GLB 放进工程后要先跑一次 `godot --headless --import`。
## gen_base_rig.gd 全量重生成时也会跑同一步，所以单独跑本脚本只是为了快（不重建骨架与 idle/walk/run）。
##
## 清单格式见 assets/avatar/source/mixamo/README.md 与 clips.example.json。
extends SceneTree

func _initialize() -> void:
	var manifest_path := MixamoRetarget.DEFAULT_MANIFEST
	var out_path := MixamoRetarget.DEFAULT_OUT
	var register := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--manifest="):
			manifest_path = a.trim_prefix("--manifest=")
		elif a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
		elif a == "--no-register":
			register = false
	quit(MixamoRetarget.build_from_manifest(manifest_path, out_path, register))
