# SGODOT-434 source and review

Six `.blend` files retain the original named bridge cables / piers, building
faces and hill layers. Source materials show the authored palette; GLB export
converts material roles to three linear palette weights for the reusable
shader. All parts stay at a local bottom-centre pivot, with no review placement
baked into geometry. `reference/provenance.json` pins source file hashes and
the sea/coast/foam commits used only in isolated review staging. Fetch these
pinned commits first if they are absent from the local Git object database.

`build.py` reopens Huang Zhong's original source cards, creates the variants and
exports only the new shared directory. Rebuilding overwrites these six new
Blender sources; keep manual edits separately and fold intended changes into
the generator before rebuilding. It never saves an Alcatraz source or asset.

Verified tools: Blender 5.2.2, Godot 4.7.2, NumPy/Pillow for independent checks.
Run Godot / Blender / Android through `flock /home/deck/gs66-render.lock`.

1. Run Blender in background with `--threads 3 --python-exit-code 1 --python
   tools/art/source/far_backdrop_434/build.py`.
2. `python3 tools/art/source/far_backdrop_434/prepare.py` stages an isolated
   project under `output/far-backdrop-434/project`, archiving pinned #837 sea
   and #831 coast only into `output/`. It copies the accepted #833 foam from
   the branch base and a fixed 1.75 m avatar fixture.
3. Godot `--headless --editor --import --path <project>`. On a first build run
   `--headless --script configure.gd --path <project>`, import again, then copy
   generated `.import` / shader and importer `.uid` files from the staged
   far_backdrop directory back to the runtime directory. On future clean
   imports, use the already committed import files.
4. `verify.gd` in the project validates imported surfaces, material bindings,
   null root scripts, UIDs and rendering budget. `verify_assets.py` independently
   parses GLB accessors, weights and actual triangle positions; the bridge,
   high city and hills A match the original triangles to 1e-6 m.
5. Run the project on a real display with Mobile / Vulkan and `--fixed-fps 30
   --disable-vsync`. Two default cameras, cards-off controls, bridge recolour,
   heavy fog and an original-projection pixel comparison are captured. Sea
   and foam TIME are frozen only for matched desktop control captures.
6. `package_review.py` labels the two 360×800 images and checks that card
   visibility / recolouring / fog change pixels in the expected horizon band.
   Media are under `docs/design/far-backdrop-434/`, excluded with `.gdignore`.
7. `prepare_android.py` stages the isolated `Android Far Backdrop QA` preset.
   Import and export to `../far-backdrop-qa.apk`; use private ADB and keep
   `export/android/shutdown_adb_on_exit=false`. Install only
   `com.sensen.farbackdrop434qa`, set 360×800 / density 160, then use
   `tools/android/run_test.sh --serial SERIAL com.sensen.farbackdrop434qa --
   python3 tools/art/source/far_backdrop_434/android_smoke.py`. Four real taps
   switch both compositions and bridge colours; the complete installed APK
   is read back. The runner stops the target; the script restores
   720×1280 / default density. This is emulator rendering, not phone timing.
8. Cold-import a fresh staged copy without `.godot`, rerun `verify.gd` and
   compare all runtime file names / SHA hashes. Preserve imported UIDs and
   `nodes/root_script=null`; no new texture compression setting is needed.

The only runtime dependency is this directory. The 432 sea, 426 coast, 430 foam,
avatar and scene are review context, not additional runtime kit files. The
432 bay copy uses render_priority=-100 so the otherwise opaque far sea renders
before the negative-priority cards; its shader and preset files are unchanged.
