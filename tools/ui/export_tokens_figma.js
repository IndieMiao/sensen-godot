// READ-ONLY Figma exporter for docs/design/tokens/tokens-v2.json (SGODOT-207 WP7-A, SGODOT-211).
// Run through the Figma MCP `use_figma` tool on file 5SVgfevrLzZXqD83uyPgmV. It never writes to Figma,
// unlike the frozen generator bundle and patch scripts under docs/design/ui-refactor-2026-10-06/figma-plugin/
// (SGODOT-197 LOCK-28). Pipe the returned object into tools/ui/save_tokens.py (pretty-prints `compact`, checks
// `fnv1a` and `bytes`, writes the tokens file), then run tools/ui/gen_theme.gd.
// Values Figma does not hold yet come from CONST below, each with its source.
// 10-27: the file moved to 5SVgfevrLzZXqD83uyPgmV (page 14 = 5:4) and every node id changed; the ids below are the new
// file's, matched by name (不知火舞 340 d7c11d35 / 047b9fd6). HUD and Compact/Command are component sets there, so node()
// takes their variants' ids. sheetSurface reads InformationSheet (0.97), not the Sheet master (1).
const CONST = {
  // Fallback for gameplay plan v2 §16.1 rarity dots if the semantic rarity/* variables are missing.
  rarityRare: '#A98BD6',
  // HUD energy chip fills are hard-coded in HUD 9:100203.
  energyHudLight: '#F4D27A', energyHudDeep: '#C9962A',
  // Fallback only: page 14 now defines color/scrimDrawer and color/scrimModal (alpha = scrim opacity).
  scrimDrawer: 0.18, scrimModal: 0.32,
  // Need Tile wrap gaps (column / row) of grouped tiles, plan §1.5 q(8) "成组用换行布局", as laid out in CRAFT-1.
  needTileGapX: 10, needTileGapY: 12,
  // Today panel position under the HUD (HUD-2 overlay frame), SGODOT-222.
  todayPanelX: 10, todayPanelY: 96,
  // Motion: Figma only has the 150 ms dissolve; others from plan §16 / §10 or engineering defaults (WP7-B).
  motion: { floatTextRise: 40, floatTextMs: 800, recenterMs: 600, doubleTapRecenterMs: 400, radialFadeMs: 200,
            quickBarRefillMs: 300, newUnlockFlashMs: 600, drawerMs: 250, joystickFadeInMs: 80, pendingDelayMs: 300,
            toastBaseMs: 2000, toastPer20CharsMs: 500, toastMaxMs: 5000 },
  naturalLineHeight: 1.364,
  // The old State=Available badge main (517:11951) has no counterpart in Gensen_US_2026 (不知火舞 340 9d80f70a): its sizes.
  statusBadge: 56, statusBadgeIcon: 28,
  // Layers the new file's mains no longer have (不知火舞 340 9d80f70a: kept at tokens-v2.json's values, Figma untouched):
  // RadialPetal State=Current has no Label (petals carry no text since q(62)); Compact/Kitchen/Cell State=default has
  // no 'Selected or cooked mark'.
  radialLabel: 12, kitchenCheck: 13, kitchenCheckIcon: 9,
  // The radial's hit circle and ring radius (ui_action_radial), added by hand to tokens-v2.json before; no layer holds them.
  radialHit: 72, radialRing: 88,
  // The unavailable icon's opacity: 0.35 in the new file's RadialPetal Unavailable, 0.45 till now — kept, under review (340 826e261e).
  unavailableIcon: 0.45,
};
const page = await figma.getNodeByIdAsync('5:4');
await figma.setCurrentPageAsync(page);
const hex = (c, a) => '#' + [c.r, c.g, c.b].map(v => Math.round(v * 255).toString(16).padStart(2, '0')).join('').toUpperCase()
  + (a !== undefined && a < 1 ? Math.round(a * 255).toString(16).padStart(2, '0').toUpperCase() : '');
