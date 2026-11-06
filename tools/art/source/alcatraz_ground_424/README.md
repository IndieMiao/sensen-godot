# Alcatraz optional ground detail / SGODOT-424

Runtime kit: `assets/landmarks/alcatraz_island/ground/`. No Blender geometry is generated or edited in this task. Editable sources are `generate.py`, the shader, materials and JSON parameters; the owner's fixed palette snapshot is in `reference/palette.json`.

1. Fetch owner #792 to ensure commit `bf0c31b1c871011008b455434d167224d14de59c` is present. The art branch itself is based on `fc19d492eabbbe96105726c5a627c30d98b4e445`.
2. Run `generate.py` with Python + NumPy/SciPy/Pillow. Seed 4241106; outputs exactly two 1024 RGB DATA textures. This regenerates textures, not hand-edited shader/parameters.
3. `python tools/art/source/alcatraz_ground_424/prepare.py` stages the fixed host, unchanged avatar dependencies and only this new ground directory under ignored `output/alcatraz-ground-424/project`. Source assets and original owner files stay separate.
4. Under `flock /home/deck/gs66-render.lock`, run Godot `--headless --path output/alcatraz-ground-424/project --editor --import`; then `--script configure_imports.gd`, then import again. On first creation, copy the generated ground PNG `.import` and shader `.uid` back to the runtime folder; later runs reuse those IDs.
5. Run Godot 4.7.2 with the same flock and display access, `--path output/alcatraz-ground-424/project --rendering-method mobile`. The QA script makes four optional material assignments only; six sets of before/zero/after images and validation appear under `captures/`.
6. Run `verify.py` with NumPy/Pillow, then `package_review.py` with Pillow. Native 360×800 frames are not scaled or repainted; caption bands are external to the frames. High-resolution views use SubViewport to avoid the Deck display size cap.

The host contains animated sea shading. Matched desktop comparisons freeze only the QA clock after assembly; sea code remains byte-identical. Revert assignments to the original `paint` to remove this optional finish completely. Shader strength zero is also checked, with minor original StandardMaterial vs shader rounding differences documented.

Android: copy the prepared project to `android-project`, copy `prepare_android.gd` and `android_review.gd`, execute the prepare script, export `Android Alcatraz Ground QA`. Isolated package `com.sensen.alcatrazground424qa`. The verified local setup is API37 / software Vulkan on emulator-5592 and private ADB5071. Run via `tools/android/run_test.sh` with `android_smoke.py`; this checks the current PID, all four material targets, three rendered positions and two real zoom-button taps. It does not establish navigation or physical-phone performance. The script restores the verified prior display 720×1280 / default density; if using another emulator, record and adjust this before running.

Full installed APK readback and packaged resources are verified separately. Art acceptance, scene integration, Android gameplay acceptance and release remain separate decisions. No production app, model, UV, palette source, navigation or water is changed by this kit.
