"""Pinned SGODOT-324 input snapshot; never modifies its branch or source assets."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "output/hotel-lobby-319/deps"
COMMIT = "104446a2a995c8a0269d12d27308b3d547b29f6e"
FILES = ["tools/art/source/hallkit_324/hallkit_324.blend"] + [
    "assets/rooms/_shared/shell_hall/" + name for name in [
        "armchair.glb", "round_side_table.glb", "frame_landscape.glb", "hallkit_palette.png", "palette.json", "asset_stats.json",
        "provenance/armchair/reuse_provenance.json", "provenance/round_side_table/reuse_provenance.json", "provenance/frame_landscape/reuse_provenance.json"]]


def main():
    manifest = {"source_commit": COMMIT, "source_pr": 563, "files": []}
    for rel in FILES:
        data = subprocess.check_output(["git", "show", COMMIT + ":" + rel], cwd=ROOT)
        path = DEST / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        manifest["files"].append({"path": rel, "sha256": hashlib.sha256(data).hexdigest()})
    (DEST / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("PINNED_HALLKIT_324", COMMIT, len(FILES))
    if "--project" in sys.argv:
        project = ROOT / "output/hotel-lobby-319/project"
        for rel in ["assets/rooms/poi_hotel_lobby", "assets/rooms/_shared/shell_hall", "assets/rooms/_shared/plants", "assets/rooms/_shared/fx",
                    "scenes/shell_hall", "scenes/poi_hotel_lobby"]:
            shutil.copytree(ROOT / rel, project / rel, dirs_exist_ok=True,
                ignore=shutil.ignore_patterns("source", "*.blend", "*.jpg"))
        shutil.copy2(ROOT / "tools/art/review_hotel_lobby_319.gd", project / "review.gd")
        shutil.copy2(ROOT / "output/hotel-lobby-319/plan/godot-navigation.json", project / "navigation.json")
        if (ROOT / "output/hotel-lobby-319/native-camera.json").exists():
            shutil.copy2(ROOT / "output/hotel-lobby-319/native-camera.json", project / "native-camera.json")
        elif (ROOT / "docs/design/poi-hotel-lobby-319-2026-10-31/native-camera-n1-v1.1.json").exists():
            shutil.copy2(ROOT / "docs/design/poi-hotel-lobby-319-2026-10-31/native-camera-n1-v1.1.json", project / "native-camera.json")
        elif (ROOT / "docs/design/poi-hotel-lobby-319-2026-10-31/native-camera-n1-v1.json").exists():
            shutil.copy2(ROOT / "docs/design/poi-hotel-lobby-319-2026-10-31/native-camera-n1-v1.json", project / "native-camera.json")
        (project / "project.godot").write_text('''config_version=5
[application]
config/name="SensenHotel319QA"
run/main_scene="res://review.tscn"
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenHotel319QA"
[display]
window/size/viewport_width=900
window/size/viewport_height=900
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
lights_and_shadows/directional_shadow/size=4096
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
''')
        (project / "review.tscn").write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://review.gd" id="1"]
[node name="Hotel319Review" type="Node"]
script=ExtResource("1")
''')
        print("STAGED", project)
        if "--import" in sys.argv:
            assert os.environ.get("ANDROID_ADB_SERVER_PORT") == "5099"
            subprocess.run(["godot", "--headless", "--path", str(project), "--editor", "--import"], check=True)
            subprocess.run(["godot", "--headless", "--path", str(project), "--script",
                str(ROOT / "tools/art/verify_hotel_imports_319.gd"), "--",
                str(ROOT / "output/hotel-lobby-319/import-validation.json")], check=True)
            for file in (project / "assets/rooms/poi_hotel_lobby").glob("*.import"):
                shutil.copy2(file, ROOT / "assets/rooms/poi_hotel_lobby" / file.name)
            print("SYNCED_N1_IMPORT_UIDS")


if __name__ == "__main__": main()
