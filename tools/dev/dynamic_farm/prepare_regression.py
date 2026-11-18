"""Stage existing game autoloads in a private, offline gdUnit project; no engine run."""
from pathlib import Path
import argparse
import json
import re
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True)
parser.add_argument('--cache-root', required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[3]
out = Path(args.output).resolve()
subprocess.run([sys.executable, str(Path(__file__).with_name('prepare_preview.py')), '--output', str(out), '--cache-root', args.cache_root, '--copy-tests'], check=True)
link = out / 'addons'
if not link.exists(): link.symlink_to(repo / 'addons', target_is_directory=True)
for name in ['export_presets.cfg', 'docs']:
    link = out / name
    if not link.exists():
        link.symlink_to(repo / name, target_is_directory=(repo / name).is_dir())
config = (repo / 'project.godot').read_text()
config = re.sub(r'^config/name=.*$', 'config/name="Dynamic Farm Regression QA"', config, flags=re.M)
config = re.sub(r'^run/main_scene=.*\n', '', config, flags=re.M)
config = config.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="SensenDynamicFarmRegressionQA"', 1)
config = re.sub(r'^network/(base_url|mobile_base_url)=.*$', lambda m: 'network/' + m.group(1) + '="http://127.0.0.1:9"', config, flags=re.M)
config = config.replace('[sensen]', '[sensen]\nnetwork/online_qa=true', 1)
(out / 'project.godot').write_text(config)
# Imported art is reusable across branches, but the script-class index may lag
# behind this source tree. Refresh project classes in this private QA copy only.
class_cache = out / '.godot/global_script_class_cache.cfg'
entries = {}
for block in re.findall(r'\{[^{}]*\}', class_cache.read_text()):
    name = re.search(r'"class": &"([^"]+)"', block)
    path = re.search(r'"path": "([^"]+)"', block)
    if name and path and not path.group(1).startswith(('res://modules/', 'res://scenes/')):
        entries[name.group(1)] = block
for folder in ['modules', 'scenes']:
    for source in sorted((repo / folder).rglob('*.gd')):
        code = source.read_text()
        name = re.search(r'^class_name\s+(\w+)', code, re.M)
        if not name:
            continue
        base = re.search(r'^(?:class_name\s+\w+\s+)?extends\s+(\w+)', code, re.M)
        if not base and re.search(r'^extends\s+', code, re.M):
            raise SystemExit('Unsupported class base in QA index: ' + str(source.relative_to(repo)))
        if name.group(1) in entries:
            raise SystemExit('Duplicate QA class: ' + name.group(1))
        entries[name.group(1)] = '{\n' + ',\n'.join([
            '"base": &' + json.dumps(base.group(1) if base else 'RefCounted'),
            '"class": &' + json.dumps(name.group(1)),
            '"icon": ""',
            '"is_abstract": ' + str(bool(re.search(r'^@abstract', code, re.M))).lower(),
            '"is_tool": ' + str(bool(re.search(r'^@tool', code, re.M))).lower(),
            '"language": &"GDScript"',
            '"path": ' + json.dumps('res://' + source.relative_to(repo).as_posix())
        ]) + '\n}'
class_cache.write_text('list=[' + ', '.join(entries[k] for k in sorted(entries)) + ']\n')
print('Private regression project staged; use SENSEN_OFFLINE=1 and P0_SERVER_URL loopback for gdUnit execution. No Godot started.')
