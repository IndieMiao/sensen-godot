#!/usr/bin/env python3
"""Bring the copied Xcode project up to what the App Store submission needs (idempotent; tech-plan-yase §4).

The release project is copied from build/ios-release and only patched, never re-exported, so what export_presets.cfg
says about Info.plist never reaches it (compliance audit A4 / A10 / A12 / A16). This patches, every pack:
  - PrivacyInfo.xcprivacy: the UserDefaults required-reason API (CA92.1: the app's own defaults; MapUnderlay.swift uses
    UserDefaults), kept beside the reasons already there; the data types the game itself collects, as the App Privacy
    answers in App Store Connect (李白 store-forms-1113.md §2, 奕星 ◆A / ◆B; Mapbox's own are in Mapbox's manifest);
    NSPrivacyTracking false, no tracking domains.
  - Info.plist: the location purpose string as q(319) (user, bot 783: P0 never asks for location; the key stays only
    because the Mapbox binary references foreground location APIs, without it the upload is refused, ITMS-90683),
    CFBundleLocalizations en + zh-Hans, ITSAppUsesNonExemptEncryption false.
  - zh-Hans.lproj/InfoPlist.strings with the Chinese purpose string, in the project's InfoPlist.strings variant group,
    and zh-Hans in knownRegions: the system shows the phone's language.
  - TARGETED_DEVICE_FAMILY = 1: iPhone only (audit A10: declaring iPad asks for iPad screenshots and review on iPad).
The microphone purpose string comes with iOS voice (SGODOT-387), when the app first asks for the microphone.
"""
import argparse
from pathlib import Path
import plistlib
import re

LOCATION_USAGE = "Gensen doesn't ask for your location. The map component requires this description."
LOCATION_USAGE_ZH = "Gensen 不会获取你的位置。这句说明是地图组件要求写的。"
USER_DEFAULTS = "NSPrivacyAccessedAPICategoryUserDefaults"
USER_DEFAULTS_REASON = "CA92.1"
_FN = "NSPrivacyCollectedDataTypePurposeAppFunctionality"
_AN = "NSPrivacyCollectedDataTypePurposeAnalytics"
# (type, linked to the player, purposes); tracking is false for all. Change only with the ASC answers.
COLLECTED = [
    ("CoarseLocation", True, [_FN]),        # the home city (and the city guessed from the address)
    ("PreciseLocation", True, [_FN]),       # the farm's spot the player pins on the map (◆A: both stores report it)
    ("UserID", True, [_FN]),                # the player id, the Apple / Google account number, the screen name
    ("GameplayContent", True, [_FN]),       # the save
    ("ProductInteraction", True, [_FN, _AN]),   # the command / UI log; reports (reasons picked from a list)
    ("PerformanceData", True, [_FN, _AN]),  # scene load times, device model / GPU
    ("OtherDiagnosticData", False, [_FN]),  # client_error: script errors, no player id, no IP (◆B: not CrashData)
    ("OtherDataTypes", True, [_FN]),        # the age check's pass / fail and the terms consent record
]


def collected_types() -> list:
    return [{"NSPrivacyCollectedDataType": "NSPrivacyCollectedDataType" + t, "NSPrivacyCollectedDataTypeLinked": linked,
             "NSPrivacyCollectedDataTypeTracking": False, "NSPrivacyCollectedDataTypePurposes": purposes}
            for t, linked, purposes in COLLECTED]


ZH_REF = "AA00000000000000000000BB"
EN_CHILD = "\t\t\t\tD0BCFE4518AEBDA2004A7AAE /* en */,"
EN_REF = ("\t\tD0BCFE4518AEBDA2004A7AAE /* en */ = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; "
          "name = en; path = en.lproj/InfoPlist.strings; sourceTree = \"<group>\"; };")


def privacy_manifest(path: Path) -> str:
    content = plistlib.loads(path.read_bytes())
    done = []
    apis = content.setdefault("NSPrivacyAccessedAPITypes", [])
    entry = next((a for a in apis if a.get("NSPrivacyAccessedAPIType") == USER_DEFAULTS), None)
    if entry is None:
        apis.append({"NSPrivacyAccessedAPIType": USER_DEFAULTS, "NSPrivacyAccessedAPITypeReasons": [USER_DEFAULTS_REASON]})
        done.append("UserDefaults (CA92.1)")
    elif USER_DEFAULTS_REASON not in entry.setdefault("NSPrivacyAccessedAPITypeReasons", []):
        entry["NSPrivacyAccessedAPITypeReasons"].append(USER_DEFAULTS_REASON)
        done.append("UserDefaults (CA92.1)")
    for key, value in (("NSPrivacyCollectedDataTypes", collected_types()), ("NSPrivacyTracking", False),
                       ("NSPrivacyTrackingDomains", [])):
        if content.get(key) != value:
            content[key] = value
            done.append(key)
    if not done:
        return "up to date"
    path.write_bytes(plistlib.dumps(content, sort_keys=False))
    return "set " + ", ".join(done)


