#!/usr/bin/env python3
"""Prepare a NEW source export with the offline gate set before any Godot/autoload runs.

This only prepares a stage-two QA source copy. No Godot, Gradle, service or device action.
Native template installation/export require separate reviewed inputs and a resource window.
"""
from pathlib import Path, PurePosixPath
import argparse, hashlib, json, re, shutil, subprocess, tarfile, tempfile

BASE='99a853f7c75e917394a3f1f229bce9a82a38235c'
PACKAGE='com.sensen.dynamicfarmqa'
USER_DIR='gensen-dynamic-farm-preview-499'
OFFLINE_URL='https://offline.invalid/v1'
NATIVE=['GodotMapPlugin.kt','ParcelMapController.kt','ParcelLayerState.kt','ParcelPayload.kt','ParcelBuildingSelection.kt']

def sha(data):return hashlib.sha256(data).hexdigest()

def parse_settings(text):
    """Read single-line settings only, rejecting ambiguous duplicate sections/keys."""
    sections={};section=None
    for line in text.splitlines():
        match=re.fullmatch(r'\s*\[([^]\r\n]+)\]\s*',line)
        if match:
            section=match[1]
            if section in sections:raise ValueError('duplicate section '+section)
            sections[section]={}
        elif section is not None:
            match=re.match(r'^\s*([A-Za-z0-9_/.-]+)\s*=(.*)$',line)
            if match:
                key,value=match.groups()
                if key in sections[section]:raise ValueError('duplicate setting '+section+'/'+key)
                sections[section][key]=value.strip()
    return sections

def set_setting(text,section,key,value):
    settings=parse_settings(text)
    if section not in settings:return text.rstrip()+'\n\n['+section+']\n'+key+'='+value+'\n'
    lines=text.splitlines(keepends=True);start=next(i for i,l in enumerate(lines) if l.strip()=='['+section+']')
    end=next((i for i in range(start+1,len(lines)) if re.fullmatch(r'\s*\[[^]]+\]\s*',lines[i].rstrip())),len(lines))
    matches=[i for i in range(start+1,end) if re.match(r'^\s*'+re.escape(key)+r'\s*=',lines[i])]
    if matches:lines[matches[0]]=key+'='+value+'\n'
    else:lines.insert(end,key+'='+value+'\n')
    return ''.join(lines)

def verify_preview(text,main_scene,original_autoload):
    settings=parse_settings(text);network=settings.get('sensen',{});application=settings.get('application',{})
    if network.get('network/online_qa')!='true':raise ValueError('offline gate must be literal true before autoload')
    for key in ('network/base_url','network/mobile_base_url'):
        if network.get(key)!=json.dumps(OFFLINE_URL):raise ValueError('unexpected game network endpoint')
    if application.get('run/main_scene')!=json.dumps(main_scene):raise ValueError('wrong preview entry')
    if application.get('config/use_custom_user_dir')!='true' or application.get('config/custom_user_dir_name')!=json.dumps(USER_DIR):raise ValueError('shared user data prohibited')
    if settings.get('autoload')!=original_autoload:raise ValueError('original autoload symbols changed')
    for name in ('Net','Avatar','AppRouter'):
        if name not in original_autoload:raise ValueError('missing required autoload '+name)
    return {'offline_gate_before_autoload':True,'game_network_endpoints':OFFLINE_URL,'autoload_symbols':sorted(original_autoload),'user_dir':USER_DIR,'main_scene':main_scene}

def preview_project(original,main_scene):
    if not re.fullmatch(r'res://scenes/dynamic_farm/[A-Za-z0-9_/-]+\.tscn',main_scene) or '..' in main_scene:raise ValueError('explicit dynamic-farm entry required')
    autoload=parse_settings(original).get('autoload',{})
    changes={
        ('sensen','network/online_qa'):'true',
        ('sensen','network/base_url'):json.dumps(OFFLINE_URL),
        ('sensen','network/mobile_base_url'):json.dumps(OFFLINE_URL),
        ('application','run/main_scene'):json.dumps(main_scene),
        ('application','config/name'):json.dumps('Dynamic Farm 3D QA'),
        ('application','config/use_custom_user_dir'):'true',
        ('application','config/custom_user_dir_name'):json.dumps(USER_DIR),
    }
    text=original
    for (section,key),value in changes.items():text=set_setting(text,section,key,value)
    return text,verify_preview(text,main_scene,autoload)

