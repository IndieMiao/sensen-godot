# SGODOT-437 lighting review

Runtime source is the three native `.tres` presets, `lighting_preset.gd` and the
small `lighting_rig.tscn` / script. No Blender source or new texture is required.
The reference directory retains the actual Alcatraz / Griffith scripts and
project rendering settings at base `4e2c401acf7940638690362fbe40a5176b623506`;
`provenance.json` records their SHA-256 hashes.

Use Godot 4.7.2 and hold `flock /home/deck/gs66-render.lock` for all Godot and
Android sessions. Existing SDK/JDK and private ADB are reused.

1. `python3 tools/art/source/lighting_437/prepare.py` stages an isolated project
   under `output/lighting-437/project`. It copies 426 coast, 430 foam, 432 sea and
   434 cards from the branch base. 435 plants come from the pinned review-only
   commit `a590b559dd6e776dc1047f858757c932c3a7cf2b` (#841); fetch it if needed.
   Those kits are neither changed nor added to the lighting runtime directory.
2. Run `godot --headless --editor --import --path <project>` and then
   `godot --headless --script verify.gd --path <project>`. On the first import,
   copy the generated lighting `.gd.uid` files back to the runtime directory.
   The verification compares every stored noon Environment setting, every
   original sun shadow setting, and preservation of Griffith's distinct shadows
   while switching all three presets. It also checks independent Environment
   copies and disabled costly effects / per-frame callbacks.
3. On the actual display, run Mobile with `--fixed-fps 30 --disable-vsync --
   --benchmark`. The original noon control and new noon must match exactly.
   Three default views and shadow-off diagnostic controls are captured. Sea and
   foam clocks are frozen only in desktop QA. The timing section measures
   viewport CPU/GPU time: 45 warm-up + 90 sampled frames per block, three
   interleaved cycles with reverse ordering in the middle. It is uncapped
   rendering with a fixed simulation delta, not phone FPS.
4. `package_review.py` requires NumPy/Pillow, labels the three 360×800 images,
   summarizes timing and records PNG hashes under `docs/design/lighting-437/`.
   Bulk per-frame timings stay under ignored `output/`.
5. `prepare_android.py` stages a separate Android export project. Import and
   export its `Android Lighting QA` preset to `../lighting-qa.apk`. Keep
   `export/android/shutdown_adb_on_exit=false`, and install only
   `com.sensen.lighting437qa` on the verified emulator. At 360×800 / density 160,
   run `tools/android/run_test.sh --serial SERIAL com.sensen.lighting437qa --
   python3 tools/art/source/lighting_437/android_smoke.py` with private `$ADB`.
   Three actual taps cycle noon → morning → dusk → noon. PID, draws, screenshots
   and full installed APK readback are checked. The script restores size/density
   and the runner stops this QA app.
6. Copy the staged project without `.godot` into a new directory, import and
   rerun `verify.gd`. Compare runtime filenames and SHA before/after, and verify
   the original Alcatraz / Griffith paths against the branch base before push.

The fixture uses the 434 camera: 360×800, width 6.72 m, pitch 43°, yaw 14.5°,
assembly rotation 65°. The six 2 m shore slots and frozen 1.75 m avatar stay fixed.
Six small 435 plants expose shaded surfaces and long shadows without blocking
the bridge. The two synthetic grass blocks receive shadows but do not cast:
this avoids self-shadow banding on the fixture's perfectly flat faces at low
sun angles, without changing the rig's shadow settings or any source kit.
The sea copy retains the review render_priority=-100 used by 434. Far cards,
sea and foam keep their accepted material colours. This scene is QA only;
there is no production layout or game integration.
