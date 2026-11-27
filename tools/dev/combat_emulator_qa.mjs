import { execFile } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { isDeepStrictEqual, promisify } from 'node:util';

const execute = promisify(execFile);
const base = 'http://127.0.0.1:3155/v1/qa/journey/scene';
// The session's serial (run_test.sh), else this Run's emulator (C-212), else the local default.
const serial = process.env.JOURNEY_SERIAL || process.env.CARDIGAN_EMULATOR_SERIAL || 'emulator-5560';
const output = 'output/combat-emulator-2026-09-15/actions';
await mkdir(output, { recursive: true });
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const snapshot = async () => {
  const response = await fetch(base, { signal: AbortSignal.timeout(5000) });
  if (!response.ok) throw new Error(`Scene inspection failed: ${response.status}`);
  return response.json();
};
const controls = s => [...(s.controls ?? []), ...(s.world?.controls ?? [])];
const summary = s => ({ version: s.version, scene: s.scene, offline: s.offline, hp: s.state?.character?.hp,
  floor: s.state?.mine?.floor, broken: s.state?.mine?.broken, combat: s.world?.combat, launch_id: s.launch_id,
  buttons: controls(s).filter(c => c.button && !c.disabled && !/^(walk|blocked):/.test(c.path)).map(c => ({ path: c.path.split('/').at(-1), text: c.text, tooltip: c.tooltip, rect: c.rect })) });
