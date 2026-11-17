#!/usr/bin/env python3
"""Fail closed if the isolated voice-media QA overlay reaches production sources/export/artifact.
No network, build, signing or device operations. Templates under tools/ios/voice_qa are inert tooling.
"""
import argparse
from pathlib import Path
import plistlib
import re
import sys

MARKERS = (b"GENSEN_VOICE_MEDIA_QA_V1", b"SensenVoiceQAScope", b"startMediaQA", b"VoiceQAPolicy", b"VoiceQAScope", b"VoiceQAPermit")
QA_BUNDLE = "app.gensen.voiceqa"
MANIFEST = ".gensen-voice-media-qa.json"


def contains_marker(path):
    carry = b""
    with path.open("rb") as stream:
        while chunk := stream.read(65536):
            data = carry + chunk
            if any(marker in data for marker in MARKERS):
                return True
            carry = data[-64:]
    return False


def reject_qa_tree(root):
    root = Path(root)
    if not root.is_dir():
        raise ValueError("Missing export/artifact directory")
    for path in root.rglob("*"):
        if path.name == MANIFEST:
            raise ValueError("Voice media QA manifest is not releasable")
        if path.is_symlink():
            # Do not follow an export symlink to an unscanned QA source or binary.
            raise ValueError("Release input contains an unaudited symlink")
        if not path.is_file():
            continue
        if path.suffix == ".plist":
            try:
                info = plistlib.loads(path.read_bytes())
            except Exception:
                raise ValueError("Unreadable release plist") from None
            if isinstance(info, dict) and (info.get("CFBundleIdentifier") == QA_BUNDLE or "SensenVoiceQAScope" in info):
                raise ValueError("Voice media QA bundle/config is not releasable")
        if contains_marker(path):
            raise ValueError("Voice media QA code/marker is not releasable")


def check_repo(root):
    root = Path(root)
    package = root / "native/voice/apple"
    bridge = package / "Sources/SensenVoiceApple/VoiceBridge.swift"
    bootstrap = root / "tools/ios/VoiceBootstrap.swift"
    for path in [bridge, bootstrap]:
        if not path.is_file() or path.is_symlink():
            raise ValueError("Missing or redirected production voice source")
    text = bridge.read_text()
    assignments = re.findall(r"(?m)^\s*private\s+static\s+let\s+releaseValidated\s*=([^\n]+)$", text)
    if len(assignments) != 1 or assignments[0].strip() != "false":
        raise ValueError("Production voice capability must remain literal false")
    reject_qa_tree(package / "Sources")
    if contains_marker(package / "Package.swift") or contains_marker(bootstrap):
        raise ValueError("QA bootstrap/package flags in production inputs")


def check_export(project_root):
    # Scan source/config inputs, not SDK caches/build products. The artifact mode scans the actual app separately.
    root = Path(project_root)
    if not (root / "sensen.xcodeproj/project.pbxproj").is_file():
        raise ValueError("Missing exported Xcode project")
    if (root / MANIFEST).exists():
        raise ValueError("Prepared voice media QA export must not enter release preparation")
    for directory in [root / "sensen", root / "Packages/SensenVoiceApple", root / "sensen.xcodeproj"]:
        if directory.exists():
            reject_qa_tree(directory)


def check_app(root):
    root = Path(root)
    info = plistlib.loads((root / "Info.plist").read_bytes())
    executable = info.get("CFBundleExecutable", "")
    if not isinstance(executable, str) or not executable or Path(executable).name != executable or not (root / executable).is_file():
        raise ValueError("Missing app executable")
    reject_qa_tree(root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument("--repo", type=Path)
    choice.add_argument("--export", type=Path)
    choice.add_argument("--app", type=Path)
    args = parser.parse_args()
    try:
        if args.repo: check_repo(args.repo)
        elif args.export: check_export(args.export)
        else: check_app(args.app)
    except (ValueError, OSError) as error:
        print("VOICE_RELEASE_REJECTED: " + str(error), file=sys.stderr)
        return 1
    print("VOICE_RELEASE_CLEAN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
