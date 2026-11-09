# SGODOT-449 Steam candidate

Scope: Steam particle parameters, billboard material and one128²RGBA soft-edge image. Pot/soup meshes, both animation blocks and `steam_lid_clearance.gd` stay unchanged; the shader retains the exact original `above_lid` expression.

Reproduction (all engine commands hold the shared render lock):

```bash
python3 tools/art/source/steam_449/make_texture.py
python3 tools/art/source/steam_449/prepare.py --out <isolated-output>
flock ~/gs66-render.lock godot --headless --path <isolated-output>/project --editor --import
STEAM_REVIEW=<capture-output> STEAM_HDR=1 STEAM_HDR_LINEAR_FIX=1 flock ~/gs66-render.lock godot --path <isolated-output>/project --rendering-method mobile --rendering-driver vulkan --fixed-fps 30 --disable-vsync
```

The temporary host comes from the pinned farm-dev revision in reference/base.json. It is copied into the isolated project, with only BOX enlarged to200×220 at80,110. Diagnostic environment options demonstrate the host alpha-composition issue: STEAM_HDR, STEAM_PREMUL, STEAM_HDR_LINEAR_FIX. They change only the review fixture; no host/runtime code is delivered. `STEAM_SINGLE=1` isolates a puff for diameter measurements; leave it unset for the production3-puff stream. The parent preview supplies43°/500px/m, the native warm light and cream/white background controls. Source shader logical frame coordinates track the whole layer when Queue moves it down14px.

`verify.py --out <isolated-output>` checks immutable assets and animations, native lid-mask expression, pixel alpha/envelope over90frames, single-puff diameters and authored interval/drift/rise. It expects refined_preview and single_puff captures in that directory, and derives the pixel measurements directly from their RGBA frames. Pixel alpha must be recorded from the full-precision diagnostic viewport; the default Mobile2-bit-alpha target is explicitly not used to certify0.5/0.6 opacity.

This is an isolated candidate. Real-overlay verification is pending the programmer's expanded-frame branch. Final review images must be from that branch, including correct transparent-target composition; do not call the isolated images final game acceptance.
