#!/usr/bin/env python3
"""Materialize an isolated Godot harness from frozen public scope. No network, export, signing or execution."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
from urllib.parse import urlsplit

import prepare

HERE = Path(__file__).resolve().parent
NATIVE_FILES = ["modules/net/voice_backend_ios.gd", "modules/net/apple_sign_in.gd"]


def canonical_origin(text, scheme):
    if not isinstance(text, str) or any(ord(c) < 33 or ord(c) == 127 for c in text): raise ValueError("Invalid origin")
    url = urlsplit(text)
    if url.scheme != scheme or not url.hostname or url.username is not None or url.password is not None or url.path not in ("", "/") or url.query or url.fragment:
        raise ValueError("A bare TLS origin is required")
    port = url.port if url.port is not None else 443
    if not 1 <= port <= 65535:raise ValueError("Invalid port")
    return url.hostname.lower(), port


def prepare_harness(qa_export, output, broker_origin, client="ios-a", validation_only=False):
    root = Path(qa_export).resolve(); output = Path(output).resolve()
    if output.exists() or output.is_relative_to(prepare.REPO) or output.is_relative_to(root):
        raise ValueError("Use a new harness output outside the repository/export")
    metadata = json.loads((root / ".gensen-voice-media-qa.json").read_text())
    info = plistlib.loads((root / "sensen/sensen-Info.plist").read_bytes())
    scope = info["SensenVoiceQAScope"]
    prepare.validate_scope(scope)
    fingerprint = hashlib.sha256(json.dumps(scope, sort_keys=True).encode()).hexdigest()
    if metadata.get("marker") != prepare.MARKER or metadata.get("scope_sha256") != fingerprint or info.get("CFBundleIdentifier") != prepare.QA_BUNDLE:
        raise ValueError("QA scope/export mismatch")
    if canonical_origin(broker_origin,"https") != canonical_origin(scope["media_origin"],"wss"):
        raise ValueError("Broker must use the frozen media authority")
    if client not in ["ios-a", "android-b"]:raise ValueError("Only A/B are enabled")
    config = dict(schema=1, marker=prepare.MARKER, environment=prepare.ENVIRONMENT, namespace=prepare.NAMESPACE,
                  broker_origin=broker_origin.rstrip("/"), media_origin=scope["media_origin"], client=client,
                  scope_sha256=fingerprint, validation_only=bool(validation_only))
    output.mkdir(parents=True)
    for name in ["main.gd", "session.gd", "broker.gd", "project.godot", "main.tscn"]:
        shutil.copy2(HERE / "harness" / name, output / name)
    for relative in NATIVE_FILES:
        target = output / relative; target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(prepare.REPO / relative,target)
    (output / "harness_config.json").write_text(json.dumps(config,sort_keys=True,indent=2))
    (output / "export_presets.cfg").write_text('''[preset.0]
name="iOS Media QA"
platform="iOS"
runnable=true
export_filter="all_resources"
include_filter="*.json"
exclude_filter="tests.gd"
export_path=""
[preset.0.options]
application/bundle_identifier="app.gensen.voiceqa"
''')
    files={str(p.relative_to(output)):hashlib.sha256(p.read_bytes()).hexdigest() for p in output.rglob("*") if p.is_file()}
    (output.parent / (output.name+"-manifest.json")).write_text(json.dumps(dict(scope_sha256=fingerprint,client=client,validation_only=validation_only,files=files),indent=2))
    return config


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qa-export",type=Path,required=True);parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--broker-origin",required=True);parser.add_argument("--client",choices=["ios-a","android-b"],default="ios-a")
    parser.add_argument("--validation-only",action="store_true")
    a=parser.parse_args()
    print(json.dumps(prepare_harness(a.qa_export,a.output,a.broker_origin,a.client,a.validation_only),indent=2))

if __name__=="__main__":main()