async function waitUntil(test, seconds = 20) {
  const deadline = Date.now() + seconds * 1000;
  while (Date.now() < deadline) {
    const state = await snapshot();
    if (test(state)) return state;
    await pause(300);
  }
  throw new Error('Timed out waiting for scene state');
}
async function input(selector, duration = 100) {
  const before = await snapshot();
  const candidates = controls(before).filter(c => c.button && !c.disabled && (c.path === selector || c.path.endsWith('/' + selector) || c.text === selector || c.tooltip === selector));
  if (candidates.length !== 1) throw new Error(`Expected one enabled ${selector}, found ${candidates.length}`);
  const target = candidates[0];
  const [left, top, width, height] = target.rect;
  // The Android UI tree exposes the map's native input overlay in the first 96 px.
  const visibleTop = before.scene === '/root/MapPoc' && top < 96 ? Math.min(top + height - 2, 96) : top;
  const [x, y] = [Math.round(left + width / 2), Math.round((visibleTop + top + height) / 2)];
  const prefix = `${output}/${new Date().toISOString().replaceAll(':', '-')}-${selector.replace(/[^a-zA-Z0-9_-]/g, '_')}`;
  await writeFile(prefix + '-before.json', JSON.stringify(before, null, 2));
  const nativeMapTap = before.scene === '/root/MapPoc' && selector === 'MyFarm';
  const args = nativeMapTap ? ['tap', String(x), String(y)]
    : ['swipe', String(x), String(y), String(x), String(y), String(duration)];
  await execute('adb', ['-s', serial, 'shell', 'input', ...args], { timeout: duration + 8000 });
  let after = await waitUntil(s => s.launch_id === before.launch_id && s.ticks_ms > before.ticks_ms + duration + 1500
    && !s.world?.moving && !s.world?.busy);
  if (selector === 'MyFarm' && after.scene === '/root/MapPoc' && after.touches.length === before.touches.length) {
    await execute('adb', ['-s', serial, 'shell', 'input', 'tap', String(x), String(y)]);
    after = await waitUntil(s => s.scene === '/root/Farm');
  }
  await writeFile(prefix + '-after.json', JSON.stringify(after, null, 2));
  await writeFile(prefix + '-action.json', JSON.stringify({ selector, target, input: nativeMapTap ? 'adb input tap' : 'adb touch hold', duration: nativeMapTap ? null : duration, screen: [x, y] }, null, 2));
  const image = await execute('adb', ['-s', serial, 'exec-out', 'screencap', '-p'], { encoding: 'buffer', maxBuffer: 8 * 1024 * 1024 });
  await writeFile(prefix + '.png', image.stdout);
  return after;
}
const [mode = 'inspect', selector, value] = process.argv.slice(2);
if (mode === 'inspect') console.log(JSON.stringify(summary(await snapshot()), null, 2));
else if (mode === 'scroll') {
  const before = await snapshot();
  const nodes = controls(before).filter(c => c.path.includes('/BagScroll/') || c.path.includes('/ContentScroll/') || c.path.includes('/@ScrollContainer@'));
  if (!nodes.length) throw new Error('No visible scroll content in the scene tree');
  const top = Math.min(...nodes.map(c => c.rect[1]));
  const bottom = Math.max(...nodes.map(c => c.rect[1] + c.rect[3]));
  const left = Math.min(...nodes.map(c => c.rect[0]));
  const right = Math.max(...nodes.map(c => c.rect[0] + c.rect[2]));
  const x = Math.round((left + right) / 2);
  const from = Math.round(top + (bottom - top) * (selector === 'down' ? 0.2 : 0.8));
  const to = Math.round(top + (bottom - top) * (selector === 'down' ? 0.8 : 0.2));
  await execute('adb', ['-s', serial, 'shell', 'input', 'swipe', String(x), String(from), String(x), String(to), '450']);
  const after = await waitUntil(s => s.ticks_ms > before.ticks_ms + 2000);
  await writeFile(`${output}/${Date.now()}-scroll.json`, JSON.stringify({ before, after, screen: [[x, from], [x, to]] }));
  console.log(JSON.stringify(summary(after), null, 2));
}
else if (mode === 'tap' || mode === 'hold') {
  const after = await input(selector, mode === 'hold' ? Number(value ?? 5000) : (selector === 'MyFarm' ? 300 : 100));
  console.log(JSON.stringify({ version: after.version, scene: after.scene, hp: after.state?.character?.hp,
    floor: after.state?.mine?.floor, monsters: after.state?.mine?.combat?.monsters, offline: after.offline }));
}
else if (mode === 'fight') {
  for (let attempt = 0; attempt < 7; attempt++) {
    const before = await waitUntil(s => !s.world?.moving && !s.world?.busy);
    if (!before.state?.mine?.floor || !Object.keys(before.world?.combat?.enemies ?? {}).length) break;
    await waitUntil(s => s.world?.can_act && !s.world.command_busy);
    const after = await input('MineAttack', 5000);
    console.log(JSON.stringify({ attempt, hp: after.state.character.hp, floor: after.state.mine.floor, enemies: after.world?.combat?.enemies }));
    if (Object.values(after.world?.combat?.enemies ?? {}).length
      && Object.values(after.world.combat.enemies).every(enemy => enemy.phase === 'idle')) break;
  }
} else if (mode === 'mine-floor') {
  const floor = (await snapshot()).state.mine.floor;
  for (let attempt = 0; attempt < 8; attempt++) {
    const state = await waitUntil(s => s.world?.can_act && !s.world.moving && !s.world.busy);
    if (state.state.mine.floor !== floor) throw new Error('Floor changed unexpectedly');
    if (Object.keys(state.world.combat?.enemies ?? {}).length) throw new Error('Defeat monsters before scripted mining');
    const rock = controls(state).find(c => c.path.startsWith('body:rock_') && !c.disabled);
    if (!rock) break;
    const id = rock.path.slice(5);
    await input(rock.path);
    const after = await waitUntil(s => s.state.mine.broken[String(floor)]?.includes(id) && !s.world.busy);
    console.log(JSON.stringify({ version: after.version, floor, mined: id }));
  }
} else if (mode === 'move-attack') {
  const before = await snapshot();
  const center = name => {
    const node = controls(before).find(c => c.path.endsWith('/' + name) && !c.disabled);
    if (!node) throw new Error(`Missing ${name}`);
    return [node.rect[0] + node.rect[2] / 2, node.rect[1] + node.rect[3] / 2];
  };
  const stick = center('MineMoveStick');
  const attack = center('MineAttack');
  const points = [...stick, ...attack, stick[0] + 70, stick[1], ...attack].map(String);
  const prefix = `${output}/${Date.now()}-move-attack`;
  await writeFile(prefix + '-before.json', JSON.stringify(before, null, 2));
  const operation = execute('adb', ['-s', serial, 'shell', 'env', 'CLASSPATH=/data/local/tmp/journey-touch.dex',
    'app_process', '/data/local/tmp', 'JourneyTouch', ...points, '1400'], { timeout: 10000 });
  await pause(600);
  const image = await execute('adb', ['-s', serial, 'exec-out', 'screencap', '-p'], { encoding: 'buffer', maxBuffer: 8 * 1024 * 1024 });
  await writeFile(prefix + '.png', image.stdout);
  await operation;
  const after = await waitUntil(s => s.ticks_ms > before.ticks_ms + 3000);
  await writeFile(prefix + '-after.json', JSON.stringify(after, null, 2));
  const distance = Math.hypot(...after.world.player.map((n, i) => n - before.world.player[i]));
  const gestures = after.gesture_events.filter(e => e.ticks_ms > before.ticks_ms);
  const report = { passed: distance > 0.5 && isDeepStrictEqual(before.world.camera_pan, after.world.camera_pan)
    && gestures.some(e => e.pointer === 0 && e.pressed) && gestures.some(e => e.pointer === 1 && e.pressed),
    distance, camera_unchanged: isDeepStrictEqual(before.world.camera_pan, after.world.camera_pan), gestures, points };
  await writeFile(prefix + '.json', JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report));
  if (!report.passed) process.exitCode = 1;
} else if (mode === 'cold-start') {
  const before = await snapshot();
  const prefix = `output/combat-emulator-2026-09-15/cold-start-${before.version}`;
  await writeFile(prefix + '-before.json', JSON.stringify(before, null, 2));
  await execute('adb', ['-s', serial, 'shell', 'am', 'force-stop', 'com.sensen.journeycombatqa']);
  await execute('adb', ['-s', serial, 'shell', 'am', 'start', '-n', 'com.sensen.journeycombatqa/com.godot.game.GodotAppLauncher']);
  const after = await waitUntil(s => s.launch_id !== before.launch_id && s.version >= before.version);
  await writeFile(prefix + '-after.json', JSON.stringify(after, null, 2));
  const checks = Object.fromEntries(['bag', 'character', 'mine', 'journey'].map(key => [key, isDeepStrictEqual(before.state[key], after.state[key])]));
  checks.version = before.version === after.version;
  checks.launch_changed = before.launch_id !== after.launch_id;
  const report = { passed: Object.values(checks).every(Boolean), checks, version: after.version, natural_player_verified: false };
  await writeFile(prefix + '.json', JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report));
  if (!report.passed) process.exitCode = 1;
} else throw new Error(`Unknown mode ${mode}`);
