import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

import prepare
sys.path.insert(0, str(prepare.HERE.parent))
import check_voice_release as guard
import inject_voice


def scope():
    now = time.time()
    return dict(schema=1, environment=prepare.ENVIRONMENT, namespace=prepare.NAMESPACE,
                media_origin="wss://qa387.devserver.test:17887", issuer_digest=hashlib.sha256(b"isolated-fixture-issuer").hexdigest(),
                not_before=now - 1, expires_at=now + 600)


def fixture(root):
    export = root / "export"
    app = export / "sensen"; app.mkdir(parents=True)
    project = export / "sensen.xcodeproj"; project.mkdir()
    (project / "project.pbxproj").write_text('{ buildSettings = { PRODUCT_BUNDLE_IDENTIFIER = "app.gensen.maps"; CODE_SIGN_ENTITLEMENTS = "sensen/old.entitlements"; }; }')
    (app / "sensen-Info.plist").write_bytes(plistlib.dumps(dict(CFBundleIdentifier="app.gensen.maps", ITSAppUsesNonExemptEncryption=False, NSMicrophoneUsageDescription="fixture microphone")))
    shutil.copyfile(prepare.REPO / "tools/ios/VoiceBootstrap.swift", app / "VoiceBootstrap.swift")
    source = prepare.REPO / "native/voice/apple"
    target = export / "Packages/SensenVoiceApple"
    shutil.copytree(source / "Sources", target / "Sources")
    for name in ["Package.swift", "Package.resolved"]:shutil.copyfile(source / name, target / name)
    (export / "unrelated-private.txt").write_text("not-an-export-input")
    (export / "sensen.pck").write_bytes(b"production-game-must-not-copy")
    (export / "ExportOptions-TestFlightUpload.plist").write_bytes(plistlib.dumps(dict(destination="upload")))
    (app / "old.entitlements").write_bytes(plistlib.dumps({}))
    return project


def snapshot(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob("*") if p.is_file()}


class VoiceQAPreparationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="voice-qa-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.project = fixture(self.root)
        self.output = self.root / "qa"

    def prepare(self):return prepare.prepare(self.project, self.output, scope())

    def test_only_copy_is_patched_and_no_game_or_signing_payload_leaks(self):
        original = snapshot(self.project.parent)
        report = self.prepare()
        self.assertEqual(original, snapshot(self.project.parent))
        self.assertFalse(report["production_capability"])
        self.assertFalse((self.output / "sensen.pck").exists())
        self.assertFalse((self.output / "unrelated-private.txt").exists())
        self.assertFalse((self.output / "ExportOptions-TestFlightUpload.plist").exists())
        self.assertFalse((self.output / "sensen/old.entitlements").exists())
        bridge = (self.output / "Packages/SensenVoiceApple/Sources/SensenVoiceApple/VoiceBridge.swift").read_text()
        self.assertIn("private static let releaseValidated = false", bridge)
        self.assertIn("qaPermit?.permits(url: url, token: token)", bridge)
        self.assertIn("transport?.publish(stamped)", bridge)
        delivery=(self.output/"Packages/SensenVoiceApple/Sources/SensenVoiceApple/VoiceEventDelivery.swift").read_text()
        self.assertIn("Self.qaClockFields(event)",delivery)
        self.assertIn("GENSEN_VOICE_MEDIA_QA_V1",delivery)
        bootstrap = (self.output / "sensen/VoiceBootstrap.swift").read_text()
        self.assertNotIn("VoiceBridge.shared.start(launchKey:", bootstrap)
        self.assertIn("for: .touchUpInside", bootstrap)
        self.assertIn("CODE_SIGNING_ALLOWED = NO", (self.output / "sensen.xcodeproj/project.pbxproj").read_text())

    def test_real_release_cli_rejects_prepared_export(self):
        self.prepare()
        result = subprocess.run([sys.executable, str(prepare.HERE.parent / "check_voice_release.py"), "--export", str(self.output)], capture_output=True, text=True)
        self.assertEqual(1, result.returncode)
        self.assertIn("VOICE_RELEASE_REJECTED", result.stderr)

    def test_release_injector_refuses_before_it_can_overwrite_qa(self):
        self.prepare(); before = snapshot(self.output)
        with self.assertRaises(ValueError):inject_voice.inject(self.output / "sensen.xcodeproj")
        self.assertEqual(before, snapshot(self.output))

    def test_removing_manifest_and_renaming_bundle_does_not_hide_overlay(self):
        self.prepare(); (self.output / guard.MANIFEST).unlink()
        info = self.output / "sensen/sensen-Info.plist"
        data = plistlib.loads(info.read_bytes()); data.pop("SensenVoiceQAScope"); data["CFBundleIdentifier"] = "app.gensen.maps"
        info.write_bytes(plistlib.dumps(data))
        with self.assertRaises(ValueError):guard.check_export(self.output)

    def test_unknown_source_modification_is_refused_without_output(self):
        bridge = self.project.parent / "Packages/SensenVoiceApple/Sources/SensenVoiceApple/VoiceBridge.swift"
        bridge.write_text(bridge.read_text() + "\n// unreviewed\n")
        with self.assertRaises(ValueError):self.prepare()
        self.assertFalse(self.output.exists())

    def test_symlinked_source_is_refused(self):
        bridge = self.project.parent / "Packages/SensenVoiceApple/Sources/SensenVoiceApple/VoiceBridge.swift"
        bridge.unlink(); bridge.symlink_to(prepare.REPO / "native/voice/apple/Sources/SensenVoiceApple/VoiceBridge.swift")
        with self.assertRaises(ValueError):self.prepare()
        self.assertFalse(self.output.exists())

    def test_clock_only_delivery_copy_is_rejected_even_without_sentinel_comment(self):
        self.prepare()
        relative = "Packages/SensenVoiceApple/Sources/SensenVoiceApple/VoiceEventDelivery.swift"
        text = (self.output / relative).read_text().replace("GENSEN_VOICE_MEDIA_QA_V1", "removed-marker")
        (self.project.parent / relative).write_text(text)
        with self.assertRaises(ValueError):guard.check_export(self.project.parent)

    def test_existing_output_and_nested_destination_are_refused(self):
        self.output.mkdir(); keep = self.output / "keep"; keep.write_text("foreign")
        with self.assertRaises(ValueError):self.prepare()
        self.assertEqual("foreign", keep.read_text())
        with self.assertRaises(ValueError):prepare.prepare(self.project, self.project.parent / "nested", scope())

    def test_production_namespace_environment_cloud_and_unsafe_urls_are_refused(self):
        variants = [("namespace", "p0-prod"), ("environment", "production"),
                    ("media_origin", "wss://livekit.cloud"), ("media_origin", "wss://livekit.cloud."), ("media_origin", "wss://Tenant.LIVEKIT.CLOUD"), ("media_origin", "wss://Tenant.LIVEKIT.CLOUD."), ("media_origin", "wss://p0-prod.livekit.cloud"), ("media_origin", "wss://p0-prod.livekit.cloud."), ("media_origin", "wss://p0-prod.livekit。cloud"), ("media_origin", "ws://devserver:17887"),
                    ("media_origin", "wss://user:secret@devserver"), ("media_origin", "wss://devserver/path"), ("media_origin", "wss://devserver:0"), ("media_origin", "wss://qa-\nallowed.test"),
                    ("media_origin", "wss://devserver?redirect=prod"), ("issuer_digest", "0" * 64)]
        for key, value in variants:
            with self.subTest(key=key, value=value):
                candidate = scope(); candidate[key] = value
                with self.assertRaises(ValueError):prepare.prepare(self.project, self.output, candidate)
        self.assertFalse(self.output.exists())

    def test_approved_host_case_is_allowed(self):
        candidate = scope(); candidate["media_origin"] = "wss://QA387.DEVSERVER.TEST:17887"
        self.assertEqual(candidate, prepare.validate_scope(candidate))

    def test_expired_future_and_overlong_scope_are_refused(self):
        now = time.time()
        for start, end in [(now-100, now-1), (now+10, now+20), (now-1, now+90000)]:
            candidate = scope(); candidate.update(not_before=start, expires_at=end)
            with self.assertRaises(ValueError):prepare.validate_scope(candidate, now)


if __name__ == "__main__": unittest.main()
