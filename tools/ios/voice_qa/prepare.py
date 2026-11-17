#!/usr/bin/env python3
"""Prepare native-only media QA sources in a NEW copied export. No PCK, signing, network or execution."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import sys
import time
from urllib.parse import urlsplit

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))
from check_voice_release import check_repo, check_export, QA_BUNDLE, MANIFEST

MARKER = "GENSEN_VOICE_MEDIA_QA_V1"
ENVIRONMENT = "devserver-isolated-387"
NAMESPACE = "p0-ios-voice-qa-1118"
KEYS = {"schema", "environment", "namespace", "media_origin", "issuer_digest", "not_before", "expires_at"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_scope(scope, now=None):
    now = time.time() if now is None else now
    if not isinstance(scope, dict) or set(scope) != KEYS:
        raise ValueError("Exact scope fields required")
    if type(scope["schema"]) is not int or scope["schema"] != 1 or scope["environment"] != ENVIRONMENT or scope["namespace"] != NAMESPACE:
        raise ValueError("Only the named devserver isolation and namespace are allowed")
    try:
        url = urlsplit(scope["media_origin"])
        valid_url = url.scheme == "wss" and url.hostname and url.path in ("", "/") and not url.query and not url.fragment and url.username is None and url.password is None and 1 <= (url.port if url.port is not None else 443) <= 65535
        host = (url.hostname or "").lower()
    except (TypeError, ValueError):
        raise ValueError("Invalid QA media origin") from None
    if not valid_url or host == "livekit.cloud" or host.endswith(".livekit.cloud"):
        raise ValueError("An exact isolated self-hosted WSS origin is required; Cloud projects are excluded")
    issuer = scope["issuer_digest"]
    if not isinstance(issuer, str) or not re.fullmatch(r"[0-9a-f]{64}", issuer) or issuer == "0" * 64:
        raise ValueError("A non-placeholder SHA256 of the isolated issuer is required")
    start, end = scope["not_before"], scope["expires_at"]
    if type(start) not in (int, float) or type(end) not in (int, float) or not start <= now < end or not 0 < end - start <= 86400:
        raise ValueError("QA scope must be currently valid for at most 24 hours")
    return scope


def replace_once(text, before, after):
    if text.count(before) != 1:
        raise ValueError("Reviewed bridge anchor changed; refuse to patch")
    return text.replace(before, after, 1)


def patch_bridge(text):
    text = replace_once(text, "    private var transport: VoiceDatagramServer?", "    private var qaPermit: VoiceQAPermit? // GENSEN_VOICE_MEDIA_QA_V1\n    private var transport: VoiceDatagramServer?")
    text = replace_once(text, "    public func start(launchKey: String) {", '''    /// QA-only copy: the bootstrap calls this only from an explicit on-screen Start action.
    public func startMediaQA(launchKey: String, scopeData: Data) -> Bool {
        guard transport == nil, qaPermit == nil, VoiceWire.validKey(launchKey),
              let scope = VoiceQAScope.decode(scopeData, bundleID: Bundle.main.bundleIdentifier,
                                             now: Date().timeIntervalSince1970) else { return false }
        qaPermit = VoiceQAPermit(scope: scope)
        start(launchKey: launchKey)
        return transport != nil
    }

    public func start(launchKey: String) {''')
    text = replace_once(text, "let server = VoiceDatagramServer(key: launchKey, mediaReady: { Self.releaseValidated },", "let server = VoiceDatagramServer(key: launchKey, mediaReady: { [weak self] in Self.releaseValidated || self?.qaPermit?.active == true },")
    text = replace_once(text, "                self.controller.command(command)", '''                guard self.qaPermit?.active == true else { self.stop(); return }
                if case .connect(let session, let url, let token) = command,
                   self.qaPermit?.permits(url: url, token: token) != true {
                    self.emit(["event": "error", "session": session, "code": "QA_SCOPE_REJECTED"])
                    self.stop()
                    return
                }
                self.controller.command(command)''')
    text = replace_once(text, "                self.controller.tick()", '''                if let permit = self.qaPermit, !permit.active { self.stop(); return }
                self.controller.tick()''')
    text = replace_once(text, "    public func stop() {\n        lifecycle &+= 1", '''    public func stop() {
        qaPermit?.disarm(); qaPermit = nil
        NotificationCenter.default.post(name: Notification.Name(VoiceQAScope.marker), object: nil)
        lifecycle &+= 1''')
    return text


def prepare(source_project, output, scope, now=None):
    validate_scope(scope, now)
    check_repo(REPO)
    source_project = Path(source_project).resolve()
    root = source_project.parent
    output = Path(output).resolve()
    if source_project.name != "sensen.xcodeproj" or output.exists() or output.is_relative_to(root) or output.is_relative_to(REPO):
        raise ValueError("Use a new output directory outside the source export and repository")
    check_export(root)
    package = root / "Packages/SensenVoiceApple"
    baseline = REPO / "native/voice/apple"
    expected = [baseline / "Package.swift", baseline / "Package.resolved", *sorted((baseline / "Sources").rglob("*.swift"))]
    for path in expected:
        if not (package / path.relative_to(baseline)).is_file() or digest(path) != digest(package / path.relative_to(baseline)):
            raise ValueError("Copied package is not the reviewed production snapshot")
    if {str(p.relative_to(package)) for p in (package / "Sources").rglob("*.swift")} != {str(p.relative_to(baseline)) for p in expected if p.suffix == ".swift" and p.name != "Package.swift"}:
        raise ValueError("Unexpected package source")
    app = root / "sensen"
    bootstrap = app / "VoiceBootstrap.swift"
    if digest(bootstrap) != digest(REPO / "tools/ios/VoiceBootstrap.swift"):
        raise ValueError("Copied bootstrap is not the reviewed production source")
    bridge = package / "Sources/SensenVoiceApple/VoiceBridge.swift"
    patched = patch_bridge(bridge.read_text())
    pbx = (source_project / "project.pbxproj").read_text()
    pbx, count = re.subn(r'(\bPRODUCT_BUNDLE_IDENTIFIER\s*=\s*)[^;]+;', r'\1"app.gensen.voiceqa";', pbx)
    if count == 0:
        raise ValueError("Missing Xcode bundle setting")
    pbx = re.sub(r'\bCODE_SIGN_ENTITLEMENTS\s*=\s*[^;]+;', 'CODE_SIGN_ENTITLEMENTS = "";', pbx)
    pbx = re.sub(r'\bCODE_SIGNING_(?:ALLOWED|REQUIRED)\s*=\s*[^;]+;', '', pbx)
    pbx, builds = re.subn(r'(\bbuildSettings\s*=\s*\{)', r'\1\n CODE_SIGNING_ALLOWED = NO;\n CODE_SIGNING_REQUIRED = NO;', pbx)
    if builds == 0:
        raise ValueError("Missing Xcode build settings")
    info = plistlib.loads((app / "sensen-Info.plist").read_bytes())
    info.update(CFBundleIdentifier=QA_BUNDLE, CFBundleDisplayName="Gensen Voice Media QA", SensenVoiceQAScope=scope)
    if "NSMicrophoneUsageDescription" not in info:
        raise ValueError("Microphone purpose must come from the production injector")
    # This is a native patch preparation, not an executable game package or a signing/export operation.
    ignore = shutil.ignore_patterns(".git", ".build", "DerivedData", "SourcePackages", "build", "*.pck", "*.mobileprovision", "*.p8", "*.p12", "*.key", "*.entitlements", "xcuserdata", "Documents", "voice_account.json", "ExportOptions*")
    try:
        output.mkdir(parents=True)
        (output / MANIFEST).write_text(json.dumps({"marker": MARKER, "incomplete": True}))
        # Only native export inputs; never clone an output directory's logs, game data or unrelated files.
        for relative in ["sensen.xcodeproj", "sensen", "Packages/SensenVoiceApple", "sensen.xcframework", "MoltenVK.xcframework"]:
            source = root / relative
            if source.is_dir():
                (output / relative).parent.mkdir(parents=True, exist_ok=True)
                shutil.copytree(source, output / relative, ignore=ignore, symlinks=True)
        if (root / "PrivacyInfo.xcprivacy").is_file():
            shutil.copyfile(root / "PrivacyInfo.xcprivacy", output / "PrivacyInfo.xcprivacy")
        out_package = output / "Packages/SensenVoiceApple"
        out_bridge = out_package / "Sources/SensenVoiceApple/VoiceBridge.swift"
        out_bridge.write_text(patched)
        shutil.copyfile(HERE / "templates/VoiceQAPolicy.swift", out_package / "Sources/SensenVoiceApple/VoiceQAPolicy.swift")
        shutil.copyfile(HERE / "templates/VoiceBootstrap.swift", output / "sensen/VoiceBootstrap.swift")
        (output / "sensen/sensen-Info.plist").write_bytes(plistlib.dumps(info, sort_keys=False))
        (output / "sensen.xcodeproj/project.pbxproj").write_text(pbx)
        patch = "".join(difflib.unified_diff(bridge.read_text().splitlines(True), patched.splitlines(True), fromfile="production/VoiceBridge.swift", tofile="qa-copy/VoiceBridge.swift"))
        (output / "voice-media-qa.patch").write_text(patch)
        report = {"marker": MARKER, "environment": ENVIRONMENT, "namespace": NAMESPACE,
                  "scope_sha256": hashlib.sha256(json.dumps(scope, sort_keys=True).encode()).hexdigest(),
                  "production_bridge_sha256": digest(bridge), "qa_bridge_sha256": digest(out_bridge),
                  "policy_sha256": digest(out_package / "Sources/SensenVoiceApple/VoiceQAPolicy.swift"),
                  "bootstrap_sha256": digest(output / "sensen/VoiceBootstrap.swift"),
                  "production_capability": False, "qa_capability": "manual-scoped-maximum-600-seconds",
                  "signing_enabled": False, "game_pck_included": False, "requires_separately_reviewed_qa_harness": True}
        (output / MANIFEST).write_text(json.dumps(report, indent=2))
        (output / "voice-injection.json").write_text(json.dumps(report, indent=2))
        return report
    except Exception:
        # Keep any partial output marked and unbuildable; never delete or modify the source tree.
        if output.exists():
            (output / MANIFEST).write_text(json.dumps({"marker": MARKER, "incomplete": True}))
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-project", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--scope", required=True, type=Path)
    args = parser.parse_args()
    try:
        result = prepare(args.source_project, args.output, json.loads(args.scope.read_text()))
    except (ValueError, OSError, KeyError) as error:
        raise SystemExit("QA_PREPARE_REFUSED: " + str(error))
    print(json.dumps(result, indent=2))


if __name__ == "__main__": main()
