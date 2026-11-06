# Alcatraz dock kit · 刘备 · SGODOT-424

Read `docs/design/alcatraz-dock-424/README.md` for the asset table, placement contract and review results.

The user-supplied `reference/landmark_alcatraz_v2.jpg` and `c_alc2.png` were inspected directly. Their dock/bench scale and soft matte palette guide the kit; the five requested furnishings are newly authored, including the blank welcome panel. `reference/layout.json`, `placement_points.json` and `alcatraz_island.gd` are read-only snapshots of #792 b16c31982f34a64cdd4f9c6683064edbf20837a0. Reference hashes and toolchain are in `provenance.json`.

`alcatraz_dock.blend` keeps five named collections and separately editable canopy uprights, seats, crate battens, continuous rope, sign parts and flowers. `build.py` deterministically rebuilds them and exports five local-pivot GLBs; it overwrites the source file, so preserve manual edits by updating the generator first. Palette values are sRGB hex converted to linear vertex colours. No images, hidden photo textures, alpha cards, animations, text or resource interactions.

From the branch root (reuse the installed tools):

```sh
flock /home/deck/gs66-render.lock blender --background --factory-startup --python "$PWD/tools/art/source/alcatraz_dock_424/build.py"
python3 tools/art/source/alcatraz_dock_424/verify_assets.py
python3 tools/art/source/alcatraz_dock_424/prepare.py
flock /home/deck/gs66-render.lock godot --headless --path output/alcatraz-dock-424/project --editor --import
flock /home/deck/gs66-render.lock godot --headless --path output/alcatraz-dock-424/project --script res://configure_imports.gd
flock /home/deck/gs66-render.lock godot --headless --path output/alcatraz-dock-424/project --editor --import
flock /home/deck/gs66-render.lock godot --headless --path output/alcatraz-dock-424/project --script res://verify.gd
DISPLAY=:0 flock /home/deck/gs66-render.lock godot --path output/alcatraz-dock-424/project --rendering-method mobile --rendering-driver vulkan res://review.tscn
```

Supply the live Xauthority path when needed. Copy only the five Godot-generated `alc_dock*.glb.import` files back to the asset directory after a first import. `verify_source.py` reopens the .blend without saving; run it through Blender. `package_review.py` requires Pillow/NumPy and adds labels outside native captures, then verifies the visible orange bridge pixels against the before view. `output/.gdignore` prevents the isolated project from entering the repository's global class cache; the source parent is already ignored by Godot.

The isolated project pins the b16c3198 scene, navigation, camera, lighting, dock, terrain and bridge. It also stages #801 / 07326180a's six nature prototypes and 114 replacement placements as identical before/after context. Those assets are not included in this PR, and their rock colour is not changed here. Only this kit's seven suggested instances are added for review.

For the Android smoke, copy the prepared project into `output/alcatraz-dock-424/android-project`, copy `android_review.gd` and `prepare_android.gd`, run the latter with Godot and export its `Android Alcatraz Dock QA` preset. It creates only `com.sensen.alcatrazdock424qa`. Use a private ADB wrapper and the repository `tools/android/run_test.sh` to run `android_smoke.py` at 360×800 / density 160 on the verified offline emulator. The fixture records current PID, complete avatar, five batches / seven instances, two real zoom-button taps and an asset view. The test restores the verified original emulator 720×1280 override / default density. It is not a full navigation or pinch test.
