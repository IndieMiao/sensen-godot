# SGODOT-432 reproducible material review

The editable source is the native shader and two `.tres` files in
`assets/landmarks/_shared/sea_backdrop/`. No Blender model, texture bake, layout or
game scene is needed. `reference/provenance.json` pins the original algorithm,
coast owner revision and accepted foam. The coast archive is staged only under
ignored `output/`; it is not copied into the delivered runtime kit.

Run from the repository root. Use Godot 4.7.2 and hold
`flock /home/deck/gs66-render.lock` for Godot and Android sessions. Python media
packaging needs Pillow, NumPy and ffmpeg.

1. `python3 tools/art/source/sea_backdrop_432/prepare.py` creates the isolated
   `output/sea-backdrop-432/project`. Fetch the pinned coast commit if absent.
2. Run Godot `--headless --editor --import --path` on that directory, then
   `--headless --script verify.gd --path` for resource checks.
3. Launch the same project with an actual display, Mobile renderer,
   `--fixed-fps 30 --disable-vsync`. `review.gd` captures both 360×800 openings,
   80 frames per preset, no-foam motion controls, and original-shader parity
   controls at t=0 and t=3.5. Desktop QA alone substitutes `TIME` with a uniform;
   samples are at t=i/20 s, preserving the production speeds. The 4 s GIF is an
   excerpt; its restart is not claimed to be a seamless wave cycle.
4. `package_review.py` labels the captures, encodes and decodes the GIF, checks
   duration and visible sea movement without foam. Media go only under
   `docs/design/sea-backdrop-432/` (excluded from Godot with `.gdignore`).
5. `prepare_android.py` stages a separate export project. Import and export its
   `Android Sea Backdrop QA` preset to `../sea-backdrop-qa.apk`. Keep
   `export/android/shutdown_adb_on_exit=false`. Install only
   `com.sensen.seabackdrop432qa` on the verified emulator, using a private ADB
   server. Use 360×800 / density 160, then run `android_smoke.py` through
   `tools/android/run_test.sh --serial SERIAL com.sensen.seabackdrop432qa -- ...`.
   It uses four real button taps, checks current process state and reads the
   complete installed APK back. Android uses the production `TIME` shader.
   The script restores 720×1280 / default density; the runner stops the app.
6. Copy the staged project into a fresh directory excluding `.godot`, import
   and rerun `verify.gd`. Compare every delivered resource hash and filename
   before/after. Native shader/tres resources need no `.import`; preserve the
   generated shader `.uid`. Verify Alcatraz and the accepted foam against the
   branch base before committing.

Camera: orthographic width 6.72 m, pitch 43°, yaw 14.5°; fixture rotated 65°.
Six 2 m shore slots, one 1.75 m character. Formal #831 v1.1 cool stone / warm
wood materials use water_level=0.20, wet_height=0.25; no simulated wet-band
shader remains. Two seaward pile rings follow the revised four-pile dock at
local fixture X=-2±0.72, Z=7.66. Sea is Y=.20; foam is Y=.218. Existing owner
runtime resources are not edited.
