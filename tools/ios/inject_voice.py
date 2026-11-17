#!/usr/bin/env python3
"""Snapshot the pinned native voice package into a copied Godot Xcode project and wire its app bootstrap.

Idempotent, no build/download/signing/device action. Native media capability stays false.
Run after inject_local_notify and before archive; that injector also calls this when the voice sources are present.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parents[1] / "native/voice/apple"
PACKAGE_PATH = "Packages/SensenVoiceApple"
MICROPHONE_USAGE = "Gensen uses the microphone only for voice chat, while your mic is on. Your voice goes live to people in the same place and isn't recorded."
MICROPHONE_USAGE_ZH = "Gensen 只在语音聊天、你开麦时使用麦克风。你的声音会实时传给同一地点的人，不会被录下来。"
IDS = {name: hashlib.sha1(("gensen.voice." + name).encode()).hexdigest()[:24].upper()
       for name in ["package", "product", "link", "source", "compile"]}


def metadata(text: str) -> dict:
    with tempfile.TemporaryDirectory(prefix="voice-pbx-check-") as tmp:
        path = Path(tmp) / "project.pbxproj"
        path.write_text(text)
        return json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)]))


def object_span(text: str, oid: str) -> tuple[int, int]:
    match = re.search(r"(?m)^\s*" + re.escape(oid) + r"(?:\s*/\*[^\n]*?\*/)?\s*=\s*\{", text)
    if not match:
        raise ValueError("Missing Xcode object " + oid)
    start = text.index("{", match.start())
    depth, quoted, escaped, comment = 0, False, False, False
    i = start
    while i < len(text):
        c = text[i]
        if comment:
            if text[i:i+2] == "*/": comment = False; i += 2; continue
        elif quoted:
            if escaped: escaped = False
            elif c == "\\": escaped = True
            elif c == '"': quoted = False
        elif text[i:i+2] == "/*": comment = True; i += 2; continue
        elif c == '"': quoted = True
        elif c == "{": depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0: return start, i + 1
        i += 1
    raise ValueError("Unterminated Xcode object " + oid)


def append_reference(text: str, oid: str, key: str, reference: str, label: str) -> str:
    start, end = object_span(text, oid)
    block = text[start:end]
    match = re.search(r"\b" + re.escape(key) + r"\s*=\s*\((.*?)\);", block, re.S)
    item = f"\n\t\t\t\t{reference} /* {label} */,"
    if match:
        body = match.group(1)
        if re.search(r"\b" + reference + r"\b", body): return text
        block = block[:match.end(1)] + item + "\n\t\t\t" + block[match.end(1):]
    else:
        block = block[:-1] + f"\n\t\t\t{key} = ({item}\n\t\t\t);\n\t\t}}"
    return text[:start] + block + text[end:]


def add_object(text: str, section: str, oid: str, label: str, fields: str) -> str:
    line = f"\t\t{oid} /* {label} */ = {{{fields}}};\n"
    marker = f"/* End {section} section */"
    if marker in text: return text.replace(marker, line + marker, 1)
    end = re.search(r"\n\t};\s*\n\trootObject\s*=", text)
    if not end: raise ValueError("Cannot find project objects end")
    section_text = f"\n/* Begin {section} section */\n{line}{marker}\n"
    return text[:end.start()] + section_text + text[end.start():]


def project_text(text: str) -> str:
    data = metadata(text)
    objects = data["objects"]
    apps = [(oid, o) for oid, o in objects.items() if o.get("isa") == "PBXNativeTarget"
            and o.get("productType") == "com.apple.product-type.application" and o.get("name") == "sensen"]
    if len(apps) != 1: raise ValueError("Expected one sensen application target")
    target_id, target = apps[0]
    groups = [oid for oid, o in objects.items() if o.get("isa") == "PBXGroup" and o.get("path") == "sensen"]
    if len(groups) != 1: raise ValueError("Expected one sensen source group")
    sources = [p for p in target["buildPhases"] if objects[p]["isa"] == "PBXSourcesBuildPhase"]
    frameworks = [p for p in target["buildPhases"] if objects[p]["isa"] == "PBXFrameworksBuildPhase"]
    if len(sources) != 1 or len(frameworks) != 1: raise ValueError("Ambiguous sources/frameworks phase")
    expected = {
        "package": ("XCLocalSwiftPackageReference", "SensenVoiceApple", {"isa": "XCLocalSwiftPackageReference", "relativePath": PACKAGE_PATH}),
        "product": ("XCSwiftPackageProductDependency", "SensenVoiceApple", {"isa": "XCSwiftPackageProductDependency", "productName": "SensenVoiceApple"}),
        "link": ("PBXBuildFile", "SensenVoiceApple in Frameworks", {"isa": "PBXBuildFile", "productRef": IDS["product"]}),
        "source": ("PBXFileReference", "VoiceBootstrap.swift", {"isa": "PBXFileReference", "lastKnownFileType": "sourcecode.swift", "path": "VoiceBootstrap.swift", "sourceTree": "<group>"}),
        "compile": ("PBXBuildFile", "VoiceBootstrap.swift in Sources", {"isa": "PBXBuildFile", "fileRef": IDS["source"]}),
    }
    for name, (section, label, props) in expected.items():
        oid = IDS[name]
        if oid in objects:
            if objects[oid] != props: raise ValueError("Conflicting existing voice registration: " + name)
        else:
            # An existing registration with a foreign ID needs explicit migration, not a silent duplicate.
            if name in ["package", "product", "source"] and any(
                all(o.get(k) == v for k, v in props.items()) for o in objects.values()
            ): raise ValueError("Voice already registered with another ID: " + name)
            fields = " ".join(f"{k} = {json.dumps(v)};" for k, v in props.items())
            text = add_object(text, section, oid, label, fields)
    for oid, key, ref, label in [
        (data["rootObject"], "packageReferences", IDS["package"], "SensenVoiceApple"),
        (target_id, "packageProductDependencies", IDS["product"], "SensenVoiceApple"),
        (frameworks[0], "files", IDS["link"], "SensenVoiceApple in Frameworks"),
        (groups[0], "children", IDS["source"], "VoiceBootstrap.swift"),
        (sources[0], "files", IDS["compile"], "VoiceBootstrap.swift in Sources"),
    ]: text = append_reference(text, oid, key, ref, label)
    after = metadata(text)["objects"]
    for oid, key, ref in [(target_id, "packageProductDependencies", IDS["product"]),
                           (sources[0], "files", IDS["compile"]), (frameworks[0], "files", IDS["link"])]:
        if after[oid][key].count(ref) != 1: raise ValueError("Voice registration must occur exactly once")
    return text


def set_usage_string(path: Path, key: str, value: str) -> None:
    text = path.read_text(encoding="utf-8") if path.exists() else "/* Localized Info.plist purposes */\n"
    line = json.dumps(key) + " = " + json.dumps(value, ensure_ascii=False) + ";"
    pattern = re.compile(r'^\s*"' + re.escape(key) + r'"\s*=\s*"(?:\\.|[^"\\])*"\s*;', re.M)
    matches = list(pattern.finditer(text))
    if len(matches) > 1: raise ValueError("Duplicate localized purpose: " + key)
    text = pattern.sub(lambda _: line, text) if matches else text.rstrip() + "\n" + line + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def inject(project: Path) -> dict:
    project = project.resolve()
    root, app = project.parent, project.parent / "sensen"
    pbx = project / "project.pbxproj"
    text = project_text(pbx.read_text()) # All structural checks before touching the project.
    if not (app / "GoogleSignInIOS.swift").is_file(): raise ValueError("Run inject_local_notify.py first (shared NativeBridgeKey)")
    info = app / "sensen-Info.plist"
    data = plistlib.loads(info.read_bytes())
    if not isinstance(data.get("ITSAppUsesNonExemptEncryption"), bool):
        raise ValueError("Explicit existing export-encryption declaration required; run store-config preparation first")
    # Preserve the explicit declaration; voice integration must not silently overwrite a future non-exempt decision.
    data["NSMicrophoneUsageDescription"] = MICROPHONE_USAGE
    localizations = data.setdefault("CFBundleLocalizations", [])
    for lang in ["en", "zh-Hans"]:
        if lang not in localizations: localizations.append(lang)
    destination = root / PACKAGE_PATH
    source_files = [PACKAGE / "Package.swift", PACKAGE / "Package.resolved", *sorted((PACKAGE / "Sources").rglob("*.swift"))]
    expected_paths = {str(source.relative_to(PACKAGE)) for source in source_files}
    unexpected = [str(p.relative_to(destination)) for p in (destination / "Sources").rglob("*.swift")
                  if str(p.relative_to(destination)) not in expected_paths]
    if unexpected: raise ValueError("Stale voice sources in copied package: " + ", ".join(unexpected))
    manifest = {}
    for source in source_files:
        relative = source.relative_to(PACKAGE)
        out = destination / relative
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, out)
        manifest[str(relative)] = hashlib.sha256(out.read_bytes()).hexdigest()
    shutil.copyfile(HERE / "VoiceBootstrap.swift", app / "VoiceBootstrap.swift")
    shutil.copyfile(HERE / "G3Spike.mm", app / "G3Spike.mm")
    info.write_bytes(plistlib.dumps(data, sort_keys=False))
    set_usage_string(app / "en.lproj/InfoPlist.strings", "NSMicrophoneUsageDescription", MICROPHONE_USAGE)
    set_usage_string(app / "zh-Hans.lproj/InfoPlist.strings", "NSMicrophoneUsageDescription", MICROPHONE_USAGE_ZH)
    pbx.write_text(text)
    report = {"package": PACKAGE_PATH, "product": "SensenVoiceApple", "files": manifest,
              "bootstrap_sha256": hashlib.sha256((app / "VoiceBootstrap.swift").read_bytes()).hexdigest(),
              "g3spike_sha256": hashlib.sha256((app / "G3Spike.mm").read_bytes()).hexdigest(),
              "capabilities_enabled": False, "non_exempt_encryption": data["ITSAppUsesNonExemptEncryption"]}
    (root / "voice-injection.json").write_text(json.dumps(report, sort_keys=True, indent=2) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    args = parser.parse_args()
    result = inject(args.project)
    print(json.dumps({k: v for k, v in result.items() if k != "files"}, sort_keys=True))


if __name__ == "__main__": main()