const r1 = n => Math.round(n * 10) / 10;
async function resolve(v, modeId) {
  let val = v.valuesByMode[modeId] ?? Object.values(v.valuesByMode)[0];
  for (let i = 0; i < 6 && val && val.type === 'VARIABLE_ALIAS'; i++) {
    const t = await figma.variables.getVariableByIdAsync(val.id);
    val = t.valuesByMode[Object.keys(t.valuesByMode)[0]];
  }
  return val;
}
const cols = await figma.variables.getLocalVariableCollectionsAsync();
async function vars(name) {
  const c = cols.find(x => x.name === name); const out = {};
  for (const id of c.variableIds) { const v = await figma.variables.getVariableByIdAsync(id); out[v.name] = await resolve(v, c.defaultModeId); }
  return out;
}
const sem = await vars('Gensen Refactor · Semantic');
const kit = await vars('Gensen · source kit colors');
const node = async id => { const n = await figma.getNodeByIdAsync(id); if (!n) throw new Error('missing node ' + id); return n; };
const variant = async (setId, name) => (await node(setId)).children.find(c => c.name === name);
const child = (n, name) => n.findOne(c => c.name === name);
const fillAlpha = n => { const p = n.fills.find(f => f.visible !== false); return p ? (p.opacity ?? 1) : 1; };
const color = {};
for (const [k, v] of Object.entries(sem)) if (k.startsWith('color/')) color[k.slice(6)] = hex(v, v.a);
Object.assign(color, {
  muted: hex(kit['kit/muted']), disabled: hex(kit['kit/disabled']), disabledInk: hex(kit['kit/disabledInk']),
  edgeStrong: hex(kit['kit/edge2']),
  energyHudFill: hex(kit['kit/amber']), energyHudLight: CONST.energyHudLight, energyHudDeep: CONST.energyHudDeep,
  scrim: hex(sem['color/text']),
});
// Rarity comes from the semantic rarity/* variables once Figma has them (WP1a added them on 2026-10-07).
if (!Object.keys(sem).some(k => k.startsWith('color/rarity/'))) Object.assign(color, {
  'rarity/common': hex(kit['kit/common']), 'rarity/fine': hex(kit['kit/blue']), 'rarity/rare': CONST.rarityRare, 'rarity/legendary': hex(kit['kit/amber']),
});
const joy = await variant('9:100420', 'State=idle');
color.joystickRing = hex(child(joy, 'Joystick outer touch circle').fills[0].color, fillAlpha(child(joy, 'Joystick outer touch circle')));
color.joystickThumb = hex(child(joy, 'Joystick thumb').fills[0].color, fillAlpha(child(joy, 'Joystick thumb')));
const space = {}, radius = {};
for (const [k, v] of Object.entries(sem)) {
  if (k.startsWith('space/')) space[k.slice(6).replace(/-(\w)/g, (_, c) => c.toUpperCase())] = v;
  if (k.startsWith('radius/')) radius[k.slice(7)] = v;
}
const quickDefault = await variant('9:99874', 'State=default');
const quickSelected = await variant('9:99874', 'State=selected');
const invDefault = await variant('9:99839', 'State=default');
const invEmpty = await variant('9:99839', 'State=empty');
const quickEmpty = await variant('9:99874', 'State=empty');
const quickLifted = await variant('9:99874', 'State=lifted');
const quickDrop = await variant('9:99874', 'State=drop-target');
const quickZero = await variant('9:99874', 'State=zero');
const kitchenDefault = await variant('9:99354', 'State=default');
const kitchenEmpty = await variant('9:99354', 'State=empty');
const cmdPressed = await variant('9:99690', 'Kind=primary-pressed');
const cmdPending = await variant('9:99690', 'Kind=primary-pending');
const firstFill = n => n.fills.find(f => f.visible !== false);
const shadowOf = n => n.effects.find(e => e.visible !== false && e.type === 'DROP_SHADOW');
const liftShadow = shadowOf(child(quickLifted, 'Slot surface'));
color.pinAmber = hex(firstFill(child(quickDefault, 'Pinned amber strip')).color);
color.pinWarm = hex(firstFill(child(quickDefault, 'Pinned warm fill')).color);
color.primaryPressed = hex(firstFill(cmdPressed).color);
color.liftShadow = hex(liftShadow.color, liftShadow.color.a);
const cmdCompact = await node('9:99711');
const filterDefault = await variant('9:99723', 'State=default');
const modeDefault = await variant('9:99496', 'State=default');
const hud = await node('9:100203');
const bagFrame = await node('9:105329');
const counterFrame = await node('9:105901');
const energyRef = await variant('9:100383', 'State=normal');
Object.assign(radius, {
  inventoryCell: invDefault.cornerRadius, track: child(energyRef, 'Energy track').cornerRadius,
  chip: child(filterDefault, 'Filter pill').cornerRadius, hudChip: child(hud, 'Energy').cornerRadius,
  compactCommand: child(cmdCompact, 'Command surface').cornerRadius, kitchenMode: child(modeDefault, 'Mode pill').cornerRadius,
  bagDrawerTop: child(bagFrame, 'Bag drawer · source proportions').topLeftRadius,
  counterDrawerTop: child(counterFrame, 'Compact/Shop counter and Bag drawer').topLeftRadius,
});
const objectHeader = await node('9:99657');
const itemRow = await node('9:100063');
// keyCompact: the Compact command keys' side padding (BARTER-2 2570:132291 Command surface; 不知火舞, 2026-10-13), no variable of its own
Object.assign(space, { quickBarGap: 4, keyCompact: 14, hudRowGap: child(hud, 'HUD second row').itemSpacing, itemRowGap: itemRow.itemSpacing });
const stroke = {
  default: (await node('9:99685')).strokeWeight,
  cellHairline: invDefault.strokeWeight,
  selectedCell: (await variant('9:99839', 'State=selected')).strokeWeight,
  selected: child(quickSelected, 'Slot surface').strokeWeight,
  pinBadge: child(quickDefault, 'Pinned icon surface').strokeWeight,
};
const opacity = {
  sheetSurface: r1(fillAlpha(await node('9:102395')) * 100) / 100,
  scrimCounter: Math.round(fillAlpha(child(counterFrame, 'Counter scene dim')) * 100) / 100,
  scrimDrawer: sem['color/scrimDrawer'] ? Math.round(sem['color/scrimDrawer'].a * 100) / 100 : CONST.scrimDrawer,
  scrimModal: sem['color/scrimModal'] ? Math.round(sem['color/scrimModal'].a * 100) / 100 : CONST.scrimModal,
  pending: Math.round(cmdPending.opacity * 100) / 100,
  zeroIcon: Math.round(quickZero.findOne(c => c.type === 'INSTANCE').opacity * 100) / 100,
  emptyCell: Math.round(fillAlpha(invEmpty) * 100) / 100,
  kitchenEmpty: Math.round(child(kitchenEmpty, 'Cell surface').opacity * 100) / 100,
};
const info = await node('9:102395');
// Toast R1 (1178:82265, WP2 accepted 2026-10-07, SGODOT-202) replaced the old Toast main 483:302.
const toast = await variant('9:104596', 'Tone=Info');
const close = await node('9:99685');
const size = {
  touch: 44,
  quickSlotW: quickDefault.width, quickSlotH: quickDefault.height,
  quickSlotSurfaceH: child(quickDefault, 'Slot surface').height,
  quickSlotIcon: child(quickDefault, 'Slot surface').children.find(c => c.type === 'INSTANCE').width,
  quickSlotLift: child(quickDefault, 'Slot surface').y - child(quickSelected, 'Slot surface').y,
  quickEndW: (await node('9:102342')).width,
  quickBarW: 336, quickBarH: quickDefault.height, quickBarX: 12, quickBarBottom: 24,
  hudW: hud.width, hudH: hud.height, hudX: 8, hudTop: 16,
  hudRow1H: child(hud, 'Status').height, hudRow2H: child(hud, 'HUD second row').height,
  command: (await variant('9:99690', 'Kind=primary')).height,
  commandCompact: child(cmdCompact, 'Command surface').height,
  navigationRow: (await node('9:99743')).height, dismiss: (await node('9:99738')).height,
  close: close.width, closeIcon: close.children[0].width,
  filterChip: child(filterDefault, 'Filter pill').height, filterTouch: filterDefault.height,
  segmentTab: (await node('9:99813')).height,
  kitchenMode: child(modeDefault, 'Mode pill').height, kitchenModeTouch: modeDefault.height,
  inventoryCell: invDefault.width, inventoryIcon: invDefault.children.find(c => c.type === 'INSTANCE').width,
  gearSlotW: (await variant('9:99820', 'State=default')).width, gearSlotH: (await variant('9:99820', 'State=default')).height,
  kitchenCellW: (await variant('9:99354', 'State=default')).width, kitchenCellH: (await variant('9:99354', 'State=default')).height,
  itemRowIcon: (await node('9:100063')).children.find(c => c.type === 'INSTANCE').width,
  stateBadgeH: (await node('9:100448')).height,
  statusBadge: CONST.statusBadge, statusBadgeIcon: CONST.statusBadgeIcon,
  toastW: toast.width, toastIcon: child(toast, 'Tone icon').width,
  toastPadTop: toast.paddingTop, toastPadRight: toast.paddingRight, toastPadBottom: toast.paddingBottom, toastPadLeft: toast.paddingLeft,
  // One-line toasts on page 14 are 232 × 40: padding + tone icon + the 1 px stroke top and bottom.
  toastMinH: toast.paddingTop + toast.paddingBottom + child(toast, 'Tone icon').height + 2 * toast.strokeWeight,
  sheetPad: info.paddingTop, sheetGap: info.itemSpacing, sheetBodyMaxH: 440,
  energyRefW: energyRef.width, energyRefH: energyRef.height,
  pinBadge: child(quickDefault, 'Pinned icon surface').width, pinIcon: child(quickDefault, 'Pin glyph').width,
  pinStripW: child(quickDefault, 'Pinned amber strip').width, pinStripH: child(quickDefault, 'Pinned amber strip').height,
  quickSlotLiftDrag: child(quickDefault, 'Slot surface').y - child(quickLifted, 'Slot surface').y,
  liftShadowRadius: liftShadow.radius, liftShadowOffsetY: liftShadow.offset.y,
  qtyPillW: child(invDefault, 'Quantity pill').width, qtyPillH: child(invDefault, 'Quantity pill').height,
  rarityDot: child(invDefault, 'Rarity dot').width,
  kitchenCheck: CONST.kitchenCheck, kitchenCheckIcon: CONST.kitchenCheckIcon,
  objectHeaderQtyW: child(objectHeader, 'Identity and quantity').children.find(c => c.name === 'Quantity').width,
  itemRowQtyW: itemRow.children.find(c => c.name === 'Quantity').width,
};
// Dash patterns [dash, gap] of empty / ghost / drop-target outlines.
const dash = {
  inventory: invEmpty.dashPattern, kitchen: child(kitchenEmpty, 'Cell surface').dashPattern,
  quick: child(quickEmpty, 'Slot surface').dashPattern, dropTarget: child(quickDrop, 'Slot surface').dashPattern,
};
// WP1a mains, accepted 2026-10-07 (SGODOT-200): HUD 1143:103373, NeedTile 1090:78003, Energy 1094:77504,
// TodayPanel 1145:81715 / TodayRow 1145:81714, ActionKey 1117:78924, SceneAction 1116:78934,
// RadialPetal 1122:79385, TapCard 1135:101133, StatusBadge 1132:79554, PinMenu 1141:80291.
const hudN = await variant('9:100202', 'Energy=Normal');
const hudBonus = await variant('9:100202', 'Energy=Bonus');
const hudChip = hudN.findOne(c => c.name === 'Energy' && c.type === 'FRAME');
const ntL = await variant('9:102402', 'Size=L, State=met, Progress=100');
const ntM = await variant('9:102402', 'Size=M, State=met, Progress=100');
const ntS = await variant('9:102402', 'Size=S, State=met, Progress=100');
const ntShort = await variant('9:102402', 'Size=L, State=short, Progress=50');
const ringStroke = t => (child(t, 'Ring').width - child(t, 'Core').width) / 2;
const energyCard = await variant('9:103148', 'Kind=Card, State=Short');
const energyPanel = await variant('9:103148', 'Kind=Panel, State=Normal');
const todayPanel = await node('9:103854');
const todayRow = await variant('9:103829', 'State=Default');
const actionKey = await node('9:103215');
const switchKey = child(actionKey, 'Switch key · LOCK-03');
const toolBadge = child(actionKey, 'Tool badge · display only');
const saDefault = await variant('9:99789', 'State=Default');
const saPressed = await variant('9:99789', 'State=Pressed');
const saPending = await variant('9:99789', 'State=Pending');
const arcWidth = (v, name) => (v.width / 2) * (1 - child(v, name).arcData.innerRadius);
// The old State=Selected was the plain petal's size and shadow (Available here) with the current petal's 3 px ring
// (Current here); Current's 72 / 38 are radialPetalCurrent / radialIconCurrent (不知火舞 340 826e261e).
const petalSel = await variant('9:103224', 'State=Current');
const petalAvail = await variant('9:103224', 'State=Available');
const petalOff = await variant('9:103224', 'State=Unavailable');
const tapCard = await variant('9:103539', 'Pointer=Center');
const sbWorld = await variant('9:103339', 'Size=World, State=Ready');
const sbNpc = await variant('9:103339', 'Size=NPC, State=Request');
const pinMenu = await variant('9:103778', 'Pinned=yes');
const todayDone = await variant('9:103829', 'State=Done');
const quickEnd = await node('9:102342');
// Collapsed quick bar (LOCK-04 "未选行动时收起成把手"): page-14 frames, not a main yet.
const handleTouch = await node('9:105624'), handle = await node('9:105625'), grip = await node('9:105626');
// EmptyState 1234:87237 (WP6 main, Kind=Panel / Row).
const emptyPanel = await variant('9:104829', 'Kind=Panel'), emptyRow = await variant('9:104829', 'Kind=Row');
// StatusBadge 1132:79554 state table: fill and ring colour per state (World size; NPC uses the same colours).
for (const v of (await node('9:103339')).children.filter(c => c.name.startsWith('Size=World'))) {
  const key = v.name.replace('Size=World, State=', '').replace(/ (\w)/g, (_, c) => c.toUpperCase()).replace(/^\w/, c => c.toLowerCase());
  const b = child(v, 'Badge');
  color['status/' + key] = hex(firstFill(b).color);
  color['status/' + key + 'Ring'] = hex(b.strokes.find(p => p.visible !== false).color);
}
const shadow = {
  card: shadowOf(energyCard), float: shadowOf(tapCard), petal: shadowOf(child(petalAvail, 'Petal')),
  menu: shadowOf(pinMenu), key: shadowOf(switchKey),
};
for (const [k, e] of Object.entries(shadow)) {
  color['shadow/' + k] = hex(e.color, e.color.a);
  size['shadow' + k[0].toUpperCase() + k.slice(1) + 'Radius'] = e.radius;
  size['shadow' + k[0].toUpperCase() + k.slice(1) + 'OffsetY'] = e.offset.y;
}
Object.assign(color, {
  'skill/farming': hex(firstFill(child(hudN, 'Skill ring · Farming')).color),
  'skill/fishing': hex(firstFill(child(hudN, 'Skill ring · Fishing')).color),
  unreadBadge: hex(firstFill(child(hudN, 'Inbox unread badge')).color),
  energyBonus: hex(firstFill(child(hudBonus, 'Energy bonus segment')).color),
  tileCore: hex(firstFill(child(ntL, 'Core')).color),
  warm: hex(firstFill(child(ntShort, 'Core')).color),
  amber: hex(kit['kit/amber']),
  quickHandle: hex(firstFill(handle).color), quickHandleGrip: hex(firstFill(grip).color),
});
Object.assign(radius, {
  radialLabel: CONST.radialLabel, captionPill: child(sbWorld, 'CaptionPill').cornerRadius,
  pinMenu: pinMenu.cornerRadius, energyTile: child(energyCard, 'Guidance · Eat').cornerRadius,
  quickHandle: handle.cornerRadius,
});
Object.assign(stroke, {
  ring: ringStroke(ntL),
  sceneAction: saDefault.strokeWeight, sceneActionPressed: saPressed.strokeWeight,
  radialSelected: child(petalSel, 'Petal').strokeWeight, statusBadgeNpc: child(sbNpc, 'Badge').strokeWeight,
});
Object.assign(opacity, {
  sceneActionPending: Math.round(saPending.opacity * 100) / 100,
  // Shared by the radial petal icon (1122:79385) and the EnergyTile unavailable icon disc (1093:77292).
  unavailableIcon: CONST.unavailableIcon,
  todayDone: Math.round(todayDone.opacity * 100) / 100,
  emptyIcon: Math.round(child(emptyPanel, 'Icon').opacity * 100) / 100,
});
Object.assign(size, {
  sceneAction: saDefault.width, switchKey: switchKey.width, switchIcon: switchKey.children[0].width,
  toolBadge: toolBadge.width, toolBadgeIcon: child(toolBadge, 'Tool').width,
  actionKeyW: actionKey.width, actionKeyH: actionKey.height,
  holdRing: arcWidth(await variant('9:99789', 'State=Holding'), 'Hold progress'), pendingRing: arcWidth(saPending, 'Pending spinner'),
  // In tokens-v2.json's order (the hand-added keys sat between these).
  radialPetal: child(petalAvail, 'Petal').width, radialPetalCurrent: child(petalSel, 'Petal').width,
  radialHit: CONST.radialHit, radialRing: CONST.radialRing,
  radialIcon: child(child(petalAvail, 'Petal'), 'Icon').width, radialIconCurrent: child(child(petalSel, 'Petal'), 'Icon').width,
  radialLockBadge: child(petalOff, 'Lock badge').width, radialLockIcon: child(petalOff, 'Lock badge').children[0].width,
  tapCardH: tapCard.height, tapGlyph: child(tapCard, 'Tap glyph').width,
  pointerW: child(tapCard, 'Pointer').width, pointerH: child(tapCard, 'Pointer').height,
  statusBadgeWorld: sbWorld.width, statusBadgeNpc: sbNpc.width,
  statusGlyphWorld: child(sbWorld, 'Glyph').width, statusGlyphNpc: child(sbNpc, 'Glyph').width,
  captionPillH: child(sbWorld, 'CaptionPill').height, pinMenuW: pinMenu.width,
  hudAvatar: child(hudN, 'Icon/i-face-player').width, skillRing: child(hudN, 'Skill ring · track').width,
  energyChipW: hudChip.width, energyChipH: hudChip.height,
  energyTrackW: child(hudChip, 'Energy track').width, energyTrackH: child(hudChip, 'Energy track').height,
  hudCapsuleH: child(hudN, 'Coins capsule').height, inbox: child(hudN, 'Inbox capsule').width,
  unreadBadgeW: child(hudN, 'Inbox unread badge').width, unreadBadgeH: child(hudN, 'Inbox unread badge').height,
  todayIconW: child(hudN, 'Today navigation').width,   // SGODOT-271: the 32 x 24 Today icon pill (安其拉 renames the layer if needed)
  needTileRingL: child(ntL, 'Ring').width, needTileRingM: child(ntM, 'Ring').width, needTileRingS: child(ntS, 'Ring').width,
  needTileStrokeL: ringStroke(ntL), needTileStrokeM: ringStroke(ntM), needTileStrokeS: ringStroke(ntS),
  needTileIconL: child(ntL, 'Icon').width, needTileIconM: child(ntM, 'Icon').width, needTileIconS: child(ntS, 'Icon').width,
  needTileW: ntL.width, needTileWS: ntS.width, needTileLabelS: child(ntS, 'Name').fontSize,
  needTileGapX: CONST.needTileGapX, needTileGapY: CONST.needTileGapY,
  energyCardW: energyCard.width, energyPanelW: energyPanel.width, energyTileH: child(energyCard, 'Guidance · Eat').height,
  todayPanelW: todayPanel.width, todayPanelX: CONST.todayPanelX, todayPanelY: CONST.todayPanelY,
  todayRowH: todayRow.height, todayIcon: child(todayRow, 'Icon').width,
  joystickOuter: child(joy, 'Joystick outer touch circle').width, joystickThumb: child(joy, 'Joystick thumb').width,
  capacityDot: child(quickEnd, 'Capacity warning').width,
  quickHandleTouchW: handleTouch.width, quickHandleTouchH: handleTouch.height,
  quickHandleW: handle.width, quickHandleH: handle.height, quickHandleGripW: grip.width, quickHandleGripH: grip.height,
  emptyDisc: child(emptyPanel, 'Icon disc').width, emptyIcon: child(emptyPanel, 'Icon').width, emptyRowIcon: child(emptyRow, 'Icon').width,
});
for (const k of Object.keys(size)) size[k] = r1(size[k]);
const weightOf = { Regular: 'regular', Bold: 'bold', ExtraBold: 'extrabold' };
const wShort = { Regular: 'R', Bold: 'B', ExtraBold: 'XB' };
const styles = {};
for (const s of await figma.getLocalTextStylesAsync()) {
  let m = s.name.match(/^Gensen Refactor\/(\w+)\/(Regular|Bold|ExtraBold)$/), key;
  if (m) key = m[1][0].toUpperCase() + m[1].slice(1) + wShort[m[2]] + s.fontSize;
  else if ((m = s.name.match(/^Gensen\/Compact\/(\d+)\/(Bold|ExtraBold)$/))) key = 'C' + m[1] + wShort[m[2]];
  else continue;
  styles[key] = { size: s.fontSize, weight: weightOf[s.fontName.style], lineHeight: Math.round(s.lineHeight.value * 10) / 1000, figma: s.name };
}
const sorted = o => Object.fromEntries(Object.keys(o).sort().map(k => [k, o[k]]));
const tokens = {
  meta: {
    schema: 2, version: '2.1-draft', status: 'draft',
    source: 'Figma 5SVgfevrLzZXqD83uyPgmV page 5:4 (read-only export, tools/ui/export_tokens_figma.js)',
    unit: '360-wide logical px = Godot UI unit',
    accepted: 'WP1a mains (HUD, NeedTile, Energy, Today, ActionKey, SceneAction, RadialPetal, TapCard, StatusBadge, PinMenu, QuickSlot, CommandButton, joystick) accepted 2026-10-07, SGODOT-200; WP2 Toast R1 accepted 2026-10-07, SGODOT-202; WP6 EmptyState accepted 2026-10-07, SGODOT-206',
    pending: {
      wp1b: 'container mains (Sheet / drawers, SegmentTab, InventoryCell, GearSlot, Kitchen/*, counter, NPC) await WP1b (SGODOT-201)',
      segmentTab: 'selected style must not use command green (LOCK-13), WP1b',
      toast: 'sizes read Toast R1 (1178:82265); ToastLayer draws its tone look (light fills, tone icon, optional action; SGODOT-233); the ToastPanel variation still holds the old dark panel for pre-P0 screens',
      entryCard: 'EntryCard 1468:94344 (SGODOT-231): radius 16 and padding 8 / 14 / 9 / 14, gap 2, Pointer=Right inset 21 are constants in UiEntryCard until the next token export adds them',
      blueprintCard: 'BlueprintCard 1434:93844 and the B2-06 Workbench drawer (SGODOT-231): card radius 16, padding 12 / 14, gap 10, icon tile 44 with a 32 icon, material gap 8, the recipe name 16 ExtraBold and the drawer title 22 ExtraBold are constants in UiBlueprintCard / P0WorkbenchDrawer until the next token export adds them',
      family: 'color/family/* (1726:32854–32857), color/newInk (1398:92869) and color/goldDeep (1755:33005, the Mastered star, C28) were added by hand under the names the exporter gives (SGODOT-226, 2026-10-08); the next full export replaces this note',
      guidePulse: 'GuidePulse 1407:113987 (SGODOT-232 U6, A-03): ring stroke 2, growth to +10 and frame inset 4 are constants in UiGuidePulse until the next token export adds them; color/primary and MOTION_NEW_UNLOCK_FLASH_MS (600 ms, ease-out) are tokens',
      systemCard: 'SystemCard 1237:87229, Wordmark (placeholder) 1187:82582, Spinner 1237:87185 and the SYS-LOADING screens (SGODOT-233): card padding 28 / 21 / 20 / 21, gap 10, icon disc 64 with a 32 icon, 6 above the button, the 0 10 28 card shadow; the wordmark\'s sprout 30, gap 6 and name 32 ExtraBold; the spinner\'s 28 ring with a 3 stroke; the scene loading\'s destination 18 ExtraBold are constants in UiSystemCard / UiWordmark / UiSpinner / P0SysScreen until the next token export adds them',
      tipCard: 'TipCard 1243:87540 (TUT-2, SGODOT-232 U6 / 235-B2): width 296, padding 14 / 12, gap 10, radius 16, one line 48, 22 px icon and the shadow (#2E3A33 at 8 %, size 28, offset 0 / 6: lighter than the main\'s 20 % / 0 / 10 / blur 28 so Godot reads as the same faint halo, 不知火舞 on 235-B2) are constants in UiTipCard until the next token export adds them; surface, border, text and BodyB14 are tokens',
    },
  },
  font: { file: 'res://assets/ui/fonts/Nunito.ttf', naturalLineHeight: CONST.naturalLineHeight,
          weights: { regular: 400, bold: 700, extrabold: 800 }, styles: sorted(styles) },
  color: sorted(color), opacity, space: sorted(space), radius: sorted(radius), stroke, size, dash,
  motion: Object.assign({ dissolveMs: 150 }, CONST.motion),
};
const json = JSON.stringify(tokens, null, 2) + '\n';
let h = 0x811c9dc5;
for (let i = 0; i < json.length; i++) { h ^= json.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
return { fnv1a: h.toString(16), bytes: json.length, compact: JSON.stringify(tokens) };
