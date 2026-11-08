# SGODOT-218 editable market props

`build.py` supports `--stage blockout` and `--stage final`. Each module has a named editable `.blend`, a floor-centre pivot, and one merged exported mesh with matte vertex colour. Sources are excluded from runtime scanning by the existing tools/art policy.

```bash
flock ~/gs66-render.lock blender --background --python-exit-code 1 --python tools/art/source/market_props_218/build.py -- --stage final
python3 tools/art/source/market_props_218/prepare_review.py --template <verified-avatar-benchmark> --out <isolated-review-dir>
flock ~/gs66-render.lock godot --headless --path <isolated-review-dir>/project --editor --import
flock ~/gs66-render.lock godot --path <isolated-review-dir>/project --rendering-method mobile --rendering-driver vulkan --disable-vsync --max-fps 60
python3 tools/art/source/market_props_218/verify.py --output <isolated-review-dir>/geometry-validation.json
python3 tools/art/source/market_props_218/package_review.py --captures <isolated-review-dir>/captures --version v1 --out docs/design/market-props-218-2026-11-08/v1
```

After import, synchronize this kit's engine-generated `.glb.import` files back from the isolated project, preserving UID and shared material mapping. Use the caller's private ADB environment and release the shared render lock after each command. Verification needs NumPy; packaging needs Pillow. The review template supplies only the existing avatar module and its assets, no gameplay/server state.

References: incoming `SGODOT-218_market_room45_v2.1.png`, confirmed on 2026-11-08; v1.1 prop sheet for detailed silhouettes. New dispatch dimensions override the illustrative reference scale. Geometry helpers are reused from the existing alcatraz_far_424 generator; no existing art asset is rewritten.
