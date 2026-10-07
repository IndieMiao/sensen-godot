# P0 UI kit

Phase 0 of the P0 UI rebuild (SGODOT-211 foundation, SGODOT-212 atomic components). Design authority is
Figma page "14 · UI semantic refactor" (481:53); locked components are listed in Plane SGODOT-197 and
must not change structure, role, entry point or key copy. Engineering specs: SGODOT-207 WP7-A / B / C.

## Tokens and theme

| File | Role |
|---|---|
| `docs/design/tokens/tokens-v2.json` | Design tokens, **draft** until the R1 revisions (WP1a / WP1b) are accepted. Never edit by hand. |
| `tools/ui/export_tokens_figma.js` | Read-only Figma export (run through the Figma MCP `use_figma` tool); writes nothing to Figma. |
| `tools/ui/gen_theme.gd` | `godot --headless --path . --script tools/ui/gen_theme.gd` regenerates the three files below. |
| `assets/ui/gensen_theme.tres` | Theme with every variation listed in `UiTokens` (`STYLE_*`, `BUTTON_*`, `PANEL_*`). |
| `modules/ui/kit/ui_tokens.gd` | `UiTokens` constants: `COLOR_*`, `OPACITY_*`, `SPACE_*`, `RADIUS_*`, `STROKE_*`, `SIZE_*`, `MOTION_*`. |
| `assets/ui/fonts/nunito_w400/700/800.tres` | Nunito weights; the theme default is 400, never the thin default instance. |

1 Figma px = 1 Godot UI unit: the project viewport is 360 wide with `canvas_items` + `expand`.

## Rules for kit components

1. **No literal values.** Colours, sizes, radii, spacing and durations come from `UiTokens`; text uses a
   `STYLE_*` variation; buttons and panels use `BUTTON_*` / `PANEL_*`. `tests/ui_kit/test_tokens_v2.gd`
   fails on `Color("…")`, `Color(r, g, b)`, `Color.html()` or a numeric `font_size` under `scenes/ui_kit`
   and `modules/ui/kit`. `Color.TRANSPARENT` and `UiKit.alpha(token, OPACITY_*)` are fine.
2. **Hit area 44.** Interactive controls are at least `SIZE_TOUCH` in both directions
   (`UiKit.ensure_hit_area`). Smaller visuals use `UiStyleBox.visual_height` (e.g. the 34 px compact
   command, the 26 px filter chip) so the drawn box stays centred in the 44 px control.
3. **Containers, not coordinates.** Build with Box / Margin / Flow / Grid containers and anchors so the
   later multi-size pass needs no rewrite. No absolute positions inside components.
4. **Data in, signals out.** Components take a plain Dictionary or typed fields (`title`, `quantity`,
   `state`, …) and emit signals; they never call the session, the server or P0Logic themselves.
5. **Scroll** with `TouchScrollContainer`, never a bare `ScrollContainer` (drags that start on a button
   must still scroll).
6. **Copy** is English and comes from the caller (LOCK-23); reasons for unavailable actions are written on
   the button itself (LOCK-10), not in a separate sentence.
7. **Class names** use the `Ui` prefix (`UiObjectHeader`, `UiItemCell`, …), one script per component
   under `scenes/ui_kit/`. Figma references use "main name + main node id", never descendant ids.

`UiKit` (`modules/ui/kit/ui_kit.gd`) has the shared helpers: `theme()`, `font(weight)`,
`label(text, style, color)`, `ensure_hit_area()`, `icon(texture, side)`, `alpha()`, `secs()`.

## Gallery and snapshots

- Register each component in `scenes/ui_kit/gallery_sections.gd` with a stable `id`, a title and its
  Figma main (`"ObjectHeader 483:196"`); `build` returns a Control at most 328 px wide showing every
  state (normal, pressed, disabled with reason, pending, selected, empty, …).
- `tools/run_tests.sh res://tests/ui_kit` checks layout snapshots (`tests/ui_kit/snapshots/<id>.json`,
  recorded on first run; refresh with `UPDATE_UI_SNAPSHOTS=1` and review the diff).
- Pixel shots need a desktop renderer: `tools/ui/shoot_gallery.sh --check` compares with
  `tests/ui_kit/snapshots/png/`, `--update` refreshes them, no argument writes to `output/ui_kit/`.
- Open `scenes/ui_kit/gallery.tscn` in the editor or run it to browse.

## Provisional values (`UiTokens.PENDING`)

SceneAction, tool badge, switch key, HUD, pin colours, Need Tile, joystick size, the blocked command
colour and the SegmentTab selected style follow the current Figma or the WP7 defaults until WP1a / WP1b
are accepted. Re-export tokens then; components should not need code changes.
