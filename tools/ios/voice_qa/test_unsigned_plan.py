import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import prepare
import prepare_harness
import build_unsigned
from test_prepare import fixture, scope

class UnsignedPlanTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='qa-unsigned-test-');self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.project=fixture(self.root);self.export=self.root/'qa';self.harness=self.root/'harness'
        prepare.prepare(self.project,self.export,scope())
        self.config=prepare_harness.prepare_harness(self.export,self.harness,'https://qa387.devserver.test:17887')
        self.pck=self.export/'sensen.pck';self.pck.write_bytes(b'GDPC-fixture-not-a-real-pack-contents')
        self.receipt={'scope_sha256':self.config['scope_sha256'],'pck_sha256':hashlib.sha256(self.pck.read_bytes()).hexdigest(),'harness_manifest_sha256':hashlib.sha256((self.root/'harness-manifest.json').read_bytes()).hexdigest()}
        (self.export/'qa-pck-receipt.json').write_text(json.dumps(self.receipt))
    def test_build_command_never_signs_archives_uploads_or_provisions(self):
        cmd=build_unsigned.build_command(self.export,self.root/'dd',self.root/'packages',self.root/'cache')
        self.assertIn('CODE_SIGNING_ALLOWED=NO',cmd);self.assertIn('CODE_SIGNING_REQUIRED=NO',cmd);self.assertIn('CODE_SIGN_IDENTITY=',cmd)
        self.assertEqual('build',cmd[-1]);self.assertNotIn('-allowProvisioningUpdates',cmd);self.assertNotIn('-exportArchive',cmd);self.assertNotIn('archive',cmd)
    def test_exact_frozen_sources_and_pack_receipt_are_required(self):
        self.assertEqual(self.receipt['pck_sha256'],build_unsigned.check_inputs(self.export,self.harness,self.pck)['pck_sha256'])
        self.pck.write_bytes(b'wrong-production-game-pack-not-qa')
        with self.assertRaises(ValueError):build_unsigned.check_inputs(self.export,self.harness,self.pck)
    def test_extra_json_or_code_cannot_silently_enter_pack(self):
        (self.harness/'unreviewed.json').write_text('{}')
        with self.assertRaises(ValueError):build_unsigned.check_inputs(self.export,self.harness,self.pck)
    def test_changed_source_or_bootstrap_is_refused(self):
        p=self.harness/'main.gd';p.write_text(p.read_text()+'\n# unexpected\n')
        with self.assertRaises(ValueError):build_unsigned.check_inputs(self.export,self.harness,self.pck)

if __name__=='__main__':unittest.main()
