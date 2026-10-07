"""Coffee Shop's per-scene staging adapter; shared scene_bench core is unchanged.
X11 VSync on this executor throttled the first run; disable it in the isolated
project and cap actual engine FPS to 60. Movement and recording remain real-time.
"""
from pathlib import Path
import subprocess,sys,json,shutil
ROOT=Path(__file__).resolve().parents[4]
slug=next((a for a in sys.argv[1:] if not a.startswith('--')),'coffee_shop')
subprocess.run([sys.executable,str(ROOT/'tools/dev/scene_bench/prepare.py'),slug],cwd=ROOT,check=True)
project=ROOT/'output/scene-bench'/slug/'project'
if slug != 'coffee_shop':
    (project/'scenes/coffee_shop').mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT/'scenes/coffee_shop/coffee_shop_art.gd',project/'scenes/coffee_shop/coffee_shop_art.gd')
# Jolt can place floor and wall contacts in the same KinematicCollision3D.
# The shared fixture reads only contact 0; collect every actual lateral contact
# in this isolated staged copy, without changing motion, assertions or the core.
physics_file=project/'tools/dev/scene_bench/scene_bench.gd'
physics=physics_file.read_text()
old="""		var collider=player.get_slide_collision(i).get_collider()
		if collider and player.get_slide_collision(i).get_normal().y<.7:
			var path:=str(collider.get_path())
			if not collided_paths.has(path):collided_paths.append(path)"""
new="""		var contact=player.get_slide_collision(i)
		for j in contact.get_collision_count():
			var collider=contact.get_collider(j)
			if collider and contact.get_normal(j).y<.7:
				var path:=str(collider.get_path())
				if not collided_paths.has(path):collided_paths.append(path)"""
assert old in physics, 'Shared contact collection changed; inspect before adapting.'
physics_file.write_text(physics.replace(old,new))
layout_file=project/'assets/rooms'/slug/'layout.json'
layout=json.loads(layout_file.read_text())
# Preserve yaw/pitch; widen framing for the harness 4:3 viewport so no roof is clipped.
layout['camera']['size']=max(10.2,float(layout['camera']['size'])*1.065)
# The extended courtyard path starts outside the building: retain the full avatar.
if slug=='coffee_shop_0':layout['camera']['size']*=1.15
layout['camera']['position'][1]+=.08
layout['camera']['target'][1]+=.08
layout_file.write_text(json.dumps(layout,indent=2)+'\n')
p=project/'project.godot';s=p.read_text().replace('[display]\n','[display]\nwindow/vsync/vsync_mode=0\n').replace('[application]\n','[application]\nrun/max_fps=60\n');p.write_text(s)
with (project.parent/'bench-import.log').open('w') as log:
    subprocess.run(['godot','--headless','--editor','--path',str(project),'--import','--quit'],stdout=log,stderr=subprocess.STDOUT,check=True)
subprocess.run([sys.executable,str(ROOT/'tools/dev/scene_bench/run.py'),slug,*[a for a in sys.argv[1:] if a.startswith('--') and a!='--record']],cwd=ROOT,check=True)

# The core's opaque debug material hides interior blockers on this open diorama.
# Render the same live shapes as wireframes without modifying the shared harness.
shutil.copy2(Path(__file__).with_name('capture_collisions.gd'),project/'capture_collisions.gd')
evidence=ROOT/'output/scene-bench'/slug/'evidence'
with (evidence/'collision-wireframe.log').open('w') as log:
    subprocess.run(['godot','--disable-vsync','--max-fps','60','--path',str(project),'--resolution','960x720','--script','res://capture_collisions.gd','--','--slug',slug,'--output',str(evidence)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=45)

if "--record" in sys.argv:
    subprocess.run([sys.executable,str(Path(__file__).with_name("record_r1.py")),slug],cwd=ROOT,check=True)
