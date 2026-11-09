#!/usr/bin/env python3
"""Put the repo's launch screen into a Godot-exported Xcode project (q(290), SGODOT-302; idempotent).

The release project is exported once and reused (build_p0_ios.sh swaps only sensen.pck), so Godot's own storyboard
settings never reach it; this copies tools/ios/Launch Screen.storyboard — the splash's sky colour alone, #61BBFA, no
art — over sensen/Launch Screen.storyboard. The plist's UILaunchStoryboardName ("Launch Screen") and the
SplashImage asset stay as they are: the storyboard no longer reads that image. iOS keeps an installed app's launch
screen in a cache: a phone shows the new one after the app is reinstalled.
"""
import argparse
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
NAME = "Launch Screen.storyboard"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True, help="path to sensen.xcodeproj")
    args = parser.parse_args()
    project = args.project.resolve()
    target = project.parent / "sensen" / NAME
    if not target.exists():
        raise SystemExit(f"{target} not found: not a Godot-exported project with a launch storyboard")
    same = target.read_bytes() == (HERE / NAME).read_bytes()
    if not same:
        shutil.copyfile(HERE / NAME, target)
    print(f"{NAME}: {'up to date' if same else 'updated from the repo'} ({target})")


if __name__ == "__main__":
    main()
