#!/usr/bin/env python3
"""Prepare an isolated two-keeper review in the runtime checkout."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

ART_ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--runtime-root", type=Path, required=True)
args = parser.parse_args()
root = args.runtime_root.resolve()
out = root / "output/keeper-hair-284"
out.mkdir(parents=True, exist_ok=True)
(root / "output/.gdignore").touch()
override = '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="SensenKeeperHair284QA"\n[sensen]\nnetwork/base_url="http://127.0.0.1:9/v1"\nnetwork/mobile_base_url="http://127.0.0.1:9/v1"\n'
if (root / "override.cfg").exists() and (root / "override.cfg").read_text() != override:
    raise RuntimeError("Preserve existing override; use an isolated runtime checkout")
(root / "override.cfg").write_text(override)
looks = {
    "keeper_auburn": {"slots": {"hairHat": "hairhat41_npc_auburn", "cloth": "cloth1", "shoes": "shoes1"}},
    "keeper_black": {"slots": {"hairHat": "hairhat43_npc_black", "cloth": "cloth1", "shoes": "shoes1"}},
}
(out / "looks-new.json").write_text(json.dumps(looks, indent=2) + "\n")
fixture = {"npcs": {key: {**look, "name": "Auburn keeper" if key.endswith("auburn") else "Soft-black keeper", "scale": 1.0}
                    for key, look in looks.items()}}
(out / "lineup-fixture.json").write_text(json.dumps(fixture, indent=2) + "\n")
source = root / "tools/dev/npc_lineup.gd"
script = source.read_text()
for old, new in [
    ('const NPCS_PATH := "res://assets/p0/outpost_npcs.json"', 'const NPCS_PATH := "res://output/keeper-hair-284/lineup-fixture.json"'),
    ('\t\trig.play_motion("idle")', '\t\trig.play_motion("idle")\n\t\tvar ap = rig.get_node("AnimationPlayer")\n\t\tap.seek(0.0, true)\n\t\tap.pause()'),
    ('Vector3(0.0, 1.0, 3.2), Vector3(1.9, 1.0, 2.6)', 'Vector3(0.0, 1.0, 3.5), Vector3(2.078125, 1.0, 2.84375)'),
    ('Vector3(0.0, 0.95, 0.0)', 'Vector3(0.0, 0.90, 0.0)'),
]:
    assert old in script, old
    script = script.replace(old, new)
script = '\n'.join(line for line in script.splitlines() if not line.startswith('\tcast.append({"id": "player"')) + '\n'
script = '\n'.join('\t\tvar parts := "hair41 / cloth1 / shoes1" if entry.id=="keeper_auburn" else "hair43 / cloth1 / shoes1"'
                   if line.startswith('\t\tvar parts := ') else line for line in script.splitlines()) + '\n'
(out / "npc_lineup_284b.gd").write_text(script)
baker = ART_ROOT / "tools/art/bake_resident_portraits.gd"
target = root / "tools/art/bake_resident_portraits.gd"
if target.exists() and target.read_bytes() != baker.read_bytes():
    raise RuntimeError("Preserve existing portrait baker; it differs from art branch")
shutil.copy2(baker, target)
(out / "review-script-provenance.json").write_text(json.dumps({
    "lineup_source": "tools/dev/npc_lineup.gd",
    "lineup_source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
    "lineup_fixture_sha256": hashlib.sha256(script.encode()).hexdigest(),
    "lineup_changes": ["Two keeper fixtures, no player column", "Frozen idle", "Full-feet framing", "Short labels"],
    "baker_source": "wp-3d-scene:tools/art/bake_resident_portraits.gd",
    "baker_sha256": hashlib.sha256(baker.read_bytes()).hexdigest(),
    "baker_unchanged": True, "baker_added_to_runtime_pr": False,
}, indent=2) + "\n")
print("Prepared two keeper looks, lineup fixture and unchanged local baker")
