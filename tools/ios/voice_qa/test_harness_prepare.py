import hashlib
import json
import plistlib
from pathlib import Path
import tempfile
import unittest
import prepare
import prepare_harness
from test_prepare import fixture, scope

class HarnessPreparationTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='qa-harness-test-');self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.project=fixture(self.root);self.export=self.root/'qa'
        prepare.prepare(self.project,self.export,scope())
    def test_exact_backend_and_public_config_only(self):
        out=self.root/'harness'
        config=prepare_harness.prepare_harness(self.export,out,'https://qa387.devserver.test:17887')
        for rel in prepare_harness.NATIVE_FILES:self.assertEqual((prepare.REPO/rel).read_bytes(),(out/rel).read_bytes())
        self.assertFalse((out/'tests.gd').exists())
        self.assertEqual('ios-a',config['client']);self.assertFalse(config['validation_only'])
        self.assertNotIn('token',config);self.assertNotIn('code',config);self.assertNotIn('issuer_secret',config)
        self.assertNotIn('[autoload]',(out/'project.godot').read_text())
    def test_other_authority_redirect_and_third_client_refused(self):
        for origin in ['https://other.test','http://qa387.devserver.test:17887','https://qa387.devserver.test:17887/path','https://user:pass@qa387.devserver.test:17887']:
            with self.assertRaises(ValueError):prepare_harness.prepare_harness(self.export,self.root/'harness',origin)
        with self.assertRaises(ValueError):prepare_harness.prepare_harness(self.export,self.root/'harness','https://qa387.devserver.test:17887','observer-c')
    def test_scope_mutation_refused_before_copy(self):
        p=self.export/'sensen/sensen-Info.plist';info=plistlib.loads(p.read_bytes());info['SensenVoiceQAScope']['issuer_digest']='a'*64;p.write_bytes(plistlib.dumps(info))
        with self.assertRaises(ValueError):prepare_harness.prepare_harness(self.export,self.root/'harness','https://qa387.devserver.test:17887')
        self.assertFalse((self.root/'harness').exists())
    def test_validation_build_is_explicit_and_cannot_overwrite_another_harness(self):
        out=self.root/'harness';cfg=prepare_harness.prepare_harness(self.export,out,'https://qa387.devserver.test:17887',validation_only=True)
        self.assertTrue(cfg['validation_only'])
        with self.assertRaises(ValueError):prepare_harness.prepare_harness(self.export,out,'https://qa387.devserver.test:17887')
    def test_qa_bootstrap_only_starts_voice_and_records_nonsecret_arm_status(self):
        source=(self.export/'sensen/G3Spike.mm').read_text()
        self.assertIn('VoiceIOS',source);self.assertNotIn('MapUnderlay',source);self.assertNotIn('GoogleSignInIOS',source)
        source=(self.export/'sensen/VoiceBootstrap.swift').read_text()
        self.assertIn('.voice_qa_state.json',source)
        self.assertNotIn('writeState(launchKey',source)
        qa_info=plistlib.loads((self.export/'sensen/sensen-Info.plist').read_bytes())
        source_info=plistlib.loads((self.project.parent/'sensen/sensen-Info.plist').read_bytes())
        self.assertIn('NSLocalNetworkUsageDescription',qa_info)
        self.assertNotIn('NSLocalNetworkUsageDescription',source_info)
        self.assertEqual(source_info['NSMicrophoneUsageDescription'],qa_info['NSMicrophoneUsageDescription'])

if __name__=='__main__':unittest.main()
