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

## Components (SGODOT-212)

| Class | Figma main | Notes |
|---|---|---|
| `UiObjectHeader` | ObjectHeader 483:196 | title + quantity column, optional state line and effect sentence |
| `UiFactRow` | Fact 483:222 · Cost 483:225 | `Kind.FACT` / `Kind.COST`; have / need counts are NEED-TILEs (LOCK-10), not fact rows |
| `UiItemRow` | ItemRow 483:228 | icon, title / state / effect, quantity column; display only |
| `UiItemCell` | Compact/InventoryCell 633:41278 · QuickSlot 633:41279 · Kitchen/Cell 655:58506 · GearSlot 663:61299 | one class, `Density` picks the main; `State` DEFAULT / SELECTED / EMPTY, plus LIFTED / DROP_TARGET / ZERO on QUICK; `pinned` draws LOCK-05. Own GestureArbiter (QUICK: SLOT, others: CELL): `tapped` only for its tap, every other outcome via `gesture(outcome)` (global `pos`) |
| `UiCommandButton` | CommandButton 483:216 · Compact/Command 633:41273 | connect `activated`; `reason` = unavailable look with the reason as label, still tappable (`unavailable_pressed`, LOCK-10); `phase` / `track()` follow `CommandLifecycle` (submitting ignores taps, pending dims); `fit_text` narrows the side padding so a long reason fills a full-width row |
| `UiNavButton` | NavigationRow 483:217 · Compact/Navigation 633:41276 | row with right chevron, or compact `Label ›`; never jumps the player (LOCK-08) |
| `UiDismissButton` | Dismiss 483:220 | quiet close text; not on the Energy card (LOCK-09) |
| `UiCloseButton` | Close 483:336 | 44 round, 20 px glyph |
| `UiFilterChip` | Compact/Filter 633:41280 | toggle chip, 26 drawn in 44; `UiFilterChip.row()` builds a grouped row |
| `UiSegmentTab` | Tab 483:322 · Compact/Kitchen/Mode 655:58504 | 2–3 way mode switch with optional count; selected is never the command green (LOCK-13) |
| `UiBadge` | StateBadge 483:324 | short state word pill |
| `UiEmptyState` | EmptyState 1234:87237 | Kind PANEL (56 grey disc, one line, optional NavigationRow) / ROW (one line in a list); navigation never jumps (LOCK-08) |

### World display (SGODOT-222)

| Class | Figma main | Notes |
|---|---|---|
| `UiNeedTile` | NeedTile 1090:78003 | LOCK-10: L / M / S; met / short / count; ring = have ÷ need rounded down to 10 %; `UiNeedTile.group()` wraps; tap shows a `UiNeedSource` |
| `UiNeedSource` | NeedSource 1092:77266 | one source line + `Show ›` (camera only, LOCK-08); `UiNeedSource.popup()` anchors it above the tile |
| `UiHud` | HUD 1143:103373 | LOCK-06: two rows; stands alone (`apply(state)`, `P0Logic.hud_state`); Energy colour by the next action's cost, never by percentage; location chip = actual place |
| `UiTodayPanel` | TodayPanel 1145:81715 · TodayRow 1145:81714 | LOCK-06: ≤ 3 rows under the chips; Show only moves the camera; done / short rows |
| `UiEnergyCard` | Energy 1094:77504 | LOCK-09: `card()` (one button `Free to do now`, 2×2 guide-only tiles, At home away from home) and `panel()` (under the HUD chip) |
| `UiEnergyTile` | EnergyTile 1093:77292 | guide-only RECOVER tile; unavailable shows the reason, no link |

## Panel parts (SGODOT-225)