def preview_preset(original,code):
    if not re.fullmatch(r'20[0-9]{8}',str(code)):raise ValueError('explicit version code required')
    sections=parse_settings(original)
    matching=[s for s,v in sections.items() if re.fullmatch(r'preset\.\d+',s) and v.get('name')=='"Android P0"']
    if len(matching)!=1:raise ValueError('expected one source Android preset')
    name=matching[0];start=original.index('['+name+']');rest=original[start:]
    next_preset=re.search(r'(?m)^\[preset\.\d+\]\s*$',rest[len('['+name+']'):])
    if next_preset:rest=rest[:len('['+name+']')+next_preset.start()]
    rest=rest.replace('['+name,'[preset.0')
    for section,key,value in [
        ('preset.0','name','"Android Dynamic Farm QA"'),('preset.0','custom_features','"dynamic_farm_preview"'),
        ('preset.0','export_path','"build/dynamic-farm-qa.apk"'),
        ('preset.0.options','package/unique_name',json.dumps(PACKAGE)),
        ('preset.0.options','package/name','"Dynamic Farm 3D QA"'),
        ('preset.0.options','version/code',str(code)),('preset.0.options','version/name','"0.0.1-dynamicqa"'),
        ('preset.0.options','user_data_backup/allow','false'),
    ]:rest=set_setting(rest,section,key,value)
    return rest

def prepare(repo,commit,output,main_scene,code):
    repo=Path(repo).resolve();output=Path(output).absolute()
    if not re.fullmatch('[0-9a-f]{40}',commit):raise ValueError('full immutable commit required')
    if output.exists() or output.is_symlink() or output.is_relative_to(repo):raise ValueError('new output outside source required')
    subprocess.run(['git','-C',str(repo),'merge-base','--is-ancestor',BASE,commit],check=True,capture_output=True)
    def blob(name):return subprocess.check_output(['git','-C',str(repo),'show',commit+':'+name])
    original=blob('project.godot').decode();project,check=preview_project(original,main_scene)
    scene_path=main_scene.removeprefix('res://');blob(scene_path)
    net_raw=blob('modules/net/net_service.gd');net=net_raw.decode()
    # Pin the reviewed Net implementation, not merely a matching comment or setting name.
    base_net=subprocess.check_output(['git','-C',str(repo),'show',BASE+':modules/net/net_service.gd'])
    if net_raw!=base_net:raise ValueError('Net source differs from reviewed base; review offline contract before repinning')
    native={name:sha(blob('tools/android/overlay/'+name)) for name in NATIVE}
    preset=preview_preset(blob('export_presets.cfg').decode(),code)
    output.parent.mkdir(parents=True,exist_ok=True)
    if output.parent.resolve()!=output.parent:raise ValueError('output parent symlink prohibited')
    stage=Path(tempfile.mkdtemp(prefix='.dynamic-preview-',dir=output.parent))
    try:
        with tempfile.TemporaryFile() as archive:
            subprocess.run(['git','-C',str(repo),'archive','--format=tar',commit],stdout=archive,check=True);archive.seek(0)
            with tarfile.open(fileobj=archive,mode='r:') as tf:
                for member in tf:
                    p=PurePosixPath(member.name)
                    if p.is_absolute() or '..' in p.parts or not (member.isfile() or member.isdir()):raise ValueError('unsupported source archive member')
                archive.seek(0)
            with tarfile.open(fileobj=archive,mode='r:') as tf:tf.extractall(stage,filter='data')
        # These writes happen before any engine/import process exists.
        (stage/'project.godot').write_text(project);(stage/'export_presets.cfg').write_text(preset)
        verify_preview((stage/'project.godot').read_text(),main_scene,parse_settings(original)['autoload'])
        receipt={'schema':1,'source_commit':commit,'source_base':BASE,'source_tree':subprocess.check_output(['git','-C',str(repo),'rev-parse',commit+'^{tree}'],text=True).strip(),
                 'package':PACKAGE,'version_code':code,'original_project_sha256':sha(original.encode()),'prepared_project_sha256':sha(project.encode()),
                 'export_presets_sha256':sha(preset.encode()),'net_source_sha256':sha(net.encode()),'native_five_sources':native,'settings_check':check,
                 'engine_started':False,'native_template_prepared':False,'runtime_media_or_gameplay_tested':False,'reviewed':False}
        (stage/'.dynamic-farm-preview-prepared.json').write_text(json.dumps(receipt,indent=2)+'\n')
        if output.exists() or output.is_symlink():raise ValueError('output appeared concurrently')
        stage.rename(output);return receipt
    except BaseException:shutil.rmtree(stage);raise

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source-repo',type=Path,required=True);p.add_argument('--source-commit',required=True)
    p.add_argument('--output',type=Path,required=True);p.add_argument('--main-scene',required=True);p.add_argument('--version-code',type=int,required=True);a=p.parse_args()
    print(json.dumps(prepare(a.source_repo,a.source_commit,a.output,a.main_scene,a.version_code)))
