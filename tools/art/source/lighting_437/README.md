# SGODOT-437 lighting review

Current revision is v1.2: one lighting preset references an Environment, one sun,
one sea ShaderMaterial and one far-material bundle (city / hills / bridge).
Runtime stays under `assets/landmarks/_shared/lighting/`. The original 432 / 434
shaders and materials are read-only dependencies. No global script classes.

Reference scripts / project settings are pinned to base
`4e2c401acf7940638690362fbe40a5176b623506`. 435 plants are staged only from
`a590b559dd6e776dc1047f858757c932c3a7cf2b` (#841). They are not delivered as new
lighting assets. `reference/provenance.json` retains original file hashes.

Use Godot 4.7.2, and hold `flock /home/deck/gs66-render.lock` for Godot / Android.
Reuse the verified SDK / JDK / private ADB. Set `LIGHTING_REVIEW_OUT` to
`output/lighting-437-v12` for the commands below; omitting it uses the original
output location for preparation and Android tools.

1. Run `python3 tools/art/source/lighting_437/prepare.py`. The isolated project
   is `<output>/project`; output remains excluded from parent Godot class scans.
2. Import with `godot --headless --editor --import --path <project>`. On first
   creation, retain generated runtime `.gd.uid` files in the source directory.
   Then run `godot --headless --path <project> --script verify.gd` (79 checks).
   One warning is intentional: assigning an unrelated Resource must leave the
   valid preset and applied lighting intact.
3. Run on the actual display with `--fixed-fps 30 --disable-vsync -- --benchmark`.
   It captures the original noon, three presets, and shadow-off controls; then
   interleaves original / noon / morning / dusk for three timing cycles.
   45 warm-up + 90 sampled frames per block; reverse the middle cycle.
   Water / foam TIME is frozen only in desktop QA. Original and shared noon
   match exactly in this fully sea-covered view; their background colours differ.
4. Run `prepare_android.py` with the same output environment. Import and export
   the `Android Lighting QA` preset from `<output>/android-project` to
   `../lighting-qa.apk`. Keep `export/android/shutdown_adb_on_exit=false`.
   Install only `com.sensen.lighting437qa` on the verified emulator; use 360×800
   and density 160. Invoke `tools/android/run_test.sh --serial SERIAL
   com.sensen.lighting437qa -- python3 tools/art/source/lighting_437/android_smoke.py`
   with private `$ADB` and the same output environment. Three real taps verify
   all companion palettes switch and return to noon; full APK readback must
   match. The script restores screen settings, and the runner stops the QA app.
5. Run `package_v12.py` using a Python with NumPy / Pillow. It writes the full
   triptych, unretouched individual captures, fixed sample polygons and metrics,
   timing / Android records and hashes into `docs/design/lighting-437/v12/`.
   Brightness is weighted display RGB Y-prime, not physical linear luminance;
   sampled regions are not a per-pixel bound over the full scene.
6. For cache-free loading, create a minimal project with only the lighting
   directory, the unchanged 432 / 434 shader files + UIDs, and `verify.gd`.
   With no `.godot` or autoloads, run the checks **before** any editor import.
   Also copy the full staged project excluding `.godot`, cold import, and rerun
   checks. Compare runtime filenames / SHA at every step; confirm protected
   original landmark and shared-kit paths have no diff against the base.

The fixture uses 360×800, orthographic width 6.72 m, pitch 43°, yaw 14.5°,
assembly yaw 65°, six 2 m shore slots, fixed 1.75 m avatar and six small 435
plants. The synthetic grass blocks receive but do not cast shadows, avoiding
low-angle self-shadow striping on flat QA geometry. All presets use this same
fixture and camera. Backdrop targets are bound to the production rig; captures
exercise the same runtime switching path rather than QA-only recolouring.

The initial v1 `package_review.py` and root review records are historical.
The v1.1 `docs/design/lighting-437/v11/` records the class-cache / noon background
fixes; the current v1.2 includes those fixes plus the visual revision.
