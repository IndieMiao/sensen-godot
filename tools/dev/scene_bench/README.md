# Shared rendered scene benchmark

Owner: Zhao Yun / 赵云, SGODOT-172. Contract introduced by the art director's first review on SGODOT-171. Consumers provide scene/layout data; extend this core through the parent card so both artists use the same movement test.

This isolated project uses the accepted Basic Room's **same default Avatar fixture**, `CharacterBody3D`, capsule radius **0.21m**, total height **1.25m**, speed **3.75m/s**, floor snap **0.20m**, and camera-relative joystick/keyboard movement. The camera reads each scene's reference camera so proportions and art comparison use one view. Production saves, outfits, network autoloads and export presets are not loaded.

## Run

From the repository root with Godot 4.7.2, FFmpeg/FFprobe and a real desktop display:

```sh
python3 tools/dev/scene_bench/prepare.py standard_room_5
godot --headless --editor --path output/scene-bench/standard_room_5/project --import --quit
python3 tools/dev/scene_bench/run.py standard_room_5 --record
```

Import may be headless; **tests and recording may not**. Supply the executor's actual `DISPLAY` and `XAUTHORITY` if the shell does not inherit them. The runner deliberately rejects headless execution. `--project` and `--output` accept alternate staging/evidence directories. Without `--record`, only the rendered checks and stills run.

For manual WASD / floating joystick / zoom inspection:

```sh
godot --path output/scene-bench/standard_room_5/project -- --slug standard_room_5
```

The authoring interface is `assets/rooms/<slug>/layout.json`, and the loaded scene is `scenes/<slug>/<slug>_art.tscn`. All physical blockers must belong to that art scene. The harness does not silently add boundaries or bypass scene collisions. A static painted door can retain its visual panel while the **collision opening** is passable; describe that convention in the scene handoff.

## Layout additions

Add a top-level `spawn: [x,y,z]` and `bench` dictionary:

- `floor_y`: expected floor surface at spawn.
- `route`: **6–10** `{name, position}` waypoints, in traversable sequence. `capture: "main"` and `capture: "door"` designate the two required landmark images. The route begins at spawn and never teleports between waypoints. Each segment must arrive within **3 seconds** using real physics movement. For elevated paths, include the actual target Y.
- `blocked`: `{name, from, to, target, seconds?}` probes. `from` must be clear floor; `to` lies beyond/inside the expected blocker; `target` is a unique node-name substring. The driver must stop before the target and identify the physical blocker by slide contact or torso ray. Use probes for furniture, walls, rails and every open floor edge.
- `gaps`: `{name, from, to, measure: [a,b], minimum: 0.70, width}`. `measure` contains points on opposing collision faces at torso height (usually floor + 0.65m). Width is measured from the midpoint against **live physics**, then the capsule traverses `from → to`. Use 0.80m where the child card requests it. `width` is the author's expected measured width; the test rejects missing faces and inaccurate measurements.
- `entrance`: `{inside, outside}` positions on continuous supporting floor on each side of an authored entrance gap. Exit and reentry are driven through the gap. Open dioramas can use one controlled entrance segment plus bounded remaining edges.
- `slide`: `{from, direction, tangent, seconds: 0.6}` against a wall, requiring contact and >0.45m movement along the free tangent.
- `input_start`: a clear point with room for a brief joystick gesture.
- `scale`: `door`, `counter`, `chair`, `table`, each `{height, source, reason?}`. Heights are measured in metres from the supporting floor in the editable source, except door clear height. Differences from Basic Room must be within ±15%, or have a specific documented reason. An inapplicable category must explicitly explain why; do not invent a measurement.

See [the Basic Room calibration fixture](fixtures/basic_room.json) for concrete fields. That fixture overrides only harness inputs and does not edit the accepted Basic Room. Its historically closed doorway is exempt from the new entrance check **only during baseline calibration**; new scene cards must supply `entrance`.

The measured fixture head top is approximately **H = 1.7455m**, including the default rigid hair mesh, derived from the actual rig's transformed mesh bounds after idle settles. Blender source measurement gives Basic Room door **2.33m**, counter **1.1525m**, chair seat **0.685m**, tabletop **1.135m** (heights above 0.082m floor). Ratios are reported from the live H; capsule height is a movement shape, not the visual head height.

## Evidence and limits

`result.json` contains every PASS/FAIL and route segment endpoint, timing and collision evidence. `scale-measurements.json` records H, fixture dimensions and per-category ratios. `spawn.png`, `main.png`, `door.png` show the character; `collisions.png` visualizes actual shape debug meshes. `walkthrough.mp4` is an **unaccelerated 15-second X11 capture**, with PID-checked recorder handshake, complete-route timing, FFprobe metadata and extracted first/middle/last frames. Each sample is decoded to grayscale and must be nonblack/nonuniform; the runner rejects black desktop grabs even when encoding and route checks pass. Visually inspect the samples as well. The app is closed after each pass. Empty/incomplete schema is a failure, not a pass.

Input release and idle/run checks inject Godot input events through `Input.parse_input_event` in the live viewport. The route driver supplies movement direction to the same controller; it does not set positions to produce successful arrivals. Independent collision probes reset their initial state, as documented in JSON. This is a desktop behavioral/scale check, not Android touch or physical-phone performance acceptance.

The initial core was validated on unmodified Basic Room: 30 rendered checks, eight sequential route legs, body visibility, idle/run progression, collision bounds, live aisle measurement and 15-second video. A controlled negative run moved one route target inside the table, aimed a required blocked probe at free floor, and claimed an impossible 2.5m gap: all three were rejected. See `evidence/basic-room-negative-control.json`. The test core intentionally reports the current uncorrected Standard Room as failed until its new bench data and boundaries are authored.
