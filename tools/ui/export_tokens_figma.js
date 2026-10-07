// READ-ONLY Figma exporter for docs/design/tokens/tokens-v2.json (SGODOT-207 WP7-A, SGODOT-211).
// Run through the Figma MCP `use_figma` tool on file OMLTC3yw3u2WDjOZhLnhaR. It never writes to Figma,
// unlike the frozen generator bundle and patch scripts under docs/design/ui-refactor-2026-10-06/figma-plugin/
// (SGODOT-197 LOCK-28). Save the returned `json` verbatim, check `fnv1a`, then run tools/ui/gen_theme.gd.
// Values Figma does not hold yet come from CONST below, each with its source.
const CONST = {
  // Gameplay plan v2 §16.1 rarity dots; Rare violet has no Figma variable yet.
  rarityRare: '#A98BD6',
  // HUD energy chip fills are hard-coded in HUD 483:304.
  energyHudLight: '#F4D27A', energyHudDeep: '#C9962A',
  // Fallback only: page 14 now defines color/scrimDrawer and color/scrimModal (alpha = scrim opacity).
  scrimDrawer: 0.18, scrimModal: 0.32,
  // Joystick: main ReferenceJoystick is 130/60, world-card instances and the shipped _TouchPad are 86/40 (WP7-A Q1, pending WP1a).
  joystickOuter: 86, joystickThumb: 40,
  // Need Tile rings and labels decided 2026-10-07, gameplay plan §1.5 q(8); main component re-export pending WP1a.
  needTileRingL: 64, needTileRingM: 48, needTileRingS: 36, needTileLabelS: 11,
  // Motion: Figma only has the 150 ms dissolve; others from plan §16 / §10 or engineering defaults (WP7-B).
  motion: { floatTextRise: 40, floatTextMs: 800, recenterMs: 600, doubleTapRecenterMs: 400, radialFadeMs: 200,
            quickBarRefillMs: 300, newUnlockFlashMs: 600, drawerMs: 250, joystickFadeInMs: 80, pendingDelayMs: 300,
            toastBaseMs: 2000, toastPer20CharsMs: 500, toastMaxMs: 5000 },
  naturalLineHeight: 1.364,
};
const page = await figma.getNodeByIdAsync('481:53');
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
  rarityCommon: hex(kit['kit/common']), rarityFine: hex(kit['kit/blue']), rarityRare: CONST.rarityRare, rarityLegendary: hex(kit['kit/amber']),
  energyHudFill: hex(kit['kit/amber']), energyHudLight: CONST.energyHudLight, energyHudDeep: CONST.energyHudDeep,
  scrim: hex(sem['color/text']),
});
const joy = await variant('517:11840', 'State=idle');
color.joystickRing = hex(child(joy, 'Joystick outer touch circle').fills[0].color, fillAlpha(child(joy, 'Joystick outer touch circle')));
color.joystickThumb = hex(child(joy, 'Joystick thumb').fills[0].color, fillAlpha(child(joy, 'Joystick thumb')));
const space = {}, radius = {};
for (const [k, v] of Object.entries(sem)) {
  if (k.startsWith('space/')) space[k.slice(6).replace(/-(\w)/g, (_, c) => c.toUpperCase())] = v;
  if (k.startsWith('radius/')) radius[k.slice(7)] = v;
}
const quickDefault = await variant('633:41279', 'State=default');
const quickSelected = await variant('633:41279', 'State=selected');
const invDefault = await variant('633:41278', 'State=default');
const cmdCompact = await node('633:41273');
const filterDefault = await variant('633:41280', 'State=default');
const modeDefault = await variant('655:58504', 'State=default');
const hud = await node('483:304');
const bagFrame = await node('482:10');
const counterFrame = await node('482:46');
const energyRef = await variant('517:11873', 'State=normal');
Object.assign(radius, {
  inventoryCell: invDefault.cornerRadius, track: child(energyRef, 'Energy track').cornerRadius,
  chip: child(filterDefault, 'Filter pill').cornerRadius, hudChip: child(hud, 'Energy').cornerRadius,
  compactCommand: child(cmdCompact, 'Command surface').cornerRadius, kitchenMode: child(modeDefault, 'Mode pill').cornerRadius,
  bagDrawerTop: child(bagFrame, 'Bag drawer · source proportions').topLeftRadius,
  counterDrawerTop: child(counterFrame, 'Compact/Shop counter and Bag drawer').topLeftRadius,
});
Object.assign(space, { quickBarGap: 4, hudRowGap: child(hud, 'HUD second row').itemSpacing });
const stroke = {
  default: (await node('483:336')).strokeWeight,
  cellHairline: invDefault.strokeWeight,
  selectedCell: (await variant('633:41278', 'State=selected')).strokeWeight,
  selected: child(quickSelected, 'Slot surface').strokeWeight,
  ring: (await variant('483:261', 'State=met')).findOne(c => c.name === 'Progress ring').strokeWeight,
};
const opacity = {
  sheetSurface: r1(fillAlpha(await node('483:190')) * 100) / 100,
  scrimCounter: Math.round(fillAlpha(child(counterFrame, 'Counter scene dim')) * 100) / 100,
  scrimDrawer: sem['color/scrimDrawer'] ? Math.round(sem['color/scrimDrawer'].a * 100) / 100 : CONST.scrimDrawer,
  scrimModal: sem['color/scrimModal'] ? Math.round(sem['color/scrimModal'].a * 100) / 100 : CONST.scrimModal,
};
const info = await node('932:71686');
const toast = await node('483:302');
const badge = await variant('517:11951', 'State=Available');
const close = await node('483:336');
const size = {
  touch: 44,
  sceneAction: (await node('488:781')).width,
  toolBadge: 28, switchKey: 44, switchIcon: 24,
  quickSlotW: quickDefault.width, quickSlotH: quickDefault.height,
  quickSlotSurfaceH: child(quickDefault, 'Slot surface').height,
  quickSlotIcon: child(quickDefault, 'Slot surface').children.find(c => c.type === 'INSTANCE').width,
  quickSlotLift: child(quickDefault, 'Slot surface').y - child(quickSelected, 'Slot surface').y,
  quickEndW: (await node('907:72112')).width,
  quickBarW: 336, quickBarH: quickDefault.height, quickBarX: 12, quickBarBottom: 24,
  hudW: hud.width, hudH: hud.height, hudX: 8, hudTop: 16,
  hudRow1H: child(hud, 'Status').height, hudRow2H: child(hud, 'HUD second row').height,
  command: (await variant('483:216', 'Kind=primary')).height,
  commandCompact: child(cmdCompact, 'Command surface').height,
  navigationRow: (await node('483:217')).height, dismiss: (await node('483:220')).height,
  close: close.width, closeIcon: close.children[0].width,
  filterChip: child(filterDefault, 'Filter pill').height, filterTouch: filterDefault.height,
  segmentTab: (await node('483:322')).height,
  kitchenMode: child(modeDefault, 'Mode pill').height, kitchenModeTouch: modeDefault.height,
  inventoryCell: invDefault.width, inventoryIcon: invDefault.children.find(c => c.type === 'INSTANCE').width,
  gearSlotW: (await variant('663:61299', 'State=default')).width, gearSlotH: (await variant('663:61299', 'State=default')).height,
  kitchenCellW: (await variant('655:58506', 'State=default')).width, kitchenCellH: (await variant('655:58506', 'State=default')).height,
  itemRowIcon: (await node('483:228')).children.find(c => c.type === 'INSTANCE').width,
  stateBadgeH: (await node('483:324')).height,
  statusBadge: badge.width, statusBadgeIcon: badge.children[0].width,
  needTileRingL: CONST.needTileRingL, needTileRingM: CONST.needTileRingM, needTileRingS: CONST.needTileRingS, needTileLabelS: CONST.needTileLabelS,
  joystickOuter: CONST.joystickOuter, joystickThumb: CONST.joystickThumb,
  toastW: toast.width, toastMinH: toast.height, toastPad: toast.paddingTop,
  sheetPad: info.paddingTop, sheetGap: info.itemSpacing, sheetBodyMaxH: 440,
  energyRefW: energyRef.width, energyRefH: energyRef.height,
};
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
    schema: 2, version: '2.0-draft', status: 'draft',
    source: 'Figma OMLTC3yw3u2WDjOZhLnhaR page 481:53 (read-only export, tools/ui/export_tokens_figma.js)',
    unit: '360-wide logical px = Godot UI unit',
    pending: {
      sceneAction: 'LOCK-02 main under WP1a revision', toolBadge: 'not in SceneAction main yet (WP1a)', switchKey: 'LOCK-03, WP1a',
      hud: 'LOCK-06, WP1a', pin: 'LOCK-05 colours, WP1a', needTile: 'sizes from plan q(8); main re-export after WP1a',
      joystick: 'WP7-A Q1: main 130/60 vs shipped 86/40', cmdBlocked: 'LOCK-10 neutral grey target, WP1a',
      segmentTab: 'selected style must not use command green (LOCK-13), WP1b',
    },
  },
  font: { file: 'res://assets/ui/fonts/Nunito.ttf', naturalLineHeight: CONST.naturalLineHeight,
          weights: { regular: 400, bold: 700, extrabold: 800 }, styles: sorted(styles) },
  color: sorted(color), opacity, space: sorted(space), radius: sorted(radius), stroke, size,
  motion: Object.assign({ dissolveMs: 150 }, CONST.motion),
};
const json = JSON.stringify(tokens, null, 2) + '\n';
let h = 0x811c9dc5;
for (let i = 0; i < json.length; i++) { h ^= json.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
return { fnv1a: h.toString(16), bytes: json.length, json };
