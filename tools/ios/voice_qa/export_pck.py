#!/usr/bin/env python3
"""Export only the frozen QA harness and bind a receipt to its source/scope/PCK. Godot window required."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import prepare


def export(harness,qa_export):
    harness=Path(harness).resolve();qa_export=Path(qa_export).resolve()
    manifest_path=harness.parent/(harness.name+'-manifest.json')
    manifest=json.loads(manifest_path.read_text());qa=json.loads((qa_export/prepare.MANIFEST).read_text())
    if qa.get('marker')!=prepare.MARKER or qa.get('scope_sha256')!=manifest.get('scope_sha256'):raise ValueError('QA export/source mismatch')
    def verify():
        for relative,digest in manifest['files'].items():
            if hashlib.sha256((harness/relative).read_bytes()).hexdigest()!=digest:raise ValueError('Frozen harness changed')
        allowed=set(manifest['files'])
        for p in harness.rglob('*'):
            if not p.is_file():continue
            rel=str(p.relative_to(harness))
            if rel in allowed or rel.startswith('.godot/') or (rel.endswith('.uid') and rel[:-4] in allowed):continue
            raise ValueError('Unexpected harness file')
    verify()
    pck=qa_export/'sensen.pck'
    command=['godot','--headless','--path',str(harness),'--export-pack','iOS Media QA',str(pck)]
    subprocess.run(command,check=True)
    verify()
    receipt={'scope_sha256':manifest['scope_sha256'],'harness_manifest_sha256':hashlib.sha256(manifest_path.read_bytes()).hexdigest(),'pck_sha256':hashlib.sha256(pck.read_bytes()).hexdigest(),'command':command}
    (qa_export/'qa-pck-receipt.json').write_text(json.dumps(receipt,indent=2))
    return receipt

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--harness',type=Path,required=True);p.add_argument('--qa-export',type=Path,required=True)
    a=p.parse_args();print(json.dumps(export(a.harness,a.qa_export),indent=2))
