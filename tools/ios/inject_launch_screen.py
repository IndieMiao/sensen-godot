#!/usr/bin/env python3
"""Put the repo's launch screen into a Godot-exported Xcode project (q(290) SGODOT-302, SGODOT-420; idempotent).

The release project is exported once and reused (build_p0_ios.sh swaps only sensen.pck), so Godot's own storyboard
settings never reach it; this copies tools/ios/Launch Screen.storyboard — the launch splash the screen's height,
centred, on the art's sky colour #61BBFA (420) — over sensen/Launch Screen.storyboard, and the splash itself
(assets/p0/ui/launch_splash.png, the boot splash's image too) into Images.xcassets/SplashImage.imageset, the asset the
storyboard reads. The plist's UILaunchStoryboardName ("Launch Screen") stays as it is. iOS keeps an installed app's
launch screen in a cache: a phone may show the old one until the app is reinstalled or the phone restarts.
"""
import argparse
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
NAME = "Launch Screen.storyboard"
SPLASH = HERE.parent.parent / "assets" / "p0" / "ui" / "launch_splash.png"
IMAGE = "launch_splash.png"
CONTENTS = {
    "images": [
        {"filename": IMAGE, "idiom": "universal", "scale": "1x"},
        {"idiom": "universal", "scale": "2x"},
        {"idiom": "universal", "scale": "3x"},
    ],
    "info": {"author": "xcode", "version": 1},
}


def _write(path: Path, data: bytes) -> bool:
    if path.exists() and path.read_bytes() == data:
        return False
    path.write_bytes(data)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True, help="path to sensen.xcodeproj")
    args = parser.parse_args()
    project = args.project.resolve()
    target = project.parent / "sensen" / NAME
    if not target.exists():
        raise SystemExit(f"{target} not found: not a Godot-exported project with a launch storyboard")
    imageset = project.parent / "sensen" / "Images.xcassets" / "SplashImage.imageset"
    if not imageset.is_dir():
        raise SystemExit(f"{imageset} not found: not a Godot-exported project with a splash image")
    changed = _write(target, (HERE / NAME).read_bytes())
    for old in imageset.glob("*.png"):   # Godot's own splash@2x / @3x
        if old.name != IMAGE:
            old.unlink()
            changed = True
    changed |= _write(imageset / IMAGE, SPLASH.read_bytes())
    changed |= _write(imageset / "Contents.json", (json.dumps(CONTENTS, indent=2) + "\n").encode())
    print(f"{NAME} + SplashImage: {'updated from the repo' if changed else 'up to date'} ({target.parent})")


if __name__ == "__main__":
    main()
