#!/usr/bin/env python3
"""Bring a Godot-exported Xcode project's native files up to the repo's, and add LocalNotify (idempotent).

Run before every archive (SGODOT-356): the release project is exported and injected once, then reused, so the
native files it holds go stale when the repo's change (0.2.15 (1) shipped a MapUnderlay.swift without q(133) v3's
TELEM and hidden ornaments). This copies G3Spike.mm, MapUnderlay.swift, AppleSignIn.swift and LocalNotify.swift next
to the app sources and registers LocalNotify.swift in the Sources phase. Local notifications need no entitlement.
SGODOT-487: also GoogleSignInIOS.swift (Sign in with Google through the system's web sheet; no entitlement, no URL type).
Needs a project that already has MapUnderlay and AppleSignIn (setup_ios_g3.sh, then inject_apple_sign_in.py).
"""
import argparse
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
FILES = ["G3Spike.mm", "MapUnderlay.swift", "AppleSignIn.swift", "LocalNotify.swift", "GoogleSignInIOS.swift"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True, help="path to sensen.xcodeproj")
    args = parser.parse_args()
    project = args.project.resolve()
    app_dir = project.parent / "sensen"

    pbxproj = project / "project.pbxproj"
    t = pbxproj.read_text()
    if "LocalNotify.swift" not in t:
        anchors = {
            "build": "\t\tAA00000000000000000000B6 /* AppleSignIn.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA00000000000000000000B5 /* AppleSignIn.swift */; };",
            "ref": "\t\tAA00000000000000000000B5 /* AppleSignIn.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppleSignIn.swift; sourceTree = \"<group>\"; };",
            "group": "\t\t\t\tAA00000000000000000000B5 /* AppleSignIn.swift */,",
            "phase": "\t\t\t\tAA00000000000000000000B6 /* AppleSignIn.swift in Sources */,",
        }
        missing = [k for k, a in anchors.items() if a not in t]
        if missing:
            raise SystemExit(f"AppleSignIn injection not found ({', '.join(missing)}); run inject_apple_sign_in.py first")
        t = t.replace(anchors["build"], anchors["build"] +
            "\n\t\tAA00000000000000000000B8 /* LocalNotify.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA00000000000000000000B7 /* LocalNotify.swift */; };", 1)
        t = t.replace(anchors["ref"], anchors["ref"] +
            "\n\t\tAA00000000000000000000B7 /* LocalNotify.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LocalNotify.swift; sourceTree = \"<group>\"; };", 1)
        t = t.replace(anchors["group"], anchors["group"] + "\n\t\t\t\tAA00000000000000000000B7 /* LocalNotify.swift */,", 1)
        t = t.replace(anchors["phase"], anchors["phase"] + "\n\t\t\t\tAA00000000000000000000B8 /* LocalNotify.swift in Sources */,", 1)
        pbxproj.write_text(t)
    if "GoogleSignInIOS.swift" not in t:
        after = {
            "build": "\t\tAA00000000000000000000B8 /* LocalNotify.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA00000000000000000000B7 /* LocalNotify.swift */; };",
            "ref": "\t\tAA00000000000000000000B7 /* LocalNotify.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LocalNotify.swift; sourceTree = \"<group>\"; };",
            "group": "\t\t\t\tAA00000000000000000000B7 /* LocalNotify.swift */,",
            "phase": "\t\t\t\tAA00000000000000000000B8 /* LocalNotify.swift in Sources */,",
        }
        missing = [k for k, a in after.items() if a not in t]
        if missing:
            raise SystemExit(f"LocalNotify registration not found ({', '.join(missing)})")
        t = t.replace(after["build"], after["build"] +
            "\n\t\tAA00000000000000000000BA /* GoogleSignInIOS.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA00000000000000000000B9 /* GoogleSignInIOS.swift */; };", 1)
        t = t.replace(after["ref"], after["ref"] +
            "\n\t\tAA00000000000000000000B9 /* GoogleSignInIOS.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GoogleSignInIOS.swift; sourceTree = \"<group>\"; };", 1)
        t = t.replace(after["group"], after["group"] + "\n\t\t\t\tAA00000000000000000000B9 /* GoogleSignInIOS.swift */,", 1)
        t = t.replace(after["phase"], after["phase"] + "\n\t\t\t\tAA00000000000000000000BA /* GoogleSignInIOS.swift in Sources */,", 1)
        pbxproj.write_text(t)

    for name in FILES:
        same = (app_dir / name).exists() and (app_dir / name).read_bytes() == (HERE / name).read_bytes()
        if not same:
            shutil.copyfile(HERE / name, app_dir / name)
        print(f"{name}: {'up to date' if same else 'copied from the repo'}")
    print(f"LocalNotify injected into {project}")


if __name__ == "__main__":
    main()
