#!/usr/bin/env python3
"""Prepare a Godot-exported iOS project for Xcode automatic signing.

Build and archive with Apple Development; Xcode selects distribution signing
when exporting with the generated app-store-connect options.
"""

import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess

# q(319) (user, bot 783): P0 never asks for location; the key is there only because the Mapbox binary references the
# foreground location APIs (inject_store_config.py writes the same sentence and its zh-Hans one).
LOCATION_USAGE = "Gensen doesn't ask for your location. The map component requires this description."
# Sentences an older copied project may still carry (Journey's, 0.2.23 and earlier; Gensen's, until q(319)): replaced
# like an empty one. Any other wording someone wrote there is kept.
RETIRED_LOCATION_USAGES = (
    "Your location helps Journey select a nearby city and center the map when you use location features.",
    "Your location helps Gensen select a nearby city and center the map when you use location features.",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--team", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--display-name", default="Journey")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Z0-9]{10}", args.team):
        parser.error("team must be a ten-character Apple Team ID")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_id):
        parser.error("invalid bundle identifier")
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("version must contain three numeric components")
    if not re.fullmatch(r"[1-9]\d{0,3}(?:\.\d{1,2}){0,2}", args.build):
        parser.error("build must use Apple's numeric CFBundleVersion format")

    project = args.project.resolve()
    pbxproj = project / "project.pbxproj"
    source = pbxproj.read_text()
    metadata = json.loads(subprocess.check_output(
        ["plutil", "-convert", "json", "-o", "-", str(pbxproj)]
    ))
    configurations = [obj for obj in metadata["objects"].values()
                      if obj.get("isa") == "XCBuildConfiguration"]
    if not configurations:
        raise SystemExit("No Xcode build configurations found")

    settings = {
        "CODE_SIGN_IDENTITY": "Apple Development",
        "CODE_SIGN_STYLE": "Automatic",
        "DEVELOPMENT_TEAM": args.team,
        "PRODUCT_BUNDLE_IDENTIFIER": args.bundle_id,
        "MARKETING_VERSION": args.version,
        "CURRENT_PROJECT_VERSION": args.build,
        "INFOPLIST_KEY_CFBundleDisplayName": args.display_name,
        "PROVISIONING_PROFILE": "",
        "PROVISIONING_PROFILE_SPECIFIER": "",
    }
    for key, value in settings.items():
        pattern = re.compile(r"(?m)^(\s*)" + re.escape(key) + r"\s*=\s*[^;]*;")
        source, count = pattern.subn(
            lambda match: match.group(1) + key + " = " + json.dumps(value) + ";",
            source,
        )
        if key not in {"PROVISIONING_PROFILE", "PROVISIONING_PROFILE_SPECIFIER"} and not count:
            raise SystemExit(f"Expected Godot export setting is missing: {key}")

    if source != pbxproj.read_text():
        pbxproj.write_text(source)

    removed_usage_keys = []
    added_usage_keys = []
    replaced_usage_keys = []
    for plist in project.parent.glob("*/*-Info.plist"):
        content = plistlib.loads(plist.read_bytes())
        # Mapbox references foreground CoreLocation APIs. Apple requires this
        # purpose string even while the Godot iOS location bridge is inactive.
        location_key = "NSLocationWhenInUseUsageDescription"
        location_added = not str(content.get(location_key, "")).strip()
        location_replaced = content.get(location_key) in RETIRED_LOCATION_USAGES
        if location_added or location_replaced:
            content[location_key] = LOCATION_USAGE
            (added_usage_keys if location_added else replaced_usage_keys).append(location_key)
        unused = [key for key, value in content.items()
                  if key.startswith("NS") and key.endswith("UsageDescription") and value == ""]
        for key in unused:
            del content[key]
            removed_usage_keys.append(key)
        if unused or location_added or location_replaced:
            plist.write_bytes(plistlib.dumps(content, sort_keys=False))

    options_path = project.parent / "ExportOptions-AppStore.plist"
    options = {
        "method": "app-store-connect",
        "destination": "export",
        "signingStyle": "automatic",
        "teamID": args.team,
        "manageAppVersionAndBuildNumber": False,
        "uploadSymbols": True,
    }
    options_path.write_bytes(plistlib.dumps(options, sort_keys=False))
    upload_options_path = project.parent / "ExportOptions-TestFlightUpload.plist"
    upload_options_path.write_bytes(plistlib.dumps(
        {**options, "destination": "upload"}, sort_keys=False
    ))
    print(json.dumps({"project": str(project), "team": args.team,
                      "bundle_id": args.bundle_id, "version": args.version,
                      "build": args.build, "removed_empty_usage_keys": removed_usage_keys,
                      "added_usage_keys": added_usage_keys, "replaced_usage_keys": replaced_usage_keys,
                      "export_options": str(options_path),
                      "upload_options": str(upload_options_path)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
