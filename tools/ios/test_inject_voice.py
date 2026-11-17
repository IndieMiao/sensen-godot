import hashlib
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

import inject_store_config
import inject_voice as voice


def fixture(root: Path) -> Path:
    project = root / "sensen.xcodeproj"
    project.mkdir()
    (root / "sensen").mkdir()
    text = '''// !$*UTF8*$!
{
 archiveVersion = 1;
 objectVersion = 46;
 objects = {
  A00000000000000000000001 = {isa = PBXProject; targets = (A00000000000000000000002,); packageReferences = (); };
  A00000000000000000000002 = {isa = PBXNativeTarget; name = sensen; productType = "com.apple.product-type.application"; buildPhases = (A00000000000000000000004,A00000000000000000000005,); packageProductDependencies = (); };
  A00000000000000000000003 = {isa = PBXGroup; path = sensen; sourceTree = "<group>"; children = (); };
  A00000000000000000000004 = {isa = PBXSourcesBuildPhase; files = (); };
  A00000000000000000000005 = {isa = PBXFrameworksBuildPhase; files = (); };
	};
	rootObject = A00000000000000000000001;
}
'''
    (project / "project.pbxproj").write_text(text)
    (root / "sensen/GoogleSignInIOS.swift").write_text("// Existing shared launch-key provider\n")
    (root / "sensen/sensen-Info.plist").write_bytes(plistlib.dumps({"ITSAppUsesNonExemptEncryption": False,
                                                                  "NSLocationWhenInUseUsageDescription": "keep location"}))
    return project


class VoiceInjectionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="voice-inject-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.project = fixture(self.root)

    def snapshot(self):
        return {str(p.relative_to(self.root)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in self.root.rglob("*") if p.is_file()}

    def test_inject_is_byte_idempotent_and_preserves_existing_graph(self):
        before = voice.metadata((self.project / "project.pbxproj").read_text())
        report = voice.inject(self.project)
        first = self.snapshot()
        self.assertEqual(report, voice.inject(self.project))
        self.assertEqual(first, self.snapshot())
        after = voice.metadata((self.project / "project.pbxproj").read_text())
        self.assertEqual(after["objects"]["A00000000000000000000001"]["targets"],
                         before["objects"]["A00000000000000000000001"]["targets"])
        self.assertEqual(after["objects"][voice.IDS["package"]]["relativePath"], voice.PACKAGE_PATH)
        self.assertEqual(after["objects"]["A00000000000000000000004"]["files"], [voice.IDS["compile"]])
        self.assertEqual(after["objects"]["A00000000000000000000005"]["files"], [voice.IDS["link"]])

    def test_snapshot_is_exact_pinned_sources_and_keeps_capabilities_false(self):
        report = voice.inject(self.project)
        for name, digest in report["files"].items():
            self.assertEqual(hashlib.sha256((voice.PACKAGE / name).read_bytes()).hexdigest(), digest)
        snapshot = self.root / voice.PACKAGE_PATH
        self.assertIn('exact: "2.19.0"', (snapshot / "Package.swift").read_text())
        self.assertIn("releaseValidated = false", (snapshot / "Sources/SensenVoiceApple/VoiceBridge.swift").read_text())
        self.assertFalse(report["capabilities_enabled"])
        self.assertFalse((snapshot / ".build").exists())
        self.assertFalse((snapshot / "Tests").exists())

    def test_bootstrap_uses_the_existing_launch_key(self):
        voice.inject(self.project)
        source = (self.root / "sensen/VoiceBootstrap.swift").read_text()
        self.assertIn("VoiceBridge.shared.start(launchKey: NativeBridgeKey.value)", source)
        self.assertIn('NSClassFromString(@"VoiceIOS")', (self.root / "sensen/G3Spike.mm").read_text())
        self.assertNotIn("generate_random", source)

    def test_microphone_localization_survives_store_config_after_voice(self):
        voice.inject(self.project)
        inject_store_config.zh_strings(self.root / "sensen")
        inject_store_config.info_plist(self.root / "sensen/sensen-Info.plist")
        info = plistlib.loads((self.root / "sensen/sensen-Info.plist").read_bytes())
        self.assertEqual(info["NSMicrophoneUsageDescription"], voice.MICROPHONE_USAGE)
        self.assertEqual(info["NSLocationWhenInUseUsageDescription"], inject_store_config.LOCATION_USAGE)
        zh = (self.root / "sensen/zh-Hans.lproj/InfoPlist.strings").read_text()
        self.assertIn(voice.MICROPHONE_USAGE_ZH, zh)
        self.assertIn(inject_store_config.LOCATION_USAGE_ZH, zh)
        inject_store_config.zh_strings(self.root / "sensen")
        self.assertEqual(zh, (self.root / "sensen/zh-Hans.lproj/InfoPlist.strings").read_text())

    def test_explicit_non_exempt_declaration_is_never_reset(self):
        path = self.root / "sensen/sensen-Info.plist"
        info = plistlib.loads(path.read_bytes()); info["ITSAppUsesNonExemptEncryption"] = True
        path.write_bytes(plistlib.dumps(info))
        self.assertTrue(voice.inject(self.project)["non_exempt_encryption"])
        inject_store_config.info_plist(path)
        self.assertTrue(plistlib.loads(path.read_bytes())["ITSAppUsesNonExemptEncryption"])

    def test_unset_or_nonboolean_declaration_refused_before_writes(self):
        path = self.root / "sensen/sensen-Info.plist"
        for invalid in [None, "false", 0]:
            path.write_bytes(plistlib.dumps({} if invalid is None else {"ITSAppUsesNonExemptEncryption": invalid}))
            before = self.snapshot()
            with self.assertRaisesRegex(ValueError, "declaration"): voice.inject(self.project)
            self.assertEqual(before, self.snapshot())

    def test_conflicting_registration_refused_without_deleting_foreign_data(self):
        voice.inject(self.project)
        path = self.project / "project.pbxproj"
        path.write_text(path.read_text().replace('productName = "SensenVoiceApple"', 'productName = "ForeignProduct"'))
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "Conflicting"): voice.inject(self.project)
        self.assertEqual(before, self.snapshot())

    def test_stale_source_snapshot_is_refused_not_silently_deleted(self):
        voice.inject(self.project)
        stale = self.root / voice.PACKAGE_PATH / "Sources/SensenVoiceApple/Unexpected.swift"
        stale.write_text("// foreign file must survive refusal\n")
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "Stale voice sources"): voice.inject(self.project)
        self.assertEqual(before, self.snapshot())

    def test_missing_key_provider_is_refused_before_snapshot(self):
        (self.root / "sensen/GoogleSignInIOS.swift").unlink()
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "NativeBridgeKey"): voice.inject(self.project)
        self.assertEqual(before, self.snapshot())

    def test_localization_preserves_unrelated_purposes_and_rejects_duplicates(self):
        path = self.root / "InfoPlist.strings"
        path.write_text('"AnotherKey" = "keep me";\n')
        voice.set_usage_string(path, "NSMicrophoneUsageDescription", voice.MICROPHONE_USAGE)
        self.assertIn('"AnotherKey" = "keep me";', path.read_text())
        path.write_text('"NSMicrophoneUsageDescription" = "a";\n"NSMicrophoneUsageDescription" = "b";\n')
        with self.assertRaisesRegex(ValueError, "Duplicate"): voice.set_usage_string(path, "NSMicrophoneUsageDescription", "new")


if __name__ == "__main__": unittest.main()
