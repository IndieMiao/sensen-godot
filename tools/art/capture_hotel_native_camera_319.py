"""Temporarily stage only new art resources in the private farm-dev worktree, then restore."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
QA = ROOT / "output/hotel-lobby-319"
STAGED = QA / "project"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", required=True)
    args = parser.parse_args()
    runtime = Path(args.runtime).resolve()
    assert os.environ.get("ANDROID_ADB_SERVER_PORT") == "5099"
    baseline = subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], cwd=runtime)
    assert not baseline, "Runtime tracked files must start clean"
    paths = ["assets/rooms/poi_hotel_lobby", "assets/rooms/_shared/shell_hall", "scenes/shell_hall", "scenes/poi_hotel_lobby"]
    assert all(not (runtime / rel).exists() for rel in paths), "Do not overwrite any pre-existing runtime art directory"
    cache_backup = {}
    created = []
    process = None
    try:
        for rel in paths:
            shutil.copytree(STAGED / rel, runtime / rel)
            created.append(runtime / rel)
            for source in (STAGED / rel).rglob("*"):
                if source.suffix not in [".glb", ".png"]: continue
                asset = "res://" + str(source.relative_to(STAGED))
                prefix = source.name + "-" + hashlib.md5(asset.encode()).hexdigest()
                for imported in (STAGED / ".godot/imported").glob(prefix + "*"):
                    dest = runtime / ".godot/imported" / imported.name
                    cache_backup[dest] = dest.read_bytes() if dest.exists() else None
                    shutil.copy2(imported, dest)
        with (QA / "native-camera.log").open("w") as log:
            process = subprocess.Popen(["godot", "--headless", "--path", str(runtime), "--script",
                str(ROOT / "tools/art/probe_hotel_camera_319.gd"), "--", str(QA / "native-camera.json")],
                stdout=log, stderr=subprocess.STDOUT)
            (QA / "native-camera.pid").write_text(str(process.pid) + "\n")
            result = process.wait(timeout=90)
            if result: raise RuntimeError(f"Native camera probe returned {result}")
            assert "SCRIPT ERROR" not in (QA / "native-camera.log").read_text()
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait()
        for path in created: shutil.rmtree(path)
        for path, data in cache_backup.items():
            if data is None: path.unlink(missing_ok=True)
            else: path.write_bytes(data)
        after = subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], cwd=runtime)
        assert after == baseline
        (QA / "native-camera-restoration.json").write_text(json.dumps({"tracked_state_unchanged": True,
            "temporary_art_directories_removed": [str(p) for p in created], "process_stopped": process is None or process.poll() is not None}, indent=2) + "\n")
    info = json.loads((QA / "native-camera.json").read_text())
    info["runtime_commit"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=runtime, text=True).strip()
    info["native_room_sha256"] = hashlib.sha256((runtime / "scenes/p0/rooms/p0_room.gd").read_bytes()).hexdigest()
    (QA / "native-camera.json").write_text(json.dumps(info, indent=2) + "\n")
    print("NATIVE_P0_CAMERA", info["width_m"], info["pitch"], "spawn_delta", info["spawn_snap_distance_m"])


if __name__ == "__main__": main()
