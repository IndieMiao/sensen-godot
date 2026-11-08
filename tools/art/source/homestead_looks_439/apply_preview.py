"""Patch only the ignored farm copy to substitute the four new assets."""
from pathlib import Path
import json,subprocess,difflib
ROOT=Path(__file__).resolve().parents[4];QA=ROOT/'output/homestead-439';P=QA/'project';head=json.loads((QA/'stage.json').read_text())['runtime_head']
rel='modules/p0/p0_garden.gd';original=subprocess.check_output(['git','show',head+':'+rel],cwd=ROOT,text=True)
a=original.index('static func look_parts(');b=original.index('\n## Master Farmhouse',a)
replacement='''static func look_parts(bp: FarmBlueprint, stage: String, look: String) -> Array:
	var house := bp.cell_to_world(ANCHORS.house)
	var mode := OS.get_environment("HOMESTEAD_439_STAGE")
	if look not in ["a", "b"]: return []
	if stage == "porch" and mode in ["porch", "kitchen"]:
		return [{"asset": "porch_" + look, "pos": house, "yaw": 0.0, "scale": Vector3.ONE}]
	if stage == "kitchen_extension" and mode == "kitchen":
		return [{"asset": "kitchen_wing_" + look, "pos": house, "yaw": 0.0, "scale": Vector3.ONE}]
	return []
'''
changed=original[:a]+replacement+original[b:];(P/rel).write_text(changed)
(QA/'preview.patch').write_text(''.join(difflib.unified_diff(original.splitlines(True),changed.splitlines(True),fromfile='runtime/'+rel,tofile='isolated-preview/'+rel,n=0)))
(P/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="Homestead439Review" type="Node"]\nscript=ExtResource("1")\n')
print('Only isolated look_parts patched; anchors and masks retained')