| Class | Figma main | Notes |
|---|---|---|
| `UiDrawer` | Sheet 483:190 as the bag / counter drawer (BAG-2-2, FARM-6) | bottom-pinned, 24 top corners, content in `body` inset 12 like the Bag layout, `height` in logical px, `safe_bottom`; slides up over `MOTION_DRAWER_MS`; a 48 px swipe down or a quick flick on the drawer itself emits `close_requested`. The scrim, Back and scrim taps stay with `ModalStack` / the P0 modal host |
| `UiDialogueCard` | head of KeeperGreeting 1205:83238 / ResidentDialogue 1213:83392 | the shared "portrait + name strip": rounded portrait (`RESIDENT_PORTRAIT` 92×178, `KEEPER_PORTRAIT` 100×220), `Name · Role ›` or `Role · Name` + `place` line, `extra` row, speech bubble (`line`), `content` slot for options. `profile_link` makes the portrait and name tappable (`identity_pressed`, 44 hit area). 2A builds the keeper greeting on it |
| `UiRequestCard` | ResidentRequestCard 1211:83296 (LOCK-18) | requester head, the line, `Bring` NEED-TILEs, Reward / Deliver to rows, one primary (Accept / Deliver; `reason` = unavailable) and `Not now`; `action_pressed`, `dismissed`. Full lifecycle is WP4 |
| `UiResidentBar` | ResidentDialogue 1213:83392 (LOCK-18) | UiDialogueCard + affinity row (stage pill, 10 % meter, `have/need · next Stage`) + Gift (primary) / Request (secondary, `request_label`), Today’s meal / Recipe lesson only when available. A reason on either button makes it unavailable with the reason as label and stacks both (Choices=Stacked, `fit_text`). Data from `P0Logic.resident_bar` (SGODOT-228) |
| `UiBagHeader` | BagHeader 1225:83885 (LOCK-12 / 13) | Bag N/cap \| Gear switch (`side_changed`), `Sort · …` on the Bag side only (`sort_pressed`, `sort_label`), capacity bar under the Bag segment, amber from 90 %; `show_tabs = false` for the gift drawer (count only) |
| `UiGearRow` | Gear candidate rows of BAG-2 · Gear (LOCK-13) | icon · name · state (`✓ Equipped` badge / `Owned` / greyed gate and source) · effect, one action from the item-info spec (`action_pressed(id)`); `UiGearRow.equipped_badge()` |
| `UiProfileTopBar` | ProfileTopBar 1233:107734 (LOCK-22) | `Kind.SELF` back + Profile + gear (`show_settings`; hidden in P0), `Kind.OTHER` back + name + ··· (`more_pressed(anchor)`) |
| `UiProfileMoreMenu` | ProfileMoreMenu 1233:107735 (LOCK-22) | rows by relation: default Unfollow / Block / Report, `close_friend` adds Remove Close Friend, `blocked` only Report (P2; `picked(id)`) |
| `UiSkillCard` | SkillRing 1251:109246 (LOCK-22) | 107×56 raised card, 40 ring floored to 10 %, icon on the cream core, skill + `Lv3`; `pressed` |
| `UiFarmCard` | Farm overview of PROFILE-1 (LOCK-22) | 62 thumbnail, farm name, `Level N`, one status line (empty lines hide) |
| `UiInventoryGrid` | Bag layout five-column grid (LOCK-12 / 15) | `TouchScrollContainer` of INVENTORY cells on the quick bar pitch (52 + 4, rows 58 apart), filled cells then dashed empties to `capacity`. Hooks for the counter (2A): `on_select` (Callable, or `item_selected`) on tapping a filled cell, tapping an empty cell clears; `sell_mode` + `can_sell` list only what that counter takes ("Sell here"). `filter` for category chips; other cell gestures come out of `cell_gesture(item, outcome)`. `density` KITCHEN for the Experiment page (items may carry `status`, `marked`) |

Positions inside a fixed-size main (e.g. the InventoryCell icon at y 10, the 3 px pill inset) are private
constants in the component script, each citing its main; everything shared comes from `UiTokens`.
Glyphs that are tinted in code (pin, check, close) are white SVGs exported from Figma under
`assets/ui/kit_icons/`.

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