def info_plist(path: Path) -> str:
    content = plistlib.loads(path.read_bytes())
    want = {"NSLocationWhenInUseUsageDescription": LOCATION_USAGE, "CFBundleLocalizations": ["en", "zh-Hans"],
            "ITSAppUsesNonExemptEncryption": False}
    changed = [k for k, v in want.items() if content.get(k) != v]
    if not changed:
        return "up to date"
    content.update(want)
    path.write_bytes(plistlib.dumps(content, sort_keys=False))
    return "set " + ", ".join(changed)


def zh_strings(app_dir: Path) -> str:
    target = app_dir / "zh-Hans.lproj" / "InfoPlist.strings"
    text = '/* Localized versions of Info.plist keys (zh-Hans, q(319)) */\n"NSLocationWhenInUseUsageDescription" = "%s";\n' % LOCATION_USAGE_ZH
    if target.exists() and target.read_text(encoding="utf-8") == text:
        return "up to date"
    target.parent.mkdir(exist_ok=True)
    target.write_text(text, encoding="utf-8")
    return "written"


ZH_PATH = "zh-Hans.lproj/InfoPlist.strings"
KNOWN_REGIONS = re.compile(r"knownRegions = \(([^)]*)\);")
DEVICE_FAMILY = re.compile(r"TARGETED_DEVICE_FAMILY = [^;]*;")


def pbxproj(path: Path) -> str:
    t = path.read_text()
    before = t
    if ZH_REF not in t and ZH_PATH not in t:   # the zh-Hans strings once, whatever id an earlier copy gave them
        for anchor in (EN_REF, EN_CHILD):
            if anchor not in t:
                raise SystemExit("InfoPlist.strings variant group (en) not found in the project")
        t = t.replace(EN_REF, EN_REF + f"\n\t\t{ZH_REF} /* zh-Hans */ = {{isa = PBXFileReference; lastKnownFileType = "
                      f"text.plist.strings; name = zh-Hans; path = {ZH_PATH}; sourceTree = \"<group>\"; }};", 1)
        t = t.replace(EN_CHILD, EN_CHILD + f"\n\t\t\t\t{ZH_REF} /* zh-Hans */,", 1)

    def regions(m):   # one entry a line (Xcode's) or all on one line
        body = m.group(1)
        if "zh-Hans" in body:
            return m.group(0)
        if "\n" in body:
            indent = re.search(r"\n(\t+)\S", body)
            return "knownRegions = (" + body.rstrip("\t") + (indent.group(1) if indent else "\t\t\t\t") + '"zh-Hans",\n' + \
                body[len(body.rstrip("\t")):] + ");"
        return "knownRegions = (" + body.rstrip().rstrip(",") + ', "zh-Hans", );'
    t = KNOWN_REGIONS.sub(regions, t, count=1)
    t = DEVICE_FAMILY.sub("TARGETED_DEVICE_FAMILY = 1;", t)   # "1,2", 1,2, 2 …: iPhone only

    # 周瑜 on #1016: what could not be patched stops the pack rather than passing unchanged
    problems = []
    region = KNOWN_REGIONS.search(t)
    if not region or "zh-Hans" not in region.group(1):
        problems.append("zh-Hans not in knownRegions")
    if t.count(ZH_PATH) != 1:
        problems.append(f"{ZH_PATH} referenced {t.count(ZH_PATH)} times")
    families = DEVICE_FAMILY.findall(t)
    if not families or any(f != "TARGETED_DEVICE_FAMILY = 1;" for f in families):
        problems.append("TARGETED_DEVICE_FAMILY is not 1 everywhere")
    if problems:
        raise SystemExit("project.pbxproj: " + "; ".join(problems))
    if t == before:
        return "up to date"
    path.write_text(t)
    return "zh-Hans, knownRegions, iPhone only"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True, help="path to sensen.xcodeproj")
    args = parser.parse_args()
    project = args.project.resolve()
    root, app_dir = project.parent, project.parent / "sensen"
    print("PrivacyInfo.xcprivacy:", privacy_manifest(root / "PrivacyInfo.xcprivacy"))
    print("sensen-Info.plist:", info_plist(app_dir / "sensen-Info.plist"))
    print("zh-Hans.lproj/InfoPlist.strings:", zh_strings(app_dir))
    print("project.pbxproj:", pbxproj(project / "project.pbxproj"))


if __name__ == "__main__":
    main()
