"""Negative release exclusion checks; artifact fixtures are not signed/real iOS binaries."""
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
import check_voice_release as guard
REPO = Path(__file__).resolve().parents[2]


class VoiceReleaseGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="voice-release-guard-"); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def repo(self):
        source = REPO / "native/voice/apple"
        shutil.copytree(source / "Sources", self.root / "native/voice/apple/Sources")
        shutil.copyfile(source / "Package.swift", self.root / "native/voice/apple/Package.swift")
        target = self.root / "tools/ios"; target.mkdir(parents=True)
        shutil.copyfile(REPO / "tools/ios/VoiceBootstrap.swift", target / "VoiceBootstrap.swift")
        return self.root

    def app(self):
        app = self.root / "candidate.app"; app.mkdir()
        (app / "Info.plist").write_bytes(plistlib.dumps(dict(CFBundleIdentifier="app.gensen.maps", CFBundleExecutable="candidate")))
        (app / "candidate").write_bytes(b"fixture-production-executable")
        return app

    def test_reviewed_production_repo_passes(self):guard.check_repo(REPO)

    def test_flipped_production_capability_is_rejected(self):
        repo = self.repo(); p = repo / "native/voice/apple/Sources/SensenVoiceApple/VoiceBridge.swift"
        p.write_text(p.read_text().replace("releaseValidated = false", "releaseValidated = true"))
        with self.assertRaises(ValueError):guard.check_repo(repo)

    def test_renamed_qa_source_in_production_package_is_rejected(self):
        repo = self.repo()
        (repo / "native/voice/apple/Sources/SensenVoiceApple/Ordinary.swift").write_text("final class VoiceQAPermit {}")
        with self.assertRaises(ValueError):guard.check_repo(repo)

    def test_qa_bootstrap_in_production_app_source_is_rejected(self):
        repo = self.repo(); (repo / "tools/ios/VoiceBootstrap.swift").write_text("// GENSEN_VOICE_MEDIA_QA_V1")
        with self.assertRaises(ValueError):guard.check_repo(repo)

    def test_artifact_binary_marker_crossing_chunk_boundary_is_rejected(self):
        app = self.app(); guard.check_app(app)
        (app / "candidate").write_bytes(b"x" * 65530 + guard.MARKERS[0] + b"x" * 128)
        with self.assertRaises(ValueError):guard.check_app(app)

    def test_artifact_plist_qa_identity_is_rejected_without_code_marker(self):
        app = self.app()
        (app / "Info.plist").write_bytes(plistlib.dumps(dict(CFBundleIdentifier=guard.QA_BUNDLE, CFBundleExecutable="candidate")))
        with self.assertRaises(ValueError):guard.check_app(app)

    def test_missing_inputs_do_not_report_clean(self):
        with self.assertRaises(ValueError):guard.check_export(self.root)
        with self.assertRaises(OSError):guard.check_app(self.root)


if __name__ == "__main__": unittest.main()
