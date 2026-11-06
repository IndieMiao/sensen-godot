# SGODOT-437 lighting review

Current revision is v1.4: one lighting preset references an Environment, one sun,
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


## v1.3 colour and shadow review

Use `LIGHTING_REVIEW_OUT=output/lighting-437-v13` with the same preparation,
import and resource checks. Run the desktop review with
`--fixed-fps 30 --disable-vsync -- --benchmark --shadow-probe`, then run
`package_v13.py` with NumPy / Pillow. Evidence goes to
`docs/design/lighting-437/v13/`.

Only the morning ambient colour and dusk sun/ambient colours, energies and
approved sun yaw change. Dusk pitch stays -18 degrees; all shadow properties,
noon/morning angles, backdrop parameters, geometry and materials are retained.
The v1.3 package reports mean RGB, weighted display brightness and HSL saturation
in explicitly outlined regions. The rock side previously sampled as a shadow
now receives direct sun; the new shaded-facet region is separately disclosed,
and v1.2/noon measurements at those exact coordinates are included.

The optional shadow probe runs after the coast captures and timing. It stages
an existing street-kit bench without changing the source asset and uses a
separate floor above sea level. The coast avatar uses a blob shadow; casting is
enabled only on its meshes in this diagnostic to show the full-height
projection. No production avatar or shadow setting changes. Both real shadows
and projected direction are recorded; the probe is excluded from coast budget
and timing measurements.

This colour-only revision reuses the already verified runtime switching path;
Android v1.2 results remain historical and are not relabelled as v1.3 tests.

## v1.4 dusk highlight review

Use `LIGHTING_REVIEW_OUT=output/lighting-437-v14` for preparation. Remove only
that isolated project's `.godot` cache, then cold import and run the unchanged
79 resource checks. Capture with `--fixed-fps 30 --disable-vsync --
--dusk-v14 --shadow-probe`. This early review branch renders v1.3's exact light
parameters, then the current production dusk resource at the same frozen clock
and camera. It also rechecks the authorized horizontal light adjustment on the
existing separate shadow probe. It does not recapture or change noon/morning.

Compare all 16 runtime resource hashes before/after import and against source;
write that record to `<output>/cold-validation.json`. Run `package_v14.py` with
NumPy / Pillow. The only review board is `v14/golden-dusk-v13-v14.png`; the raw
current 360x800 capture and explicit fixed sampling polygons accompany it.
The recreated v1.3 image is pixel-identical to the committed v1.3 capture.
Shadow-probe images stay in ignored output; its direction is recorded in the
render JSON. Android and timing evidence from earlier versions remains
historical; this revision adds no geometry, shading work or runtime logic.
