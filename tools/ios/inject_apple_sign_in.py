#!/usr/bin/env python3
"""Add Sign in with Apple to a Godot-exported Xcode project (idempotent).

Copies AppleSignIn.swift next to the app sources, registers it in the Sources
phase and adds the com.apple.developer.applesignin entitlement. Automatic
signing with -allowProvisioningUpdates then enables the capability on the App ID.
Run after setup_ios_g3.sh has injected G3Spike.mm (which bootstraps the class).
"""
import argparse
from pathlib import Path
import plistlib
import shutil

HERE = Path(__file__).resolve().parent
ENTITLEMENT = "com.apple.developer.applesignin"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True, help="path to sensen.xcodeproj")
    args = parser.parse_args()
    project = args.project.resolve()
    app_dir = project.parent / "sensen"
    shutil.copyfile(HERE / "AppleSignIn.swift", app_dir / "AppleSignIn.swift")

    pbxproj = project / "project.pbxproj"
    t = pbxproj.read_text()
    if "AppleSignIn.swift" not in t:
        anchors = {
            "build": "\t\tAA00000000000000000000B4 /* MapUnderlay.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA00000000000000000000B3 /* MapUnderlay.swift */; };",
            "ref": "\t\tAA00000000000000000000B3 /* MapUnderlay.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MapUnderlay.swift; sourceTree = \"<group>\"; };",
            "group": "\t\t\t\tAA00000000000000000000B3 /* MapUnderlay.swift */,",
            "phase": "\t\t\t\tAA00000000000000000000B4 /* MapUnderlay.swift in Sources */,",
        }
        missing = [k for k, a in anchors.items() if a not in t]
        if missing:
            raise SystemExit(f"MapUnderlay injection not found ({', '.join(missing)}); run setup_ios_g3.sh first")
        t = t.replace(anchors["build"], anchors["build"] +
            "\n\t\tAA00000000000000000000B6 /* AppleSignIn.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA00000000000000000000B5 /* AppleSignIn.swift */; };", 1)
        t = t.replace(anchors["ref"], anchors["ref"] +
            "\n\t\tAA00000000000000000000B5 /* AppleSignIn.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppleSignIn.swift; sourceTree = \"<group>\"; };", 1)
        t = t.replace(anchors["group"], anchors["group"] + "\n\t\t\t\tAA00000000000000000000B5 /* AppleSignIn.swift */,", 1)
        t = t.replace(anchors["phase"], anchors["phase"] + "\n\t\t\t\tAA00000000000000000000B6 /* AppleSignIn.swift in Sources */,", 1)
        pbxproj.write_text(t)

    entitlements = app_dir / "sensen.entitlements"
    content = plistlib.loads(entitlements.read_bytes()) if entitlements.exists() else {}
    if content.get(ENTITLEMENT) != ["Default"]:
        content[ENTITLEMENT] = ["Default"]
        entitlements.write_bytes(plistlib.dumps(content, sort_keys=False))
    if "CODE_SIGN_ENTITLEMENTS" not in t:
        raise SystemExit("project has no CODE_SIGN_ENTITLEMENTS; the entitlement would be ignored")
    print(f"Sign in with Apple injected into {project}")


if __name__ == "__main__":
    main()
