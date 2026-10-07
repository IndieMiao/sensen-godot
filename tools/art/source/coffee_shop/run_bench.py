"""Coffee Shop's per-scene staging adapter; shared scene_bench core is unchanged.
X11 VSync on this executor throttled the first run; disable it in the isolated
project and cap actual engine FPS to 60. Movement and recording remain real-time.
"""
from pathlib import Path
import subprocess,sys,json,shutil
ROOT=Path(__file__).resolve().parents[4]
subprocess.run([sys.executable,str(ROOT/'tools/dev/scene_bench/prepare.py'),'coffee_shop'],cwd=ROOT,check=True)
project=ROOT/'output/scene-bench/coffee_shop/project'
layout_file=project/'assets/rooms/coffee_shop/layout.json'
layout=json.loads(layout_file.read_text())
# Preserve yaw/pitch; widen framing for the harness 4:3 viewport so no roof is clipped.
layout['camera']['size']=10.2
layout['camera']['position'][1]+=.08
layout['camera']['target'][1]+=.08
layout_file.write_text(json.dumps(layout,indent=2)+'\n')
p=project/'project.godot';s=p.read_text().replace('[display]\n','[display]\nwindow/vsync/vsync_mode=0\n').replace('[application]\n','[application]\nrun/max_fps=60\n');p.write_text(s)
with (ROOT/'output/coffee_shop'/layout.get('revision','R1').lower()/'bench-import.log').open('w') as log:
    subprocess.run(['godot','--headless','--editor','--path',str(project),'--import','--quit'],stdout=log,stderr=subprocess.STDOUT,check=True)
subprocess.run([sys.executable,str(ROOT/'tools/dev/scene_bench/run.py'),'coffee_shop',*[a for a in sys.argv[1:] if a!='--record']],cwd=ROOT,check=True)

# The core's opaque debug material hides interior blockers on this open diorama.
# Render the same live shapes as wireframes without modifying the shared harness.
shutil.copy2(Path(__file__).with_name('capture_collisions.gd'),project/'capture_collisions.gd')
evidence=ROOT/'output/scene-bench/coffee_shop/evidence'
with (evidence/'collision-wireframe.log').open('w') as log:
    subprocess.run(['godot','--disable-vsync','--max-fps','60','--path',str(project),'--resolution','960x720','--script','res://capture_collisions.gd','--','--slug','coffee_shop','--output',str(evidence)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=45)

if "--record" in sys.argv:
    subprocess.run([sys.executable,str(Path(__file__).with_name("record_r1.py"))],cwd=ROOT,check=True)
