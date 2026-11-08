#!/usr/bin/env python3
"""Put the repo's app icon into a Godot-exported Xcode project (SGODOT-66; idempotent).

The release project is exported once and reused (build_p0_ios.sh swaps only sensen.pck), so its AppIcon came from
icon.svg (a plain green square). This writes every file the project's Images.xcassets/AppIcon.appiconset/Contents.json
names, at its pixel size, from tools/app_icon/ios/icon_1024.png (上官婉儿's icon 3, the pin and the island; the user
11-08 20:09) with sips. App Store Connect refuses an icon with an alpha channel, opaque or not: each file is checked.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
MASTER = HERE.parent / "app_icon" / "ios" / "icon_1024.png"


def _pixels(image: dict) -> int:
    side = float(image["size"].split("x")[0])
    return round(side * float(image.get("scale", "1x").rstrip("x")))


def _has_alpha(path: Path) -> bool:
    out = subprocess.run(["sips", "-g", "hasAlpha", str(path)], check=True, capture_output=True, text=True).stdout
    return "hasAlpha: yes" in out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True, help="path to sensen.xcodeproj")
    args = parser.parse_args()
    iconset = args.project.resolve().parent / "sensen" / "Images.xcassets" / "AppIcon.appiconset"
    if not (iconset / "Contents.json").exists():
        raise SystemExit(f"{iconset} not found: not a Godot-exported project with an app icon")
    if _has_alpha(MASTER):
        raise SystemExit(f"{MASTER} has an alpha channel: App Store Connect refuses it")
    images = [i for i in json.loads((iconset / "Contents.json").read_text())["images"] if i.get("filename")]
    changed = []
    with tempfile.TemporaryDirectory() as tmp:
        for image in images:
            px = _pixels(image)
            out = Path(tmp) / image["filename"]
            subprocess.run(["sips", "-z", str(px), str(px), str(MASTER), "--out", str(out)], check=True,
                           capture_output=True)
            if _has_alpha(out):
                raise SystemExit(f"{out.name} came out with an alpha channel")
            target = iconset / image["filename"]
            if not target.exists() or target.read_bytes() != out.read_bytes():
                target.write_bytes(out.read_bytes())
                changed.append(f"{image['filename']} ({px})")
    print(f"AppIcon: {len(images)} files, {'updated ' + ', '.join(changed) if changed else 'up to date'} ({iconset})")


if __name__ == "__main__":
    main()
