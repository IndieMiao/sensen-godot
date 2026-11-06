# Rebuild / review water-edge 430

`water_edge.blend` retains five named editable mesh collections and local pivots. `build.py` deterministically exports the five GLBs and copies the accepted #824 texture without changing it. The Blender material is an export stub; final appearance is the external Godot ShaderMaterial bound by generated `.import` files.

Run all Blender / Godot commands under `flock /home/deck/gs66-render.lock`. The verified tools are Blender 5.2.2 and Godot 4.7.2. Python geometry / image checks require NumPy and Pillow. `verify_geometry.py` reuses the repository's #824 GLB accessor reader.

1. `blender -b -t 2 --python /absolute/path/to/build.py`
2. `python3 tools/art/source/water_edge_430/prepare.py` stages an isolated project and archives only the pinned coast reference from Git. The commit must be available locally; fetch Zhao Yun's coast branch if needed. No coast files are committed here.
3. Godot `--headless --path output/water-edge-430-v11/project --editor --import`; then `--script configure_imports.gd`; then import again. Copy only generated water_edge `.import` / shader `.uid` back to the asset directory for first-time delivery. Existing generated UID must be retained on revisions.
4. Run `verify_geometry.py`, and Godot `--headless ... --script verify.gd`.
5. Run the isolated project with a real Mobile renderer, `--fixed-fps 30 --disable-vsync` for deterministic offline screenshots. `review.gd` substitutes a time uniform in QA only, renders 110 evenly spaced samples of the 5.5 s motion cycle. `package_review.py` creates annotated PNGs and a shared-palette GIF under docs/design, checks loop closure and adjacent-frame deltas.
6. `prepare_android.py` stages an isolated APK project, retaining the production TIME shader for actual Android rendering. Export with its dedicated preset, install only `com.sensen.wateredge430qa`; run `android_smoke.py` through `tools/android/run_test.sh` with a private ADB server. It checks 3 real button taps and full installed APK hash readback.
7. Cold-import the delivered resources in a new empty-cache project, run `verify.gd`, and compare all runtime file hashes. Cold import must not rewrite `.import` / UIDs. This review's results are in `docs/design/water-edge-430/`.

The review's 0.25 m opaque wet band is explicitly a temporary treatment, not a change to Zhao Yun's files. No sea material, gameplay scene or layout is delivered.

For v1.1 also run `measure_v11.tscn` in the staged Mobile project, then `measure_v11.py`. It checks actual alpha contours at 2 Hz, nominal shore width, inner-contact continuity and pile/shore peak-to-peak displacement. Diagnostic output changes albedo only; the production alpha formula is retained.
