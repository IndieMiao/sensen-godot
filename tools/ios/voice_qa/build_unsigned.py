#!/usr/bin/env python3
"""Validate/freeze the harness PCK and print or run an explicitly unsigned iOS build. Reserve a build window first."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import time

import prepare


def check_inputs(export, harness, pck):
    export=Path(export).resolve();harness=Path(harness).resolve();pck=Path(pck).resolve()
    info=plistlib.loads((export/'sensen/sensen-Info.plist').read_bytes())
    scope=info['SensenVoiceQAScope'];prepare.validate_scope(scope)
    fingerprint=hashlib.sha256(json.dumps(scope,sort_keys=True).encode()).hexdigest()
    report=json.loads((export/prepare.MANIFEST).read_text())
    config=json.loads((harness/'harness_config.json').read_text())
    manifest=json.loads((harness.parent/(harness.name+'-manifest.json')).read_text())
    if info.get('CFBundleIdentifier')!=prepare.QA_BUNDLE or report.get('scope_sha256')!=fingerprint or config.get('scope_sha256')!=fingerprint or manifest.get('scope_sha256')!=fingerprint:
        raise ValueError('Scope/bundle mismatch')
    for relative,sha in manifest['files'].items():
        path=harness/relative
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=sha:raise ValueError('Harness source changed after freeze')
    allowed=set(manifest['files'])
    for path in harness.rglob('*'):
        if not path.is_file():continue
        rel=str(path.relative_to(harness))
        if rel.startswith('.godot/') or rel in allowed or (rel.endswith('.uid') and rel[:-4] in allowed):continue
        raise ValueError('Unexpected harness file after freeze')
    if (harness/'tests.gd').exists() or '[autoload]' in (harness/'project.godot').read_text():raise ValueError('Unreviewed test/game autoload in harness')
    for name,field in [('VoiceBootstrap.swift','bootstrap_sha256'),('G3Spike.mm','g3spike_sha256')]:
        if hashlib.sha256((export/'sensen'/name).read_bytes()).hexdigest()!=report.get(field):raise ValueError('Native bootstrap changed')
    package=export/'Packages/SensenVoiceApple/Sources/SensenVoiceApple'
    for name,field in [('VoiceBridge.swift','qa_bridge_sha256'),('VoiceQAPolicy.swift','policy_sha256'),('VoiceEventDelivery.swift','qa_delivery_sha256')]:
        if hashlib.sha256((package/name).read_bytes()).hexdigest()!=report.get(field):raise ValueError('QA native policy changed')
    if not pck.is_file() or pck.stat().st_size<16:raise ValueError('Export the frozen QA PCK first')
    pck_sha=hashlib.sha256(pck.read_bytes()).hexdigest()
    receipt=json.loads((export/'qa-pck-receipt.json').read_text())
    if receipt.get('pck_sha256')!=pck_sha or receipt.get('scope_sha256')!=fingerprint or receipt.get('harness_manifest_sha256')!=hashlib.sha256((harness.parent/(harness.name+'-manifest.json')).read_bytes()).hexdigest():
        raise ValueError('Missing or mismatched QA pack export receipt')
    return {'scope_sha256':fingerprint,'pck_sha256':pck_sha,'client':config['client'],'validation_only':config['validation_only']}


def build_command(export,derived,packages,cache):
    return ['xcodebuild','-project',str(Path(export)/'sensen.xcodeproj'),'-scheme','sensen','-configuration','Release','-sdk','iphoneos','-destination','generic/platform=iOS','-derivedDataPath',str(derived),'-clonedSourcePackagesDirPath',str(packages),'-packageCachePath',str(cache),'-skipPackageUpdates','-onlyUsePackageVersionsFromResolvedFile','-jobs','2','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','CODE_SIGN_IDENTITY=','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','build']


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['export','harness','pck','derived','packages','cache']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--run',action='store_true')
    a=p.parse_args();facts=check_inputs(a.export,a.harness,a.pck)
    if a.pck.resolve()!=(a.export/'sensen.pck').resolve():raise SystemExit('PCK must already be at this QA export root')
    command=build_command(a.export,a.derived,a.packages,a.cache)
    result={'signing_allowed':False,'registered_or_installed':False,'facts':facts,'command':command}
    (a.export/'qa-unsigned-build-input.json').write_text(json.dumps(result,indent=2))
    if not a.run:print(json.dumps(result,indent=2));return
    if __import__('os').environ.get('SENSEN_LIVEKIT_SWIFT_SOURCE'):raise SystemExit('Unpinned SDK override refused')
    with (a.export/'qa-unsigned-build.log').open('w') as log:
        process=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT)
        (a.export/'qa-unsigned-build-process.json').write_text(json.dumps({'pid':process.pid,'started':time.time()}))
        print('UNSIGNED_BUILD_PID',process.pid,flush=True)
        code=process.wait()
    if code:raise SystemExit(code)
    import re
    log_text=(a.export/'qa-unsigned-build.log').read_text(errors='replace')
    if re.search(r'(?m)^CodeSign\b|^\s+/usr/bin/codesign\s',log_text):raise SystemExit('Unexpected signing operation in build log')
    app=a.derived/'Build/Products/Release-iphoneos/sensen.app'
    if (app/'embedded.mobileprovision').exists():raise SystemExit('Unexpected provisioning profile in unsigned QA app')
    actual=plistlib.loads((app/'Info.plist').read_bytes())
    if actual.get('CFBundleIdentifier')!=prepare.QA_BUNDLE or actual.get('SensenVoiceQAScope')!=info_scope(a.export):raise SystemExit('Built QA scope mismatch')
    if hashlib.sha256((app/'sensen.pck').read_bytes()).hexdigest()!=facts['pck_sha256']:raise SystemExit('Built PCK mismatch')
    result.update(build_succeeded=True,app=str(app),executable_sha256=hashlib.sha256((app/actual['CFBundleExecutable']).read_bytes()).hexdigest(),bundle=actual['CFBundleIdentifier'])
    (a.export/'qa-unsigned-readback.json').write_text(json.dumps(result,indent=2))
    print('UNSIGNED_QA_BUILD_COMPLETE; not signed/installed/media-tested')


def info_scope(export):return plistlib.loads((export/'sensen/sensen-Info.plist').read_bytes())['SensenVoiceQAScope']
if __name__=='__main__':main()
